-- The framework's outward-facing event bus (design doc 3.9).
--
-- Nothing inside the framework listens to these -- they exist so UI
-- mods, quest mods and later content can react to the simulation
-- without editing framework code. Names are string constants rather
-- than inline literals so a typo in a listener is at least greppable
-- against one definition.
--
-- Every event is delivered twice, to two different audiences:
--   * as a global event, for other GLOBAL scripts;
--   * as an object event on each player, for PLAYER scripts (which is
--     where any UI reaction has to live).
-- A listener therefore handles it in whichever context it runs in and
-- doesn't need to know which one the framework "really" sends to.
--
-- GLOBAL context only -- requires openmw.world.

local core = require('openmw.core')
local world = require('openmw.world')

local M = {}

-- A territory changed hands: { territory, kind, from, to, day }
M.TERRITORY_FLIPPED = 'BoP_TerritoryFlipped'

-- A settlement's siege streak advanced: { territory, streak, threshold }
-- Fires every day the streak grows, well before a flip is possible, so
-- "the town is under pressure" can be surfaced early.
M.SETTLEMENT_SIEGED = 'BoP_SettlementSieged'

-- A faction's power moved: { faction, delta, newTotal }
M.POWER_CHANGED = 'BoP_PowerChanged'

-- An invasion crossed a stage boundary: { invasion, oldStage, newStage }
M.INVASION_ESCALATED = 'BoP_InvasionEscalated'

-- An invader overran a territory / it was taken back:
-- { territory, invasion } and { territory, invasion, to }
M.TERRITORY_CORRUPTED = 'BoP_TerritoryCorrupted'
M.TERRITORY_LIBERATED = 'BoP_TerritoryLiberated'

--- Broadcast an event to global scripts and to every player script.
-- @param name string one of the constants above
-- @param data table payload; must contain only serializable values
function M.emit(name, data)
    core.sendGlobalEvent(name, data)
    for _, player in ipairs(world.players) do
        player:sendEvent(name, data)
    end
end

return M
