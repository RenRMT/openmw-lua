-- Arriving in the state vanilla leaves you in.
--
-- Split from adapter.lua because it cannot run where the adapter does. A
-- dynamic stat on the player is only writable from the player's own
-- script -- a global one gets "Allowed only in local scripts for
-- 'openmw.self'" from the setter, which is a runtime error and not a
-- load-time one, so it ships happily and fails on arrival.
--
-- PLAYER context (or the traveller's own local script).

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
    -- A dynamic stat's ceiling is its base plus whatever is fortifying or
    -- draining it, so this is "full" whatever else is acting on them.
    stat.current = stat.base + (stat.modifier or 0)
    return true
end

--- Restore what the journey earned.
--
-- Vanilla treats a ride as a rest and a guild guide as a wait: step off a
-- silt strider and health, magicka and fatigue have all come back; step
-- out of a guild hall and only fatigue has.
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
