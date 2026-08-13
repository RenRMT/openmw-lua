-- Balance of Power -- debug overlay, player half.
--
-- The framework is a global script, so nothing it does is visible from
-- inside the game on its own -- it writes to openmw.log and that's it.
-- This puts a keyboard in front of it and echoes results on screen.
--
-- All hotkeys are Ctrl + a number key. The function keys are not
-- available: Morrowind already uses F1-F12 for quick slots, quicksave,
-- quickload and screenshots, and the engine acts on those bindings
-- whether or not a modifier is held. The number row is free in a clean
-- install, and the Ctrl requirement keeps these out of the way of
-- anything a user has bound there themselves.

local core = require('openmw.core')
local input = require('openmw.input')
local self = require('openmw.self')
local time = require('openmw_aux.time')
local ui = require('openmw.ui')

--------------------------------------------------------------------------
-- Bindings and tuning
--------------------------------------------------------------------------

-- Grouped by what they do: look at things, advance time, change power,
-- then the toggles and self-tests.
local KEYS = {
    map         = input.KEY._1,   -- map around you, full map to the log
                                  --   (Shift: next mode)
    dump        = input.KEY._2,   -- standings and territory counts
    forceDay    = input.KEY._3,   -- run a day now (Shift: seven)
    boostOwner  = input.KEY._4,   -- push whoever holds this ground
    boostRival  = input.KEY._5,   -- push whoever is about to take it
    toggleWatch = input.KEY._6,   -- show/hide the live event feed
    selfTest    = input.KEY._7,   -- prove validation rejects bad data
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

-- The live event feed is loud by design -- power propagates to every
-- faction with an opinion, so one award is several events -- so it starts
-- off and is toggled on when you want to watch a specific change.
local watching = false
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

local function show(text)
    ui.showMessage(text)
end

--------------------------------------------------------------------------
-- Cell watcher
--------------------------------------------------------------------------

-- Answers "whose ground am I standing on?" as you walk around, and keeps
-- the cell key current so the power keys know what to target.
local function checkCell()
    local key = cellKey(self.cell)
    if key == nil or key == lastCellKey then
        return
    end
    lastCellKey = key
    core.sendGlobalEvent('BoPDebug_WhereAmI', { cell = key })
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
        -- The cell is what lets the on-screen half be a window around
        -- the player rather than the whole unreadable island.
        lastCellKey = cellKey(self.cell) or lastCellKey
        core.sendGlobalEvent('BoPDebug_Map', {
            mode = MAP_MODES[mapMode],
            cell = lastCellKey,
        })

    elseif key.code == KEYS.dump then
        core.sendGlobalEvent('BoPDebug_Dump', {})

    elseif key.code == KEYS.forceDay then
        core.sendGlobalEvent('BoPDebug_ForceDay', { count = key.withShift and 7 or 1 })

    elseif key.code == KEYS.boostOwner or key.code == KEYS.boostRival then
        -- Refresh rather than trusting the poll, so a press immediately
        -- after crossing a border targets the cell you're actually in.
        lastCellKey = cellKey(self.cell) or lastCellKey
        core.sendGlobalEvent('BoPDebug_Boost', {
            cell = lastCellKey,
            target = key.code == KEYS.boostRival and 'challenger' or 'owner',
            amount = key.withShift and -BOOST_AMOUNT or BOOST_AMOUNT,
        })

    elseif key.code == KEYS.selfTest then
        core.sendGlobalEvent('BoPDebug_SelfTest', {})

    elseif key.code == KEYS.toggleWatch then
        watching = not watching
        show('BoP event feed: ' .. (watching and 'ON' or 'OFF'))
    end
end

--------------------------------------------------------------------------
-- Framework events
--------------------------------------------------------------------------

-- The framework broadcasts to every player script as well as globally,
-- so these arrive here with no subscription step.

local function onPowerChanged(data)
    if watching then
        show(string.format('%s power %+.2f -> %.1f', data.faction, data.delta, data.newTotal))
    end
end

local function onTerritoryFlipped(data)
    show(string.format('%s: %s -> %s', data.territory, tostring(data.from), tostring(data.to)))
end

local function onAnchorSieged(data)
    if watching then
        show(string.format('%s under pressure (%d/%d)', data.territory, data.streak, data.threshold))
    end
end

-- Phase 6 fires these; wired up now so there's already something
-- watching the moment it lands.
local function onInvasionEscalated(data)
    show(string.format('%s escalated: %s -> %s', data.invasion, tostring(data.oldStage), data.newStage))
end

local function onTerritoryCorrupted(data)
    show(string.format('%s has been overrun', data.territory))
end

local function onTerritoryLiberated(data)
    show(string.format('%s has been retaken', data.territory))
end

--------------------------------------------------------------------------

local function onActive()
    lastCellKey = nil
    show('BoP debug overlay loaded.\n'
        .. 'Ctrl+1 map, Ctrl+2 standings, Ctrl+3 run a day,\n'
        .. 'Ctrl+4 push holder, Ctrl+5 push challenger,\n'
        .. 'Ctrl+6 event feed, Ctrl+7 validation test.\n'
        .. 'Shift reverses 4 and 5, and cycles the map mode on 1.')
end

time.runRepeatedly(checkCell, CELL_POLL)

return {
    engineHandlers = {
        onActive = onActive,
        onKeyPress = onKeyPress,
    },
    eventHandlers = {
        BoPDebug_Report = function(data) show(data.text) end,

        BoP_PowerChanged = onPowerChanged,
        BoP_TerritoryFlipped = onTerritoryFlipped,
        BoP_AnchorSieged = onAnchorSieged,
        BoP_InvasionEscalated = onInvasionEscalated,
        BoP_TerritoryCorrupted = onTerritoryCorrupted,
        BoP_TerritoryLiberated = onTerritoryLiberated,
    },
}
