-- Routing, on hand-built graphs.
--
-- Costs are in game units throughout: a penalty says "worth this much of a
-- detour", so every case here is arranged so the wrong answer would be the
-- shorter one in plain distance.

local expect = require('support.expect')
local graph = require('scripts.TravelNetwork.graph')
local route = require('scripts.TravelNetwork.route')

local M = {}

local MODES = {
    classes = {
        ['caravaner'] = { id = 'strider', label = 'Silt strider' },
        ['shipmaster'] = { id = 'boat', label = 'Boat' },
    },
    overrides = {},
    exclude = {},
    unknown = { id = 'unknown', label = 'Unknown' },
}

local function exterior(name, x, y)
    return {
        cellId = string.format('esm3exteriorcell:%d:%d', math.floor(x / 8192), math.floor(y / 8192)),
        cellName = name,
        isInterior = false,
        position = { x = x, y = y, z = 0 },
        gridX = math.floor(x / 8192),
        gridY = math.floor(y / 8192),
    }
end

local function operator(id, class, place, destinations)
    return { id = id, name = id, class = class, place = place, destinations = destinations }
end

local function build(operators)
    return graph.build(operators, { modes = MODES })
end

--- No penalties, so a case can test the search itself rather than the tariff.
local FREE = { transferPenalty = 0, modeChangePenalty = 0 }

function M.theCheapestJourneyIsFound()
    local a = exterior('A', 0, 0)
    local b = exterior('B', 20000, 0)
    local c = exterior('C', 40000, 0)
    local g = build({
        operator('short', 'caravaner', a, { b }),
        operator('onward', 'caravaner', b, { c }),
        operator('long', 'caravaner', a, { c }),
    })
    -- Direct is 40000; through B is 40000 plus a transfer, so direct wins.
    local found = route.find(g, 'place:a', 'place:c')

    expect.count(found.legs, 1, 'legs')
    expect.equal(found.transfers, 0, 'transfers')
    expect.near(found.distance, 40000, 1, 'distance')
end

function M.anUnreachableStopHasNoRoute()
    local a = exterior('A', 0, 0)
    local b = exterior('B', 20000, 0)
    local island = exterior('Island', 90000, 0)
    local elsewhere = exterior('Elsewhere', 95000, 0)
    local g = build({
        operator('mainland', 'caravaner', a, { b }),
        operator('islander', 'shipmaster', island, { elsewhere }),
    })

    expect.isNil(route.find(g, 'place:a', 'place:island'), 'no route to the island')
end

function M.aStopIsZeroLegsFromItself()
    local a = exterior('A', 0, 0)
    local b = exterior('B', 20000, 0)
    local g = build({ operator('driver', 'caravaner', a, { b }) })
    local found = route.find(g, 'place:a', 'place:a')

    expect.count(found.legs, 0, 'legs')
    expect.equal(found.distance, 0, 'distance')
    expect.equal(found.transfers, 0, 'transfers')
end

function M.aOneWayLegDoesNotComeBack()
    local a = exterior('A', 0, 0)
    local b = exterior('B', 20000, 0)
    local g = build({ operator('driver', 'caravaner', a, { b }) })

    expect.truthy(route.find(g, 'place:a', 'place:b'), 'there')
    expect.isNil(route.find(g, 'place:b', 'place:a'), 'and not back')
end

function M.theTransferPenaltyIsAddedToTheCost()
    -- A journey has to change at B, so its cost is the ground it covers plus
    -- the price of the change. Distance is untouched by the tariff.
    local a = exterior('A', 0, 0)
    local b = exterior('B', 10000, 0)
    local c = exterior('C', 20000, 0)
    local g = build({
        operator('hop one', 'caravaner', a, { b }),
        operator('hop two', 'caravaner', b, { c }),
    })

    local free = route.find(g, 'place:a', 'place:c', FREE)
    local charged = route.find(g, 'place:a', 'place:c',
        { transferPenalty = 4000, modeChangePenalty = 0 })

    expect.near(free.cost, 20000, 1, 'cost with nothing charged for changing')
    expect.near(charged.cost, 24000, 1, 'cost with a change worth 4000')
    expect.near(charged.distance, 20000, 1, 'distance is unchanged by the tariff')
end

function M.aChainLosesToTheSingleLegAlongsideIt()
    -- Three stops in a line, so hopping through the middle covers exactly the
    -- same ground as going straight past it. Changing vehicles for no gain is
    -- what the transfer penalty exists to refuse.
    --
    -- A chain can never be *shorter* than the leg beside it -- the triangle
    -- inequality sees to that -- so an equal-length chain is the real choice
    -- the router faces, and in vanilla it faces it constantly.
    local a = exterior('A', 0, 0)
    local b = exterior('B', 10000, 0)
    local c = exterior('C', 20000, 0)
    local g = build({
        operator('hop one', 'caravaner', a, { b }),
        operator('hop two', 'caravaner', b, { c }),
        operator('direct', 'caravaner', a, { c }),
    })

    local found = route.find(g, 'place:a', 'place:c')
    expect.count(found.legs, 1, 'legs')
    expect.equal(found.transfers, 0, 'transfers')
end

function M.changingModeIsWorseThanChangingVehicle()
    -- Both routes are two legs over the same ground. One stays on silt
    -- striders, the other swaps to a boat halfway, and only the mode-change
    -- penalty can tell them apart.
    local a = exterior('A', 0, 0)
    local viaLand = exterior('Land', 10000, 0)
    local viaSea = exterior('Sea', 10000, 5000)
    local c = exterior('C', 20000, 0)
    local g = build({
        operator('strider out', 'caravaner', a, { viaLand }),
        operator('strider on', 'caravaner', viaLand, { c }),
        operator('boat out', 'caravaner', a, { viaSea }),
        operator('boat on', 'shipmaster', viaSea, { c }),
    })

    local found = route.find(g, 'place:a', 'place:c',
        { transferPenalty = 0, modeChangePenalty = 20000 })

    expect.equal(found.legs[2].mode, 'strider', 'stays on the strider')
    expect.count(found.modes, 1, 'one mode for the whole journey')
