-- Stub for openmw_aux.time, for headless tests.
--
-- Timers are recorded rather than run: nothing in a headless test has a
-- frame loop to drive them, and every scheduled function the framework
-- registers is also callable directly, which is how the tests drive it.

local M = {}

M.second = 1
M.minute = 60
M.hour = 3600
M.day = 86400

M.SimulationTime = 'SimulationTime'
M.GameTime = 'GameTime'

M._test = {
    timers = {},   -- { {fn = ..., period = ..., options = ...}, ... }
}

function M.runRepeatedly(fn, period, options)
    local timers = M._test.timers
    local entry = { fn = fn, period = period, options = options or {} }
    timers[#timers + 1] = entry
    return function()
        for i, candidate in ipairs(timers) do
            if candidate == entry then
                table.remove(timers, i)
                return
            end
        end
    end
end

function M._test.reset()
    M._test.timers = {}
end

return M
