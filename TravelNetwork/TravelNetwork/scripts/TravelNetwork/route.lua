-- Finding the way from one stop to another.
--
-- Pure, like graph.lua and walk.lua: plain tables in, plain tables out.
--
-- Dijkstra, but over (stop, mode) pairs rather than stops alone. What a leg
-- costs depends on how you arrived: staying on the same silt strider is free
-- where changing to a boat is not, and a search that only remembered which
-- stop it was at could not tell those apart. Five modes and 33 stops make that
-- a small price.
--
-- Cost is in game units, so a penalty is expressed as "worth this much of a
-- detour". Distance alone would send a player through three vehicle changes to
-- save a few metres of coastline.

local config = require('scripts.TravelNetwork.config')
local graph = require('scripts.TravelNetwork.graph')

local M = {}

local function stateKey(nodeKey, mode)
    return nodeKey .. '|' .. mode
end

--- What it costs to take this leg, having arrived on `arrivedBy`.
-- Boarding the first leg of a journey is free; every later one is a change of
-- vehicle, and changing to a different *kind* of vehicle costs more again.
local function legCost(edge, arrivedBy, opts)
    local cost = edge.distance
    if arrivedBy ~= nil then
        cost = cost + opts.transferPenalty
        if edge.mode ~= arrivedBy then
            cost = cost + opts.modeChangePenalty
        end
    end
    return cost
end

local function options(opts)
    opts = opts or {}
    return {
        transferPenalty = opts.transferPenalty or config.TRANSFER_PENALTY,
        modeChangePenalty = opts.modeChangePenalty or config.MODE_CHANGE_PENALTY,
        maxLegs = opts.maxLegs or config.MAX_ROUTE_LEGS,
    }
end

--- Walk the search backwards into the list of legs it took.
local function rebuild(states, finalKey)
    local legs = {}
    local state = states[finalKey]
    while state and state.edge do
        table.insert(legs, 1, state.edge)
        state = states[state.from]
    end
    return legs
end

local function summarise(legs)
    local summary = {
        legs = legs,
        transfers = math.max(#legs - 1, 0),
        distance = 0,
        walked = 0,
        hours = 0,
        fare = 0,
        modes = {},
    }
    for index, leg in ipairs(legs) do
        summary.distance = summary.distance + leg.distance
        summary.hours = summary.hours + leg.distance * config.HOURS_PER_UNIT
        if leg.mode == 'walk' then
            summary.walked = summary.walked + leg.distance
        else
            -- Nobody charges for a door. Fares are provisional until phase 5
            -- gives them a formula worth quoting.
            summary.fare = summary.fare + leg.distance * config.FARE_PER_UNIT
        end
        if index == 1 or leg.mode ~= legs[index - 1].mode then
            summary.modes[#summary.modes + 1] = leg.mode
        end
    end
    summary.fare = math.floor(summary.fare + 0.5)
    return summary
end

--- Every stop reachable from `fromKey`, cheapest first.
--
-- The same search `route` runs, stopped at nothing -- which is what the
-- planner needs when it asks "where can I get to from here".
--
-- @return table keyed by stop: { cost, distance, legs, transfers }
function M.reachable(graph_, fromKey, opts)
    opts = options(opts)
    if graph_.nodes[fromKey] == nil then
        return {}
    end

    -- states[stateKey] = { node, mode, cost, legCount, from, edge }
    local states = {}
    local queue = {}

    local function offer(nodeKey, mode, cost, legCount, fromState, edge)
        local key = stateKey(nodeKey, mode)
        local existing = states[key]
        if existing and existing.cost <= cost then
            return
        end
        states[key] = {
            node = nodeKey, mode = mode, cost = cost,
            legCount = legCount, from = fromState, edge = edge,
        }
        queue[#queue + 1] = key
    end

    for _, edge in ipairs(graph.edgesFrom(graph_, fromKey)) do
        offer(edge.to, edge.mode, legCost(edge, nil, opts), 1, nil, edge)
    end

    -- A linear scan for the cheapest pending state. With 33 stops and five
    -- modes a heap would be more code than it saves.
    local settled = {}
    while true do
        local bestKey, bestCost = nil, nil
        for _, key in ipairs(queue) do
            local state = states[key]
            if not settled[key] and (bestCost == nil or state.cost < bestCost) then
                bestKey, bestCost = key, state.cost
            end
        end
        if bestKey == nil then
            break
        end
        settled[bestKey] = true

        local state = states[bestKey]
        if state.legCount < opts.maxLegs then
            for _, edge in ipairs(graph.edgesFrom(graph_, state.node)) do
                if edge.to ~= fromKey then
                    offer(edge.to, edge.mode, state.cost + legCost(edge, state.mode, opts),
                        state.legCount + 1, bestKey, edge)
                end
            end
        end
    end

    -- One entry per stop: the cheapest way to be standing there, whichever
    -- vehicle brought you.
    local best = {}
    for key, state in pairs(states) do
        local current = best[state.node]
        if current == nil or state.cost < current.cost then
            local legs = rebuild(states, key)
            local summary = summarise(legs)
            summary.cost = state.cost
            best[state.node] = summary
        end
    end
    return best
end

--- The cheapest journey between two stops.
-- @return a Route, or nil when there is no way through
function M.find(graph_, fromKey, toKey, opts)
    if graph_.nodes[fromKey] == nil or graph_.nodes[toKey] == nil then
        return nil
    end
    if fromKey == toKey then
        local summary = summarise({})
        summary.cost = 0
        return summary
    end
    return M.reachable(graph_, fromKey, opts)[toKey]
end

--- What you can change to at a stop -- the modes reachable there, walking
-- included, minus nothing. A stop with one entry is a stop you pass through.
function M.transfersAt(graph_, key)
    return graph.modesWithinWalk(graph_, key)
end

--- Reachable stops as a list, cheapest first, for anything that has to show
-- them in order.
function M.destinations(graph_, fromKey, opts)
    local reachable = M.reachable(graph_, fromKey, opts)
    local list = {}
    for key, summary in pairs(reachable) do
        summary.key = key
        summary.name = graph_.nodes[key].name
        list[#list + 1] = summary
    end
    table.sort(list, function(a, b)
        if a.cost ~= b.cost then
            return a.cost < b.cost
        end
        return a.name:lower() < b.name:lower()
    end)
    return list
end

return M
