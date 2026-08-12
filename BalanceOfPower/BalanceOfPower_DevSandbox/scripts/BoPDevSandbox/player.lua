-- Dev sandbox: the player half of the debug console.
--
-- The framework is a global script, so nothing it does is visible from
-- inside the game on its own -- it writes to openmw.log and that's it.
-- This puts a keyboard in front of it and echoes results on screen.
--
-- All hotkeys are Ctrl + a function key, so they can't collide with
-- vanilla bindings (quicksave on F5, quickload on F9 and so on).

local core = require('openmw.core')
local input = require('openmw.input')
local self = require('openmw.self')
local time = require('openmw_aux.time')
local ui = require('openmw.ui')

--------------------------------------------------------------------------
-- Bindings and tuning
--------------------------------------------------------------------------

local KEYS = {
    dump        = input.KEY.F10,  -- print the whole simulation
    award       = input.KEY.F11,  -- award power, to watch propagation
    forceDay    = input.KEY.F12,  -- run a day now, without sleeping
    toggleWatch = input.KEY.F9,   -- show/hide the live event feed
    badRegister = input.KEY.F8,   -- prove validation rejects bad data
}

-- Which faction Ctrl+F11 pushes, and by how much. Hlaalu is a good
-- subject: it has a real reaction row, so the propagation to everyone
-- else is real game data rather than something authored here.
local AWARD_FACTION = 'hlaalu'
local AWARD_AMOUNT = 10

-- How often to check whether the player has changed cell.
local CELL_POLL = 1 * time.second

--------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------

-- The live event feed is loud by design (power propagates to every
-- faction with an opinion, so one award is several events), so it starts
-- off and is toggled on when you want to watch a specific change.
local watching = false
local lastCellKey = nil

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

-- Answers "whose ground am I standing on?" as you walk around, which is
-- the only part of phase 1 that's observable without pressing anything.
local function checkCell()
    local key = cellKey(self.cell)
    if key == nil or key == lastCellKey then
        return
    end
    lastCellKey = key
    core.sendGlobalEvent('BoPDev_WhereAmI', { cell = key })
end

--------------------------------------------------------------------------
-- Input
--------------------------------------------------------------------------

local function onKeyPress(key)
    if not key.withCtrl then
        return
    end

    if key.code == KEYS.dump then
        core.sendGlobalEvent('BoPDev_Dump', {})
    elseif key.code == KEYS.award then
        core.sendGlobalEvent('BoPDev_Award', {
            faction = AWARD_FACTION,
            amount = key.withShift and -AWARD_AMOUNT or AWARD_AMOUNT,
        })
    elseif key.code == KEYS.forceDay then
        core.sendGlobalEvent('BoPDev_ForceDay', { count = key.withShift and 7 or 1 })
    elseif key.code == KEYS.badRegister then
        core.sendGlobalEvent('BoPDev_BadRegister', {})
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

-- Phase 2 and 6 fire these; they're wired up now so the moment those
-- phases land there's already something watching.
local function onTerritoryFlipped(data)
    show(string.format('%s: %s -> %s', data.territory, tostring(data.from), tostring(data.to)))
end

local function onAnchorSieged(data)
    if watching then
        show(string.format('%s under pressure (%d/%d)', data.territory, data.streak, data.threshold))
    end
end

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
    show('BoP dev sandbox loaded.\nCtrl+F10 dump, Ctrl+F11 award, Ctrl+F12 run a day,\n'
        .. 'Ctrl+F9 event feed, Ctrl+F8 validation test.')
end

time.runRepeatedly(checkCell, CELL_POLL)

return {
    engineHandlers = {
        onActive = onActive,
        onKeyPress = onKeyPress,
    },
    eventHandlers = {
        BoPDev_Report = function(data) show(data.text) end,

        BoP_PowerChanged = onPowerChanged,
        BoP_TerritoryFlipped = onTerritoryFlipped,
        BoP_AnchorSieged = onAnchorSieged,
        BoP_InvasionEscalated = onInvasionEscalated,
        BoP_TerritoryCorrupted = onTerritoryCorrupted,
        BoP_TerritoryLiberated = onTerritoryLiberated,
    },
}
