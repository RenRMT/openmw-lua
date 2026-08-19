-- The journey plan, as data.

local graphlib = require('scripts.TravelAgents.graph')
local modesData = require('scripts.TravelAgents.data.modes')
local route = require('scripts.TravelAgents.route')

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

    -- One row per place, not per stop.
    local here, taken = {}, {}
    for _, member in ipairs(graphlib.walkGroup(graph, originKey)) do
        here[member] = true
    end

    for _, stop in ipairs(route.destinations(graph, originKey, opts)) do
        local place = graphlib.place(graph, stop.key)
        -- Somewhere you already are is not a journey.
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
                -- journey actually ends.
                name = place.name,
                -- Which networks this place is on. Reachable on foot rather
                -- than met exactly here, so a stop the vehicles do not touch
                -- but a short walk does (Caldera, Wolverine Hall) counts as
                -- being on the network that gets you there.
                servedBy = graphlib.modesWithinWalk(graph, stop.key),
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

--- How many times a journey puts the traveller off one vehicle and onto
-- another.
--
-- Counted in vehicles boarded, not legs travelled: `stop.transfers` counts
-- every leg including the walk to the dock, and walking to the dock is not a
-- change of vehicle. A journey made entirely on foot boards nothing and so
-- changes nothing.
function M.changes(stop)
    return math.max((stop.vehicleLegs or 0) - 1, 0)
end

--- The same, but with everything at or past `most` sharing its answer.
-- Long journeys are rare and differ from each other in ways the count stops
-- describing, so a window grouping by it has somewhere to put them.
function M.changeBucket(stop, most)
    local changes = M.changes(stop)
    if most and changes > most then
        return most
    end
    return changes
end

--- How to say what a journey asks of the player, as a message key and the
-- values that fill it in. The window renders it; nothing here writes English.
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
