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
-- restores stats separately -- and why that happens in the player script
-- rather than here. See restore.lua.
function M.advanceTime(hours)
    if hours and hours > 0 then
        world.advanceTime(hours)
    end
end

--- Every travel operator in the world, in the shape graph.build takes.
--
-- Discovery is by a non-empty `travelDestinations`.
--- Every record id in the load order that offers travel at all.
--
-- Asked of the record lists once, before any cell is touched. The scan below
-- then tests each placed object against a plain Lua table instead of indexing
-- the record list and reading a field off the result, which is the difference
-- between a hash lookup and a trip into the engine -- and it is run against
-- every NPC and creature standing anywhere in the world.
--
-- Roughly one record in a hundred offers travel, so the set stays small
-- however large the load order gets.
-- Keyed on the lowercased id, and looked up the same way. The record store
-- is a C++ map that resolves an id however it is capitalised; a plain Lua
-- table is not, and the ESM capitalises inconsistently -- 'Nevosi Hlan' sits
-- next to 'navam veran' in the same file. Matching exactly would have found
-- some operators and silently lost others.
local function offersTravel()
    local wanted = {}
    for _, kind in ipairs(RECORD_KINDS) do
        for index = 1, #kind.records do
            local record = kind.records[index]
            local destinations = record and record.travelDestinations
            if destinations and #destinations > 0 and type(record.id) == 'string' then
                wanted[string.lower(record.id)] = record
            end
        end
    end
    return wanted
end

--- The cell walk, as a coroutine that gives the frame back.
--
-- Finding an operator's own position means asking every cell in the load
-- order what is standing in it: a travel destination lives on a record, but
-- the near end of every leg does not. On a load order with a mainland in it
-- that is nine thousand cells and eighteen thousand `getAll` calls, which is
-- somewhere between a stutter and a hang if it happens between two frames.
--
-- So it happens across many. `resume` hands in the real time to run until;
-- the body checks the clock between cells and yields when it is spent, which
-- keeps a slice near the budget however slow the cells in it turn out to be.
--
-- @return a coroutine. Resume with a deadline; it yields until it is done,
--   and returns the operator list.
function M.operatorScan()
    return coroutine.create(function(deadline)
        local operators = {}
        local wanted = offersTravel()
        for _, cell in ipairs(world.cells) do
            for _, kind in ipairs(RECORD_KINDS) do
                local ok, objects = pcall(cell.getAll, cell, kind.objectType)
                if ok and objects then
                    for _, object in ipairs(objects) do
                        local id = object.recordId
                        local record = type(id) == 'string' and wanted[string.lower(id)]
                        if record then
                            local operator = operatorFrom(record, object, cell)
                            if operator then
                                operators[#operators + 1] = operator
                            end
                        end
                    end
                end
            end
            -- Between cells, never inside one: a half-scanned cell would have
            -- to be resumed mid-list, and the list is the engine's.
            if deadline and core.getRealTime() >= deadline then
                deadline = coroutine.yield()
            end
        end
        return operators
    end)
end

--- The same scan, run to completion here and now.
-- Kept for anything that has to have an answer before it can return one.
function M.operators()
    local scan = M.operatorScan()
    while true do
        local ok, result = coroutine.resume(scan)
        if not ok then
            error(result, 0)
        end
        if coroutine.status(scan) == 'dead' then
            return result or {}
        end
    end
end

return M
