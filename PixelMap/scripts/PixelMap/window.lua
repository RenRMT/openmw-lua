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
local scroll = require('scripts.PixelMap.ui.scroll')
local widgets = require('scripts.PixelMap.ui.widgets')

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
local toggleBoxes = {}
-- The layer toggles scroll sideways when there are more of them than fit.
-- The slot is held so a resize can refill it at the new width.
local toggleSlot = nil
local toggleStrip = nil
local toggleBar = nil
local toggleOffset = 0
local toggleContent = 0
local toggleView = 0
-- What the canvas content was assembled for. When the set of layers or
-- their draw order changes the container has to be reassembled; when only
-- their contents change, it does not.
local canvasStructure = nil

-- The gesture in progress: a frame drag, a map pan, or the toggle scrollbar.
local drag = nil
-- Cursor relative to the window, kept from the last move so the wheel can tell
-- whether it was aimed at the toggle row or at the map.
local cursorOffset = nil
-- Set when a press/release pair has handled the gesture, so the
-- mouseClick that follows does not recentre on top of it.
local dragHandled = false

local refresh
local hide
local scrollToggles
local rebuildToggles
local toggleThumb

--------------------------------------------------------------------------
-- Small widgets
--------------------------------------------------------------------------

local function text(content, template)
    return {
        template = template or I.MWUI.templates.textNormal,
        props = { text = content },
    }
end

-- Hover recolouring mutates a layout in place and shows only on the next update.
widgets.setRefresh(function()
    if windowElement then
        windowElement:update()
    end
end)

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
    -- The toggle row spans the canvas, so its viewport and scrollbar are built
    -- for a width that the resize has just invalidated.
    rebuildToggles(canvasSize.x)

    if redrawLayers then
        refresh()
    else
        windowElement:update()
    end
end

--------------------------------------------------------------------------

-- Drag begins on first mouseMove with button held (mousePress never arrives).
-- Kind determined by cursor position within window; resolves from anchor (idempotent).

-- The toggle row's band, measured down from the top of the window. It starts
-- where the frame's title band ends, off the same constant, so the two agree
-- about where one stops and the other begins even though neither measures the
-- rendered text. Answers false when nothing overflows: there is no bar to hit.
local function overToggles(offset)
    if not (toggleBar and offset) then
        return false
    end
    local top = config.FRAME_GRAB + config.FRAME_TITLE_HEIGHT
    return offset.y >= top and offset.y <= top + config.TOGGLE_HEIGHT + config.SCROLL_THICKNESS
end

-- The toggle scrollbar claims its band; everything else is the frame's to read.
local function classifyGesture(offset, size)
    if overToggles(offset) then
        return 'toggles'
    end
    return frame.classify(offset, size)
end

local function beginDrag(kind, event)
    if not windowElement then
        return
    end
    dragHandled = false
    if kind == 'toggles' then
        drag = { toggles = true, origin = event.position, offset = toggleOffset }
    elseif kind == 'map' then
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

    if drag.toggles then
        local track = toggleView - 2 * config.SCROLL_ARROW
        local scale = scroll.dragScale(toggleContent, toggleView, track)
        toggleOffset = scroll.clamp(drag.offset + dx * scale, toggleContent, toggleView)
        toggleStrip.props.position = util.vector2(-toggleOffset, 0)
        widgets.thumbAt(toggleBar, toggleThumb(), config.SCROLL_ARROW,
                        config.SCROLL_THICKNESS, true)
        windowElement:update()
        return
    end

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

    if drag.toggles then
        -- Nothing on the map moved, so there is nothing to redraw.
        dragHandled = travelled >= config.DRAG_TAP_PIXELS
        drag = nil
        return
    end

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
    cursorOffset = event.offset or cursorOffset

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
        beginDrag(classifyGesture(event.offset, windowElement.layout.props.size), event)
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
    -- Over the toggle row the wheel scrolls it; anywhere else it zooms the map.
    if overToggles(cursorOffset) then
        scrollToggles(vertical > 0 and -config.SCROLL_STEP or config.SCROLL_STEP)
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

-- Rough width of one toggle, for deciding whether the row overflows. The engine
-- reports no measured size back to Lua, so the strip's extent has to be
-- estimated; over-estimating only shows a scrollbar a little early.
local function toggleWidth(layer)
    return config.TOGGLE_BOX + 5 + #layer.name * 8 + config.TOGGLE_GAP
end

toggleThumb = function()
    local track = toggleView - 2 * config.SCROLL_ARROW
    return scroll.thumb(toggleContent, toggleView, track, toggleOffset, config.TOGGLE_GAP)
end

