-- Where a stop inside a building lets you out.
--
-- Travel records describe vehicles and nothing else, so a guild hall and the
-- town around it are unrelated as far as the graph is concerned -- in the
-- world you walk through a door, and the data says nothing about that. Doors
-- do, though: a teleport door names the cell and position it opens onto, and
-- following those out of a building is what joins the guide network to the
-- rest of the map.
--
-- Pure, like graph.lua: the caller supplies `doorsFor`, so this runs against
-- the engine in game and against the fixture in the suite.
--
-- A door, as the provider must hand it over:
--   { position = {x=, y=, z=}, dest = <point> }
-- where `dest` is a point in graph.lua's sense -- cell, position, and whether
-- it is interior.

local config = require('scripts.TravelNetwork.config')

local M = {}

local function distance(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- The way out of one building.
--
-- Breadth-first through doors, because the way out is not always one door:
-- Vivec's guild hall opens onto a canton plaza and Sadrith Mora's onto the
-- inside of Wolverine Hall, both of which then open onto the street. The
-- first exterior reached wins, and distance accumulates along the way -- each
-- leg measured within one cell, which is the only place coordinates can be
-- compared at all.
local function exitFrom(stop, doorsFor, maxHops)
    local best = nil
    local visited = { [stop.cellId] = true }
    local queue = { { cellId = stop.cellId, position = stop.position, walked = 0, hops = 0 } }
    local index = 1

    while index <= #queue do
        local here = queue[index]
        index = index + 1
        for _, door in ipairs(doorsFor(here.cellId) or {}) do
            local walked = here.walked + distance(here.position, door.position)
            local destination = door.dest
            if destination == nil then -- a door the provider could not resolve
                break
            end
            if not destination.isInterior then
                if best == nil or walked < best.walked then
                    best = { point = destination, walked = walked }
                end
            elseif here.hops < maxHops and not visited[destination.cellId] then
                visited[destination.cellId] = true
                queue[#queue + 1] = {
                    cellId = destination.cellId,
                    position = destination.position,
                    walked = walked,
                    hops = here.hops + 1,
                }
            end
        end
    end

    return best
end

--- Walk links for every stop that sits inside a building.
-- @param stops list of { cellId, position } -- interior stops
-- @param doorsFor function(cellId) -> list of doors, see the header
-- @param opts optional { maxHops = <number> }
-- @return list of { cellId, point, walked }
function M.links(stops, doorsFor, opts)
    opts = opts or {}
    local maxHops = opts.maxHops or config.MAX_DOOR_HOPS
    local links = {}

    for _, stop in ipairs(stops) do
        local exit = exitFrom(stop, doorsFor, maxHops)
        if exit then
            links[#links + 1] = {
                cellId = stop.cellId,
                point = exit.point,
                walked = exit.walked,
            }
        end
    end

    return links
end

return M
