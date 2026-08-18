-- Walk links: finding the way out of a building, and joining it to the graph.

local expect = require('support.expect')
local graph = require('scripts.TravelNetwork.graph')
local walk = require('scripts.TravelNetwork.walk')

local M = {}

local MODES = {
    classes = { ['caravaner'] = { id = 'strider', label = 'Silt strider' } },
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

local function interior(cellName, x, y)
    return {
        cellId = string.lower(cellName),
        cellName = cellName,
        isInterior = true,
        position = { x = x, y = y, z = 0 },
    }
end

local function door(x, y, dest)
    return { position = { x = x, y = y, z = 0 }, dest = dest }
end

--- A door table keyed the way the providers key theirs: by cell id.
local function doorsFrom(table_)
    return function(cellId)
        return table_[cellId] or {}
    end
end

local function stopIn(point)
    return { cellId = point.cellId, position = point.position }
end

function M.aStopInsideABuildingFindsTheStreet()
    local hall = interior('Town, Guild', 0, 0)
    local street = exterior('Town', 30000, 0)
    local links = walk.links({ stopIn(hall) }, doorsFrom({
        ['town, guild'] = { door(300, 400, street) },
    }))

    expect.count(links, 1, 'links')
    expect.equal(links[1].point.cellName, 'Town', 'where the door lets out')
    expect.near(links[1].walked, 500, 1, 'distance walked to the door')
end

function M.aChainOfDoorsIsFollowedOut()
    -- Vivec's guild hall opens onto a canton plaza, not the street, and
    -- Sadrith Mora's onto the inside of Wolverine Hall. One door is not
    -- always enough.
    local hall = interior('Canton, Guild', 0, 0)
    local plaza = interior('Canton, Plaza', 1000, 0)
    local street = exterior('Canton', 30000, 0)
    local links = walk.links({ stopIn(hall) }, doorsFrom({
        ['canton, guild'] = { door(0, 100, plaza) },
        ['canton, plaza'] = { door(1000, 400, street) },
    }))

    expect.count(links, 1, 'links')
    expect.equal(links[1].point.cellName, 'Canton', 'the street beyond the plaza')
    -- 100 to the first door, then 400 from where it drops you to the second.
    expect.near(links[1].walked, 500, 1, 'distance across both cells')
end

function M.theShortestWayOutWins()
    local hall = interior('Town, Guild', 0, 0)
    local near = exterior('Town', 30000, 0)
    local far = exterior('Elsewhere', 90000, 0)
    local links = walk.links({ stopIn(hall) }, doorsFrom({
        ['town, guild'] = { door(0, 900, far), door(0, 200, near) },
    }))

    expect.equal(links[1].point.cellName, 'Town', 'the nearer door')
    expect.near(links[1].walked, 200, 1, 'distance walked')
end

function M.aWayOutDeeperThanTheLimitIsNotFound()
    local hall = interior('Deep, Guild', 0, 0)
    local middle = interior('Deep, Hallway', 0, 0)
    local street = exterior('Deep', 30000, 0)
    local links = walk.links({ stopIn(hall) }, doorsFrom({
        ['deep, guild'] = { door(0, 100, middle) },
        ['deep, hallway'] = { door(0, 100, street) },
    }), { maxHops = 0 })

    expect.count(links, 0, 'links found within zero hops')
end

function M.doorsThatLoopBackDoNotHang()
    -- Two interiors opening onto each other and nothing else. The search has
    -- to notice it has been here before, or it never returns.
    local one = interior('Loop, A', 0, 0)
    local two = interior('Loop, B', 0, 0)
    local links = walk.links({ stopIn(one) }, doorsFrom({
        ['loop, a'] = { door(0, 100, two) },
        ['loop, b'] = { door(0, 100, one) },
    }))

    expect.count(links, 0, 'a building with no way out produces no link')
end

function M.aStopWithNoDoorsAtAllIsLeftAlone()
    local hall = interior('Sealed, Guild', 0, 0)
    expect.count(walk.links({ stopIn(hall) }, doorsFrom({})), 0, 'links')
end

function M.linkingJoinsTheStopToTheStreetBothWays()
    local hall = interior('Town, Guild', 0, 0)
    local street = exterior('Town', 30000, 0)
    local far = exterior('Far', 90000, 0)
    local g = graph.build({
        { id = 'guide', name = 'Guide', class = 'caravaner', place = hall,
          destinations = { interior('Other, Guild', 0, 0) } },
        { id = 'driver', name = 'Driver', class = 'caravaner', place = street,
          destinations = { far } },
    }, { modes = MODES })

    graph.link(g, walk.links({ stopIn(hall) }, doorsFrom({
        ['town, guild'] = { door(0, 100, street) },
    })))

    local out = graph.edgesFrom(g, 'cell:town, guild')
    local back = graph.edgesFrom(g, 'place:town')
    local walkOut, walkBack = nil, nil
    for _, leg in ipairs(out) do
        if leg.mode == 'walk' then walkOut = leg end
    end
    for _, leg in ipairs(back) do
        if leg.mode == 'walk' then walkBack = leg end
    end

    expect.truthy(walkOut, 'a leg out of the hall')
    expect.truthy(walkBack, 'a leg back into it')
    expect.equal(walkOut.to, 'place:town', 'where the walk leads')
    expect.near(walkOut.distance, walkBack.distance, 1, 'the same walk both ways')
    expect.equal(g.stats.walkLegs, 2, 'walk legs counted')
end

function M.aWalkLegCarriesBothSidesOfTheDoor()
    -- 100 units to the door inside, then 5000 from where it drops you to the
    -- stop out on the street.
    local hall = interior('Town, Guild', 0, 0)
    local doorstep = exterior('Town', 25000, 0)
    local street = exterior('Town', 30000, 0)
    local far = exterior('Far', 90000, 0)
    local g = graph.build({
        { id = 'guide', name = 'Guide', class = 'caravaner', place = hall,
          destinations = { interior('Other, Guild', 0, 0) } },
        { id = 'driver', name = 'Driver', class = 'caravaner', place = street,
          destinations = { far } },
    }, { modes = MODES })

    graph.link(g, walk.links({ stopIn(hall) }, doorsFrom({
        ['town, guild'] = { door(0, 100, doorstep) },
    })))

    for _, leg in ipairs(graph.edgesFrom(g, 'cell:town, guild')) do
        if leg.mode == 'walk' then
            expect.near(leg.distance, 5100, 1, 'inside plus outside')
        end
    end
end

function M.aWalkLegMakesAStopAnInterchange()
    -- Walking counts: a player standing at the strider stop can reach the boat
    -- through one door, and does. What `modesAt` reports stays narrower --
    -- what meets on this exact spot -- so the two facts remain separable.
    local hall = interior('Town, Guild', 0, 0)
    local street = exterior('Town', 30000, 0)
    local far = exterior('Far', 90000, 0)
    local g = graph.build({
        { id = 'sailor', name = 'Sailor', class = 'shipmaster', place = hall,
          destinations = { interior('Other, Guild', 0, 0) } },
        { id = 'driver', name = 'Driver', class = 'caravaner', place = street,
          destinations = { far } },
    }, { modes = { classes = {
            ['caravaner'] = { id = 'strider', label = 'Silt strider' },
            ['shipmaster'] = { id = 'boat', label = 'Boat' },
        }, overrides = {}, exclude = {}, unknown = { id = 'unknown', label = 'Unknown' } } })

    graph.link(g, walk.links({ stopIn(hall) }, doorsFrom({
        ['town, guild'] = { door(0, 100, street) },
    })))

    expect.truthy(graph.isTransfer(g, 'place:town'), 'an interchange, on foot')
    expect.equal(table.concat(graph.modesAt(g, 'place:town'), '+'), 'strider',
        'what meets on the spot')
    expect.equal(table.concat(graph.modesWithinWalk(g, 'place:town'), '+'), 'boat+strider',
        'what is reachable on foot')
end

function M.aHallAndItsStreetAreOneInterchangeNotTwo()
    -- Counted as places: both stops are interchanges in their own right, and
    -- reporting both would count the same junction twice.
    local hall = interior('Town, Guild', 0, 0)
    local street = exterior('Town', 30000, 0)
    local far = exterior('Far', 90000, 0)
    local g = graph.build({
        { id = 'sailor', name = 'Sailor', class = 'shipmaster', place = hall,
          destinations = { interior('Other, Guild', 0, 0) } },
        { id = 'driver', name = 'Driver', class = 'caravaner', place = street,
          destinations = { far } },
    }, { modes = { classes = {
            ['caravaner'] = { id = 'strider', label = 'Silt strider' },
            ['shipmaster'] = { id = 'boat', label = 'Boat' },
        }, overrides = {}, exclude = {}, unknown = { id = 'unknown', label = 'Unknown' } } })

    graph.link(g, walk.links({ stopIn(hall) }, doorsFrom({
        ['town, guild'] = { door(0, 100, street) },
    })))

    local found = graph.interchanges(g)
    expect.count(found, 1, 'interchanges')
    expect.equal(found[1].name, 'Town', 'named after the street, not the hall')
    expect.count(found[1].stops, 2, 'stops folded into it')
    expect.truthy(found[1].onFoot, 'the change costs a walk')
    expect.equal(table.concat(found[1].modes, '+'), 'boat+strider', 'modes across the junction')
end

function M.linkingCanAddAStopNoVehicleServes()
    -- Caldera's case: a guild hall, and nothing else in the town at all. The
    -- street outside it is a stop the operators never mentioned.
    local hall = interior('Caldera, Guild', 0, 0)
    local street = exterior('Caldera', 30000, 0)
    local g = graph.build({
        { id = 'guide', name = 'Guide', class = 'caravaner', place = hall,
          destinations = { interior('Other, Guild', 0, 0) } },
    }, { modes = MODES })

    expect.isNil(g.nodes['place:caldera'], 'the street is unknown before linking')
    graph.link(g, walk.links({ stopIn(hall) }, doorsFrom({
        ['caldera, guild'] = { door(0, 100, street) },
    })))

    expect.truthy(g.nodes['place:caldera'], 'the street is a stop after linking')
    expect.equal(g.nodes['place:caldera'].name, 'Caldera', 'named after its cell')
end

return M
