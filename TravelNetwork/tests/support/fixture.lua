-- Turns the ESM dump into the operator tables the graph builder takes.
--
-- This is the test-side twin of adapter.lua: same output shape, different
-- source. Where the adapter reads live cells and records, this reads what
-- esmtool found in the content files, so a disagreement between the two shows
-- up as the graph coming out different in game than in the suite.
--
-- Two conversions the fixture forces, both documented in its header: positions
-- arrive as arrays rather than vectors, and a destination carries a cell name
-- only when it is interior -- an exterior one has a position and nothing else,
-- exactly as the ESM stores it.

local data = require('fixtures.vanilla_travel')

local CELL_SIZE = 8192

local M = {}

local function vector(array)
    return { x = array[1], y = array[2], z = array[3] }
end

local function gridOf(position)
    return math.floor(position.x / CELL_SIZE), math.floor(position.y / CELL_SIZE)
end

--- The id the engine reports for an exterior cell, rebuilt from its grid.
-- Verified in game 2026-08-18; see the repo's openmw-lua-notes.md §3.
local function exteriorId(gridX, gridY)
    return string.format('esm3exteriorcell:%d:%d', gridX, gridY)
end

local function exteriorPoint(position)
    local gridX, gridY = gridOf(position)
    return {
        cellId = exteriorId(gridX, gridY),
        cellName = data.exteriorNames[string.format('%d,%d', gridX, gridY)],
        isInterior = false,
        position = position,
        gridX = gridX,
        gridY = gridY,
    }
end

local function interiorPoint(position, cellName)
    return {
        cellId = string.lower(cellName),
        cellName = cellName,
        isInterior = true,
        position = position,
    }
end

local function pointFrom(entry)
    local position = vector(entry.position)
    -- The fixture marks placements explicitly; a destination is interior
    -- exactly when the ESM gave it a cell.
    local interior = entry.isInterior
    if interior == nil then
        interior = entry.cell ~= nil
    end
    if interior then
        return interiorPoint(position, entry.cell)
    end
    return exteriorPoint(position)
end

--- Every operator in the shipped content, in the shape graph.build takes.
function M.operators()
    local operators = {}
    for _, record in ipairs(data.operators) do
        local destinations = {}
        for _, destination in ipairs(record.destinations) do
            destinations[#destinations + 1] = pointFrom(destination)
        end
        operators[#operators + 1] = {
            id = record.id,
            name = record.name,
            class = record.class,
            -- One placement each in vanilla; a record placed twice would need
            -- a decision, and none is.
            place = record.placements[1] and pointFrom(record.placements[1]) or nil,
            destinations = destinations,
        }
    end
    return operators
end

--- Teleport doors in one cell, in the shape walk.links takes.
--
-- The test-side twin of `adapter.doorsFor`. The fixture keys doors by
-- lowercased cell name, which is also what the engine reports as an interior
-- cell's id -- see the repo's openmw-lua-notes.md §4.
function M.doorsFor(cellId)
    local entries = data.doors[string.lower(cellId)]
    if not entries then
        return {}
    end
    local doors = {}
    for _, entry in ipairs(entries) do
        local destination = vector(entry.destPosition)
        doors[#doors + 1] = {
            position = vector(entry.position),
            dest = entry.destCell and interiorPoint(destination, entry.destCell)
                or exteriorPoint(destination),
        }
    end
    return doors
end

function M.raw()
    return data
end

return M
