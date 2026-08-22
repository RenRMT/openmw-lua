-- The engine-facing half: everything that knows about cells, records and
-- GameObjects, so that graph.lua can know about none of it.
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
-- Exterior ids resolve to the cell whose name is the town.
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
-- An exterior is teleported to with an empty cell name. An interior is named
-- by its own cell.
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
-- @return gold per game unit, or nil when the setting is missing or unusable,
--   in which case config.FARE_PER_UNIT stands
function M.travelRate()
    local ok, multiplier = pcall(core.getGMST, 'fTravelMult')
    if not ok or type(multiplier) ~= 'number' or multiplier <= 0 then
        return nil
    end
    return 1 / multiplier
end

--- Move the clock forward by the length of a journey. Regeneration does not
-- move, so arriving restores stats separately. See restore.lua.
function M.advanceTime(hours)
    if hours and hours > 0 then
        world.advanceTime(hours)
    end
end

--- Every record id in the load order that offers travel at all.
-- Asked once. Keyed on lowercased id.
-- @param checkpoint called every so often, to give the frame back
-- @return the id-to-record map, the record kinds worth walking cells for, and
--   how many records were read
local function offersTravel(checkpoint)
    local wanted = {}
    local kinds = {}
    -- Counted across both kinds up front so the progress line has a
    -- denominator, rather than reporting NPCs and creatures as two runs
    -- that each restart at one.
    local total = 0
    for _, kind in ipairs(RECORD_KINDS) do
        total = total + #kind.records
    end

    local read, since = 0, 0
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
            read = read + 1
            since = since + 1
            if since >= config.SCAN_RECORDS_PER_CHECK then
                since = 0
                checkpoint('records', read, total)
            end
        end
        -- If a mod adds travel by creature then the
        -- pass above finds it and this turns itself back on.
        if any then
            kinds[#kinds + 1] = kind
        end
    end
    return wanted, kinds, read
end

-- Finding operator positions requires asking every cell. Sliced across
-- frames to stay within budget. @return a coroutine yielding until done.
--- The cell a hint names, or nil if not found.
-- Grid or name, matching the engine lookups.
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

--- A cell shape for hint tables: grid for exterior, name for interior.
function M.hintFor(cell)
    if cell == nil then
        return nil
    end
    if cell.isExterior then
        if type(cell.gridX) == 'number' and type(cell.gridY) == 'number' then
            return { x = cell.gridX, y = cell.gridY }
        end
        return nil
    end
    if type(cell.name) == 'string' and cell.name ~= '' then
        return { name = cell.name }
    end
    return nil
end

--- Look for the operators the shipped table places.
-- Opens one cell per known operator; stale entries force full walk.
-- @param wanted id->record map
-- @param into operator list to add to
-- @param learned id->hint list from earlier walk
-- @return unaccounted ids, cells opened
local function collectHinted(wanted, into, learned)
    local unaccounted = {}
    local opened = 0
    for id, record in pairs(wanted) do
        local hints = learned[id] or knownCells[id]
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

--- Does anything already place this operator in this cell?
-- Learned (measured on this load order) takes precedence over shipped.
--
-- @param id lowercased record id
-- @param hint from M.hintFor
-- @param learned id -> hint list, what earlier observation found
function M.knowsPlacement(id, hint, learned)
    if id == nil or hint == nil then
        return true
    end
    local hints = (learned and learned[id]) or knownCells[id]
    if hints == nil then
        return false
    end
    for _, known in ipairs(hints) do
        if hint.name ~= nil then
            if known.name == hint.name then
                return true
            end
        elseif known.x == hint.x and known.y == hint.y then
            return true
        end
    end
    return false
end

--- The records the shipped table says are placed in no cell at all.
--
-- Skipped by the hinted pass by design, and so the one way the table can
-- cost a missing operator rather than only time. Named so that a load order
-- which places one of them has something to go on.
function M.standNowhere()
    local ids = {}
    for id, hints in pairs(knownCells) do
        if #hints == 0 then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    return ids
end

--- Look for records the tables could not place.
-- Expensive but can be deferred to run behind the graph.
--
-- @param missing id -> record, only what is still to be found
-- @param kinds the record kinds worth opening cells for
-- @param operators the list to append to
-- @param report filled in with what the walk cost
-- @param checkpoint called between cells, to give the frame back
local function walkFor(missing, kinds, operators, report, checkpoint)
    local searching = 0
    for _ in pairs(missing) do
        searching = searching + 1
    end

    -- Where the walk finds the operators it had to go looking for. Only
    -- those: everything the tables already place was never searched for,
    -- so this stays a list of corrections rather than a second copy of
    -- data/operators.lua.
    local discovered = {}

    -- Exteriors first, and it is worth being plain about why: 131 of the
    -- 155 operators the shipped table places stand out of doors, and the
    -- walk stops the moment it has found everybody. Looking outside first
    -- is therefore not a preference but the shorter half of the search --
    -- most of the time the interiors are never opened at all.
    --
    -- Both halves come out of the one `world.cells`, ordered without
    -- opening anything: `isExterior` is a field, and it is `getAll` that
    -- costs.
    local cells = world.cells
    local cellCount = #cells
    local outside, inside = {}, {}
    for index = 1, cellCount do
        local cell = cells[index]
        if cell.isExterior then
            outside[#outside + 1] = cell
        else
            inside[#inside + 1] = cell
        end
    end

    -- Stopping early is the whole of the saving, so what is left to find
    -- has to be counted rather than inferred from the operator list: one
    -- record may be placed in several cells, and #operators would then
    -- reach `searching` while somebody was still missing.
    local outstanding = searching
    local seen = {}
    local walked = 0
    local function sweep(list)
        for index = 1, #list do
            if outstanding == 0 then
                return true
            end
            local cell = list[index]
            for _, kind in ipairs(kinds) do
                local ok, objects = pcall(cell.getAll, cell, kind.objectType)
                if ok and objects then
                    for _, object in ipairs(objects) do
                        local id = object.recordId
                        local key = type(id) == 'string' and string.lower(id) or nil
                        local record = key and missing[key]
                        if record then
                            local operator = operatorFrom(record, object, cell)
                            if operator then
                                operators[#operators + 1] = operator
                            end
                        -- Sighting is what ends the search, not
                        -- learning: a cell with no name to write down
                        -- still answers where this record is, and a
                        -- record whose destinations will not resolve
                        -- has still been looked for and found. Tying
                        -- the count to the hint instead would walk the
                        -- whole load order after operators that were
                        -- located in the first hundred cells.
                            if not seen[key] then
                                seen[key] = true
                                outstanding = outstanding - 1
                            end
                        -- The first cell a record turns up in is the
                        -- one it is remembered by. A record in two
                        -- cells is already more than the graph can
                        -- express -- see graph.duplicated -- and
                        -- walking on for the second copy would cost
                        -- the load order to learn something nothing
                        -- reads.
                            local hint = M.hintFor(cell)
                            if hint and discovered[key] == nil then
                                discovered[key] = { hint }
                            end
                        end
                    end
                end
            end
            walked = walked + 1
        -- Between cells, never inside one: a half-scanned cell would
        -- have to be resumed mid-list, and the list is the engine's.
            checkpoint('cells', walked, cellCount)
        end
        return outstanding == 0
    end

    if not sweep(outside) then
        sweep(inside)
    end
    report.walked = walked
    report.cells = cellCount
    report.found = searching - outstanding
    report.learned = discovered
    return operators
end

-- @param opts optional:
--   ignoreHints = true  search every cell even for operators the table places
--   learned = <table>   id -> hint list an earlier walk found, tried before
--     the shipped table
--   report = <table>    filled in with what the scan actually did. The two
--     paths through here cost wildly different amounts and produce the same
--     graph, so without this the only way to tell which one ran is to time it
--     and do arithmetic.
function M.operatorScan(opts)
    local ignoreHints = opts and opts.ignoreHints
    -- Deferring means answering from what the tables placed while the walk
    -- runs behind. Ignoring the tables leaves nothing to answer from, so the
    -- two cancel: asked for both, the walk is not put off.
    local deferWalk = (opts and opts.deferWalk) and not ignoreHints
    local learned = (opts and opts.learned) or {}
    local report = (opts and opts.report) or {}
    report.ignoredHints = ignoreHints and true or false
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

        local wanted, kinds, read = offersTravel(checkpoint)
        report.records = read
        report.offerTravel = 0
        for _ in pairs(wanted) do
            report.offerTravel = report.offerTravel + 1
        end
        checkpoint('records', read, read)

        -- The shipped table first: one cell per operator rather than all of
        -- them. On a load order it covers this is the whole scan, and the
        -- walk below never runs.
        local missing, opened = wanted, 0
        if not ignoreHints then
            missing, opened = collectHinted(wanted, operators, learned)
        end
        report.hinted = opened
        checkpoint('hinted', opened)

        -- Anything the table did not account for has to be looked for the
        -- long way. Only those: a single unknown operator should cost one
        -- walk, not re-find everybody.
        local searching = 0
        for _ in pairs(missing) do
            searching = searching + 1
        end
        report.unaccounted = searching
        -- Named, not just counted. One stale entry sends the scan round every
        -- cell, so which entry it is is the whole of what has to be fixed.
        -- Not when the table was ignored -- then every record is "missing" by
        -- construction and the list is the load order.
        if not ignoreHints then
            report.unaccountedIds = {}
            for id in pairs(missing) do
                report.unaccountedIds[#report.unaccountedIds + 1] = id
            end
            table.sort(report.unaccountedIds)
        end
        report.walked = 0
        if searching == 0 then
            report.operators = #operators
            return operators
        end

        if deferWalk then
            -- Handed back rather than done. The caller assembles a graph from
            -- what the tables already placed -- which on a covered load order
            -- is everybody -- and runs this behind it.
            report.owed = { missing = missing, kinds = kinds }
            report.operators = #operators
            return operators
        end

        walkFor(missing, kinds, operators, report, checkpoint)
        report.operators = #operators
        return operators
    end)
end

--- The deferred walk half, as its own coroutine.
-- @param owed `report.owed` from deferred scan
-- @return coroutine yielding found operators only
function M.walkScan(owed, opts)
    local report = (opts and opts.report) or {}
    return coroutine.create(function(deadline)
        local function checkpoint(phase, done, total)
            if deadline and core.getRealTime() >= deadline then
                deadline = coroutine.yield(phase, done, total)
            end
        end
        local operators = {}
        walkFor(owed.missing, owed.kinds, operators, report, checkpoint)
        report.operators = #operators
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
