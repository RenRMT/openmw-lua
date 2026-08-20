-- The engine-facing half: everything that knows about cells, records and
-- GameObjects, so that graph.lua can know about none of it. Reading the world
-- to build the graph, and the two calls that change it when a journey is
-- bought -- moving the traveller and moving the clock.
local core = require('openmw.core')
local types = require('openmw.types')
local util = require('openmw.util')
local world = require('openmw.world')

local config = require('scripts.TravelAgents.config')
local knownCells = require('scripts.TravelAgents.data.operators')

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

--- Every record id in the load order that offers travel at all.
--
-- Asked of the record lists once, before any cell is touched. The cell walk
-- below then tests each placed object against a plain Lua table rather than
-- indexing the record list and reading a field off the result -- a hash
-- lookup instead of a trip into the engine, run against every NPC and
-- creature standing anywhere in the world.
--
-- Roughly one record in a hundred offers travel, so the set stays small
-- however large the load order gets.
--
-- Keyed on the lowercased id, and looked up the same way. The record store
-- is a C++ map that resolves an id however it is capitalised; a plain Lua
-- table is not, and the ESM capitalises inconsistently -- 'Nevosi Hlan' sits
-- next to 'navam veran' in the same file. Matching exactly would have found
-- some operators and silently lost others.
--
-- @param checkpoint called every so often, to give the frame back
-- @return the id-to-record map, and the record kinds worth walking cells for
local function offersTravel(checkpoint)
    local wanted = {}
    local kinds = {}
    local since = 0
    for _, kind in ipairs(RECORD_KINDS) do
        local any = false
        for index = 1, #kind.records do
            local record = kind.records[index]
            local destinations = record and record.travelDestinations
            if destinations and #destinations > 0 and type(record.id) == 'string' then
                wanted[string.lower(record.id)] = record
                any = true
            end
            -- Not every record: reading the clock is itself a call, and
            -- there are more records here than cells to walk afterwards.
            since = since + 1
            if since >= config.SCAN_RECORDS_PER_CHECK then
                since = 0
                checkpoint('records', since)
            end
        end
        -- Asking every cell for its creatures when no creature record in the
        -- load order offers travel is half the walk spent on a question whose
        -- answer cannot matter. Nothing in Morrowind, Tribunal, Bloodmoon or
        -- Tamriel Rebuilt travels by creature -- but a mod may, and then the
        -- pass above finds it and this turns itself back on.
        if any then
            kinds[#kinds + 1] = kind
        end
    end
    return wanted, kinds
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
--- The cell a hint names, or nil if the game has no such cell.
--
-- Grid coordinates for exteriors and a name for interiors, which is what the
-- two engine lookups take -- so nothing here has to know how a cell id is
-- spelled, and a hint written against a different version of a mod fails by
-- returning nothing rather than by resolving to the wrong place.
local function cellFromHint(hint)
    local ok, cell
    if hint.x and hint.y then
        ok, cell = pcall(world.getExteriorCell, hint.x, hint.y)
    elseif hint.name then
        ok, cell = pcall(world.getCellByName, hint.name)
    end
    if ok then
        return cell
    end
    return nil
end

--- Look for the operators the shipped table places, in the cells it names.
--
-- Everything the table accounts for is found by opening one cell each --
-- about 130 rather than the whole load order. Anything it does not account
-- for is handed back, and the caller walks every cell looking for those.
--
-- An operator counts as accounted for only when every cell the table names
-- for them resolves *and* they are standing in it. A hint that points at a
-- cell this game does not have, or at a cell they have since been moved out
-- of, sends them to the full walk -- which is what keeps a stale table a
-- cost in speed rather than in missing boats. An empty hint list is an
-- answer in itself: offers travel, stands nowhere, do not go looking.
--
-- @param wanted id -> record, every record that offers travel
-- @param into the operator list to add to
-- @return the ids still unaccounted for, and how many cells were opened
local function collectHinted(wanted, into)
    local unaccounted = {}
    local opened = 0
    for id, record in pairs(wanted) do
        local hints = knownCells[id]
        if hints == nil then
            unaccounted[id] = record
        else
            local accounted = true
            for _, hint in ipairs(hints) do
                local cell = cellFromHint(hint)
                if cell == nil then
                    accounted = false
                else
                    opened = opened + 1
                    local standingHere = false
                    for _, kind in ipairs(RECORD_KINDS) do
                        local ok, objects = pcall(cell.getAll, cell, kind.objectType)
                        for _, object in ipairs((ok and objects) or {}) do
                            if type(object.recordId) == 'string'
                                and string.lower(object.recordId) == id then
                                local operator = operatorFrom(record, object, cell)
                                if operator then
                                    into[#into + 1] = operator
                                end
                                standingHere = true
                            end
                        end
                    end
                    if not standingHere then
                        accounted = false
                    end
                end
            end
            if not accounted then
                unaccounted[id] = record
            end
        end
    end
    return unaccounted, opened
end

-- @param opts optional { ignoreHints = true } to search every cell even for
--   operators data/operators.lua accounts for
function M.operatorScan(opts)
    local ignoreHints = opts and opts.ignoreHints
    return coroutine.create(function(deadline)
        local operators = {}

        -- Both phases give the frame back through this. A nil deadline is
        -- how a caller says "run it out", and then nothing ever yields.
        --
        -- Yields carry how far along the scan is, so the driver can say what
        -- rate it is managing rather than leaving it to be guessed at.
        local function checkpoint(phase, done, total)
            if deadline and core.getRealTime() >= deadline then
                deadline = coroutine.yield(phase, done, total)
            end
        end

        local wanted, kinds = offersTravel(checkpoint)
        checkpoint('records', 0)

        -- The shipped table first: one cell per operator rather than all of
        -- them. On a load order it covers this is the whole scan, and the
        -- walk below never runs.
        local missing, opened = wanted, 0
        if not ignoreHints then
            missing, opened = collectHinted(wanted, operators)
        end
        checkpoint('hinted', opened)

        -- Anything the table did not account for has to be looked for the
        -- long way. Only those: a single unknown operator should cost one
        -- walk, not re-find everybody.
        local searching = 0
        for _ in pairs(missing) do
            searching = searching + 1
        end
        if searching == 0 then
            return operators
        end

        local cells = world.cells
        local cellCount = #cells
        for index = 1, cellCount do
            local cell = cells[index]
            for _, kind in ipairs(kinds) do
                local ok, objects = pcall(cell.getAll, cell, kind.objectType)
                if ok and objects then
                    for _, object in ipairs(objects) do
                        local id = object.recordId
                        local record = type(id) == 'string' and missing[string.lower(id)]
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
            checkpoint('cells', index, cellCount)
        end
        return operators
    end)
end

--- The same scan, run to completion here and now.
-- Kept for anything that has to have an answer before it can return one.
function M.operators(opts)
    local scan = M.operatorScan(opts)
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
