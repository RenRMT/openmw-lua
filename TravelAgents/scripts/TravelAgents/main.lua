-- Graph building and journey selling (only global scripts can do these).

local async = require('openmw.async')
local core = require('openmw.core')
local storage = require('openmw.storage')

local I = require('openmw.interfaces')

local adapter = require('scripts.TravelAgents.adapter')
local config = require('scripts.TravelAgents.config')
local events = require('scripts.TravelAgents.events')
local money = require('scripts.TravelAgents.money')
local plan = require('scripts.TravelAgents.plan')
local graph = require('scripts.TravelAgents.graph')
local route = require('scripts.TravelAgents.route')
local walk = require('scripts.TravelAgents.walk')

local TAG = '[TravelAgents]'

-- Built once and kept.
local cached = nil

local function out(fmt, ...)
    -- Tagged output line
    if select('#', ...) > 0 then
        print(TAG .. ' ' .. string.format(fmt, ...))
    else
        print(TAG .. ' ' .. fmt)
    end
end

--- Interior stops (need walk links to outside).
local function interiorStops(g)
    local stops = {}
    for _, key in ipairs(g.order) do
        local node = g.nodes[key]
        if not node.isExterior then
            stops[#stops + 1] = { cellId = node.cellId, position = node.position }
        end
    end
    return stops
end

--------------------------------------------------------------------------
-- Escape hatch for when the mod has not detected one or more operators
-- Searches every cell regardless of the shipped table. Costs half a
-- minute of background work. Global script may register the group,
-- the page comes from player.lua. This attaches to it.
local SETTINGS = 'SettingsGlobalTravelAgents'

-- Behind a pcall because this runs at file scope.
local registered = I.Settings ~= nil and I.Settings.registerGroup ~= nil
if registered then
    registered = pcall(I.Settings.registerGroup, {
        key = SETTINGS,
        page = 'TravelAgents',
        l10n = 'TravelAgents',
        name = 'searchGroup',
        description = 'searchGroupDescription',
        permanentStorage = true,
        settings = {
            {
                key = 'fullSearch',
                name = 'fullSearch',
                description = 'fullSearchDescription',
                renderer = 'checkbox',
                default = false,
            },
        },
    })
end

if not registered then
    out('the full-search setting is unavailable; the travel network will '
        .. 'always be built from the shipped table of operator places')
end

-- Check if full-search setting is enabled
local function searchEverything()
    local ok, value = pcall(function()
        return storage.globalSection(SETTINGS):get('fullSearch')
    end)
    return ok and value == true
end

-- What the walk learned last time
-- It remembers where it found the operators the tables could not place,
-- and those are tried first next time.
-- Ticking "search every cell" makes the walk look for everybody, and then
-- it learns everybody. Persists in global_storage.bin.
local LEARNED = 'TravelAgentsLearned'

local function learnedSection()
    local ok, section = pcall(storage.globalSection, LEARNED)
    if not ok or section == nil then
        return nil
    end
    -- Without this the section lives only as long as the session, and the
    -- walk would re-learn the same corrections on every load.
    pcall(section.setLifeTime, section, storage.LIFE_TIME.Persistent)
    return section
end

--- Earlier walk findings (id -> hints).
local function learnedHints()
    local section = learnedSection()
    if section == nil then
        return {}
    end
    local ok, value = pcall(section.get, section, 'places')
    if not ok or type(value) ~= 'table' then
        return {}
    end
    -- Copied out rather than used in place: storage hands back values that
    -- are read-only, and collectHinted only ever reads them, but the merge
    -- below has to build something writable anyway.
    local hints = {}
    for id, places in pairs(value) do
        local copied = {}
        for _, place in ipairs(places) do
            copied[#copied + 1] = { x = place.x, y = place.y, name = place.name }
        end
        hints[id] = copied
    end
    return hints
end

--- Save learned hints back to storage.
-- @return true if stored
local function writeHints(hints)
    local section = learnedSection()
    if section == nil then
        return false
    end
    return pcall(section.set, section, 'places', hints) and true or false
end

--- Merge walk findings with previous learns.
local function rememberHints(found)
    if type(found) ~= 'table' or next(found) == nil then
        return
    end
    local merged = learnedHints()
    local added = 0
    for id, places in pairs(found) do
        merged[id] = places
        added = added + 1
    end
    if writeHints(merged) then
        out('remembered where %d operator(s) the tables could not place actually '
            .. 'stand; the next load opens their cell instead of walking', added)
    end
end

--- Remember where an operator the player is talking to actually stands.
-- It corrects as well as adds, and by the same rule: what is written down
-- has to agree with where they are standing.
-- Learning something means the graph in hand was built from a table now
-- known to be wrong, so it is thrown away and built again in the background.
local function noteOperator(actor)
    if actor == nil or type(actor.recordId) ~= 'string' then
        return
    end
    local hint = adapter.hintFor(actor.cell)
    if hint == nil then
        return
    end
    local id = string.lower(actor.recordId)
    local learned = learnedHints()
    if adapter.knowsPlacement(id, hint, learned) then
        return
    end
    learned[id] = { hint }
    if not writeHints(learned) then
        return
    end
    out('%s stands somewhere the tables did not say; remembered', id)
    return true
end

-- The cell walk, part-done. nil either before it starts or once it has
-- finished and `cached` holds the answer.
local scan = nil
-- The walk the hinted pass handed back rather than doing, and the coroutine
-- running it. Both nil on a load order the tables cover, which is the point.
local owedWalk = nil
local walkScan = nil
local walkStarted = nil
-- What the hinted pass placed, kept so the walk's findings can be added to it
-- without asking the tables a second time.
local hintedOperators = nil
local scanStarted = nil
-- What the scan did, filled in as it goes.
local scanReport = {}
-- Whether the next scan ignores the shipped table, settled once.
local ignoreHints = nil

-- Kept only to be logged.
local slices = 0
local longestSlice = 0
local lastReport = 0
-- How far the walk had got at the last yield, so the guard can say what it
-- is about to do rather than only that it is doing something.
local lastDone, lastTotal = 0, nil

--- Everything after the cell walk: not worth slicing.
local assembleSeconds = 0

local function assemble(operators)
    rememberHints(scanReport.learned)
    local started = core.getRealTime()
    local built = graph.build(operators)
    graph.link(built, walk.links(interiorStops(built), adapter.doorsFor))
    assembleSeconds = core.getRealTime() - started
    scan = nil
    cached = built
    return built
end

--- Fold what the deferred walk found into the graph the tables gave.
local function absorb(found)
    walkScan, owedWalk = nil, nil
    if found == nil or #found == 0 then
        out('the walk found none of them; the network is unchanged')
        hintedOperators = nil
        return cached
    end
    local operators = {}
    for _, operator in ipairs(hintedOperators or {}) do
        operators[#operators + 1] = operator
    end
    for _, operator in ipairs(found) do
        operators[#operators + 1] = operator
    end
    hintedOperators = nil
    local before = cached and cached.stats.nodes or 0
    local built = assemble(operators)
    -- The walk's report counts only what the walk found. The line reportScan
    -- prints is about the network, so it gets the whole of it.
    scanReport.operators = #operators
    out('the walk added %d operator(s): %d stops, %d legs (was %d stops)',
        #found, built.stats.nodes, built.stats.edges, before)
    return built
end

--- Push the cell walk along, for at most `budget` real seconds.
--
-- A nil budget means run it out here and now, which is what every caller
-- that has to return an answer does.
--
-- @return the finished graph, or nil while there is still walking to do
local function advance(budget)
    if cached then
        return cached
    end
    if scan == nil then
        if ignoreHints == nil then
            ignoreHints = searchEverything()
        end
        scanReport = {}
        scan = adapter.operatorScan({
            ignoreHints = ignoreHints,
            deferWalk = true,
            learned = learnedHints(),
            report = scanReport,
        })
        scanStarted = core.getRealTime()
    end
    local sliceStarted = core.getRealTime()
    local ok, result, done, total = coroutine.resume(scan, budget and (sliceStarted + budget) or nil)
    local slice = core.getRealTime() - sliceStarted
    if slice > longestSlice then
        longestSlice = slice
    end
    slices = slices + 1
    if not ok then
        -- A graph that cannot be built must not be retried every frame for
        -- the rest of the session. An empty one is wrong but quiet, and the
        -- log says why.
        out('graph build failed: %s', tostring(result))
        return assemble({})
    end
    if coroutine.status(scan) == 'dead' then
        local found = result or {}
        if scanReport.owed then
            hintedOperators = found
            owedWalk = scanReport.owed
        end
        return assemble(found)
    end

    if result == 'cells' then
        lastDone, lastTotal = done, total
    end

    local now = core.getRealTime()
    if now - lastReport >= config.BUILD_REPORT_SECONDS then
        lastReport = now
        out('  building: %s %s/%s, %d slice(s) in %.0fs, longest %.0fms',
            tostring(result), tostring(done), tostring(total or '?'),
            slices, now - (scanStarted or now), longestSlice * 1000)
    end
    return nil
end

--- Push the deferred walk along, for at most `budget` real seconds.
--
-- A nil budget runs it out here and now, which is what a traveller standing
-- in front of an operator the graph does not know does.
--
-- @return the rebuilt graph when the walk finished on this call, else nil
local function advanceWalk(budget)
    if owedWalk == nil then
        return nil
    end
    if walkScan == nil then
        walkScan = adapter.walkScan(owedWalk, { report = scanReport })
        walkStarted = core.getRealTime()
        out('%d record(s) the tables could not place; walking for them in the '
            .. 'background', scanReport.unaccounted or 0)
    end
    local sliceStarted = core.getRealTime()
    local ok, result, done, total = coroutine.resume(
        walkScan, budget and (sliceStarted + budget) or nil)
    local slice = core.getRealTime() - sliceStarted
    if slice > longestSlice then
        longestSlice = slice
    end
    slices = slices + 1
    if not ok then
        -- The graph built from the tables is still good; only the corrections
        -- are lost. Said once and then dropped, rather than retried forever.
        out('the deferred walk failed: %s', tostring(result))
        walkScan, owedWalk, hintedOperators = nil, nil, nil
        return nil
    end
    if coroutine.status(walkScan) == 'dead' then
        return absorb(result)
    end
    if result == 'cells' then
        lastDone, lastTotal = done, total
    end
    local now = core.getRealTime()
    if now - lastReport >= config.BUILD_REPORT_SECONDS then
        lastReport = now
        out('  walking: %s/%s, %d slice(s) in %.0fs, longest %.0fms',
            tostring(done), tostring(total or '?'),
            slices, now - (walkStarted or now), longestSlice * 1000)
    end
    return nil
end

--- Finish deferred walk now (blocking).
-- @return the graph, rebuilt if the walk changed anything
local function finishWalk(why)
    if owedWalk == nil then
        return cached
    end
    out('%s; finishing the deferred walk now', why)
    local started = core.getRealTime()
    local built = advanceWalk(nil)
    out('  the walk took %.3fs', core.getRealTime() - started)
    return built or cached
end

-- The guard for a player who reaches a travel service before the build has
-- finished. What it has to finish is now only the hinted pass.
local function current()
    if cached then
        return cached
    end
    if scan then
        out('a travel service was reached before the tables had been read; '
            .. 'finishing that now')
    else
        out('a travel service was reached before the graph was started; building it now')
    end
    return advance(nil)
end

--- Which of the two ways of finding operators actually ran, and what it cost.
-- one that worked.
local function reportScan()
    local r = scanReport
    out('  %d record(s) read, %d offer travel, %d operator(s) placed',
        r.records or 0, r.offerTravel or 0, r.operators or 0)
    local outstanding = (r.unaccounted or 0) - (r.found or 0)
    if r.ignoredHints then
        out('  every record searched for by setting: %d cell(s) walked of %d',
            r.walked or 0, r.cells or 0)
    elseif (r.walked or 0) > 0 then
        out('  shipped table: %d cell(s) opened, %d record(s) unaccounted, '
            .. 'then %d cell(s) walked of %d', r.hinted or 0, r.unaccounted or 0,
            r.walked, r.cells or 0)
        -- The walk this falls back to costs seconds on a cold load, so the
        -- entry that caused it is worth naming rather than counting.
        local ids = r.unaccountedIds or {}
        if #ids > 0 then
            local named, more = ids, ''
            if #ids > 12 then
                named, more = {}, string.format(' and %d more', #ids - 12)
                for index = 1, 12 do
                    named[index] = ids[index]
                end
            end
            out('  not where data/operators.lua says, so the world was walked: %s%s',
                table.concat(named, ', '), more)
        end
        -- Found means the walk could stop.
        if outstanding > 0 then
            out('  %d of those were never found, which is why the walk ran to '
                .. 'the end', outstanding)
        end
    else
        out('  shipped table: %d cell(s) opened, all accounted for, no walk needed',
            r.hinted or 0)
    end
end

--- Two things a built graph cannot tell you on its own:
-- an operator the shipped table skip
-- a record standing in two cells
local function reportBlindSpots(g)
    if #g.duplicated > 0 then
        out('%d operator record(s) stand in more than one cell; the planner '
            .. 'opens from one of them whichever is talked to: %s',
            #g.duplicated, table.concat(g.duplicated, ', '))
    end
    if not searchEverything() then
        local skipped = adapter.standNowhere()
        if #skipped > 0 then
            out('%d record(s) offer travel and are placed nowhere in the shipped '
                .. 'data, so they were not looked for. Tick "Search every cell" '
                .. 'if your load order places one: %s',
                #skipped, table.concat(skipped, ', '))
        end
    end
end

--- Rebuild graph here and now (console only).
local function rebuild()
    cached = nil
    scan = nil
    walkScan, owedWalk, hintedOperators = nil, nil, nil
    ignoreHints = searchEverything()
    slices, longestSlice, lastReport = 0, 0, 0
    lastDone, lastTotal = 0, nil

    local started = core.getRealTime()
    local g = advance(nil)
    -- The console asked for the whole thing, so the deferral does not apply.
    g = finishWalk('rebuilding in one go') or g
    local elapsed = core.getRealTime() - started
    if g then
        out('rebuilt in one go: %.3fs (%.3fs scanning, %.3fs assembling)',
            elapsed, elapsed - assembleSeconds, assembleSeconds)
        out('  %d stops, %d legs', g.stats.nodes, g.stats.edges)
        reportScan()
        reportBlindSpots(g)
    end
    return g
end

--- Trigger background rebuild (for full-search setting).
local function rebuildInBackground()
    cached = nil
    scan = nil
    walkScan, owedWalk, hintedOperators = nil, nil, nil
    -- Read once, here, and handed to the scan. The message below is then a
    -- report of what will happen rather than a second guess at it.
    ignoreHints = searchEverything()
    slices, longestSlice, lastReport = 0, 0, 0
    lastDone, lastTotal = 0, nil
    out('the travel network will be rebuilt%s',
        ignoreHints and ', searching every cell' or '')
end

-- Ticking the setting rebuilds, so it reads as an action.
if I.Settings and I.Settings.registerGroup then
    local ok = pcall(function()
        storage.globalSection(SETTINGS):subscribe(async:callback(function(_, key)
            if key == nil or key == 'fullSearch' then
                rebuildInBackground()
            end
        end))
    end)
    if not ok then
        out('could not watch the full-search setting; it will apply on the next load')
    end
end

--- Every stop, what meets there, and how many legs leave it.
-- @param opts optional { legs = true } to list each leg under its stop
local function dump(opts)
    opts = opts or {}
    local g = current()

    out('%d stops, %d legs (%d on foot), from %d operators (%d unplaced, %d excluded, %d doubled)',
        g.stats.nodes, g.stats.edges, g.stats.walkLegs or 0,
        g.stats.operators, g.stats.unplaced, g.stats.excluded, #g.duplicated)

    for _, key in ipairs(g.order) do
        local node = g.nodes[key]
        local modes = graph.modesAt(g, key)
        local onFoot = graph.modesWithinWalk(g, key)
        local legs = graph.edgesFrom(g, key)
        local note = ''
        if graph.isTransfer(g, key) then
            note = '  <- interchange'
        elseif #onFoot > #modes then
            -- Reachable on foot is not the same as meeting here, and the
            -- planner should never blur the two.
            note = '  (' .. table.concat(onFoot, '+') .. ' within a walk)'
        end
        out('  %-46s %-22s out=%d%s', node.name, table.concat(modes, '+'), #legs, note)
        if opts.legs then
            for _, leg in ipairs(legs) do
                out('        -> %-40s %-10s %6.0f  (%s)',
                    g.nodes[leg.to].name, leg.mode, leg.distance, leg.operatorName or leg.operator)
            end
        end
    end
end

--- Where a player can change vehicle -- counted as places, not as stops, so a
-- guild hall and the street outside it are one junction.
local function interchanges()
    return graph.interchanges(current())
end

local function dumpInterchanges()
    local found = interchanges()
    out('%d interchange(s)', #found)
    for _, stop in ipairs(found) do
        out('  %-30s %-24s %s', stop.name, table.concat(stop.modes, '+'),
            stop.onFoot and 'change costs a walk' or 'vehicles meet here')
        if #stop.stops > 1 then
            local names = {}
            for _, key in ipairs(stop.stops) do
                names[#names + 1] = current().nodes[key].name
            end
            out('        %s', table.concat(names, '  +  '))
        end
    end
end

--- Route options with the game's own travel rate filled in, so a journey
-- quoted at the console is priced the same as one quoted in the window.
local function priced(opts)
    opts = opts or {}
    if opts.farePerUnit == nil then
        opts.farePerUnit = adapter.travelRate()
    end
    return opts
end

--- The cheapest journey between two stops, by key.
local function findRoute(fromKey, toKey, opts)
    return route.find(current(), fromKey, toKey, priced(opts))
end

local function describe(g, leg)
    return string.format('    %-8s %-34s -> %-34s %7.0f  %s', leg.mode,
        g.nodes[leg.from].name, g.nodes[leg.to].name, leg.distance,
        leg.operatorName or leg.operator or 'on foot')
end

--- Print a journey, or say plainly that there is not one.
local function dumpRoute(fromKey, toKey, opts)
    local g = current()
    if g.nodes[fromKey] == nil then
        out('no stop keyed %s', tostring(fromKey))
        return
    end
    if g.nodes[toKey] == nil then
        out('no stop keyed %s', tostring(toKey))
        return
    end

    local found = findRoute(fromKey, toKey, opts)
    if found == nil then
        out('%s -> %s: no route within %d legs',
            g.nodes[fromKey].name, g.nodes[toKey].name, config.MAX_ROUTE_LEGS)
        return
    end

    out('%s -> %s: %d leg(s), %d transfer(s), %.0f units, %.1f h, %d gold',
        g.nodes[fromKey].name, g.nodes[toKey].name, #found.legs, found.transfers,
        found.distance, found.hours, found.fare)
    for _, leg in ipairs(found.legs) do
        out('%s', describe(g, leg))
    end
end

--- Everywhere you can get to from a stop, cheapest first -- the planner's own
-- list, in the console.
local function dumpDestinations(fromKey)
    local g = current()
    if g.nodes[fromKey] == nil then
        out('no stop keyed %s', tostring(fromKey))
        return
    end
    local list = route.destinations(g, fromKey, priced())
    out('from %s: %d stop(s) reachable', g.nodes[fromKey].name, #list)
    for _, stop in ipairs(list) do
        out('  %-46s %d leg(s) %-24s %.1f h  %d gold', stop.name, #stop.legs,
            table.concat(stop.modes, '+'), stop.hours, stop.fare)
    end
end

--- The player's settings, in the shape route.lua takes.
local function preferencesFrom(data)
    local sent = data and data.preferences or {}
    local function positive(value)
        local number = tonumber(value)
        if number and number >= 0 then
            return number
        end
        return nil
    end
    return {
        legSurcharge = positive(sent.legSurcharge),
        modeChangeSurcharge = positive(sent.modeChangeSurcharge),
        -- Not a setting and not the player's to send.
        farePerUnit = adapter.travelRate(),
    }
end

--- The last plan built, and what it was built from.
local lastPlan, lastKey, lastGraph = nil, nil, nil

local function planFor(g, originKey, options)
    local key = string.format('%s|%s|%s|%s|%s', originKey,
        tostring(options.legSurcharge), tostring(options.modeChangeSurcharge),
        tostring(options.farePerUnit), tostring(options.limit))
    -- Compared by identity, so a rebuilt graph throws its plan away without
    -- anyone having to remember to.
    if lastGraph ~= g or lastKey ~= key then
        lastPlan, lastKey, lastGraph = plan.build(g, originKey, options), key, g
    end
    return lastPlan
end

--- Answer plan request (note operator placement).
-- A correction here lands in the graph the next conversation asks for,
-- not this one: the rebuild it starts runs in the background.
local function onRequestPlan(data)
    local player = data and data.player
    if player == nil then
        return
    end
    if data.actor and noteOperator(data.actor) then
        rebuildInBackground()
    end
    local g = current()
    local operator = data.actor and graph.stopOf(g, data.actor.recordId)
    if operator == nil and data.actor and owedWalk then
        -- What the deferred walk is actually for. Somebody who sells
        -- travel is standing here and the graph has never heard of them.
        g = finishWalk('a travel service the tables do not place was reached')
        operator = graph.stopOf(g, data.actor.recordId)
    end
    if operator == nil then
        player:sendEvent(events.PLAN, {})
        return
    end
    local options = preferencesFrom(data)
    options.limit = data.limit
    local built = planFor(g, operator.key, options)
    if built == nil then
        player:sendEvent(events.PLAN, {})
        return
    end
    player:sendEvent(events.PLAN, { origin = built.origin, stops = built.stops })
end

--- Operator classes and their declarations (diagnostic).
--
-- Diagnostic, and the way to find out what a real load order actually
-- contains rather than guessing at it.
local function dumpClasses()
    local modes = require('scripts.TravelAgents.data.modes')
    local seen = {}
    for _, operator in ipairs(adapter.operators()) do
        local class = (operator.class or ''):lower()
        seen[class] = seen[class] or { count = 0, example = operator.name }
        seen[class].count = seen[class].count + 1
    end

    local names = {}
    for class in pairs(seen) do
        names[#names + 1] = class
    end
    table.sort(names)

    out('--- operator classes -----------------------------------')
    local unclaimed = 0
    for _, class in ipairs(names) do
        local entry = seen[class]
        local known = modes.classes[class]
        if not known then
            unclaimed = unclaimed + 1
        end
        out('  %-24s %3d operator(s)  %s%s',
            class == '' and '(no class)' or class, entry.count,
            known and ('-> ' .. known.label) or '-> own tab, named after the class',
            known and '' or string.format('   e.g. %s', tostring(entry.example)))
    end
    out('%d class(es), %d not claimed by data/modes.lua', #names, unclaimed)
    out('--------------------------------------------------------')
end

--- Build graph incrementally in background.
--
-- The build walks every cell in the load order looking for placed
-- operators, because a travel destination lives on a record and the near
-- end of every edge does not
-- It is done a slice at a time while the player gets on with whatever
-- they were doing. `current` is the guard for anyone who arrives
-- before it is finished.
local function warmUp()
    if cached then
        -- The graph is up and answering; anything still owed is the walk,
        -- and it gets the same slice the build had.
        advanceWalk(config.BUILD_SLICE_SECONDS)
        return
    end
    local g = advance(config.BUILD_SLICE_SECONDS)
    if g then
        out('graph ready: %d stops, %d legs', g.stats.nodes, g.stats.edges)
        out('  %.2fs of play, %d slice(s), longest %.0fms, assembling %.0fms',
            core.getRealTime() - (scanStarted or 0), slices,
            longestSlice * 1000, assembleSeconds * 1000)
        reportScan()
        reportBlindSpots(g)
    end
end

--- Book and execute a journey.
local function onBook(data)
    local player = data and data.player
    if player == nil then
        return
    end
    local g = current()
    local operator = data.actor and graph.stopOf(g, data.actor.recordId)
    if operator == nil then
        player:sendEvent(events.BOOKED, { ok = false, reason = 'operator' })
        return
    end

    -- The same preferences the plan was drawn with, so the fare charged is the
    -- fare the window showed.
    local options = preferencesFrom(data)
    options.gold = money.held(player)
    local quote = route.quote(g, operator.key, data.to, options)
    -- Only what a refusal has to say. Arriving is silent.
    local answer = {
        ok = quote.ok,
        reason = quote.reason,
        fare = quote.fare,
        short = quote.short,
    }
    if not quote.ok then
        player:sendEvent(events.BOOKED, answer)
        return
    end

    -- Move first, charge second.
    if not adapter.arrive(player, quote.arrival) then
        answer.ok, answer.reason = false, 'arrival'
        player:sendEvent(events.BOOKED, answer)
        return
    end
    money.take(player, quote.fare)
    adapter.advanceTime(quote.hours)
    -- Asked for rather than done here: the player's own script is the only
    -- context allowed to write their dynamic stats.
    player:sendEvent(events.RESTORE, { rests = quote.rests })
    -- Said out loud for anyone who cares. See events.lua.
    player:sendEvent(events.ARRIVED, {
        class = operator.class,
        place = quote.arrival and quote.arrival.name,
        hours = quote.hours,
    })
    player:sendEvent(events.BOOKED, answer)
end

return {
    interfaceName = 'TravelAgents',
    interface = {
        graph = current,
        rebuild = rebuild,
        dump = dump,
        interchanges = interchanges,
        dumpInterchanges = dumpInterchanges,
        -- Queries re-exported so a caller holding a graph does not have to
        -- require an internal module to ask anything about it.
        route = findRoute,
        destinations = function(fromKey, opts)
            return route.destinations(current(), fromKey, priced(opts))
        end,
        dumpRoute = dumpRoute,
        dumpDestinations = dumpDestinations,
        dumpClasses = dumpClasses,
        modesAt = graph.modesAt,
        modesWithinWalk = graph.modesWithinWalk,
        edgesFrom = graph.edgesFrom,
        isTransfer = graph.isTransfer,
    },
    engineHandlers = {
        onUpdate = warmUp,
    },
    eventHandlers = {
        [events.REQUEST_PLAN] = onRequestPlan,
        [events.BOOK] = onBook,
    },
}
