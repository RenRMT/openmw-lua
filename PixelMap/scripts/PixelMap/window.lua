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
local terrain = require('scripts.PixelMap.core.terrain')
local tooltip = require('scripts.PixelMap.core.tooltip')
local view = require('scripts.PixelMap.core.view')
local uiResize = require('scripts.PixelMap.ui.resize')
local widgets = require('scripts.PixelMap.ui.widgets')

local storage = require('openmw.storage')

-- Where the window was left. Position and size both live here rather than in
-- the settings page: they are a place on the screen, not something to type.
local geometry = storage.playerSection('PixelMap/Window')

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
-- The layer toggles wrap onto as many rows as the width needs. The slot is held
-- so a resize can refill it, and the width it was filled at so one that has not
-- changed does nothing.
local toggleSlot = nil
local toggleSlotWidth = nil
-- What the canvas content was assembled for. When the set of layers or
-- their draw order changes the container has to be reassembled; when only
-- their contents change, it does not.
local canvasStructure = nil

-- The map pan in progress. The chrome's own drags live in their widgets.
local drag = nil
-- The window rect recorded when a move- or resize-strip drag began, so the
-- gesture resolves from its anchor rather than from the previous event.
local windowStart = nil
-- Canvas size when the layers were last redrawn during a resize, so a slow drag
-- still redraws once it has moved far enough.
local resizeDrawnAt = nil
-- Set when a press/release pair has handled the gesture, so the
-- mouseClick that follows does not recentre on top of it.
local dragHandled = false

local refresh
local hide
local rebuildToggles
local toggleRowCount

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


-- The margin covers one row of toggles; every row they wrap onto beyond the
-- first comes out of the map rather than off the bottom of the window.
local function canvasSizeFor(windowSize)
    local width = math.max(config.CANVAS_MIN_WIDTH, windowSize.x - config.WINDOW_MARGIN_X)
    local extraRows = math.max(0, toggleRowCount(width) - 1)
    return util.vector2(width, math.max(config.CANVAS_MIN_HEIGHT,
        windowSize.y - config.WINDOW_MARGIN_Y - extraRows * config.TOGGLE_HEIGHT))
end

-- Window sized to screen fraction (same ratio on 4K and 1080p).
local function defaultWindowSize()
    local screen = frame.screenBounds()
    return util.vector2(
        math.max(config.WINDOW_MIN_WIDTH, math.floor(screen.x * config.CANVAS_SCREEN_FRACTION)),
        math.max(config.WINDOW_MIN_HEIGHT, math.floor(screen.y * config.CANVAS_SCREEN_FRACTION)))
end

-- The bounds every drag is clamped to: the screen, and the window's minimum.
local function screenLimits()
    local screen = frame.screenBounds()
    return {
        minW = config.WINDOW_MIN_WIDTH,
        minH = config.WINDOW_MIN_HEIGHT,
        screenW = screen.x,
        screenH = screen.y,
    }
end

local function saveGeometry()
    if not windowElement then
        return
    end
    local props = windowElement.layout.props
    geometry:set('rect', {
        x = math.floor(props.position.x), y = math.floor(props.position.y),
        w = math.floor(props.size.x), h = math.floor(props.size.y),
    })
end

-- Where to open. A remembered rect is clamped back onto the screen first, so a
-- window left on a second monitor -- or saved before a resolution change -- does
-- not open off the edge.
local function openingRect()
    local screen = frame.screenBounds()
    local saved = geometry:get('rect')
    if saved and saved.w and saved.h then
        local w = math.min(math.max(saved.w, config.WINDOW_MIN_WIDTH), screen.x)
        local h = math.min(math.max(saved.h, config.WINDOW_MIN_HEIGHT), screen.y)
        return util.vector2(
            math.max(0, math.min(saved.x or 0, screen.x - w)),
            math.max(0, math.min(saved.y or 0, screen.y - h))), util.vector2(w, h)
    end
    local size = defaultWindowSize()
    return util.vector2(math.floor((screen.x - size.x) * 0.5),
                        math.floor((screen.y - size.y) * 0.5)), size
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
    -- The toggles wrap to the canvas width, which the resize has just changed.
    rebuildToggles(canvasSize.x)

    if redrawLayers then
        refresh()
    else
        windowElement:update()
    end
end

--------------------------------------------------------------------------

