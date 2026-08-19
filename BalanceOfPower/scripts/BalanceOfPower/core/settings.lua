-- The settings page, and the bridge from what the player chose back to
-- the constants the simulation reads.
--
-- config.lua stays the source of truth. A setting's default is read out
-- of the constant it governs rather than written again here, so the page
-- and the shipped value cannot disagree -- and every entry names a
-- constant that must actually exist, which is what stops a renamed
-- constant leaving a slider that silently governs nothing.
--
-- Only BEHAVIOUR is exposed. The map-shape constants are consumed once
-- at load, when the frontier grid is generated, so a slider for one
-- would do nothing until the player started a new game -- worse than no
-- slider at all.
--
-- GLOBAL context only: the code that reads these constants runs in
-- global context, and storage.playerSection is not available there. The
-- notification settings are the mirror case and live in player.lua,
-- because only a player script can reach openmw.ui.

local async = require('openmw.async')
local storage = require('openmw.storage')

local config = require('scripts.BalanceOfPower.core.config')
local log = require('scripts.BalanceOfPower.core.log')

local M = {}

-- The engine's own convention for a group backed by global storage.
M.GROUP = 'SettingsGlobalBalanceOfPower'

-- Each entry: the storage key, the config constant it writes, and the
-- renderer. `key` is also the l10n key for the label, and `key ..
-- 'Description'` for the help text, so the two always travel together.
local SETTINGS = {
    { key = 'driftEnabled', constant = 'DRIFT_ENABLED', renderer = 'checkbox' },
    { key = 'powerReversionRate', constant = 'POWER_REVERSION_RATE', renderer = 'number',
      argument = { min = 0, max = 1 } },
    { key = 'fortuneSwing', constant = 'FORTUNE_SWING', renderer = 'number',
      argument = { min = 0, max = 2 } },
    { key = 'strainDefencePenalty', constant = 'STRAIN_DEFENCE_PENALTY', renderer = 'number',
      argument = { min = 0, max = 1 } },
    { key = 'tributePowerPerUnit', constant = 'TRIBUTE_POWER_PER_UNIT', renderer = 'number',
      argument = { min = 0, max = 10 } },
}

--- The config constants this page governs, in page order.
-- Diagnostic, and what the test suite checks against config.
function M.exposedConstants()
    local names = {}
    for index, entry in ipairs(SETTINGS) do
        names[index] = entry.constant
    end
    return names
end

--- Register the page the framework's groups attach to.
--
-- Called by every half that owns a group -- the global one here and the
-- two player scripts -- rather than once from whichever loads first.
-- Registration is keyed on the page key, so doing it three times is the
-- same as doing it once, and nothing has to be right about the order
-- three contexts happen to load in.
--
-- @return true if the page registered
function M.registerPage(interfaces)
    local settingsInterface = interfaces and interfaces.Settings
    if not settingsInterface then
        return false
    end
    settingsInterface.registerPage({
        key = config.SETTINGS_PAGE,
        l10n = config.L10N_CONTEXT,
        name = 'settingsPage',
        description = 'settingsPageDescription',
    })
    return true
end

--- Register the page and the simulation group.
--
-- A game whose built-in settings scripts are missing or have not loaded
-- yet must still run the simulation, on the shipped defaults, so this
-- declines rather than failing.
-- @return true if the group registered
function M.register(interfaces)
    local settingsInterface = interfaces and interfaces.Settings
    if not settingsInterface then
        log.warn('the built-in Settings interface is unavailable -- '
            .. 'the framework will run on its shipped defaults')
        return false
    end

    M.registerPage(interfaces)

    local entries = {}
    for index, entry in ipairs(SETTINGS) do
        entries[index] = {
            key = entry.key,
            name = entry.key,
            description = entry.key .. 'Description',
            -- The shipped constant is the default, whatever it is.
            default = config[entry.constant],
            renderer = entry.renderer,
            argument = entry.argument,
        }
    end

    settingsInterface.registerGroup({
        key = M.GROUP,
        page = config.SETTINGS_PAGE,
        l10n = config.L10N_CONTEXT,
        name = 'simulationGroup',
        description = 'simulationGroupDescription',
        permanentStorage = true,
        settings = entries,
    })
    return true
end

--- Copy every stored value onto the constant it governs.
--
-- A setting the player has never touched is absent from storage, and
-- must leave the shipped value alone rather than writing nil over it.
-- @return number of constants overwritten
function M.sync()
    local section = storage.globalSection(M.GROUP)
    local applied = 0
    for _, entry in ipairs(SETTINGS) do
        local value = section:get(entry.key)
        if value ~= nil and value ~= config[entry.constant] then
            config[entry.constant] = value
            applied = applied + 1
        end
    end
    return applied
end

--- Run `callback` whenever the player changes one of these.
--
-- A slider moved mid-game should bite on the next resolved day rather
-- than the next session, which is the whole reason this exists.
function M.subscribe(callback)
    -- Wrapped, because the engine requires a callback that survives a
    -- save/load boundary rather than a bare closure.
    storage.globalSection(M.GROUP):subscribe(async:callback(callback))
end

return M
