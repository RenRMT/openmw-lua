-- What the player is told when the map moves.
--
-- A PLAYER script, because openmw.ui is unreachable from global context
-- and every event the framework emits is delivered to both. It reads the
-- simulation and never writes to it: nothing here can change an outcome,
-- which is why the notification settings can be per-player while the
-- simulation settings cannot.
--
-- The names come from core/eventnames.lua rather than core/events.lua --
-- that module requires openmw.world to broadcast, and a player script
-- cannot load it.

local core = require('openmw.core')
local interfaces = require('openmw.interfaces')
local storage = require('openmw.storage')
local ui = require('openmw.ui')

local config = require('scripts.BalanceOfPower.core.config')
local eventnames = require('scripts.BalanceOfPower.core.eventnames')
local settings = require('scripts.BalanceOfPower.core.settings')

local l10n = core.l10n(config.L10N_CONTEXT, 'en')

local GROUP = 'SettingsPlayerBalanceOfPower'

-- Not spelled `off`, `log`, `screen`: YAML reads `off` as a boolean, so
-- the key would stop being a string and its label would never resolve.
local SILENT, LOG, SCREEN = 'notifySilent', 'notifyLog', 'notifyScreen'

--------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------

local function registerSettings()
    local settingsInterface = interfaces.Settings
    if not settingsInterface then
        return
    end

    -- The page as well as the group. Which context loads first is not
    -- something to rely on, and registering a page twice costs nothing.
    settings.registerPage(interfaces)

    settingsInterface.registerGroup({
        key = GROUP,
        page = config.SETTINGS_PAGE,
        l10n = config.L10N_CONTEXT,
        name = 'notificationsGroup',
        description = 'notificationsGroupDescription',
        permanentStorage = true,
        settings = {
            {
                key = 'notifications',
                name = 'notifications',
                description = 'notificationsDescription',
                -- The log, not the screen. Territory changes hands
                -- constantly once power is drifting, so the interrupting
                -- option has to be the one you opt into.
                default = LOG,
                renderer = 'select',
                argument = {
                    l10n = config.L10N_CONTEXT,
                    items = { SILENT, LOG, SCREEN },
                },
            },
            {
                key = 'settlementsOnly',
                name = 'settlementsOnly',
                description = 'settlementsOnlyDescription',
                -- Hundreds of frontier cells change hands a season.
                -- Announcing each one is unusable, so named places are
                -- the default and the firehose is the opt-in.
                default = true,
                renderer = 'checkbox',
            },
        },
    })
end

registerSettings()

local function setting(key, fallback)
    local value = storage.playerSection(GROUP):get(key)
    if value == nil then
        return fallback
    end
    return value
end

--------------------------------------------------------------------------
-- Saying it
--------------------------------------------------------------------------

-- Formatting happens after the silence check rather than before, so a
-- player who turned notices off costs nothing per flip -- and there are
-- a great many flips.
local function announce(key, args)
    local mode = setting('notifications', LOG)
    if mode == SILENT then
        return
    end
    local text = l10n(key, args)
    if mode == SCREEN then
        ui.showMessage(text)
    else
        print(text)
    end
end

--------------------------------------------------------------------------
-- Handlers
--------------------------------------------------------------------------
--
-- Every one of these treats its payload as hostile. These events cross
-- from global context and a third-party mod can emit them too, so a
-- malformed one must be inert rather than taking the player script down.

local function onTerritoryFlipped(data)
    if type(data) ~= 'table' then
        return
    end
    if setting('settlementsOnly', true) and data.kind ~= 'settlement' then
        return
    end
    local place = data.name or data.territory
    if type(place) ~= 'string' then
        return
    end

    -- Ground nobody can hold any more reads differently from ground
    -- taken, and the payload distinguishes them by `to` being absent.
    if data.to == nil then
        announce('flipReleased', { place = place })
    else
        announce('flipTaken', { place = place, faction = data.toName or data.to })
    end
end

local function settlementNotice(key)
    return function(data)
        if type(data) ~= 'table' then
            return
        end
        local place = data.name or data.territory
        if type(place) ~= 'string' then
            return
        end
        announce(key, { place = place })
    end
end

return {
    eventHandlers = {
        [eventnames.TERRITORY_FLIPPED] = onTerritoryFlipped,
        [eventnames.SETTLEMENT_SURROUNDED] = settlementNotice('surrounded'),
        [eventnames.SETTLEMENT_RELIEVED] = settlementNotice('relieved'),
    },
}
