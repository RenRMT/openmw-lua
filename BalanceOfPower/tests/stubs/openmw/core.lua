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

--- Faction records, keyed by id. Tests populate this to stand in for
-- the ESM data that core.factions.records exposes in game.
M.factions = {
    records = {},
}

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
