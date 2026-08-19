-- Locating the player, and the plan handed to the window.
--
-- The window itself is not tested: it needs the engine to draw. Everything it
-- decides is here instead, which is the reason plan.lua produces data rather
-- than widgets.

local expect = require('support.expect')
local fixture = require('support.fixture')
local graph = require('scripts.TravelNetwork.graph')
local locate = require('scripts.TravelNetwork.locate')
local plan = require('scripts.TravelNetwork.plan')
local walk = require('scripts.TravelNetwork.walk')

local M = {}

local function linked()
    local g = graph.build(fixture.operators())
    local stops = {}
    for _, key in ipairs(g.order) do
        if not g.nodes[key].isExterior then
            stops[#stops + 1] = { cellId = g.nodes[key].cellId, position = g.nodes[key].position }
        end
    end
    graph.link(g, walk.links(stops, fixture.doorsFor))
    return g
end

local function outside(x, y, z)
    return { isInterior = false, position = { x = x, y = y, z = z or 0 } }
end

function M.standingAtAStopFindsThatStop()
    local g = linked()
    local balmora = g.nodes['place:balmora'].position
    local key, distance = locate.nearest(g, outside(balmora.x + 40, balmora.y - 30, balmora.z))

    expect.equal(key, 'place:balmora', 'nearest stop')
    expect.truthy(distance < 100, 'and it is right here')
end

function M.standingInTheWildsFindsTheNearestStop()
    local g = linked()
    local balmora = g.nodes['place:balmora'].position
    local key = locate.nearest(g, outside(balmora.x + 9000, balmora.y, balmora.z))

    expect.equal(key, 'place:balmora', 'still Balmora, from nine thousand units out')
end

function M.standingInsideAStopFindsIt()
    local g = linked()
    local key, distance = locate.nearest(g, {
        cellId = 'Balmora, Guild of Mages', -- the engine's casing varies; ours must not care
        isInterior = true,
        position = { x = 0, y = 0, z = 0 },
    })

    expect.equal(key, 'cell:balmora, guild of mages', 'the hall itself')
    expect.equal(distance, 0, 'you are standing in it')
end

function M.standingInSomeOtherRoomFindsNothing()
    -- A tavern is not a stop, and its coordinates mean nothing outside its own
    -- walls. Guessing a stop from them would put the player at whichever stop
    -- happened to sit near the origin of an unrelated worldspace; the caller
    -- has to walk the doors out first.
    local g = linked()
    expect.isNil(locate.nearest(g, {
        cellId = 'balmora, south wall cornerclub',
        isInterior = true,
        position = { x = 0, y = 0, z = 0 },
    }), 'no stop guessed from inside an unrelated room')
end

function M.aPlanNamesWhereItStartsAndWhatServesIt()
    local g = linked()
    local built = plan.build(g, 'place:balmora')

    expect.equal(built.origin.name, 'Balmora', 'origin')
    expect.equal(table.concat(built.origin.modes, '+'), 'guide+strider', 'what is reachable on foot')
    expect.truthy(built.origin.isTransfer, 'Balmora is an interchange')
end

function M.aPlanListsEverywhereReachableCheapestFirst()
    local g = linked()
    local built = plan.build(g, 'place:balmora')

    expect.equal(#built.stops, g.stats.nodes - 1, 'every other stop in the game')
    for index = 2, #built.stops do
        expect.truthy(built.stops[index].cost >= built.stops[index - 1].cost,
            'stop ' .. index .. ' is no cheaper than the one before it')
    end
end

function M.aPlanCanBeCutShort()
    local g = linked()
    expect.count(plan.build(g, 'place:balmora', { limit = 5 }).stops, 5, 'stops when limited')
end

function M.everyLegCarriesWhatAPlayerNeedsToRead()
    local g = linked()
    local built = plan.build(g, 'place:balmora')
    local caldera = nil
    for _, stop in ipairs(built.stops) do
        if stop.name == 'Caldera' then
            caldera = stop
        end
    end

    expect.truthy(caldera, 'Caldera is in the plan')
    expect.count(caldera.legs, 3, 'legs')
    expect.equal(caldera.legs[2].modeLabel, 'Guild guide', 'the mode reads as a label, not an id')
    expect.equal(caldera.legs[2].to, 'Caldera, Guild of Mages', 'legs name their stops')
    expect.truthy(caldera.legs[2].operator, 'and who runs them')
end

function M.aJourneySummaryReadsAsAPlayerWouldSayIt()
    expect.equal(plan.summarise({ transfers = 0, hours = 2.0, fare = 40 }), 'direct, 2.0 h, 40 gold')
    expect.equal(plan.summarise({ transfers = 1, hours = 3.5, fare = 90 }), '1 change, 3.5 h, 90 gold')
    expect.equal(plan.summarise({ transfers = 3, hours = 9.25, fare = 250 }),
        '3 changes, 9.2 h, 250 gold')
end

function M.aWalkLegSaysWalkRatherThanNamingAnOperator()
    expect.equal(plan.describeLeg({ mode = 'walk', to = 'Balmora, Guild of Mages' }),
        'walk to Balmora, Guild of Mages')
    expect.equal(plan.describeLeg({ mode = 'boat', modeLabel = 'Boat', to = 'Khuul',
        operator = 'Baleni Salavel' }), 'Boat to Khuul (Baleni Salavel)')
end

function M.planningFromAnUnknownStopGivesNothing()
    expect.isNil(plan.build(linked(), 'place:nowhere'), 'no plan from a stop that does not exist')
end

return M
