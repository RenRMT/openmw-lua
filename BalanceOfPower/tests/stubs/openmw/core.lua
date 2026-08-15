-- Stub for openmw.core, for headless tests.
--
-- Only the surface the framework actually touches is implemented.
-- Anything a test needs to control is settable through the `_test`
-- table, which the real module obviously does not have.

local M = {}

M._test = {
    gameTime = 0,
    globalEvents = {},   -- { {name = ..., data = ...}, ... }
}

--- Faction records, keyed by id. Tests populate this through
-- `_test.setFactionRecords` to stand in for the ESM data that
-- core.factions.records exposes in game.
--
-- The engine's asymmetry is modelled deliberately, because it is the
-- whole of the case problem:
--
--   * LOOKUP is case-insensitive. `records[id]` goes through a RefId in
--     the engine, so 'temple' finds the record the ESM calls "Temple".
--   * A REACTION MAP is a plain Lua table, whose keys arrive in whatever
--     case the content file used -- "Camonna Tong", "Sixth House".
--
-- A stub that lowercased both would let a framework regression on the
-- second one pass unnoticed.
M.factions = {
    records = {},
}

--- Install faction records from a plain `{ id -> { other = value } }` map,
-- or from `{ id -> { name = ..., reactions = {...} } }` where a test
-- needs to pin the record's display name.
--
-- Ids and reaction keys go in exactly as written, capitals and all, so a
-- test can pin the case handling by registering a faction as
-- `'sixth house'` and giving the record the ESM's own `'Sixth House'`.
--
-- The result is both an integer-indexed list and an id-keyed map, which
-- is how the engine presents it.
function M._test.setFactionRecords(rows)
    local records, byLower, ids = {}, {}, {}
    for id in pairs(rows or {}) do
        ids[#ids + 1] = id
    end
    table.sort(ids)

    for index, id in ipairs(ids) do
        local entry = rows[id]
        -- A `reactions` key marks the richer form; anything else is a
        -- bare reaction map.
        local rich = entry.reactions ~= nil
        local record = {
            id = id,
            name = (rich and entry.name) or id,
            reactions = rich and entry.reactions or entry,
        }
        records[index] = record
        byLower[string.lower(id)] = record
    end

    M.factions.records = setmetatable(records, {
        __index = function(_, key)
            return type(key) == 'string' and byLower[string.lower(key)] or nil
        end,
    })
    return M.factions.records
end

function M.getGameTime()
    return M._test.gameTime
end

function M.getSimulationTime()
    return M._test.gameTime
end

function M.sendGlobalEvent(name, data)
    local events = M._test.globalEvents
    events[#events + 1] = { name = name, data = data }
end

--- Drop every recorded event. Tests call this between phases.
function M._test.reset()
    M._test.globalEvents = {}
end

--- Recorded events of one name, in order.
function M._test.eventsNamed(name)
    local out = {}
    for _, entry in ipairs(M._test.globalEvents) do
        if entry.name == name then
            out[#out + 1] = entry.data
        end
    end
    return out
end

return M
