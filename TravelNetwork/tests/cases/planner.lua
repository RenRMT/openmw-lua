-- Finding the operator being talked to, and the plan handed to the window.
--
-- The window itself is not tested: it needs the engine to draw. Everything it
-- decides is here instead, which is the reason plan.lua produces data rather
-- than widgets.

local expect = require('support.expect')
local fixture = require('support.fixture')
local graph = require('scripts.TravelNetwork.graph')
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

function M.theStopAnOperatorStandsAtIsKnownByRecordId()
    -- What the planner opens from: the caravaner you are talking to, resolved
    -- to their stop without measuring anything.
    local g = linked()
    local operator = graph.stopOf(g, 'navam veran')

    expect.truthy(operator, 'Navam Veran is an operator')
    expect.equal(operator.key, 'place:ald-ruhn', 'stands at Ald-ruhn')
    expect.equal(operator.mode, 'strider', 'and drives a silt strider')
end

function M.anOperatorIsFoundWhateverTheCasingOfTheId()
    -- The ESM stores some ids capitalised and some not; the engine lowercases
    -- what it hands back. Neither side should have to care.
    local g = linked()
    expect.truthy(graph.stopOf(g, 'Nevosi Hlan'), 'as the ESM spells it')
    expect.truthy(graph.stopOf(g, 'nevosi hlan'), 'as the engine reports it')
end

function M.someoneWhoRunsNothingIsNotAnOperator()
    local g = linked()
    expect.isNil(graph.stopOf(g, 'fargoth'), 'a townsman runs no vehicle')
    expect.isNil(graph.stopOf(g, nil), 'and neither does nobody')
end

function M.theExcludedTestOperatorIsNotSelectable()
    expect.isNil(graph.stopOf(linked(), 'todd'), "Bethesda's test NPC stays out")
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
