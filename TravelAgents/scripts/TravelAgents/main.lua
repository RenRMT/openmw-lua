-- TravelAgents -- global script.
--
-- The graph is built here because only global scripts may walk cells, and
-- journeys are sold here because only global scripts may move the player, take
-- their gold or advance the clock. The window that asks for both lives in
-- player.lua and is told nothing it could get wrong.

local adapter = require('scripts.TravelAgents.adapter')
local book = require('scripts.TravelAgents.book')
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

local function current()
    if not cached then
        local built = graph.build(adapter.operators())
        -- Vehicles first, then the doors joining the stops inside buildings to
        -- the streets outside them. Order matters: a walk link needs the stop
        -- it starts from to exist.
        graph.link(built, walk.links(interiorStops(built), adapter.doorsFor))
        cached = built
    end
    return cached
end

local function rebuild()
    cached = nil
    return current()
end

--- Every stop, what meets there, and how many legs leave it.
-- @param opts optional { legs = true } to list each leg under its stop
local function dump(opts)
    opts = opts or {}
    local g = current()

    out('%d stops, %d legs (%d on foot), from %d operators (%d unplaced, %d excluded)',
        g.stats.nodes, g.stats.edges, g.stats.walkLegs or 0,
        g.stats.operators, g.stats.unplaced, g.stats.excluded)

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
        transferPenalty = positive(sent.transferPenalty),
        modeChangePenalty = positive(sent.modeChangePenalty),
        legSurcharge = positive(sent.legSurcharge),
        modeChangeSurcharge = positive(sent.modeChangeSurcharge),
        -- Not a setting and not the player's to send.
        farePerUnit = adapter.travelRate(),
    }
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
    local built = plan.build(g, operator.key, options)
    if built then
        built.operator = { name = operator.name, mode = operator.mode }
    end
    player:sendEvent(events.PLAN, built or {})
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
    local quote = book.quote(g, operator.key, data.to, options)
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
    adapter.restoreFatigue(player)
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
        transfersAt = function(key) return route.transfersAt(current(), key) end,
        dumpRoute = dumpRoute,
        dumpDestinations = dumpDestinations,
        modesAt = graph.modesAt,
        modesWithinWalk = graph.modesWithinWalk,
        edgesFrom = graph.edgesFrom,
        isTransfer = graph.isTransfer,
    },
    eventHandlers = {
        [events.REQUEST_PLAN] = onRequestPlan,
        [events.BOOK] = onBook,
    },
}
