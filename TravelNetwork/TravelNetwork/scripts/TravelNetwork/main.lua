-- TravelNetwork -- global script.
--
-- Phase 1: build the graph and let the console look at it. No UI, no routing,
-- no gameplay yet.

local adapter = require('scripts.TravelNetwork.adapter')
local graph = require('scripts.TravelNetwork.graph')
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

--- The stops where more than one mode meets -- the question the mod exists to
-- answer, and in vanilla the answer is three.
local function interchanges()
    local g = current()
    local found = {}
    for _, key in ipairs(g.order) do
        if graph.isTransfer(g, key) then
            found[#found + 1] = { key = key, name = g.nodes[key].name, modes = graph.modesAt(g, key) }
        end
    end
    return found
end

local function dumpInterchanges()
    local found = interchanges()
    out('%d interchange(s)', #found)
    for _, stop in ipairs(found) do
        out('  %-46s %s', stop.name, table.concat(stop.modes, '+'))
    end
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
        modesAt = graph.modesAt,
        modesWithinWalk = graph.modesWithinWalk,
        edgesFrom = graph.edgesFrom,
        isTransfer = graph.isTransfer,
    },
}
