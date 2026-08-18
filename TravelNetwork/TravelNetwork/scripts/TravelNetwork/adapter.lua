-- The engine-facing half: everything that knows about cells, records and
-- GameObjects, so that graph.lua can know about none of it.
--
-- Global context only. `Cell:getAll` is global-scripts-only, and it is the
-- call the whole mod rests on: it returns objects from cells the player has
-- never loaded, with readable positions (verified 2026-08-18; see the repo's
-- openmw-lua-notes.md §3). A full sweep costs around 600 ms, which is why
-- main.lua builds once and caches rather than rebuilding on demand.

local types = require('openmw.types')
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
-- ever asked -- five guild halls and their hallways in vanilla. Sweeping every
-- cell for doors would mean thousands of them, none of which any route can
-- use.
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

--- Every travel operator in the world, in the shape graph.build takes.
--
-- Discovery is by a non-empty `travelDestinations`, never by
-- `servicesOffered.Travel`: the ESM has no travel bit at all, and while the
-- engine does derive the flag correctly, the destination list is the thing
-- that cannot be wrong.
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
