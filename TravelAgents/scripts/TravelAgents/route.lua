-- Finding the way from one stop to another.
-- Dijkstra, but over (stop, mode) pairs rather than stops alone.
-- Cost is in game units
local config = require('scripts.TravelAgents.config')
local modesData = require('scripts.TravelAgents.data.modes')
local graph = require('scripts.TravelAgents.graph')

local M = {}

local function stateKey(nodeKey, mode)
    return nodeKey .. '|' .. mode
end

--- What it costs to take this leg, having arrived on `arrivedBy`
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
        farePerUnit = opts.farePerUnit or config.FARE_PER_UNIT,
        legSurcharge = opts.legSurcharge or config.FARE_LEG_SURCHARGE,
        modeChangeSurcharge = opts.modeChangeSurcharge or config.FARE_MODE_CHANGE_SURCHARGE,
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

--- Add up a journey: how far, how long, what it asks of the traveller, and
-- what it costs once the convenience of buying it in one go is priced in.
local function summarise(legs, opts)
    local summary = {
        legs = legs,
        transfers = math.max(#legs - 1, 0),
        distance = 0,
        walked = 0,
        hours = 0,
        fare = 0,
        modes = {},
        -- Two legs are not the same as two vehicles.
        vehicleLegs = 0,
        modeChanges = 0,
        -- Whether the traveller spent the journey aboard something that
        -- took time. Vanilla treats such a trip as a rest -- health,
        -- magicka and fatigue all come back -- while a guild guide is a
        -- wait and returns fatigue alone.
        rests = false,
    }
    local lastVehicle = nil
    for index, leg in ipairs(legs) do
        summary.distance = summary.distance + leg.distance
        -- A teleport covers its distance in no time at all, so its length
        -- prices the ticket and not the clock. Charging hours for a guild
        -- guide would make the mod strictly worse than the service it
        -- replaces: vanilla puts you in Balmora at the hour you left.
        if not modesData.instant[leg.mode] then
            summary.hours = summary.hours + leg.distance * config.HOURS_PER_UNIT
            if leg.mode ~= 'walk' then
                -- Time spent aboard something. This is what makes the
                -- journey a rest rather than a wait.
                summary.rests = true
            end
        end
        if leg.mode == 'walk' then
            summary.walked = summary.walked + leg.distance
        else
            -- Nobody charges for a door: the base fare is distance ridden.
            summary.fare = summary.fare + leg.distance * opts.farePerUnit
            summary.vehicleLegs = summary.vehicleLegs + 1
            if lastVehicle ~= nil and leg.mode ~= lastVehicle then
                summary.modeChanges = summary.modeChanges + 1
            end
            lastVehicle = leg.mode
        end
        if index == 1 or leg.mode ~= legs[index - 1].mode then
            summary.modes[#summary.modes + 1] = leg.mode
        end
    end

    -- The legs are what they are; the ticket costs more than their sum..
    local extraLegs = math.max(summary.vehicleLegs - 1, 0)
    local extra = extraLegs * opts.legSurcharge + summary.modeChanges * opts.modeChangeSurcharge
    summary.baseFare = math.floor(summary.fare + 0.5)
    summary.fare = math.floor(summary.fare * (1 + extra) + 0.5)
    summary.surcharge = summary.fare - summary.baseFare
    summary.surchargePercent = math.floor(extra * 100 + 0.5)
    return summary
end

--- Every stop reachable from `fromKey`, cheapest first.
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
            local summary = summarise(legs, opts)
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
        local summary = summarise({}, options(opts))
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
