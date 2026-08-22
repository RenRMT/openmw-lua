-- Restore player stats after journey. Split from adapter because only player
-- scripts can write dynamic stats. Separate file so it can run headless (and test).

local types = require('openmw.types')

local M = {}

-- The three that a night's sleep returns.
local STATS = { 'health', 'magicka', 'fatigue' }

local function fill(traveller, name)
    local ok, stat = pcall(function()
        return types.Actor.stats.dynamic[name](traveller)
    end)
    if not ok or stat == nil then
        return false
    end
    -- Dynamic stat ceiling = base + modifiers, so this is full.
    stat.current = stat.base + (stat.modifier or 0)
    return true
end

--- Restore what the journey earned.
--
-- Vanilla: ride = rest (all stats), guide = wait (fatigue only).
--
-- @param traveller the actor who travelled
-- @param rests true when the journey spent time aboard something
-- @return how many stats were filled
function M.afterJourney(traveller, rests)
    if traveller == nil then
        return 0
    end
    local filled = 0
    for _, name in ipairs(STATS) do
        if (rests or name == 'fatigue') and fill(traveller, name) then
            filled = filled + 1
        end
    end
    return filled
end

return M