-- Every draggable part of the chrome -- the top move band and the eight resize
-- strips -- owns its own press/move/release through widgets.draggable, and
-- resolves from the rect recorded at press so a repeated event lands in the same
-- place. Only the map pan is left on the root, because the canvas is a single
-- widget and the gesture has to be told apart from the click that recentres.

-- Move the window. The strip hands over the total delta since its press.
local function moveWindow(delta)
    if not (windowElement and windowStart) then
        return
    end
    local rect = uiResize.apply('move', windowStart, delta, screenLimits())
    windowElement.layout.props.position = util.vector2(rect.x, rect.y)
    windowElement:update()
end

-- Resize the window. Layer redraws are throttled by how far the canvas has
-- actually travelled, so a slow drag still redraws on the way.
local function resizeWindow(grab, delta)
    if not (windowElement and windowStart) then
        return
    end
    local rect = uiResize.apply(grab, windowStart, delta, screenLimits())
    local size = util.vector2(rect.w, rect.h)
    local canvasSize = canvasSizeFor(size)
    local moved = math.abs(canvasSize.x - resizeDrawnAt.x)
        + math.abs(canvasSize.y - resizeDrawnAt.y)
    local redraw = moved >= config.RESIZE_REDRAW_PIXELS
    if redraw then
        resizeDrawnAt = canvasSize
    end
    applyWindowRect(util.vector2(rect.x, rect.y), size, redraw)
end

-- Handed to frame.grabs() so each strip drives the resize itself.
local frameHandlers = {
    onStart = function()
        if not windowElement then
            return
        end
        local props = windowElement.layout.props
        windowStart = { x = props.position.x, y = props.position.y,
                        w = props.size.x, h = props.size.y }
        resizeDrawnAt = view.canvasSize
    end,
    onMove = function(grab, delta)
        if grab == 'move' then
            moveWindow(delta)
        else
            resizeWindow(grab, delta)
        end
    end,
    onEnd = function()
        windowStart = nil
        -- Whatever the redraw throttle skipped on the way.
        refresh()
        saveGeometry()
    end,
}

local function beginPan(event)
    dragHandled = false
    drag = {
        origin = event.position,
        center = view.center,
        drawnDx = 0,
        drawnDy = 0,
    }
end

local function continuePan(event)
    if not drag then
        return
    end
    local dx = event.position.x - drag.origin.x
    local dy = event.position.y - drag.origin.y
    -- Where the gesture had genuinely reached, for a drag that ends
    -- without a release telling us where it ended.
    drag.last = event.position

    -- Anchored on the centre the drag began at, so this cannot drift.
    view.centerOn(drag.center.x - dx / view.zoom, drag.center.y + dy / view.zoom)
    if math.abs(dx - drag.drawnDx) + math.abs(dy - drag.drawnDy)
        >= config.DRAG_REDRAW_PIXELS then
        drag.drawnDx, drag.drawnDy = dx, dy
        refresh()
    end
end

local function endPan(event)
    if not drag then
        return
    end
    local dx = event.position.x - drag.origin.x
    local dy = event.position.y - drag.origin.y
    local travelled = math.abs(dx) + math.abs(dy)

    view.centerOn(drag.center.x - dx / view.zoom, drag.center.y + dy / view.zoom)
    -- Below the tap threshold this was a click, and the click handler
    -- is about to recentre on the exact point instead.
    if travelled >= config.DRAG_TAP_PIXELS then
        dragHandled = true
        refresh()
    end
    drag = nil
end

--- Panning the map, on the root.
--
-- The chrome having taken its own gestures, a press that reaches here is over
-- the map. `button` is 1 while a button is held and nil otherwise, which stands
-- in for a release that can land off the window and never arrive.
local onRootMove = async:callback(function(event)
    -- The only place a cursor position is available. A hovered marker
    -- cannot place its own tooltip without it.
    tooltip.cursor(event.position)

    if event.button ~= 1 then
        if drag then
            endPan { position = drag.last or drag.origin }
        end
        return
    end
    if not drag then
        if not windowElement or not event.offset then
            return
        end
        -- Only the middle of the window pans; the chrome has its own handlers,
        -- and a press on it must not also drag the map underneath.
        if frame.classify(event.offset, windowElement.layout.props.size) ~= 'map' then
            return
        end
        beginPan(event)
    end
    continuePan(event)
end)

local onRootRelease = async:callback(endPan)

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

-- Rough width of one toggle, for deciding where a row breaks. The engine reports
-- no measured size back to Lua, so the extent has to be estimated;
-- over-estimating only wraps a toggle a little early.
local function toggleWidth(layer)
    return config.TOGGLE_BOX + 5 + #layer.name * 8 + config.TOGGLE_GAP