local function buildToggleStrip()
    toggleBoxes = {}
    local row = {}
    toggleContent = 0
    for _, layer in ipairs(layers.list()) do
        local key = layer.key
        local box = widgets.checkbox {
            checked = layer.enabled,
            label = layer.name,
            size = config.TOGGLE_BOX,
            onClick = function() toggleLayer(key) end,
        }
        toggleBoxes[key] = box
        row[#row + 1] = box
        row[#row + 1] = { props = { size = util.vector2(config.TOGGLE_GAP, 0) } }
        toggleContent = toggleContent + toggleWidth(layer)
    end
    return row
end

-- Viewport clipping an inner flex, plus a scrollbar that appears only when the
-- toggles outrun the window. The bar carries no drag handler: a child widget
-- gets neither mousePress nor mouseMove, so the root gesture handler drives it.
--
-- Returned as the contents of `toggleSlot`, which the window keeps a reference
-- to so a resize can refill it at the new width rather than rebuild the window.
local function toggleRowContent(width)
    toggleView = width
    local strip = buildToggleStrip()
    if #strip == 0 then
        return { text(l10n('noLayers')) }
    end

    toggleOffset = scroll.clamp(toggleOffset, toggleContent, toggleView)
    toggleStrip = {
        type = ui.TYPE.Flex,
        props = { horizontal = true, arrange = ui.ALIGNMENT.Center,
                  position = util.vector2(-toggleOffset, 0) },
        content = ui.content(strip),
    }

    local viewport = {
        type = ui.TYPE.Widget,
        props = { size = util.vector2(width, config.TOGGLE_HEIGHT) },
        content = ui.content { toggleStrip },
    }

    -- A hidden widget still occupies its place in a flex, so the bar is left out
    -- entirely rather than hidden when everything fits.
    local thumb = toggleThumb()
    if not thumb.visible then
        toggleBar = nil
        toggleOffset = 0
        toggleStrip.props.position = util.vector2(0, 0)
        return { viewport }
    end

    toggleBar = widgets.scrollbar {
        horizontal = true,
        thickness = config.SCROLL_THICKNESS,
        length = width,
        arrow = config.SCROLL_ARROW,
        thumb = thumb,
        onStepBack = function() scrollToggles(-config.SCROLL_STEP) end,
        onStepOn = function() scrollToggles(config.SCROLL_STEP) end,
    }

    return { viewport, toggleBar }
end

local function buildToggleRow(width)
    toggleSlot = {
        type = ui.TYPE.Flex,
        props = { horizontal = false, arrange = ui.ALIGNMENT.Start },
        content = ui.content(toggleRowContent(width)),
    }
    return toggleSlot
end

-- Refill the slot at a new width. Called on resize, and when a layer registers
-- or unregisters and the row's contents are no longer what was built.
--
-- `force` is for the latter: a resize fires every frame the cursor moves and the
-- width usually has not changed, so by default an unchanged width does nothing.
rebuildToggles = function(width, force)
    if not toggleSlot or (not force and width == toggleView) then
        return
    end
    toggleSlot.content = ui.content(toggleRowContent(width))
end

-- Shift the toggle strip and move its thumb, without rebuilding either.
scrollToggles = function(delta)
    if not (windowElement and toggleStrip and toggleBar) then
        return
    end
    toggleOffset = scroll.clamp(toggleOffset + delta, toggleContent, toggleView)
    toggleStrip.props.position = util.vector2(-toggleOffset, 0)
    widgets.thumbAt(toggleBar, toggleThumb(), config.SCROLL_ARROW,
                    config.SCROLL_THICKNESS, true)
    windowElement:update()
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
    for key, box in pairs(toggleBoxes) do
        local layer = layers.get(key)
        if layer then
            widgets.setChecked(box, layer.enabled)
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
    updateChrome()
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
        -- A layer that has just appeared or gone needs its toggle added or
        -- removed, which the width alone would not tell us.
        rebuildToggles(view.canvasSize.x, true)
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
    updateChrome()
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
                buildToggleRow(view.canvasSize.x),
                { template = I.MWUI.templates.interval },
                canvasContainer,
                { template = I.MWUI.templates.interval },
                flex(true, {
                    widgets.button(l10n('zoomOut'), function()
                        view.zoomBy(1 / config.ZOOM_STEP)
                        refresh()
                    end),
                    { template = I.MWUI.templates.interval },
                    widgets.button(l10n('zoomIn'), function()
                        view.zoomBy(config.ZOOM_STEP)
                        refresh()
                    end),
                    { template = I.MWUI.templates.interval },
                    widgets.button(l10n('recenter'), centerOnPlayer),
                    { template = I.MWUI.templates.interval },
                    widgets.button(l10n('close'), function() hide() end),
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
    cursorOffset = nil

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
    toggleBoxes = {}
    toggleSlot = nil
    toggleStrip = nil
    toggleBar = nil
    toggleOffset = 0

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
