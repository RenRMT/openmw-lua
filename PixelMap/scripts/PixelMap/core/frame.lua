-- Window frame: eight invisible grab strips for resize/move. Hand-rolled: ui.TYPE.Window cannot resize.
-- The arithmetic lives in ui/resize.lua; this owns the strips and the screen.

local ui = require('openmw.ui')
local util = require('openmw.util')

local config = require('scripts.PixelMap.core.config')
local draw = require('scripts.PixelMap.core.draw')
local resize = require('scripts.PixelMap.ui.resize')
local widgets = require('scripts.PixelMap.ui.widgets')

local v2 = util.vector2

local POINTERS = {
    move = 'arrow',
    left = 'hresize',
    right = 'hresize',
    top = 'vresize',
    bottom = 'vresize',
    topLeft = 'dresize',
    topRight = 'dresize2',
    bottomLeft = 'dresize2',
    bottomRight = 'dresize',
}

-- Build strips using relativeSize: `relativeSize * parent + size` spans full width without knowing width.
--
-- `handlers` (optional) gives each strip its own drag: onStart(key),
-- onMove(key, delta), onEnd(key). Without it the strips are cursor hints only
-- and whatever owns the root is left to read the gesture.
local function grabs(handlers)
    local g = config.FRAME_GRAB
    local out = {}

    local function strip(key, props)
        props.pointer = POINTERS[key]
        props.propagateEvents = false
        local node = {
            name = 'grab_' .. key,
            type = ui.TYPE.Image,
            props = draw.invisible(props),
        }
        if handlers then
            widgets.draggable(node, {
                onStart = function() handlers.onStart(key) end,
                onMove = function(delta) handlers.onMove(key, delta) end,
                onEnd = function() handlers.onEnd(key) end,
            })
        end
        out[#out + 1] = node
    end

    -- The empty band the body reserves at the top. First, so the edge and
    -- corner strips win wherever they overlap it.
    strip('move', { position = v2(g, g), relativeSize = v2(1, 0),
                    size = v2(-2 * g, config.FRAME_MOVE_HEIGHT) })

    -- Edges first, then corners on top.
    strip('top', { position = v2(g, 0), relativeSize = v2(1, 0), size = v2(-2 * g, g) })
    strip('bottom', { position = v2(g, -g), relativePosition = v2(0, 1),
                      relativeSize = v2(1, 0), size = v2(-2 * g, g) })
    strip('left', { position = v2(0, g), relativeSize = v2(0, 1), size = v2(g, -2 * g) })
    strip('right', { position = v2(-g, g), relativePosition = v2(1, 0),
                     relativeSize = v2(0, 1), size = v2(g, -2 * g) })

    strip('topLeft', { size = v2(g, g) })
    strip('topRight', { position = v2(-g, 0), relativePosition = v2(1, 0), size = v2(g, g) })
    strip('bottomLeft', { position = v2(0, -g), relativePosition = v2(0, 1), size = v2(g, g) })
    strip('bottomRight', { position = v2(-g, -g), relativePosition = v2(1, 1), size = v2(g, g) })

    return out
end

local function screenBounds()
    local index = ui.layers.indexOf('Windows')
    if index then
        return ui.layers[index].size
    end
    return ui.screenSize()
end

-- What a drag means: edges/corners, the top move band, rest (pan).
local function classify(offset, size)
    return resize.classify(offset, size, {
        grab = config.FRAME_GRAB,
        move = config.FRAME_MOVE_HEIGHT,
        fallback = 'map',
    })
end

return {
    grabs = grabs,
    classify = classify,
    screenBounds = screenBounds,
}
