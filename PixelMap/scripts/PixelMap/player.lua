-- PixelMap: keybinding, settings, and public interface. Single script for layer registry isolation.
local async = require('openmw.async')
local input = require('openmw.input')
local self = require('openmw.self')
local storage = require('openmw.storage')

local I = require('openmw.interfaces')

local config = require('scripts.PixelMap.core.config')
local draw = require('scripts.PixelMap.core.draw')
local layers = require('scripts.PixelMap.core.layers')
local terrain = require('scripts.PixelMap.core.terrain')
local view = require('scripts.PixelMap.core.view')
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

local function open()
    window.show()
    -- Without a mode there is no cursor, and nothing on the map can be
    -- clicked. The empty window list keeps the engine's own windows off
    -- the screen while this one is up.
    I.UI.setMode('Interface', { windows = {} })
end

local function toggle()
    if window.isOpen() then
        window.hide()
    else
        open()
    end
end

input.registerTriggerHandler(TRIGGER, async:callback(toggle))

    -- PixelMapReady fires after every script loads (and reloadlua), giving mods a second chance to register.
local function ready()
    applySettings()
    self:sendEvent('PixelMapReady', { version = 1 })
end

    -- Destroy map if something else takes the screen; torn down directly (don't reset their mode).
local function onUiModeChanged(data)
    if window.isOpen() and data and data.newMode ~= 'Interface' then
        window.destroy()
    end
end

--------------------------------------------------------------------------
-- Interface
--------------------------------------------------------------------------

return {
    interfaceName = 'PixelMap',
    ---
    -- @module PixelMap
    -- @context player
    -- @usage local I = require('openmw.interfaces')
    interface = {
        version = 1,

        --- Add a layer to the map. See API.md.
        --
        -- Fields: key, name, order, enabled, alpha, interactive, draw(required).
        registerLayer = layers.register,

        --- Take a layer off the map. Returns false if it was not there.
        unregisterLayer = layers.unregister,

        --- Turn a layer on/off (same toggle in map).
        setLayerEnabled = layers.setEnabled,

        --- Fade a layer: 0 invisible, 1 opaque. Applied to the layer as a
        -- whole, which its widgets inherit.
        setLayerAlpha = layers.setAlpha,

        --- A solid rectangle in canvas pixels: x, y, w, h, color, alpha.
        quad = draw.quad,

        --- A quad covering one exterior cell, by its grid coordinates:
        -- gridX, gridY, color, alpha, tooltip. The unit for a territory
        -- or ownership overlay.
        --
        -- `tooltip` is optional text shown while the cursor is anywhere
        -- over the cell; it needs `interactive = true` on the layer, and
        -- turns the quad into a widget, so leave it off the fills that
        -- do not need to answer.
        cell = draw.cell,

        --- A marker centred on a world position, sized in screen pixels
        -- so it stays the same size at every zoom.
        --
        -- opts: `position` (Vector3 or Vector2, world), `size`, `color`,
        -- `outline`, `outlineColor`, `alpha`, `resource` (a `ui.texture`),
        -- `onClick` (an async callback), `tooltip` (text shown while the
        -- cursor is over it). Clicks and hover need `interactive = true`
        -- on the layer.
        marker = draw.marker,

        --- Current viewport and layout argument for draw. See view.lua.
        view = view,

        --- Open/close/redraw; redraw is no-op while window closed.
        open = open,
        close = window.hide,
        redraw = window.refresh,
        isOpen = window.isOpen,
    },
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
