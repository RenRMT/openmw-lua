-- The journey plan, as data.
--
-- Pure, and deliberately the whole of what crosses between contexts: the
-- graph lives in the global script because only global scripts may walk
-- cells, while the window lives in the player script because only local
-- scripts may draw. This is the thing that travels between them, so it holds
-- names and numbers and nothing that would need the engine to read.

local graphlib = require('scripts.TravelNetwork.graph')
local modesData = require('scripts.TravelNetwork.data.modes')
local route = require('scripts.TravelNetwork.route')

local M = {}

local function legOf(graph, leg, modes)
    return {
        mode = leg.mode,
        modeLabel = graphlib.modeLabel(leg.mode, modes),
        from = graph.nodes[leg.from].name,
        to = graph.nodes[leg.to].name,
        distance = leg.distance,
        operator = leg.operatorName or leg.operator,
    }
end

--- Everywhere reachable from a stop, cheapest first, in a shape a window can
-- render without asking the graph anything further.
--
-- @param graph the built graph
-- @param originKey where the player is starting from
-- @param opts optional { modes = <modes table>, limit = <max stops> } plus
--   anything route.destinations takes
function M.build(graph, originKey, opts)
    opts = opts or {}
    local modes = opts.modes or modesData
    local origin = graph.nodes[originKey]
    if origin == nil then
        return nil
    end

    local plan = {
        origin = {
            key = originKey,
            name = origin.name,
            modes = graphlib.modesWithinWalk(graph, originKey),
            isTransfer = graphlib.isTransfer(graph, originKey),
        },
        stops = {},
    }

    for _, stop in ipairs(route.destinations(graph, originKey, opts)) do
        local legs = {}
        for _, leg in ipairs(stop.legs) do
            legs[#legs + 1] = legOf(graph, leg, modes)
        end
        plan.stops[#plan.stops + 1] = {
            key = stop.key,
            name = stop.name,
            cost = stop.cost,
            distance = stop.distance,
            walked = stop.walked,
            hours = stop.hours,
            fare = stop.fare,
            transfers = stop.transfers,
            modes = stop.modes,
            legs = legs,
        }
        if opts.limit and #plan.stops >= opts.limit then
            break
        end
    end

    return plan
end

--- A one-line summary of a journey, in the order a player reads it: how many
-- changes, how long, what it costs.
function M.summarise(stop)
    local changes
    if stop.transfers == 0 then
        changes = 'direct'
    elseif stop.transfers == 1 then
        changes = '1 change'
    else
        changes = string.format('%d changes', stop.transfers)
    end
    return string.format('%s, %.1f h, %d gold', changes, stop.hours, stop.fare)
end

--- One leg, as a line: what carries you, and where it leaves you.
function M.describeLeg(leg)
    if leg.mode == 'walk' then
        return string.format('walk to %s', leg.to)
    end
    return string.format('%s to %s (%s)', leg.modeLabel, leg.to, leg.operator or '?')
end

return M
