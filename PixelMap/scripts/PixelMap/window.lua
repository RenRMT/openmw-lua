-- Map window: frame, chrome, and the canvas the layers draw into.

local async = require('openmw.async')
local core = require('openmw.core')
local self = require('openmw.self')
local ui = require('openmw.ui')
local util = require('openmw.util')

local I = require('openmw.interfaces')

local config = require('scripts.PixelMap.core.config')
local draw = require('scripts.PixelMap.core.draw')
local frame = require('scripts.PixelMap.core.frame')
local layers = require('scripts.PixelMap.core.layers')
local profile = require('scripts.PixelMap.core.profile')
local tooltip = require('scripts.PixelMap.core.tooltip')
local view = require('scripts.PixelMap.core.view')

local l10n = core.l10n(config.L10N_CONTEXT, 'en')

local windowElement = nil
-- One Element per layer, kept across redraws so that a redraw replaces
-- that layer's contents and touches nothing else.
local layerElements = {}
-- Layout tables held by reference so chrome can be changed in place
-- rather than rebuilt.
local canvasContainer = nil
-- The player's own marker. Not a registered layer: it has no business in
-- the toggle row, and a map that can hide where you are is not a feature.
local playerElement = nil
local statusText = nil
local toggleTexts = {}
-- What the canvas content was assembled for. When the set of layers or
-- their draw order changes the container has to be reassembled; when only
-- their contents change, it does not.
local canvasStructure = nil

-- The gesture in progress: either a frame drag or a map pan.
local drag = nil
-- Set when a press/release pair has handled the gesture, so the
-- mouseClick that follows does not recentre on top of it.
local dragHandled = false

local refresh
local hide

--------------------------------------------------------------------------
-- Small widgets
--------------------------------------------------------------------------

local function text(content, template)
    return {
        template = template or I.MWUI.templates.textNormal,
        props = { text = content },
    }
end

local function button(label, onClick)
    return {
        template = I.MWUI.templates.box,
        content = ui.content {
            {
                template = I.MWUI.templates.textNormal,
                props = { text = ' ' .. label .. ' ' },
                events = { mouseClick = async:callback(onClick) },
            },
        },
    }
end

local function flex(horizontal, content)
    return {
        type = ui.TYPE.Flex,
        props = { horizontal = horizontal, arrange = ui.ALIGNMENT.Start },
        content = ui.content(content),
    }
end


local function canvasSizeFor(windowSize)
    return util.vector2(
        math.max(config.CANVAS_MIN_WIDTH, windowSize.x - config.WINDOW_MARGIN_X),
        math.max(config.CANVAS_MIN_HEIGHT, windowSize.y - config.WINDOW_MARGIN_Y))
end

-- Window sized to screen fraction (same ratio on 4K and 1080p).
local function defaultWindowSize()
    local screen = frame.screenBounds()
    return util.vector2(
        math.max(config.WINDOW_MIN_WIDTH, math.floor(screen.x * config.CANVAS_SCREEN_FRACTION)),
        math.max(config.WINDOW_MIN_HEIGHT, math.floor(screen.y * config.CANVAS_SCREEN_FRACTION)))
end

-- Apply window rect; redrawLayers=false while resize throttles layer updates.
local function applyWindowRect(position, size, redrawLayers)
    if not windowElement then
        return
    end
    windowElement.layout.props.position = position
    windowElement.layout.props.size = size

    local canvasSize = canvasSizeFor(size)
    view.setCanvasSize(canvasSize)
    if canvasContainer then
        canvasContainer.props.size = canvasSize
    end

    if redrawLayers then
        refresh()
    else
        windowElement:update()
    end
end

--------------------------------------------------------------------------

-- Drag begins on first mouseMove with button held (mousePress never arrives).
-- Kind determined by cursor position within window; resolves from anchor (idempotent).

local function beginDrag(kind, event)
    if not windowElement then
        return
    end
    dragHandled = false
    if kind == 'map' then
        drag = {
            map = true,
            origin = event.position,
            center = view.center,
            drawnDx = 0,
            drawnDy = 0,
        }
    else
        drag = {
            grab = kind,
            origin = event.position,
            position = windowElement.layout.props.position,
            size = windowElement.layout.props.size,
            -- Canvas size when the layers were last redrawn, so a slow
            -- drag still redraws once it has moved far enough.
            drawnAt = view.canvasSize,
        }
    end
end

