-- PixelMap: keybinding, settings, and the mode handling that opening the map
-- drags in. Single script for layer registry isolation.
--
-- What the mod exposes to other mods is not here: it is api.lua, whole, so
-- the public surface can be read without wading through the settings page.
local async = require('openmw.async')
local input = require('openmw.input')
local self = require('openmw.self')
local storage = require('openmw.storage')

local I = require('openmw.interfaces')

local api = require('scripts.PixelMap.api')
local config = require('scripts.PixelMap.core.config')
local layers = require('scripts.PixelMap.core.layers')
local terrain = require('scripts.PixelMap.core.terrain')
local window = require('scripts.PixelMap.window')

local TRIGGER = 'PixelMapOpen'

-- Two binding slots: key and controller button each get their own id.
local BINDING = 'PixelMapOpenBinding'
local CONTROLLER_BINDING = 'PixelMapOpenControllerBinding'

local GROUP = 'SettingsPlayerPixelMap'

--------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------

input.registerTrigger {
    key = TRIGGER,
    l10n = config.L10N_CONTEXT,
    name = 'openKey',
    description = 'openKeyDescription',
}

if I.Settings then
    I.Settings.registerPage {
        key = config.SETTINGS_PAGE,
        l10n = config.L10N_CONTEXT,
        name = 'settingsPage',
        description = 'settingsPageDescription',
    }
    I.Settings.registerGroup {
        key = GROUP,
        page = config.SETTINGS_PAGE,
        l10n = config.L10N_CONTEXT,
        name = 'settingsGroup',
        description = 'settingsGroupDescription',
        permanentStorage = true,
        settings = {
            {
                key = 'terrainTheme',
                name = 'terrainTheme',
                description = 'terrainThemeDescription',
                default = config.TERRAIN_THEME,
                renderer = 'select',
                argument = { l10n = config.L10N_CONTEXT, items = config.TERRAIN_THEME_ORDER },
            },
            {
                key = 'terrainStyle',
                name = 'terrainStyle',
                description = 'terrainStyleDescription',
                default = config.TERRAIN_STYLE,
                renderer = 'select',
                -- The renderer localises each value through this context,
                -- so 'relief' and 'flat' are l10n keys as well as values.
                argument = { l10n = config.L10N_CONTEXT, items = { 'relief', 'flat' } },
            },
            {
                key = 'openKey',
                name = 'openKey',
                description = 'openKeyDescription',
                -- Default is the binding slot, not a button (nothing bound until player sets it).
                default = BINDING,
                renderer = 'inputBinding',
                argument = { key = TRIGGER, type = 'trigger' },
            },
            {
                key = 'openController',
                name = 'openController',
                description = 'openControllerDescription',
                default = CONTROLLER_BINDING,
                renderer = 'inputBinding',
                argument = { key = TRIGGER, type = 'trigger' },
            },
        },
    }
end

local settings = storage.playerSection(GROUP)

local function applySettings()
    terrain.setTheme(settings:get('terrainTheme') or config.TERRAIN_THEME)
    terrain.setStyle(settings:get('terrainStyle') or config.TERRAIN_STYLE)
    -- A no-op while the map is shut, so this is safe to call from a
    -- subscription that fires whenever the player touches the page.
    window.refresh()
end

settings:subscribe(async:callback(applySettings))

--------------------------------------------------------------------------
-- Built-in layers
--------------------------------------------------------------------------

-- Two, and only two. The player's own marker is drawn by the window
-- rather than registered, because a toggle that hides where you are is
-- not worth a button; everything else belongs to whichever mod wants it.
layers.register(require('scripts.PixelMap.layers.terrain'))
layers.register(require('scripts.PixelMap.layers.grid'))

--------------------------------------------------------------------------
-- Opening and closing
--------------------------------------------------------------------------

local function toggle()
    if window.isOpen() then
        window.hide()
    else
        api.open()
    end
end

input.registerTriggerHandler(TRIGGER, async:callback(toggle))

-- PixelMapReady fires after every script loads (and reloadlua), giving mods a
-- second chance to register.
local function ready()
    applySettings()
    self:sendEvent('PixelMapReady', { version = api.version })
end

-- The single teardown path: whatever closed the map -- the key, the Close
-- button, Escape, another screen taking over -- only drops the mode, and the
-- destroy happens here.
local function onUiModeChanged(data)
    if not window.isOpen() then
        return
    end
    if data and data.newMode == 'Interface' then
        return                      -- still our own mode: nothing to do
    end
    -- Torn down directly, without resetting the mode of whatever took over.
    window.destroy()

    -- api.open() hid the HUD and any pinned windows with setMode('Interface',
    -- {windows = {}}). The engine only restores those on mode ENTER, never
    -- when the stack empties on the way out -- so dropping straight back to
    -- gameplay would leave a pinned map hidden until the player opened their
    -- inventory to get it back. Re-assert Interface once, which restores
    -- everything we hid, then drop it.
    if not (data and data.newMode) then
        I.UI.setMode('Interface')
        -- setMode(), not removeMode('Interface'): by the time this event
        -- fires the built-in mode stack is already empty, so removeMode finds
        -- nothing to remove and no-ops, leaving the re-asserted Interface
        -- stuck open on screen.
        I.UI.setMode()
    end
end

return {
    interfaceName = 'PixelMap',
    interface = api,
    eventHandlers = {
        UiModeChanged = onUiModeChanged,
    },
    engineHandlers = {
        onInit = ready,
        onLoad = ready,

        --- Mouse wheel is global; window decides if meant for map.
        onMouseWheel = function(vertical)
            window.wheel(vertical)
        end,
    },
}
