-- TravelAgents -- global script.
--
-- The graph is built here because only global scripts may walk cells, and
-- journeys are sold here because only global scripts may move the player, take
-- their gold or advance the clock. The window that asks for both lives in
-- player.lua and is told nothing it could get wrong.

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
    if select('#', ...) > 0 then
        print(TAG .. ' ' .. string.format(fmt, ...))
    else
        print(TAG .. ' ' .. fmt)
    end
end

--- Stops that sit inside a building, which are the ones needing a way out.
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
-- The escape hatch
--------------------------------------------------------------------------
--
-- data/operators.lua says where the known travel services stand, and the
-- scan opens one cell each rather than all ten thousand. Anything the table
-- does not account for already sends it round every cell -- but that rests
-- on the mod having spotted the operator in the first place, and this is
-- for when it has not.
--
-- Turning it on searches every cell regardless of what the table says. It
-- costs half a minute of background work per load and is the behaviour the
-- mod had before the table existed, so it can only find more, never less.
--
-- A global group rather than a player one: the graph is global, and a
-- global script may register a group. It may not register a *page* -- that
-- is a screen and needs a context that can draw one -- so the page comes
-- from player.lua and this only attaches to it.
local SETTINGS = 'SettingsGlobalTravelAgents'

-- Behind a pcall because this runs at file scope: were an engine to refuse a
-- group naming a page a *player* script registers, the raise would take the
-- whole global script with it -- no graph, no booking, no interface. That
-- combination is checked working (openmw-lua-notes.md, section 11), but a
-- mod that loses a checkbox fails far better than one that does not load.
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

local function searchEverything()
    local ok, value = pcall(function()
        return storage.globalSection(SETTINGS):get('fullSearch')
    end)
    return ok and value == true
end

-- The cell walk, part-done. nil either before it starts or once it has
-- finished and `cached` holds the answer.
local scan = nil
local scanStarted = nil
-- What the scan did, filled in as it goes. The hinted path and the full walk
-- build the same graph at wildly different cost, so without this the only way
-- to tell which one ran is to time it and do arithmetic.
local scanReport = {}
-- Whether the next scan ignores the shipped table, settled once. The message
-- announcing a rebuild and the scan that carries it out used to read the
-- setting separately, which meant they could disagree and nothing would say
-- so.
local ignoreHints = nil

-- Kept only to be logged. The whole point of slicing is that no single
-- slice is long enough to see, and the only way to know whether that held
-- on someone else's load order is to say so when the graph is ready.
local slices = 0
local longestSlice = 0
local lastReport = 0
-- How far the walk had got at the last yield, so the guard can say what it
-- is about to do rather than only that it is doing something.
local lastDone, lastTotal = 0, nil

--- Everything after the cell walk: cheap, and not worth slicing.
--
-- Vehicles first, then the doors joining the stops inside buildings to the
-- streets outside them. Order matters: a walk link needs the stop it starts
-- from to exist.
local assembleSeconds = 0

local function assemble(operators)
    local started = core.getRealTime()
    local built = graph.build(operators)
    graph.link(built, walk.links(interiorStops(built), adapter.doorsFor))
    assembleSeconds = core.getRealTime() - started
    scan = nil
    cached = built
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
        scan = adapter.operatorScan({ ignoreHints = ignoreHints, report = scanReport })
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
        return assemble(result or {})
    end

    -- Say how it is going, occasionally. Without this the only way to know
    -- whether the budget is being spent is to wait and see whether the graph
    -- ever turns up, which is what happened.
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

--- The graph, whatever it takes.
--
-- The guard for a player who reaches a travel service before the walk has
-- finished: rather than answer from a half-built graph, or make them wait
-- for a frame that a paused game may never run, the rest of the walk happens
-- now. That is the stall this whole change exists to avoid -- but it is only
-- ever the part not already done, it is logged so it can be told apart from
-- the old behaviour, and walking anywhere for a second or two after load
-- makes it impossible.
local function current()
    if cached then
        return cached
    end
    if scan and lastTotal then
        out('a travel service was reached with %d of %d cells walked; '
            .. 'finishing the last %d now', lastDone, lastTotal, lastTotal - lastDone)
    else
        out('a travel service was reached before the graph was started; building it now')
    end
    return advance(nil)
end

