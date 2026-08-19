-- The framework's outward-facing event bus (design doc 3.9).
--
-- Nothing inside the framework listens to these -- they exist so UI
-- mods, quest mods and later content can react to the simulation.
-- Names are string constants, so a typo in a listener is at least
-- greppable against one definition.
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

-- A settlement's surrounding frontier passed into, or back out of, rival
-- hands: { territory, day }. Fires on the change, not every day it holds.
--
-- The framework reports this and does nothing about it. What being
-- surrounded means (siege, blockade, nothing) is a question for whatever
-- extension cares.
M.SETTLEMENT_SURROUNDED = 'BoP_SettlementSurrounded'
M.SETTLEMENT_RELIEVED = 'BoP_SettlementRelieved'

-- A faction's power moved: { faction, delta, newTotal }
M.POWER_CHANGED = 'BoP_PowerChanged'

-- A faction's holdings passed STRAIN_EVENT_THRESHOLD, or fell back under
-- it: { faction, strain, day }. Fires on the crossing, not every day it
-- holds -- the same contract as SETTLEMENT_SURROUNDED, and for the same
-- reason: what overreach means is a question for whatever extension
-- cares.
M.FACTION_STRAINED = 'BoP_FactionStrained'
M.FACTION_RELIEVED = 'BoP_FactionRelieved'

-- One in-game day finished resolving: { day }.
--
-- The scheduling hook for everything built on top. An extension that has
-- to act once a day runs from this rather than keeping a timer that
-- drifts against the framework's own pass.
--
-- Delivery is queued rather than synchronous, so a listener acts on the
-- day *after* the one it hears about. That is invisible in play, but an
-- extension needing strict ordering should poll getCurrentDay() instead,
-- which is the pattern the driver itself uses.
M.DAY_RESOLVED = 'BoP_DayResolved'

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