local function continueDrag(event)
    if not drag then
        return
    end
    local dx = event.position.x - drag.origin.x
    local dy = event.position.y - drag.origin.y
    -- Where the gesture had genuinely reached, for a drag that ends
    -- without a release telling us where it ended.
    drag.last = event.position

    if drag.map then
        -- Anchored on the centre the drag began at, so this cannot drift.
        view.centerOn(drag.center.x - dx / view.zoom, drag.center.y + dy / view.zoom)
        if math.abs(dx - drag.drawnDx) + math.abs(dy - drag.drawnDy)
            >= config.DRAG_REDRAW_PIXELS then
            drag.drawnDx, drag.drawnDy = dx, dy
            refresh()
        end
        return
    end

    local position, size = frame.resolve(drag.grab, drag.position, drag.size,
                                         util.vector2(dx, dy), frame.screenBounds())
    local canvasSize = canvasSizeFor(size)
    local moved = math.abs(canvasSize.x - drag.drawnAt.x)
        + math.abs(canvasSize.y - drag.drawnAt.y)
    local redraw = moved >= config.RESIZE_REDRAW_PIXELS
    if redraw then
        drag.drawnAt = canvasSize
    end
    applyWindowRect(position, size, redraw)
end

local function endDrag(event)
    if not drag then
        return
    end
    local dx = event.position.x - drag.origin.x
    local dy = event.position.y - drag.origin.y
    local travelled = math.abs(dx) + math.abs(dy)

    if drag.map then
        view.centerOn(drag.center.x - dx / view.zoom, drag.center.y + dy / view.zoom)
        -- Below the tap threshold this was a click, and the click handler
        -- is about to recentre on the exact point instead.
        if travelled >= config.DRAG_TAP_PIXELS then
            dragHandled = true
            refresh()
        end
    else
        -- Whatever the redraw throttle skipped during the resize.
        refresh()
        dragHandled = travelled >= config.DRAG_TAP_PIXELS
    end
    drag = nil
end

--- The whole gesture system: one handler, on the root.
--
-- `button` is 1 while a button is held and nil otherwise, which is what
-- stands in for the press and release that never arrive.
local onRootMove = async:callback(function(event)
    -- The only place a cursor position is available. A hovered marker
    -- cannot place its own tooltip without it.
    tooltip.cursor(event.position)

    if event.button ~= 1 then
        -- Button up; end here at last drag point if release never arrived.
        if drag then
            endDrag { position = drag.last or drag.origin }
        end
        return
    end
    if not drag then
        if not windowElement or not event.offset then
            return
        end
        beginDrag(frame.classify(event.offset, windowElement.layout.props.size), event)
    end
    continueDrag(event)
end)

local onRootRelease = async:callback(endDrag)

--- Recentre on a click.
--
-- Kept on the canvas rather than the root because only a widget-local
-- event carries `offset`, and a recentre needs the point inside the
-- canvas, not the point on the screen.
local onCanvasClick = async:callback(function(event)
    if dragHandled then
        dragHandled = false
        return
    end
    local world = view.canvasToWorld(event.offset.x, event.offset.y)
    view.centerOn(world.x, world.y)
    refresh()
end)

--- The wheel is not a widget event. It arrives as the onMouseWheel engine
-- handler, which is global to the script, so the window decides for
-- itself whether the wheel was meant for it.
local function wheel(vertical)
    if not windowElement or drag or vertical == 0 then
        return
    end
    view.zoomBy(vertical > 0 and config.ZOOM_STEP or 1 / config.ZOOM_STEP)
    refresh()
end


local function catcher()
    -- A transparent sheet over the drawing layers. A press that lands on
    -- a terrain quad does not reach the widget underneath it, so this is
    -- the widget that receives the gesture on behalf of the map. It sits
    -- below the interactive layers, so their markers keep their own
    -- hover and clicks.
    return {
        type = ui.TYPE.Image,
        props = draw.invisible { relativeSize = util.vector2(1, 1) },
        -- The drag is handled on the root, so this only needs the click.
        -- A child widget does receive mouseMove and focusGain/focusLoss
        -- as well, provided nothing above it has taken the mouse.
        events = { mouseClick = onCanvasClick },
    }
end

