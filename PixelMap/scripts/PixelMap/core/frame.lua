-- Window frame: eight invisible grab strips for resize/move. Hand-rolled: ui.TYPE.Window cannot resize.
-- The arithmetic lives in ui/resize.lua; this owns the strips and the screen.

local ui = require('openmw.ui')
local util = require('openmw.util')

local config = require('scripts.PixelMap.core.config')
local draw = require('scripts.PixelMap.core.draw')
local resize = require('scripts.PixelMap.ui.resize')

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
local function grabs()
    local g = config.FRAME_GRAB
    local out = {}

    local function strip(key, props)
        props.pointer = POINTERS[key]
        out[#out + 1] = {
            type = ui.TYPE.Image,
            props = draw.invisible(props),
        }
    end

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

-- What a drag means: edges/corners, title bar (move), rest (pan).
-- Includes button rows to allow dragging; minor wrong vs unmovable window.
local function classify(offset, size)
    return resize.classify(offset, size, {
        grab = config.FRAME_GRAB,
        title = config.FRAME_TITLE_HEIGHT,
        fallback = 'map',
    })
end

-- Apply drag to window rect, idempotent from anchor (arrival twice is harmless).
local function resolve(key, startPos, startSize, delta, screen)
    local rect = resize.apply(key,
        { x = startPos.x, y = startPos.y, w = startSize.x, h = startSize.y },
        delta,
        {
            minW = config.WINDOW_MIN_WIDTH,
            minH = config.WINDOW_MIN_HEIGHT,
            screenW = screen.x,
            screenH = screen.y,
        })
    return v2(rect.x, rect.y), v2(rect.w, rect.h)
end

return {
    grabs = grabs,
    classify = classify,
    resolve = resolve,
    screenBounds = screenBounds,
}
