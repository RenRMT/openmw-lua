-- Graph building, on hand-built input.
--
-- Every case here is the smallest arrangement that can tell the rule apart
-- from its plausible wrong version. The shipped-data checks live in
-- cases/vanilla.lua.

local expect = require('support.expect')
local graph = require('scripts.TravelNetwork.graph')

local M = {}

local MODES = {
    classes = {
        ['caravaner']  = { id = 'strider', label = 'Silt strider' },
        ['shipmaster'] = { id = 'boat', label = 'Boat' },
    },
    overrides = { ['secretly a captain'] = 'boat' },
    exclude = { ['test dummy'] = true },
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

local function interior(cellName, x, y)
    return {
        cellId = string.lower(cellName),
        cellName = cellName,
        isInterior = true,
        position = { x = x, y = y, z = 0 },
    }
end

local function operator(id, class, place, destinations)
    return { id = id, name = id, class = class, place = place, destinations = destinations }
end

local function build(operators, opts)
    opts = opts or {}
    opts.modes = opts.modes or MODES
    return graph.build(operators, opts)
end

function M.aStopServedByTwoModesIsATransfer()
    local port = exterior('Port', 0, 0)
    local inland = exterior('Inland', 40000, 0)
    local island = exterior('Island', 0, 40000)
    local g = build({
        operator('driver', 'caravaner', port, { inland }),
        operator('sailor', 'shipmaster', port, { island }),
    })

    expect.truthy(graph.isTransfer(g, 'place:port'), 'port serves two modes')
    expect.falsy(graph.isTransfer(g, 'place:inland'), 'inland is a strider dead end')
    expect.equal(table.concat(graph.modesAt(g, 'place:port'), '+'), 'boat+strider', 'modes at port')
end

function M.aStopIsATransferEvenWhenBothModesOnlyArrive()
    -- Modes are counted on incident edges, not outgoing ones: a stop two
    -- different vehicles drop you at is still where you change between them.
    local port = exterior('Port', 0, 0)
    local inland = exterior('Inland', 40000, 0)
    local island = exterior('Island', 0, 40000)
    local g = build({
        operator('driver', 'caravaner', inland, { port }),
        operator('sailor', 'shipmaster', island, { port }),
    })

    expect.truthy(graph.isTransfer(g, 'place:port'), 'port is an interchange')
    expect.count(graph.edgesFrom(g, 'place:port'), 0, 'legs leaving port')
end

function M.aOneWayLegDoesNotImplyAReturn()
    local here = exterior('Here', 0, 0)
    local there = exterior('There', 40000, 0)
    local g = build({ operator('driver', 'caravaner', here, { there }) })

    expect.count(graph.edgesFrom(g, 'place:here'), 1, 'legs from here')
    expect.count(graph.edgesFrom(g, 'place:there'), 0, 'legs from there')
end

function M.twoStopsInOneNamedTownCollapse()
    -- The dock and the platform of one town, far apart and in different grid
    -- cells. Vanilla's widest such pair is 10896 units, which no sane merge
    -- radius would join -- the shared cell name is what joins them.
    local dock = exterior('Bigtown', 0, 0)
    local platform = exterior('Bigtown', 10800, 0)
    local away = exterior('Away', 60000, 0)
    local g = build({
        operator('sailor', 'shipmaster', dock, { away }),
        operator('driver', 'caravaner', platform, { away }),
    })

    expect.equal(g.stats.nodes, 2, 'node count')
    expect.count(graph.edgesFrom(g, 'place:bigtown'), 2, 'legs leaving the town')
end

function M.nearbyTownsWithDifferentNamesStaySeparate()
    -- 4192 units apart is the real gap between Vivec and Vivec, Foreign
    -- Quarter. Distance alone must never merge them.
    local one = exterior('Vivec', 0, 0)
    local two = exterior('Vivec, Foreign Quarter', 4192, 0)
    local away = exterior('Away', 60000, 0)
    local g = build({
        operator('a', 'caravaner', one, { away }),
        operator('b', 'shipmaster', two, { away }),
    })

    expect.equal(g.stats.nodes, 3, 'node count')
end

function M.interiorsNeverMergeOnPosition()
    -- Interior coordinates are cell-local, so two unrelated guild halls can
    -- sit a few hundred units apart in raw numbers. Merging them would be a
    -- worldspace confusion, not a rounding error.
    local hallA = interior('Aville, Guild', 0, 0)
    local hallB = interior('Bville, Guild', 500, 0)
    local away = exterior('Away', 60000, 0)
    local g = build({
        operator('guideA', 'caravaner', hallA, { away }),
        operator('guideB', 'caravaner', hallB, { away }),
    })

    expect.equal(g.stats.nodes, 3, 'node count')
    expect.truthy(g.nodes['cell:aville, guild'], 'first hall is its own node')
    expect.truthy(g.nodes['cell:bville, guild'], 'second hall is its own node')
end

function M.anUnnamedPointJoinsTheNearestNamedStop()
    local town = exterior('Town', 0, 0)
    local outside = exterior(nil, 396, 0)
    local away = exterior('Away', 60000, 0)
    local g = build({
        operator('local', 'shipmaster', town, { away }),
        operator('outsider', 'shipmaster', outside, { away }),
    })

    expect.equal(g.stats.nodes, 2, 'node count')
    expect.count(graph.edgesFrom(g, 'place:town'), 2, 'both operators depart the town')
end

function M.mergingUnnamedPointsIsOrderIndependent()
    -- The unnamed operator is listed first, so an inline merge would key it
    -- before the town it belongs to exists. Same input, same graph.
    local town = exterior('Town', 0, 0)
    local outside = exterior(nil, 396, 0)
    local away = exterior('Away', 60000, 0)
    local g = build({
        operator('outsider', 'shipmaster', outside, { away }),
        operator('local', 'shipmaster', town, { away }),
    })

    expect.equal(g.stats.nodes, 2, 'node count')
    expect.count(graph.edgesFrom(g, 'place:town'), 2, 'both operators depart the town')
end

function M.anUnnamedPointTooFarOutStandsAlone()
    local town = exterior('Town', 0, 0)
    local wilds = exterior(nil, 9000, 0)
    local away = exterior('Away', 60000, 0)
    local g = build({
        operator('local', 'shipmaster', town, { away }),
        operator('hermit', 'shipmaster', wilds, { away }),
    })

    expect.equal(g.stats.nodes, 3, 'node count')
    expect.equal(g.nodes['at:9000,0'].name, 'Wilderness (1, 0)', 'fallback name')
end

function M.anUnnamedPointIsNamedAfterItsRegionWhenThereIsOne()
    local wilds = exterior(nil, 9000, 0)
    wilds.region = "Azura's Coast"
    local away = exterior('Away', 60000, 0)
    local g = build({ operator('hermit', 'shipmaster', wilds, { away }) })

    expect.equal(g.nodes['at:9000,0'].name, "Azura's Coast (1, 0)", 'region-derived name')
end

function M.anOperatorNoCellPlacesIsSkipped()
    local away = exterior('Away', 60000, 0)
    local g = build({ operator('ghost', 'shipmaster', nil, { away }) })

    expect.equal(g.stats.unplaced, 1, 'unplaced count')
    expect.equal(g.stats.nodes, 0, 'a stop nobody departs from is not a stop')
    expect.equal(g.stats.edges, 0, 'edge count')
end

function M.anExcludedOperatorIsDropped()
    local here = exterior('Here', 0, 0)
    local there = exterior('There', 40000, 0)
    local g = build({ operator('test dummy', 'caravaner', here, { there }) })

    expect.equal(g.stats.excluded, 1, 'excluded count')
    expect.equal(g.stats.nodes, 0, 'node count')
end

function M.anIdOverrideBeatsTheClass()
    local here = exterior('Here', 0, 0)
    local there = exterior('There', 40000, 0)
    local g = build({ operator('secretly a captain', 'caravaner', here, { there }) })

    expect.equal(graph.edgesFrom(g, 'place:here')[1].mode, 'boat', 'overridden mode')
end

function M.anUnrecognisedClassStillFormsLegs()
    local here = exterior('Here', 0, 0)
    local there = exterior('There', 40000, 0)
    local g = build({ operator('mystery', 'balloonist', here, { there }) })

    local legs = graph.edgesFrom(g, 'place:here')
    expect.count(legs, 1, 'legs from here')
    expect.equal(legs[1].mode, 'unknown', 'mode label degrades')
    expect.equal(graph.modeLabel('unknown', MODES), 'Unknown', 'label for the unknown mode')
end

function M.aLegToItsOwnStopIsNotAnEdge()
    local here = exterior('Here', 0, 0)
    local alsoHere = exterior('Here', 200, 0)
    local g = build({ operator('driver', 'caravaner', here, { alsoHere }) })

    expect.equal(g.stats.selfEdges, 1, 'self-edge count')
    expect.equal(g.stats.edges, 0, 'edge count')
end

function M.legDistanceIsThreeDimensional()
    local low = exterior('Low', 0, 0)
    local high = exterior('High', 30000, 0)
    high.position.z = 40000
    local g = build({ operator('driver', 'caravaner', low, { high }) })

    expect.near(graph.edgesFrom(g, 'place:low')[1].distance, 50000, 1, 'leg distance')
end

return M