--- The player's own marker, in an element of its own so a pan can move it
-- without rebuilding the canvas.
--
-- The element is sized to the marker rather than to the canvas. A
-- full-canvas widget on top of the stack is a sheet over the whole map,
-- and a widget that needs mouse focus takes every click and hover with
-- it -- including the ones meant for the layers and the pan-catcher
-- underneath. Sized to the marker it covers a few dozen pixels, and only
-- the pixels it actually draws on.
local function drawPlayer()
    if not playerElement then
        return
    end

    local marker = view.cell and draw.marker {
        position = self.position,
        size = config.PLAYER_MARKER_SIZE,
        outline = config.PLAYER_MARKER_OUTLINE,
        color = config.COLOR_PLAYER,
    } or nil

    if marker then
        -- Take the marker's own geometry onto the wrapper, and its
        -- visuals inside at the origin.
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

local function elementFor(layer)
    local element = layerElements[layer.key]
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
        layerElements[layer.key] = element
    end
    return element
end

local function drawLayer(layer)
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

    local applied = profile.now()
    element.layout.props.visible = true
    element.layout.props.alpha = layer.alpha
    element.layout.props.inheritAlpha = layer.alpha and true or nil
    element.layout.content = ui.content(type(drawn) == 'table' and drawn or {})
    element:update()
    profile.add(layer.key .. '.ui', applied)
end

--- Empty a layer without destroying its Element.
--
-- Both the content and the visible flag are cleared: `visible` alone is
-- enough if the prop behaves as its name says, and emptying the content
-- is enough if it does not.
local function clearLayer(key)
    local element = layerElements[key]
    if not element then
        return
    end
    element.layout.props.visible = false
    element.layout.content = ui.content {}
    element:update()
end

