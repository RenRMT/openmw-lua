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

--- Leg cost, accounting for transfer and mode change penalties.
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

--- Summarize journey: distance, time, what traveller pays (with surcharges).
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
        -- took time. Treated as a rest -- health, magicka and fatigue all
        -- restore -- while a guild guide is a wait, and returns fatigue alone.
        rests = false,
    }
    local lastVehicle = nil
    for index, leg in ipairs(legs) do
        summary.distance = summary.distance + leg.distance
        -- A teleport covers its distance in no time at all, so its length
        -- prices the ticket and not the clock.
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
    -- Sequence number for tie-breaking so cost-equal routes resolve consistently.
    local seen = {}
    local offers = 0

    -- Pending states as a binary min-heap, cheapest at the root. Lazy: a
    -- state that gets cheaper is pushed again rather than moved, and the
    -- stale copy is skipped when it surfaces already settled.
    local heap, heapSize = {}, 0

    local function cheaper(a, b)
        -- Cost first, then sequence for tie-breaking.
        if a.cost ~= b.cost then
            return a.cost < b.cost
        end
        return a.seq < b.seq
    end

    local function push(entry)
        heapSize = heapSize + 1
        heap[heapSize] = entry
        local child = heapSize
        while child > 1 do
            local parent = math.floor(child / 2)
            if not cheaper(heap[child], heap[parent]) then
                break
            end
            heap[parent], heap[child] = heap[child], heap[parent]
            child = parent
        end
    end

    local function pop()
        if heapSize == 0 then
            return nil
        end
        local top = heap[1]
        heap[1] = heap[heapSize]
        heap[heapSize] = nil
        heapSize = heapSize - 1
        local parent = 1
        while true do
            local left, right = parent * 2, parent * 2 + 1
            local least = parent
            if left <= heapSize and cheaper(heap[left], heap[least]) then
                least = left
            end
            if right <= heapSize and cheaper(heap[right], heap[least]) then
                least = right
            end
            if least == parent then
                break
            end
            heap[parent], heap[least] = heap[least], heap[parent]
            parent = least
        end
        return top
    end

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
        if seen[key] == nil then
            offers = offers + 1
            seen[key] = offers
        end
        push({ key = key, cost = cost, seq = seen[key] })
    end

    for _, edge in ipairs(graph.edgesFrom(graph_, fromKey)) do
        offer(edge.to, edge.mode, legCost(edge, nil, opts), 1, nil, edge)
    end

    local settled = {}
    while true do
        local entry = pop()
        if entry == nil then
            break
        end
        -- First state surface is cheapest (later ones are stale pushes).
        if not settled[entry.key] then
            settled[entry.key] = true
            local state = states[entry.key]
            if state.legCount < opts.maxLegs then
                for _, edge in ipairs(graph.edgesFrom(graph_, state.node)) do
                    if edge.to ~= fromKey then
                        offer(edge.to, edge.mode, state.cost + legCost(edge, state.mode, opts),
                            state.legCount + 1, entry.key, edge)
                    end
                end
            end
        end
    end

    -- One entry per stop: cheapest way there. Settled before walking back legs.
    local winner = {}
    for key, state in pairs(states) do
        local held = winner[state.node]
        if held == nil then
            winner[state.node] = key
        else
            local heldCost = states[held].cost
            if state.cost < heldCost or (state.cost == heldCost and seen[key] < seen[held]) then
                winner[state.node] = key
            end
        end
    end

    local best = {}
    for node, key in pairs(winner) do
        local summary = summarise(rebuild(states, key), opts)
        summary.cost = states[key].cost
        best[node] = summary
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

--------------------------------------------------------------------------
-- Buying one
--------------------------------------------------------------------------
--
-- Everything about a purchase that can be decided without the engine.

local function refuse(reason, quote)
    quote = quote or {}
    quote.ok = false
    quote.reason = reason
    return quote
end

--- Quote a journey's cost and feasibility.
-- @param graph_ built graph
-- @param fromKey operator stop
-- @param toKey chosen stop
-- @param opts { gold = <held> } + route.find options
-- @return quote with fare/hours even when refused (reason: 'route' or 'gold')
function M.quote(graph_, fromKey, toKey, opts)
    opts = opts or {}
    if type(fromKey) ~= 'string' or type(toKey) ~= 'string' or fromKey == toKey then
        return refuse('route')
    end
    if graph_.nodes[fromKey] == nil or graph_.nodes[toKey] == nil then
        return refuse('route')
    end

    local journey = M.find(graph_, fromKey, toKey, opts)
    if journey == nil or #journey.legs == 0 then
        return refuse('route')
    end

    -- Where the last leg leaves you, which is not always the stop asked for.
    local arrival = graph_.nodes[journey.legs[#journey.legs].to]
    local quote = {
        ok = true,
        fare = journey.fare,
        baseFare = journey.baseFare,
        surcharge = journey.surcharge,
        surchargePercent = journey.surchargePercent,
        hours = journey.hours,
        -- Whether arriving counts as rest (worked out here, not player-side).
        rests = journey.rests,
        distance = journey.distance,
        walked = journey.walked,
        legs = #journey.legs,
        transfers = journey.transfers,
        arrival = {
            key = arrival.key,
            name = arrival.name,
            cellId = arrival.cellId,
            isExterior = arrival.isExterior,
            position = arrival.position,
        },
    }

    if opts.gold ~= nil and opts.gold < quote.fare then
        quote.short = quote.fare - opts.gold
        return refuse('gold', quote)
    end
    return quote
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
