-- Window frame: eight invisible grab strips for resize/move. Hand-rolled: ui.TYPE.Window cannot resize.

local ui = require('openmw.ui')
local util = require('openmw.util')

local config = require('scripts.PixelMap.core.config')
local draw = require('scripts.PixelMap.core.draw')

local v2 = util.vector2

local GRABS = {
    { key = 'move', pointer = 'arrow' },
    { key = 'left', pointer = 'hresize', x = -1 },
    { key = 'right', pointer = 'hresize', x = 1 },
    { key = 'top', pointer = 'vresize', y = -1 },
    { key = 'bottom', pointer = 'vresize', y = 1 },
    { key = 'topLeft', pointer = 'dresize', x = -1, y = -1 },
    { key = 'topRight', pointer = 'dresize2', x = 1, y = -1 },
    { key = 'bottomLeft', pointer = 'dresize2', x = -1, y = 1 },
    { key = 'bottomRight', pointer = 'dresize', x = 1, y = 1 },
}

local byKey = {}
for _, grab in ipairs(GRABS) do
    byKey[grab.key] = grab
end

-- Build strips using relativeSize: `relativeSize * parent + size` spans full width without knowing width.
local function grabs()
    local g = config.FRAME_GRAB
    local out = {}

    local function strip(key, props)
        props.pointer = byKey[key].pointer
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

-- What a drag means: edges/corners, title bar (move), rest (pan).
-- Includes button rows to allow dragging; minor wrong vs unmovable window.
local function classify(offset, size)
    local g = config.FRAME_GRAB
    local left = offset.x < g
    local right = offset.x > size.x - g
    local top = offset.y < g
    local bottom = offset.y > size.y - g

    if top and left then return 'topLeft' end
    if top and right then return 'topRight' end
    if bottom and left then return 'bottomLeft' end
    if bottom and right then return 'bottomRight' end
    if left then return 'left' end
    if right then return 'right' end
    if top then return 'top' end
    if bottom then return 'bottom' end
    if offset.y < g + config.FRAME_TITLE_HEIGHT then return 'move' end
    return 'map'
end

-- Apply drag to window rect, idempotent from anchor (arrival twice is harmless).
local function resolve(key, startPos, startSize, delta, screen)
    local grab = byKey[key]
    if not grab then
        return startPos, startSize
    end

    if key == 'move' then
        return v2(
            util.clamp(startPos.x + delta.x, 0, math.max(0, screen.x - startSize.x)),
            util.clamp(startPos.y + delta.y, 0, math.max(0, screen.y - startSize.y))), startSize
    end

    local x, y = startPos.x, startPos.y
    local w, h = startSize.x, startSize.y

    if grab.x == -1 then
        -- Left edge: move corner, shrink width equally; right edge stays put.
        local dx = util.clamp(delta.x, -startPos.x, startSize.x - config.WINDOW_MIN_WIDTH)
        x, w = startPos.x + dx, startSize.x - dx
    elseif grab.x == 1 then
        w = util.clamp(startSize.x + delta.x, config.WINDOW_MIN_WIDTH, screen.x - startPos.x)
    end

    if grab.y == -1 then
        local dy = util.clamp(delta.y, -startPos.y, startSize.y - config.WINDOW_MIN_HEIGHT)
        y, h = startPos.y + dy, startSize.y - dy
    elseif grab.y == 1 then
        h = util.clamp(startSize.y + delta.y, config.WINDOW_MIN_HEIGHT, screen.y - startPos.y)
    end

    return v2(x, y), v2(w, h)
end

local function screenBounds()
    local index = ui.layers.indexOf('Windows')
    if index then
        return ui.layers[index].size
    end
    return ui.screenSize()
end

return {
    grabs = grabs,
    classify = classify,
    resolve = resolve,
    screenBounds = screenBounds,
}