local function structureOf()
    local parts = {}
    for _, layer in ipairs(layers.list()) do
        parts[#parts + 1] = layer.key .. (layer.interactive and '!' or '')
    end
    return table.concat(parts, ',')
end

-- Assemble canvas: background, static layers, click-catcher, interactive layers.
local function buildCanvasContent()
    local content = {
        -- Sized by ratio (fills canvas during resize while layers use old size).
        {
            type = ui.TYPE.Image,
            props = {
                resource = draw.whiteTexture,
                color = config.COLOR_VOID,
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

    -- A layer that has unregistered still owns an Element. Nothing else
    -- will ever reference it again, so this is where it goes.
    for key, element in pairs(layerElements) do
        if not live[key] then
            element:destroy()
            layerElements[key] = nil
        end
    end
    content[#content + 1] = catcher()
    for _, element in ipairs(above) do
        content[#content + 1] = element
    end

    -- Rebuilt every time rather than cached like the layer elements, and
    -- appended last, so the player is above whatever is registered on the
    -- map. A cached one is created the first time the canvas is built,
    -- which puts every layer registering after that -- anything wired up
    -- on PixelMapReady -- newer than the marker, and a mod's opaque
    -- ownership fills then paint over the one thing that must stay
    -- visible.
    if playerElement then
        playerElement:destroy()
    end
    playerElement = ui.create {
        type = ui.TYPE.Widget,
        -- Geometry is written by drawPlayer, which sizes this to the
        -- marker. Starts at zero rather than filling the canvas: see
        -- there for why a full-size one is a problem.
        props = {
            position = util.vector2(0, 0),
            size = util.vector2(0, 0),
        },
        content = ui.content {},
    }
    content[#content + 1] = playerElement

    canvasStructure = structureOf()
    return ui.content(content)
end


local toggleLayer

local function buildToggleRow()
    toggleTexts = {}
    local row = {}
    for _, layer in ipairs(layers.list()) do
        local key = layer.key
        local label = {
            template = I.MWUI.templates.textNormal,
            props = { text = ' [x] ' .. layer.name .. ' ' },
            events = { mouseClick = async:callback(function() toggleLayer(key) end) },
        }
        toggleTexts[key] = label
        row[#row + 1] = {
            template = I.MWUI.templates.box,
            content = ui.content { label },
        }
        row[#row + 1] = { template = I.MWUI.templates.interval }
    end
    if #row == 0 then
        return text(l10n('noLayers'))
    end
    return flex(true, row)
end

local function statusFor()
    if not view.cell then
        return l10n('interior')
    end
    return l10n('status', {
        cellX = math.floor(view.center.x / config.CELL_SIZE),
        cellY = math.floor(view.center.y / config.CELL_SIZE),
        cellPixels = string.format('%.0f', config.CELL_SIZE * view.zoom),
    })
end

-- Labels only; never rebuilds a layer.
local function updateChrome()
    if not windowElement then
        return
    end
    if statusText then
        statusText.props.text = statusFor()
    end
    for key, label in pairs(toggleTexts) do
        local layer = layers.get(key)
        if layer then
            label.props.text = (layer.enabled and ' [x] ' or ' [ ] ') .. layer.name .. ' '
        end
    end
    windowElement:update()
end

toggleLayer = function(key)
    layers.toggle(key)
    local layer = layers.get(key)
    if layer and layer.enabled then
        drawLayer(layer)
    else
        clearLayer(key)
    end

end

local function centerOnPlayer()
    view.centerOn(self.position.x, self.position.y)
    refresh()
end


local function redrawLayers()
    -- A layer registered since the window opened has no place in the
    -- canvas yet, and one removed still has one.
    if windowElement and canvasContainer and structureOf() ~= canvasStructure then
        canvasContainer.content = buildCanvasContent()
    end
    for _, layer in ipairs(layers.list()) do
        if layer.enabled then
            drawLayer(layer)
        else
            clearLayer(layer.key)
        end
    end
    drawPlayer()
end

refresh = function()
    if not windowElement then
        return
    end
    profile.reset()
    redrawLayers()

    local started = profile.now()

    profile.add('chrome', started)
    profile.flush('redraw')
end


local function body()
    canvasContainer = {
        type = ui.TYPE.Widget,
        props = { size = view.canvasSize },
        content = buildCanvasContent(),
    }
    statusText = text(statusFor())

    return {
        template = I.MWUI.templates.boxSolid,
        props = { relativeSize = util.vector2(1, 1) },
        content = ui.content {
            flex(false, {
                -- Top band drags window; invisible child strip doesn't work (can't receive drag).
                text(l10n('windowTitle'), I.MWUI.templates.textHeader),
                { template = I.MWUI.templates.horizontalLine },
                buildToggleRow(),
                { template = I.MWUI.templates.interval },
                canvasContainer,
                { template = I.MWUI.templates.interval },
                flex(true, {
                    button(l10n('zoomOut'), function()
                        view.zoomBy(1 / config.ZOOM_STEP)
                        refresh()
                    end),
                    { template = I.MWUI.templates.interval },
                    button(l10n('zoomIn'), function()
                        view.zoomBy(config.ZOOM_STEP)
                        refresh()
                    end),
                    { template = I.MWUI.templates.interval },
                    button(l10n('recenter'), centerOnPlayer),
                    { template = I.MWUI.templates.interval },
                    button(l10n('close'), function() hide() end),
                    { template = I.MWUI.templates.interval },
                    statusText,
                }),
            }),
        },
    }
end

local function show()
    -- Exterior worldspace determines land layer queries; read once per open.
    local cell = self.cell
    local exterior = (cell and cell.isExterior) and cell or nil
    view.cell = exterior
    view.worldSpaceId = exterior and exterior.worldSpaceId or nil
    if exterior then
        view.centerOn(self.position.x, self.position.y)
    end

    if windowElement then
        refresh()
        return
    end

    local windowSize = defaultWindowSize()
    local screen = frame.screenBounds()
    view.setCanvasSize(canvasSizeFor(windowSize))

    local content = { body() }
    for _, grab in ipairs(frame.grabs()) do
        content[#content + 1] = grab
    end

    windowElement = ui.create {
        layer = 'Windows',
        props = {
            position = util.vector2(math.floor((screen.x - windowSize.x) * 0.5),
                                    math.floor((screen.y - windowSize.y) * 0.5)),
            size = windowSize,
        },
        -- Only mouseMove and mouseRelease delivered (mousePress never arrives).
        events = {
            mouseMove = onRootMove,
            mouseRelease = onRootRelease,
        },
        content = ui.content(content),
    }
    refresh()
end

-- Tear down without touching UI mode (used when other screen mode takes over).
local function destroy()
    -- Tooltip lives on own layer; hide to prevent hanging over game.
    tooltip.hide()
    drag = nil
    dragHandled = false

    for key, element in pairs(layerElements) do
        element:destroy()
        layerElements[key] = nil
    end
    if playerElement then
        playerElement:destroy()
        playerElement = nil
    end
    canvasContainer = nil
    canvasStructure = nil
    statusText = nil
    toggleTexts = {}

    if windowElement then
        windowElement:destroy()
        windowElement = nil
    end
end

hide = function()
    destroy()
    if I.UI.getMode() == 'Interface' then
        I.UI.setMode()
    end
end

return {
    show = show,
    hide = hide,
    destroy = destroy,
    refresh = refresh,
    wheel = wheel,
    isOpen = function() return windowElement ~= nil end,
}