end

function M.aJourneyLongerThanTheLegLimitIsRefused()
    local stops = {}
    local operators = {}
    for index = 0, 4 do
        stops[index] = exterior(string.format('Stop%d', index), index * 10000, 0)
    end
    for index = 0, 3 do
        operators[#operators + 1] = operator('hop' .. index, 'caravaner', stops[index], { stops[index + 1] })
    end
    local g = build(operators)

    expect.truthy(route.find(g, 'place:stop0', 'place:stop4', { maxLegs = 4 }), 'within the limit')
    expect.isNil(route.find(g, 'place:stop0', 'place:stop4', { maxLegs = 3 }), 'beyond it')
end

function M.theSummaryDescribesTheWholeJourney()
    local a = exterior('A', 0, 0)
    local b = exterior('B', 10000, 0)
    local c = exterior('C', 30000, 0)
    local g = build({
        operator('first', 'caravaner', a, { b }),
        operator('second', 'shipmaster', b, { c }),
    })
    local found = route.find(g, 'place:a', 'place:c')

    expect.count(found.legs, 2, 'legs')
    expect.equal(found.transfers, 1, 'transfers')
    expect.near(found.distance, 30000, 1, 'distance')
    expect.equal(table.concat(found.modes, '+'), 'strider+boat', 'modes in order of travel')
    expect.greater(found.hours, 0, 'hours')
    expect.greater(found.fare, 0, 'fare')
    expect.equal(found.vehicleLegs, 2, 'vehicle legs')
    expect.equal(found.modeChanges, 1, 'and one of them is a change of vehicle')
end

function M.stayingOnOneKindOfVehicleIsNotCountedAsChangingIt()
    -- Two silt strider legs in a row: a transfer, but nothing the traveller
    -- has to think about. The planner draws that distinction and the count is
    -- where it comes from.
    local a = exterior('A', 0, 0)
    local b = exterior('B', 10000, 0)
    local c = exterior('C', 30000, 0)
    local g = build({
        operator('first', 'caravaner', a, { b }),
        operator('second', 'caravaner', b, { c }),
    })
    local found = route.find(g, 'place:a', 'place:c', FREE)

    expect.equal(found.transfers, 1, 'one transfer')
    expect.equal(found.vehicleLegs, 2, 'two vehicle legs')
    expect.equal(found.modeChanges, 0, 'and no change of vehicle')
end

function M.aDoorBetweenTwoRidesIsNotAChangeOfVehicle()
    -- Walk legs are not vehicles and must not be counted as one: a guide leg
    -- with a door at each end is one ride, not three.
    local hall = {
        cellId = 'town, guild', cellName = 'Town, Guild', isInterior = true,
        position = { x = 0, y = 0, z = 0 },
    }
    local street = exterior('Town', 30000, 0)
    local far = exterior('Far', 90000, 0)
    local g = build({
        operator('driver', 'caravaner', street, { far }),
        operator('guide', 'caravaner', hall, { street }),
    })
    graph.link(g, { { cellId = 'town, guild', point = street, walked = 100 } })

    local found = route.find(g, 'cell:town, guild', 'place:far', FREE)
    expect.greater(#found.legs, 1, 'more than one leg')
    expect.equal(found.modeChanges, 0, 'and none of them a change of vehicle')
end

function M.walkingIsFreeOfChargeButNotOfTime()
    local hall = {
        cellId = 'town, guild', cellName = 'Town, Guild', isInterior = true,
        position = { x = 0, y = 0, z = 0 },
    }
    local street = exterior('Town', 30000, 0)
    local far = exterior('Far', 90000, 0)
    local g = build({
        operator('guide', 'caravaner', hall, { { cellId = 'other, guild', cellName = 'Other, Guild',
            isInterior = true, position = { x = 0, y = 0, z = 0 } } }),
        operator('driver', 'caravaner', street, { far }),
    })
    graph.link(g, { { cellId = 'town, guild', point = street, walked = 100 } })

    local found = route.find(g, 'cell:town, guild', 'place:town')
    expect.count(found.legs, 1, 'legs')
    expect.equal(found.legs[1].mode, 'walk', 'on foot')
    expect.equal(found.fare, 0, 'nobody charges for a door')
    expect.greater(found.hours, 0, 'but it takes time')
end

function M.destinationsComeBackCheapestFirst()
    local a = exterior('A', 0, 0)
    local near = exterior('Near', 10000, 0)
    local far = exterior('Far', 50000, 0)
    local g = build({
        operator('driver', 'caravaner', a, { near, far }),
    })
    local list = route.destinations(g, 'place:a')

    expect.count(list, 2, 'destinations')
    expect.equal(list[1].name, 'Near', 'nearest first')
    expect.equal(list[2].name, 'Far', 'then the far one')
end

function M.transfersAtNamesWhatYouCanChangeTo()
    local port = exterior('Port', 0, 0)
    local inland = exterior('Inland', 40000, 0)
    local island = exterior('Island', 0, 40000)
    local g = build({
        operator('driver', 'caravaner', port, { inland }),
        operator('sailor', 'shipmaster', port, { island }),
    })

    expect.equal(table.concat(route.transfersAt(g, 'place:port'), '+'), 'boat+strider', 'at the port')
    expect.count(route.transfersAt(g, 'place:inland'), 1, 'at a stop you only pass through')
end

return M
