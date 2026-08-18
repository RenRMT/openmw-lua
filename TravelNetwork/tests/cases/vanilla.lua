-- The graph built from the shipped content, against the numbers the ESM dump
-- and the in-game probe both produced.
--
-- These are regression guards on real data, not on the rules: if a merge rule
-- changes and the node count moves, one of the two is wrong and this says so.

local expect = require('support.expect')
local fixture = require('support.fixture')
local graph = require('scripts.TravelNetwork.graph')

local M = {}

local function vanilla()
    return graph.build(fixture.operators())
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

function M.theGuildNetworkIsAnIslandUntilWalkLinksExist()
    -- Guild guides operate between interiors, and no leg connects a guild hall
    -- to the town it stands in -- in the world you walk out of the door, and
    -- the graph has no concept of that yet. Guarding it so the day walk links
    -- land, this test fails and gets rewritten rather than quietly passing.
    local g = vanilla()
    expect.truthy(g.nodes['cell:balmora, guild of mages'], 'the guild hall is a stop')
    expect.truthy(g.nodes['place:balmora'], 'the town is a stop')

    for _, leg in ipairs(graph.edgesFrom(g, 'place:balmora')) do
        expect.falsy(leg.to == 'cell:balmora, guild of mages', 'no leg from town to hall')
    end
    for _, leg in ipairs(graph.edgesFrom(g, 'cell:balmora, guild of mages')) do
        expect.falsy(leg.to == 'place:balmora', 'no leg from hall to town')
    end
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
