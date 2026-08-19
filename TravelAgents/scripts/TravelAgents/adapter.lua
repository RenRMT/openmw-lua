-- The engine-facing half: everything that knows about cells, records and
-- GameObjects, so that graph.lua can know about none of it. Reading the world
-- to build the graph, and the two calls that change it when a journey is
-- bought -- moving the traveller and moving the clock.
local core = require('openmw.core')
local types = require('openmw.types')
local util = require('openmw.util')
local world = require('openmw.world')

local M = {}

-- Creature records carry travelDestinations too. No vanilla creature uses it,
-- but the loop costs nothing and a content mod might.
local RECORD_KINDS = {
    { objectType = types.NPC, records = types.NPC.records },
    { objectType = types.Creature, records = types.Creature.records },
}

local function pointFromCell(cell, position)
    if cell == nil or position == nil then
        return nil
    end
    local exterior = cell.isExterior
    return {
        cellId = cell.id,
        cellName = cell.name,
        isInterior = not exterior,
        position = { x = position.x, y = position.y, z = position.z },
        gridX = exterior and cell.gridX or nil,
        gridY = exterior and cell.gridY or nil,
        region = cell.region,
    }
end

--- Where a travel destination actually is.
-- The id is real for exteriors as well as interiors -- an exterior one reads
-- `Esm3ExteriorCell:<x>:<y>` and resolves to the cell whose name is the town,
-- which is where every exterior stop's name comes from.
local function pointFromDestination(destination)
    local ok, cell = pcall(world.getCellById, destination.cellId)
    if not ok or cell == nil then
        return nil
    end
    return pointFromCell(cell, destination.position)
end

local function operatorFrom(record, object, cell)
    local destinations = {}
    for _, destination in ipairs(record.travelDestinations) do
        local point = pointFromDestination(destination)
        if point then
            destinations[#destinations + 1] = point
        end
    end
    if #destinations == 0 then
        return nil
    end
    return {
        id = object.recordId,
        name = record.name,
        class = record.class,
        place = pointFromCell(cell, object.position),
        destinations = destinations,
    }
end

--- Teleport doors in one cell, in the shape walk.links takes.
--
-- Only cells that hold a stop, and the few a door chain passes through, are
-- ever asked.
function M.doorsFor(cellId)
    local ok, cell = pcall(world.getCellById, cellId)
    if not ok or cell == nil then
        return {}
    end
    local objects = select(2, pcall(cell.getAll, cell, types.Door))
    if type(objects) ~= 'userdata' and type(objects) ~= 'table' then
        return {}
    end

    local doors = {}
    for _, door in ipairs(objects) do
        if types.Door.isTeleport(door) then
            local destination = pointFromCell(types.Door.destCell(door), types.Door.destPosition(door))
            if destination then
                doors[#doors + 1] = {
                    position = { x = door.position.x, y = door.position.y, z = door.position.z },
                    dest = destination,
                }
            end
        end
    end
    return doors
end

--- Put a traveller down at a stop, at the end of a journey they paid for.
--
-- An exterior is teleported to with an empty cell name. An interior is named
-- by its own cell. No `onGround`. The position is an authored travel
-- destination.

-- @return false when the arrival cell cannot be resolved, so a caller can
--   decline to charge for a journey it could not make
function M.arrive(traveller, arrival)
    if traveller == nil or arrival == nil or arrival.position == nil then
        return false
    end
    local destination = ''
    if not arrival.isExterior then
        local ok, cell = pcall(world.getCellById, arrival.cellId)
        if not ok or cell == nil then
            return false
        end
        destination = cell
    end
    local position = util.vector3(arrival.position.x, arrival.position.y, arrival.position.z)
    traveller:teleport(destination, position)
    return true
end

--- What a unit of travel is worth in gold, as the loaded content prices it.
--
-- @return gold per game unit, or nil when the setting is missing or unusable,
--   in which case config.FARE_PER_UNIT stands
function M.travelRate()
    local ok, multiplier = pcall(core.getGMST, 'fTravelMult')
    if not ok or type(multiplier) ~= 'number' or multiplier <= 0 then
        return nil
    end
    return 1 / multiplier
end

--- Move the clock forward by the length of a journey.
--
-- Weather and AI move with it; regeneration does not, which is why arriving
-- restores fatigue separately.
function M.advanceTime(hours)
    if hours and hours > 0 then
        world.advanceTime(hours)
    end
end

--- Arrive rested, the way vanilla travel leaves you.
-- TODO: restore Health & Magicka too. Ideally should
-- be restored at natural restoration rate for the
-- amount of hours spent travelling.

function M.restoreFatigue(traveller)
    if traveller == nil then
        return false
    end
    local ok, stat = pcall(function()
        return types.Actor.stats.dynamic.fatigue(traveller)
    end)
    if not ok or stat == nil then
        return false
    end
    -- A dynamic stat's ceiling is its base plus whatever is fortifying or
    -- draining it, so this is "full" whatever else is acting on the traveller.
    stat.current = stat.base + (stat.modifier or 0)
    return true
end

--- Every travel operator in the world, in the shape graph.build takes.
--
-- Discovery is by a non-empty `travelDestinations`.
function M.operators()
    local operators = {}
    for _, cell in ipairs(world.cells) do
        for _, kind in ipairs(RECORD_KINDS) do
            local ok, objects = pcall(cell.getAll, cell, kind.objectType)
            if ok and objects then
                for _, object in ipairs(objects) do
                    local record = kind.records[object.recordId]
                    local destinations = record and record.travelDestinations
                    if destinations and #destinations > 0 then
                        local operator = operatorFrom(record, object, cell)
                        if operator then
                            operators[#operators + 1] = operator
                        end
                    end
                end
            end
        end
    end
    return operators
end

return M
