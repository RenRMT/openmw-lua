-- TravelNetwork -- global script.
--
-- Phase 1: build the graph and let the console look at it. No UI, no routing,
-- no gameplay yet.

local adapter = require('scripts.TravelNetwork.adapter')
local config = require('scripts.TravelNetwork.config')
local events = require('scripts.TravelNetwork.events')
local locate = require('scripts.TravelNetwork.locate')
local plan = require('scripts.TravelNetwork.plan')
local graph = require('scripts.TravelNetwork.graph')
local route = require('scripts.TravelNetwork.route')
local walk = require('scripts.TravelNetwork.walk')

local TAG = '[TravelNetwork]'

-- Built once and kept. The sweep behind it costs around 600 ms, and nothing it
-- reads changes during a session: records are static and operators do not move
-- between towns.
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

--- The cheapest journey between two stops, by key.
local function findRoute(fromKey, toKey, opts)
    return route.find(current(), fromKey, toKey, opts)
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

--- Everywhere you can get to from a stop, cheapest first. What the phase 3
-- planner will show, in the only interface phase 2 has.
local function dumpDestinations(fromKey)
    local g = current()
    if g.nodes[fromKey] == nil then
        out('no stop keyed %s', tostring(fromKey))
        return
    end
    local list = route.destinations(g, fromKey)
    out('from %s: %d stop(s) reachable', g.nodes[fromKey].name, #list)
    for _, stop in ipairs(list) do
        out('  %-46s %d leg(s) %-24s %.1f h  %d gold', stop.name, #stop.legs,
            table.concat(stop.modes, '+'), stop.hours, stop.fare)
    end
end

--- Where a player standing here would board.
--
-- Indoors and not at a stop -- a tavern, a shop -- the player's coordinates
-- are cell-local and mean nothing outside the room, so the doors are followed
-- out first and the search starts from the street. That reuses exactly the
-- walk that joins guild halls to their towns.
local function stopNearest(g, player)
    local cell = player.cell
    local where = {
        cellId = cell.id,
        isInterior = not cell.isExterior,
        position = player.position,
    }

    local key, distance = locate.nearest(g, where)
    if key then
        return key, distance
    end
    if not where.isInterior then
        return nil
    end

    local exits = walk.links({ { cellId = cell.id, position = player.position } }, adapter.doorsFor)
    if #exits == 0 then
        return nil
    end
    local exit = exits[1]
    return locate.nearest(g, {
        cellId = exit.point.cellId,
        isInterior = exit.point.isInterior,
        position = exit.point.position,
    })
end

--- Answer a player script asking where it can get to.
local function onRequestPlan(data)
    local player = data and data.player
    if player == nil then
        return
    end
    local g = current()
    local originKey = stopNearest(g, player)
    if originKey == nil then
        player:sendEvent(events.PLAN, {})
        return
    end
    player:sendEvent(events.PLAN, plan.build(g, originKey, { limit = data.limit }))
end

return {
    interfaceName = 'TravelNetwork',
    interface = {
        graph = current,
        rebuild = rebuild,
        dump = dump,
        interchanges = interchanges,
        dumpInterchanges = dumpInterchanges,
        -- Queries re-exported so a caller holding a graph does not have to
        -- require an internal module to ask anything about it.
        route = findRoute,
        destinations = function(fromKey, opts) return route.destinations(current(), fromKey, opts) end,
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
    },
}
