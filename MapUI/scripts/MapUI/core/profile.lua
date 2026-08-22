-- Redraw timing profiler; splits Lua layout time and MyGUI widget time.

local core = require('openmw.core')

local config = require('scripts.MapUI.core.config')

local enabled = config.PROFILE == true

local timings = {}
local counters = {}
local order = {}

local function reset()
    if not enabled then
        return
    end
    timings = {}
    counters = {}
    order = {}
end

-- Real time, not simulation time: map opens a UI mode that pauses the game.
local function now()
    if not enabled then
        return 0
    end
    return core.getRealTime()
end

local function add(label, since)
    if not enabled then
        return
    end
    if timings[label] == nil then
        order[#order + 1] = label
    end
    timings[label] = (timings[label] or 0) + (core.getRealTime() - since)
end

local function count(label, n)
    if not enabled then
        return
    end
    counters[label] = (counters[label] or 0) + (n or 1)
end

local function flush(header)
    if not enabled then
        return
    end
    local parts = {}
    for _, label in ipairs(order) do
        parts[#parts + 1] = string.format('%s %.1fms', label, timings[label] * 1000)
    end
    for label, value in pairs(counters) do
        parts[#parts + 1] = string.format('%s %d', label, value)
    end
    print('MapUI ' .. header .. ': ' .. table.concat(parts, '  '))
end

return {
    enabled = enabled,
    reset = reset,
    now = now,
    add = add,
    count = count,
    flush = flush,
}