end

-- Walk the toggles, calling `onRow` at every break. Shared so the row count the
-- canvas is sized from and the rows that are built cannot disagree.
local function wrapToggles(width, onLayer, onRow)
    local used = 0
    for _, layer in ipairs(layers.list()) do
        local span = toggleWidth(layer)
        if used > 0 and used + span > width then
            onRow()
            used = 0
        end
        used = used + span
        if onLayer then
            onLayer(layer)
        end
    end
    return used
end

toggleRowCount = function(width)
    local rows = 1
    local used = wrapToggles(width, nil, function() rows = rows + 1 end)
    return used > 0 and rows or math.max(1, rows - 1)
end

-- Returned as the contents of `toggleSlot`, which the window keeps a reference
-- to so a resize can refill it at the new width rather than rebuild the window.
local function toggleRowContent(width)
    toggleBoxes = {}
    local rows = {}
    local row = {}

    local function flush()
        rows[#rows + 1] = {
            type = ui.TYPE.Flex,
            props = { horizontal = true, arrange = ui.ALIGNMENT.Center },
            content = ui.content(row),
        }
        row = {}
    end

    wrapToggles(width, function(layer)
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
    end, flush)

    if #row > 0 then
        flush()
    end
    if #rows == 0 then
        return { text(l10n('noLayers')) }
    end
    return rows
end

local function buildToggleRow(width)
    toggleSlotWidth = width
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
    if not toggleSlot or (not force and width == toggleSlotWidth) then
        return
    end
    toggleSlotWidth = width
    toggleSlot.content = ui.content(toggleRowContent(width))
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
    -- The layer's widgets, and any tooltip of theirs the cursor is sitting in,
    -- are about to be rebuilt or cleared.
    tooltip.dismiss()
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
        -- removed, and may push the row count -- and so the map's height -- over
        -- or under a wrap. Neither follows from the width alone.
        local canvasSize = canvasSizeFor(windowElement.layout.props.size)
        view.setCanvasSize(canvasSize)
        canvasContainer.props.size = canvasSize
        rebuildToggles(canvasSize.x, true)
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
        -- The engine's own thick window border, rather than a plain filled box.
        type = ui.TYPE.Container,
        template = I.MWUI.templates.boxTransparentThick,
        props = { relativeSize = util.vector2(1, 1) },
        content = ui.content {
            flex(false, {
                -- Empty band where a title bar would be. The frame's invisible
                -- 'move' strip sits over it, so the window still drags from the
                -- top without anything being drawn there.
                { props = { size = util.vector2(0, config.FRAME_MOVE_HEIGHT) } },
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

    local windowPos, windowSize = openingRect()
    view.setCanvasSize(canvasSizeFor(windowSize))

    -- Body first, then the grab strips on top of it, so the strips win the
    -- overlapping hit area at the window's edge.
    local content = { body() }
    for _, grab in ipairs(frame.grabs(frameHandlers)) do
        content[#content + 1] = grab
    end

    windowElement = ui.create {
        layer = 'Windows',
        props = { position = windowPos, size = windowSize },
        -- The chrome takes its own gestures; what reaches the root is the map.
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
    -- dismiss, not hide: the click that closed the map destroyed whatever was
    -- hovered, so no focusLoss is coming and a trailing move would show it again
    -- over the game.
    tooltip.dismiss()
    drag = nil
    dragHandled = false
    windowStart = nil

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
    toggleSlotWidth = nil

    if windowElement then
        windowElement:destroy()
        windowElement = nil
    end
end

hide = function()
    if not windowElement then
        return
    end
    -- Drop our mode and let the UiModeChanged handler do the destroy: that is
    -- the one path every close goes through -- this button, the open key,
    -- Escape, another screen taking over -- and it also restores the windows
    -- the open hid. Doing it here as well would tear down twice.
    if I.UI.getMode() == 'Interface' then
        I.UI.setMode()
    else
        -- The map is up without our mode, so no mode change is coming.
        destroy()
    end
end

return {
    show = show,
    hide = hide,
    destroy = destroy,
    refresh = refresh,
    wheel = wheel,
    isOpen = function() return windowElement ~= nil end,
    -- The live Element, for the tests that drive the chrome's own drag
    -- callbacks. Nothing in the mod reads this.
    _test_element = function() return windowElement end,
}
