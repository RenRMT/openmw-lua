-- The journey plan, as data.

local graphlib = require('scripts.TravelAgents.graph')
local modesData = require('scripts.TravelAgents.data.modes')
local route = require('scripts.TravelAgents.route')

local M = {}

-- Leg as window needs it: destination, via line, label. Router details stay there.
local function legOf(graph, leg, modes)
    return {
        modeLabel = graphlib.modeLabel(leg.mode, modes),
        to = graph.nodes[leg.to].name,
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

    -- One row per place (not per stop).
    local here, taken = {}, {}
    for _, member in ipairs(graphlib.walkGroup(graph, originKey)) do
        here[member] = true
    end

    for _, stop in ipairs(route.destinations(graph, originKey, opts)) do
        local place = graphlib.place(graph, stop.key)
        -- Skip places already reachable.
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
                arrival = stop.name,
                -- The sort key, kept so the order the list is drawn in can
                -- be checked against the order it was built in.
                cost = stop.cost,
                hours = stop.hours,
                fare = stop.fare,
                baseFare = stop.baseFare,
                surcharge = stop.surcharge,
                surchargePercent = stop.surchargePercent,
                vehicleLegs = stop.vehicleLegs,
                modeChanges = stop.modeChanges,
                firstModeLabel = firstModeLabel,
                legs = legs,
            }
        end
        if opts.limit and #plan.stops >= opts.limit then
            break
        end
    end

    return plan
end

--- How many times a journey puts the traveller onto a different kind of
-- vehicle.
-- Neither `transfers` nor `vehicleLegs` says this. `transfers` counts every
-- leg including the walk to the dock, and the walk to the dock is not a
-- change of anything.
function M.changes(stop)
    return stop.modeChanges or 0
end

--- The same, but with everything at or past `most` sharing its answer.
-- Long journeys differ in ways count stops describing.
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

return M
