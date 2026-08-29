-- The canvas: one Element per layer, and the drawing into them.
--
-- Each layer gets an Element of its own and keeps it across redraws, so a
-- redraw replaces that layer's contents and touches nothing else. That is the
-- whole reason this is not one big widget tree -- a pan redraws the terrain
-- without disturbing a mod's markers, and a mod's markers can change without
-- the terrain being rebuilt underneath them.
--
-- The window owns the container these go into and the gestures over them;
-- this owns what is inside it.

local ui = require('openmw.ui')
local util = require('openmw.util')

local config = require('scripts.PixelMap.core.config')
local draw = require('scripts.PixelMap.core.draw')
local layers = require('scripts.PixelMap.core.layers')
local profile = require('scripts.PixelMap.core.profile')
local terrain = require('scripts.PixelMap.core.terrain')
local view = require('scripts.PixelMap.core.view')

local M = {}

-- One Element per layer key, kept across redraws.
local elements = {}

-- The player's own marker. Not a registered layer: it has no business in the
-- toggle row, and a map that can hide where you are is not a feature.
local playerElement = nil

local function elementFor(layer)
    local element = elements[layer.key]
    if not element then
        -- No `layer` field: this Element is not attached to a UI layer of
        -- its own, it is placed inside the window's content.
        element = ui.create {
            type = ui.TYPE.Widget,
            props = {
                relativeSize = util.vector2(1, 1),
                alpha = layer.alpha,
                inheritAlpha = layer.alpha and true or nil,
            },
            content = ui.content {},
        }
        elements[layer.key] = element
    end
    return element
end

--- Run one layer's draw and put the result on screen.
function M.drawLayer(layer)
    local element = elementFor(layer)

    local started = profile.now()
    local ok, drawn = pcall(layer.draw, view)
    profile.add(layer.key .. '.draw', started)

    if not ok then
        -- A broken third-party layer takes itself off the map, not the
        -- map off the screen.
        print('PixelMap: layer "' .. layer.key .. '" failed to draw: ' .. tostring(drawn))
        layer.enabled = false
        drawn = {}
    end

    -- A layer is allowed to be expensive, but silently expensive is what a
    -- player experiences as the map having become slow for no reason.
    if type(drawn) == 'table' and #drawn > config.LAYER_WIDGET_WARN then
        print(string.format('PixelMap: layer "%s" returned %d layouts; consider culling '
            .. 'to view.cellBounds() or drawing through PixelMap.cells',
            layer.key, #drawn))
    end

    local applied = profile.now()
    element.layout.props.visible = true
    element.layout.props.alpha = layer.alpha
    element.layout.props.inheritAlpha = layer.alpha and true or nil
    element.layout.content = ui.content(type(drawn) == 'table' and drawn or {})
    element:update()
    profile.add(layer.key .. '.ui', applied)
end

--- Empty a disabled layer's Element without destroying it, so re-enabling it
-- does not have to build one again.
function M.clearLayer(key)
    local element = elements[key]
    if not element then
        return
    end
    element.layout.props.visible = false
    element.layout.content = ui.content {}
    element:update()
end

--- The player's own marker, in an element of its own so a pan can move it
-- without rebuilding the canvas.
--
-- The element is sized to the marker rather than to the canvas. A full-canvas
-- widget on top of the stack is a sheet over the whole map, and a widget that
-- needs mouse focus takes every click and hover with it -- including the ones
-- meant for the layers and the pan-catcher underneath. Sized to the marker it
-- covers a few dozen pixels, and only the pixels it actually draws on.
local function drawPlayer(position)
    if not playerElement then
        return
    end

    local marker = view.cell and draw.marker {
        position = position,
        size = config.PLAYER_MARKER_SIZE,
        outline = config.PLAYER_MARKER_OUTLINE,
        color = config.COLOR_PLAYER,
        -- The window centres on the player often enough that culling the one
        -- marker that is usually dead centre buys nothing.
        cull = false,
    } or nil

    if marker then
        -- Take the marker's own geometry onto the wrapper, and its visuals
        -- inside at the origin.
        playerElement.layout.props.position = marker.props.position
        playerElement.layout.props.size = marker.props.size
        playerElement.layout.content = marker.content
    else
        playerElement.layout.props.position = util.vector2(0, 0)
        playerElement.layout.props.size = util.vector2(0, 0)
        playerElement.layout.content = ui.content {}
    end
    playerElement:update()
end

--- Draw every enabled layer, and clear the rest.
function M.drawAll(playerPosition)
    for _, layer in ipairs(layers.list()) do
        if layer.enabled then
            M.drawLayer(layer)
        else
            M.clearLayer(layer.key)
        end
    end
    drawPlayer(playerPosition)
end

--- Assemble the canvas: backdrop, ordinary layers, the caller's click-catcher,
-- then the interactive layers and the player on top.
--
-- `catcher` is passed in rather than built here because what a press on the
-- empty map means -- a pan -- is the window's business, not the canvas's.
function M.canvasContent(catcher)
    local content = {
        -- Sized by ratio (fills canvas during resize while layers use old size).
        {
            type = ui.TYPE.Image,
            props = {
                resource = draw.whiteTexture,
                color = terrain.voidColor(),
                relativeSize = util.vector2(1, 1),
            },
        },
    }

    local above = {}
    local live = {}
    for _, layer in ipairs(layers.list()) do
        live[layer.key] = true
        local element = elementFor(layer)
        if layer.interactive then
            above[#above + 1] = element
        else
            content[#content + 1] = element
        end
    end

    -- A layer that has unregistered still owns an Element. Nothing else will
    -- ever reference it again, so this is where it goes.
    for key, element in pairs(elements) do
        if not live[key] then
            element:destroy()
            elements[key] = nil
        end
    end

    content[#content + 1] = catcher
    for _, element in ipairs(above) do
        content[#content + 1] = element
    end

    -- Rebuilt every time rather than cached like the layer elements, and
    -- appended last, so the player is above whatever is registered on the map.
    -- A cached one is created the first time the canvas is built, which puts
    -- every layer registering after that -- anything wired up on
    -- PixelMapReady -- newer than the marker, and a mod's opaque ownership
    -- fills then paint over the one thing that must stay visible.
    if playerElement then
        playerElement:destroy()
    end
    playerElement = ui.create {
        type = ui.TYPE.Widget,
        -- Geometry is written by drawPlayer, which sizes this to the marker.
        -- Starts at zero rather than filling the canvas: see there for why a
        -- full-size one is a problem.
        props = {
            position = util.vector2(0, 0),
            size = util.vector2(0, 0),
        },
        content = ui.content {},
    }
    content[#content + 1] = playerElement

    return ui.content(content)
end

--- Destroy every Element, for a window teardown.
function M.reset()
    for key, element in pairs(elements) do
        element:destroy()
        elements[key] = nil
    end
    if playerElement then
        playerElement:destroy()
        playerElement = nil
    end
end

return M
