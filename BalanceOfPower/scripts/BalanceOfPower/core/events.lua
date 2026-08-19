-- The framework's outward-facing event bus (design doc 3.9).
--
-- Nothing inside the framework listens to these -- they exist so UI
-- mods, quest mods and later content can react to the simulation.
--
-- The names themselves live in core/eventnames.lua and are re-exported
-- here, so global code has one module to require and a player script can
-- take the names without dragging openmw.world in behind them.
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

local eventnames = require('scripts.BalanceOfPower.core.eventnames')

local M = {}

for name, value in pairs(eventnames) do
    M[name] = value
end

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
