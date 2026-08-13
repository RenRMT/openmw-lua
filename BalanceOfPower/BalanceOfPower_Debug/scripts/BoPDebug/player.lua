-- Balance of Power -- debug overlay, player half.
--
-- Input only. Every command is forwarded to the global script, which
-- owns all output; nothing is drawn over the HUD. OpenMW's own log
-- viewer (F11) is a better place for anything worth reading twice, and
-- a fifty-row map was never going to fit in a message box.
--
-- All hotkeys are Ctrl + a number key. The function keys are not
-- available: Morrowind already uses F1-F12 for quick slots, quicksave,
-- quickload, screenshots and that log viewer, and the engine acts on
-- those bindings whether or not a modifier is held. The number row is
-- free in a clean install, and the Ctrl requirement keeps these out of
-- the way of anything a user has bound there themselves.

local core = require('openmw.core')
local input = require('openmw.input')
local self = require('openmw.self')
local time = require('openmw_aux.time')

--------------------------------------------------------------------------
-- Bindings and tuning
--------------------------------------------------------------------------

-- Grouped by what they do: look at things, advance time, change power,
-- then the toggles and self-tests.
local KEYS = {
    map         = input.KEY._1,   -- map around you, and the full map
                                  --   (Shift: next mode)
    dump        = input.KEY._2,   -- standings and territory counts
    forceDay    = input.KEY._3,   -- run a day now (Shift: seven)
    boostOwner  = input.KEY._4,   -- push whoever holds this ground
    boostRival  = input.KEY._5,   -- push whoever is about to take it
    toggleWatch = input.KEY._6,   -- show/hide the live event feed
    selfTest    = input.KEY._7,   -- prove validation rejects bad data
    here        = input.KEY._8,   -- full report on the cell you're in
}

-- How hard the power keys push. Large on purpose: the point is to move
-- a front within a few presses, not to tune anything.
local BOOST_AMOUNT = 50

-- The map views, cycled by Ctrl+Shift+1.
local MAP_MODES = { 'owner', 'projection', 'contest' }

-- How often to check whether the player has changed cell.
local CELL_POLL = 1 * time.second

--------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------

local lastCellKey = nil
local mapMode = 1

--------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------

--- The key a cell is registered under: "#x,y" for exteriors (whose name
-- is the region, or empty), the cell name for interiors.
local function cellKey(cell)
    if not cell then
        return nil
    end
    if cell.isExterior then
        return string.format('#%d,%d', cell.gridX, cell.gridY)
    end
    return cell.name
end

--- Refresh rather than trusting the poll, so a command issued
-- immediately after crossing a border acts on the cell you're actually
-- standing in.
local function currentCell()
    lastCellKey = cellKey(self.cell) or lastCellKey
    return lastCellKey
end

--------------------------------------------------------------------------
-- Cell watcher
--------------------------------------------------------------------------

-- One line per cell entered, so walking across the island annotates the
-- log rather than burying it.
local function checkCell()
    local key = cellKey(self.cell)
    if key == nil or key == lastCellKey then
        return
    end
    lastCellKey = key
    core.sendGlobalEvent('BoPDebug_Entered', { cell = key })
end

--------------------------------------------------------------------------
-- Input
--------------------------------------------------------------------------

local function onKeyPress(key)
    if not key.withCtrl then
        return
    end

    if key.code == KEYS.map then
        if key.withShift then
            mapMode = mapMode % #MAP_MODES + 1
        end
        core.sendGlobalEvent('BoPDebug_Map', {
            mode = MAP_MODES[mapMode],
            cell = currentCell(),
        })

    elseif key.code == KEYS.dump then
        core.sendGlobalEvent('BoPDebug_Dump', {})

    elseif key.code == KEYS.here then
        core.sendGlobalEvent('BoPDebug_Here', { cell = currentCell() })

    elseif key.code == KEYS.forceDay then
        core.sendGlobalEvent('BoPDebug_ForceDay', { count = key.withShift and 7 or 1 })

    elseif key.code == KEYS.boostOwner or key.code == KEYS.boostRival then
        core.sendGlobalEvent('BoPDebug_Boost', {
            cell = currentCell(),
            target = key.code == KEYS.boostRival and 'challenger' or 'owner',
            amount = key.withShift and -BOOST_AMOUNT or BOOST_AMOUNT,
        })

    elseif key.code == KEYS.selfTest then
        core.sendGlobalEvent('BoPDebug_SelfTest', {})

    elseif key.code == KEYS.toggleWatch then
        core.sendGlobalEvent('BoPDebug_ToggleFeed', {})
    end
end

--------------------------------------------------------------------------

time.runRepeatedly(checkCell, CELL_POLL)

return {
    engineHandlers = {
        onKeyPress = onKeyPress,
    },
}
