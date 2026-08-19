-- Buying a journey: everything about it that can be decided without the
-- engine.
--
local route = require('scripts.TravelAgents.route')

local M = {}

local function refuse(reason, quote)
    quote = quote or {}
    quote.ok = false
    quote.reason = reason
    return quote
end

--- What a journey costs, and whether it can be bought.
--
-- @param graph the built graph
-- @param fromKey the operator's stop.
-- @param toKey the stop the player picked
-- @param opts optional { gold = <what the player holds> } plus anything
--   route.find takes
-- @return a quote. `fare` and `hours` are filled in whenever a route exists,
--   including when it is refused, so the refusal can say what the journey
--   would have cost. `reason` is 'route' or 'gold'.
function M.quote(graph, fromKey, toKey, opts)
    opts = opts or {}
    if type(fromKey) ~= 'string' or type(toKey) ~= 'string' or fromKey == toKey then
        return refuse('route')
    end
    if graph.nodes[fromKey] == nil or graph.nodes[toKey] == nil then
        return refuse('route')
    end

    local journey = route.find(graph, fromKey, toKey, opts)
    if journey == nil or #journey.legs == 0 then
        return refuse('route')
    end

    -- Where the last leg leaves you, which is not always the stop asked for.
    local arrival = graph.nodes[journey.legs[#journey.legs].to]
    local quote = {
        ok = true,
        fare = journey.fare,
        baseFare = journey.baseFare,
        surcharge = journey.surcharge,
        surchargePercent = journey.surchargePercent,
        hours = journey.hours,
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

return M