--- Throw the graph away and build another, here and now.
-- Asked for from the console, where waiting for it is the point.
local function rebuild()
    cached = nil
    scan = nil
    ignoreHints = searchEverything()
    slices, longestSlice, lastReport = 0, 0, 0
    lastDone, lastTotal = 0, nil
    return advance(nil)
end

--- Throw the graph away and let it be built again in the background.
--
-- What ticking the full-search setting does. Rebuilding on the spot would
-- freeze the game for as long as the search takes, which is the thing this
-- whole area of the mod exists to avoid.
local function rebuildInBackground()
    cached = nil
    scan = nil
    -- Read once, here, and handed to the scan. The message below is then a
    -- report of what will happen rather than a second guess at it.
    ignoreHints = searchEverything()
    slices, longestSlice, lastReport = 0, 0, 0
    lastDone, lastTotal = 0, nil
    out('the travel network will be rebuilt%s',
        ignoreHints and ', searching every cell' or '')
end

-- Ticking the setting rebuilds, so it reads as an action rather than a
-- preference that waits for a restart.
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
--
-- Only the two surcharges: they price a journey and nothing else, so the
-- route the planner finds no longer depends on anything the player can set.
-- The routing penalties live in config.lua.
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
--
-- A plan is a pure function of the graph, the stop it starts from and what
-- the counter charges. The traveller's gold is not in it -- the window asks
-- for that when it draws -- and the route stopped depending on any player
-- setting when the routing penalties became constants.
--
-- One entry rather than a table of them, because a plan holds a row per
-- reachable stop and keeping one per operator would pin a few hundred of
-- those for the session. What actually repeats is a single conversation:
-- reopened, or asked twice because the key was pressed before the first
-- answer came back.
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

--- Answer a player script asking where a conversation could take them.
local function onRequestPlan(data)
    local player = data and data.player
    if player == nil then
        return
    end
    local g = current()
    local operator = data.actor and graph.stopOf(g, data.actor.recordId)
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

--- Every operator class in the load order, and whether the mod knows it.
--
-- The mode a vehicle is filed under comes from its operator's class, which
-- is a string a content pack's author typed. Vanilla's four are known; a
-- landmass mod inventing a guar caravan is not, and the tab it gets is
-- named after the raw class until data/modes.lua claims it.
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

--- Which of the two ways of finding operators actually ran, and what it cost.
--
-- The hinted path opens one cell per known operator; the full walk opens
-- every cell in the load order. They produce the same graph and differ by two
-- orders of magnitude in cost, and the log used to distinguish them not at
-- all -- so a setting that silently failed to take effect looked exactly like
-- one that worked.
local function reportScan()
    local r = scanReport
    out('  %d record(s) read, %d offer travel, %d operator(s) placed',
        r.records or 0, r.offerTravel or 0, r.operators or 0)
    if r.ignoredHints then
        out('  every cell searched by setting: %d cell(s) walked', r.walked or 0)
    elseif (r.walked or 0) > 0 then
        out('  shipped table: %d cell(s) opened, %d record(s) unaccounted, '
            .. 'then %d cell(s) walked', r.hinted or 0, r.unaccounted or 0, r.walked)
    else
        out('  shipped table: %d cell(s) opened, all accounted for, no walk needed',
            r.hinted or 0)
    end
end

--- The two things a built graph cannot tell you on its own.
--
-- Both are silent by nature: an operator the shipped table skips is one
-- nobody looks for, and a record standing in two cells resolves to one of
-- them without complaint. Said once per build so that a missing boat has
-- somewhere to start.
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

--- Build the graph before anything asks for it.
--
-- The build walks every cell in the load order looking for placed
-- operators, because a travel destination lives on a record and the near
-- end of every edge does not -- it is wherever the operator is standing.
-- That is seconds of work on Tamriel Rebuilt.
--
-- Doing it lazily meant paying for it on the first conversation with a
-- travel NPC, which is the worst possible moment: the game appears to hang,
-- mid-greeting, on the one interaction the mod exists to improve. Doing it
-- in one piece on the first frame after load only moved the hang.
--
-- So it is done a slice at a time, from here, while the player gets on with
-- whatever they were doing. `current` is the guard for anyone who arrives
-- before it is finished.
local function warmUp()
    if cached then
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

--- Sell a journey and make it.
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
    local answer = {
        ok = quote.ok,
        reason = quote.reason,
        fare = quote.fare,
        short = quote.short,
        hours = quote.hours,
        legs = quote.legs,
        transfers = quote.transfers,
        place = quote.arrival and quote.arrival.name,
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
