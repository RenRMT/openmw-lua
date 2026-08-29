-- The game's own faction records, read once and normalized.
--
-- The same job core/survey.lua does for cells, done for factions: whatever
-- the load order actually contains, turned into something the simulation
-- can use without knowing where it came from. Nothing here decides who
-- exists in the politics -- that is the registry's call -- it only reports
-- what the records say.
--
-- Everything is keyed lowercase. The ESM stores record ids as they were
-- authored ("Sixth House", "Camonna Tong") while the framework registers
-- them lowercase, and a reaction row is a plain table whose key case the
-- engine does not normalize. Getting this wrong reads as an empty row and
-- nothing else, which is why both ends are lowered in one place.
--
-- GLOBAL context only: core.factions is not reachable elsewhere.

local core = require('openmw.core')

local log = require('scripts.BalanceOfPower.core.log')

local M = {}

local rows = nil    -- lowered id -> { lowered id -> reaction }
local names = nil   -- lowered id -> record display name

local EMPTY = {}

-- Lazy rather than eager: records can only be read once content files have
-- loaded, which is later than this module is required.
local function read()
    if rows then
        return
    end
    rows, names = {}, {}

    local ok, records = pcall(function()
        return core.factions.records
    end)
    if not ok or not records then
        log.warn('no faction records available -- there is nobody to simulate')
        return
    end

    for _, record in ipairs(records) do
        local id = string.lower(record.id)
        names[id] = record.name
        local row = {}
        for other, value in pairs(record.reactions or EMPTY) do
            local key = string.lower(tostring(other))
            -- Every record carries a reaction toward itself; it is not an
            -- opinion about anybody.
            if key ~= id then
                row[key] = value
            end
        end
        rows[id] = row
    end
end

--- Normalized reaction rows, keyed lowercase.
-- core/power.lua reads these; nothing else should need them.
function M.rows()
    read()
    return rows
end

--- The display name on a faction's record, or nil where there is none.
function M.nameOf(recordId)
    read()
    return names[string.lower(recordId)]
end

--- Whether the game has a record under this id at all.
-- Used to tell a real faction with no politics from a typo.
function M.exists(recordId)
    read()
    return rows[recordId] ~= nil
end

--- Record ids that take part in the politics at all: a non-zero opinion of
-- somebody, or somebody's non-zero opinion of them.
--
-- The filter exists because content files keep dead ids alive. Tamriel Data
-- ships a dozen records named "<Deprecated>" so old saves still load; every
-- one has an empty row and no column, and without this they would all
-- appear in the standings.
function M.participatingIds()
    read()
    local moves, movedBy = {}, {}
    for id, row in pairs(rows) do
        for other, value in pairs(row) do
            if value ~= 0 then
                movedBy[id] = true
                moves[other] = true
            end
        end
    end

    local ids = {}
    for id in pairs(rows) do
        if moves[id] or movedBy[id] then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    return ids
end

return M
