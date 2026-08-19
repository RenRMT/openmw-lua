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

    -- One row per place, not per stop. A guild hall and the street outside it
    -- are the same town to a traveller, and offering both offers Caldera
    -- twice at the same price. The list is cheapest-first, so the first member
    -- of a place to come up is the one worth selling.
    local here, taken = {}, {}
    for _, member in ipairs(graphlib.walkGroup(graph, originKey)) do
        here[member] = true
    end

    for _, stop in ipairs(route.destinations(graph, originKey, opts)) do
        local place = graphlib.place(graph, stop.key)
        -- Somewhere you already are is not a journey, whatever the graph says
        -- it costs: the hall across the street from this silt strider is where
        -- the player is standing.
        local worth = not here[stop.key] and not taken[place.key]
        if worth then
            taken[place.key] = true
            local legs = {}
            local firstModeLabel = nil
            for _, leg in ipairs(stop.legs) do
                legs[#legs + 1] = legOf(graph, leg, modes)
                if firstModeLabel == nil and leg.mode ~= 'walk' then
                    firstModeLabel = legs[#legs].modeLabel
                end
            end
            plan.stops[#plan.stops + 1] = {
                key = stop.key,
                -- The place is what the list calls it; the stop is where the
                -- journey actually ends, and the two differ whenever the
                -- cheapest way into a town is through its guild hall.
                name = place.name,
                arrival = stop.name,
                cost = stop.cost,
                distance = stop.distance,
                walked = stop.walked,
                hours = stop.hours,
                fare = stop.fare,
                baseFare = stop.baseFare,
                surcharge = stop.surcharge,
                surchargePercent = stop.surchargePercent,
                transfers = stop.transfers,
                vehicleLegs = stop.vehicleLegs,
                modeChanges = stop.modeChanges,
                firstModeLabel = firstModeLabel,
                modes = stop.modes,
                legs = legs,
            }
        end
        if opts.limit and #plan.stops >= opts.limit then
            break
        end
    end

    return plan
end

--- How to say what a journey asks of the player, as a message key and the
-- values that fill it in. The window renders it; nothing here writes English.
--
-- The distinction the key carries is between legs and vehicles. Staying on one
-- silt strider through a stop it calls at costs the player nothing, while
-- changing to a boat costs them a wait and a walk to the dock, and a summary
-- reading "2 changes" for both told them the same thing about two different
-- journeys. Walk legs are not counted at all: a door is not a change.
--
-- @return the l10n key, and a table of arguments for it
function M.summarise(stop)
    local args = {
        hours = string.format('%.1f', stop.hours or 0),
        fare = stop.fare or 0,
        legs = stop.vehicleLegs or 0,
        changes = stop.modeChanges or 0,
        mode = stop.firstModeLabel,
    }
    if args.legs == 0 then
        return 'journeyOnFoot', args
    end
    if args.legs == 1 then
        return 'journeyDirect', args
    end
    if args.changes == 0 then
        return 'journeySameVehicle', args
    end
    return 'journeyChanging', args
end

--- One leg, as a line: what carries you, and where it leaves you.
function M.describeLeg(leg)
    if leg.mode == 'walk' then
        return string.format('walk to %s', leg.to)
    end
    return string.format('%s to %s (%s)', leg.modeLabel, leg.to, leg.operator or '?')
end

return M
