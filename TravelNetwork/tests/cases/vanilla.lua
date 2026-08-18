-- The graph built from the shipped content, against the numbers the ESM dump
-- and the in-game probe both produced.
--
-- These are regression guards on real data, not on the rules: if a merge rule
-- changes and the node count moves, one of the two is wrong and this says so.

local expect = require('support.expect')
local fixture = require('support.fixture')
local graph = require('scripts.TravelNetwork.graph')
local walk = require('scripts.TravelNetwork.walk')

local M = {}

--- The vehicle network on its own, before any door is opened.
local function vanilla()
    return graph.build(fixture.operators())
end

--- The whole thing: vehicles, then the doors joining stops inside buildings
-- to the streets outside them. This is what the mod builds in game.
local function linked()
    local g = vanilla()
    local stops = {}
    for _, key in ipairs(g.order) do
        local node = g.nodes[key]
        if not node.isExterior then
            stops[#stops + 1] = { cellId = node.cellId, position = node.position }
        end
    end
    graph.link(g, walk.links(stops, fixture.doorsFor))
    return g
end

function M.theShippedNetworkHasTheShapeTheDumpFound()
    local g = vanilla()

    -- 38 operators in the ESM: one is cut content no cell places, one is a
    -- test dummy in a debug cell. 117 destinations less the dummy's one.
    expect.equal(g.stats.operators, 36, 'operators used')
    expect.equal(g.stats.unplaced, 1, 'operators no cell places')
    expect.equal(g.stats.excluded, 1, 'operators excluded by id')
    expect.equal(g.stats.edges, 115, 'legs')
    expect.equal(g.stats.nodes, 31, 'stops')
end

function M.everyLegLandsOnAKnownStop()
    local g = vanilla()
    for _, key in ipairs(g.order) do
        for _, leg in ipairs(graph.edgesFrom(g, key)) do
            expect.truthy(g.nodes[leg.to], 'leg from ' .. key .. ' lands on a known stop')
        end
    end
end

function M.theWholeNetworkHasExactlyThreeInterchanges()
    -- The headline the mod exists to produce, and it is a smaller number than
    -- anyone would guess: Khuul and Molag Mar are where boat meets strider,
    -- Vivec's Foreign Quarter is where boat meets gondola. Nowhere else in
    -- Morrowind can you change vehicle without walking.
    local g = vanilla()
    local interchanges = {}
    for _, key in ipairs(g.order) do
        if graph.isTransfer(g, key) then
            interchanges[#interchanges + 1] = g.nodes[key].name
        end
    end
    table.sort(interchanges)

    expect.equal(#interchanges, 3, 'interchange count')
    expect.equal(table.concat(interchanges, ', '),
        'Khuul, Molag Mar, Vivec, Foreign Quarter', 'the interchanges')
end

function M.everyGuildHallFindsItsWayOutside()
    -- All five, and none of them needs more than two doors: three open onto
    -- the street, Vivec's onto a canton plaza first, Sadrith Mora's onto the
    -- inside of Wolverine Hall.
    local g = linked()
    local halls = {
        ['cell:ald-ruhn, guild of mages'] = 'Ald-ruhn',
        ['cell:balmora, guild of mages'] = 'Balmora',
        ['cell:caldera, guild of mages'] = 'Caldera',
        ['cell:vivec, guild of mages'] = 'Vivec, Foreign Quarter',
        ["cell:sadrith mora, wolverine hall: mage's guild"] = 'Wolverine Hall',
    }

    for key, street in pairs(halls) do
        local found = nil
        for _, leg in ipairs(graph.edgesFrom(g, key)) do
            if leg.mode == 'walk' then
                found = g.nodes[leg.to].name
            end
        end
        expect.equal(found, street, key .. ' walks out to')
    end
end

function M.walkingJoinsTheGuideNetworkToTheRest()
    -- The gap that used to make the guide network an island: standing at
    -- Balmora's silt strider, the guild guide is one door away.
    local g = linked()
    expect.equal(table.concat(graph.modesAt(g, 'place:balmora'), '+'), 'strider',
        'what meets at the strider stop')
    expect.equal(table.concat(graph.modesWithinWalk(g, 'place:balmora'), '+'), 'guide+strider',
        'what is reachable on foot from it')
end

function M.walkLinksDoNotInventInterchanges()
    -- Still three. A change of vehicle that costs a walk is a different thing
    -- from one that does not, and the headline number must not blur them.
    local g = linked()
    local count = 0
    for _, key in ipairs(g.order) do
        if graph.isTransfer(g, key) then
            count = count + 1
        end
    end
    expect.equal(count, 3, 'interchanges after linking')
end

function M.doorsAddTheTwoStopsNoVehicleServes()
    -- Caldera has a guild hall and no vehicle at all; Wolverine Hall is where
    -- Sadrith Mora's guide lets you out, 11593 units from the boats. Neither
    -- exists in the vehicle-only graph.
    local before, after = vanilla(), linked()
    expect.equal(before.stats.nodes, 31, 'stops before linking')
    expect.equal(after.stats.nodes, 33, 'stops after linking')
    expect.equal(after.stats.edges, 125, 'legs after linking')
    expect.equal(after.stats.walkLegs, 10, 'walk legs -- five doors, both ways')

    expect.isNil(before.nodes['place:caldera'], 'Caldera is unserved by vehicles')
    expect.truthy(after.nodes['place:caldera'], 'and reachable once doors count')
    expect.truthy(after.nodes['place:wolverine hall'], 'Wolverine Hall likewise')
end

function M.sadrithMoraIsNotQuietlyJoinedToItsGuide()
    -- The choice made when walk links were designed: doors only. The guide
    -- lets out at Wolverine Hall, the boats are at Sadrith Mora, and no door
    -- connects two exteriors -- so the graph says they are different stops,
    -- because they are.
    local g = linked()
    for _, leg in ipairs(graph.edgesFrom(g, 'place:wolverine hall')) do
        expect.falsy(leg.to == 'place:sadrith mora', 'no leg to Sadrith Mora')
    end
    expect.equal(table.concat(graph.modesWithinWalk(g, 'place:sadrith mora'), '+'), 'boat',
        'Sadrith Mora is boats only, even on foot')
end

function M.aTownWhoseStopsStraddleAGridBoundaryIsOneStop()
    -- Khuul's dock and platform are 7492 units apart in two different grid
    -- cells, and both are called Khuul.
    local g = vanilla()
    expect.truthy(g.nodes['place:khuul'], 'Khuul is a stop')
    expect.count(graph.edgesFrom(g, 'place:khuul'), 6, 'legs leaving Khuul')
    expect.equal(table.concat(graph.modesAt(g, 'place:khuul'), '+'), 'boat+strider', 'modes at Khuul')
end

function M.theHolamayanLandingIsTheOneStopTheGameNeverNamed()
    local g = vanilla()
    local unnamed = {}
    for _, key in ipairs(g.order) do
        if string.sub(key, 1, 3) == 'at:' then
            unnamed[#unnamed + 1] = key
        end
    end

    expect.equal(#unnamed, 1, 'stops in cells with no name')
    expect.count(graph.edgesFrom(g, unnamed[1]), 1, 'the boat back to Ebonheart')
end

function M.theOddlyClassedOperatorsAreLabelledBoats()
    -- Three vanilla operators are authored as a Pauper, a Monk and a Rogue.
    -- All three run boats, and the override table is what knows it.
    local g = vanilla()
    for _, key in ipairs(g.order) do
        for _, leg in ipairs(graph.edgesFrom(g, key)) do
            if leg.operator == 'rindral dralor' or leg.operator == 'Blatta Hateria'
                or leg.operator == 'vevrana aryon' then
                expect.equal(leg.mode, 'boat', leg.operator .. "'s mode")
            end
        end
    end
end

function M.noStopIsStranded()
    -- Every stop has at least one leg touching it, in or out. A stop with
    -- none would mean a node invented by the merge rules rather than found in
    -- the data.
    local g = vanilla()
    local touched = {}
    for _, key in ipairs(g.order) do
        for _, leg in ipairs(graph.edgesFrom(g, key)) do
            touched[leg.from] = true
            touched[leg.to] = true
        end
    end
    for _, key in ipairs(g.order) do
        expect.truthy(touched[key], g.nodes[key].name .. ' has a leg')
    end
end

function M.mournholdIsNotInTheNetwork()
    -- Tribunal ships no travel operator at all: Mournhold is reached by a
    -- scripted dialogue teleport. Worth a test so nobody spends an afternoon
    -- hunting for the bug that lost it.
    local g = vanilla()
    for _, key in ipairs(g.order) do
        expect.falsy(string.find(string.lower(g.nodes[key].name), 'mournhold', 1, true),
            'no Mournhold stop')
    end
end

return M
