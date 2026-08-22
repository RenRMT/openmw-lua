-- Drawing shapes: quads and markers. Exposed for external layers (positioning is error-prone).

local async = require('openmw.async')
local ui = require('openmw.ui')
local util = require('openmw.util')

local config = require('scripts.PixelMap.core.config')
local tooltip = require('scripts.PixelMap.core.tooltip')
local view = require('scripts.PixelMap.core.view')

local whiteTexture = ui.texture { path = 'white' }

-- ui.texture{path='transparent'} is opaque white; use white at alpha 0 instead.
local function invisible(props)
    props.resource = whiteTexture
    props.alpha = 0
    return props
end

local function quad(x, y, w, h, color, alpha)
    return {
        type = ui.TYPE.Image,
        props = {
            resource = whiteTexture,
            color = color,
            alpha = alpha,
            position = util.vector2(x, y),
            size = util.vector2(w, h),
        },
    }
end

-- Marker at world position; screen pixels (don't scale with zoom). Tooltip via focusGain/focusLoss and window cursor.
-- opts: position, size, color, outline, outlineColor, alpha, resource, onClick, tooltip
local function marker(opts)
    local pos = opts.position
    local p = view.worldToCanvas(pos.x, pos.y)
    local size = opts.size or config.MARKER_SIZE
    local outline = opts.outline or config.MARKER_OUTLINE

    -- Wrapper at full size; inset body avoids clipping outline.
    local total = size + outline * 2

    local content = {}
    if outline > 0 then
        content[#content + 1] = quad(0, 0, total, total,
            opts.outlineColor or config.COLOR_MARKER_OUTLINE, opts.alpha)
    end
    content[#content + 1] = {
        type = ui.TYPE.Image,
        props = {
            resource = opts.resource or whiteTexture,
            color = opts.color or config.COLOR_PLAYER,
            alpha = opts.alpha,
            position = util.vector2(outline, outline),
            size = util.vector2(size, size),
        },
    }

    local events = nil
    if opts.onClick then
        events = { mouseClick = opts.onClick }
    end
    if opts.tooltip then
        events = events or {}
        local label = opts.tooltip
        events.focusGain = async:callback(function() tooltip.hover(label) end)
        events.focusLoss = async:callback(function() tooltip.unhover(label) end)
    end

    return {
        type = ui.TYPE.Widget,
        props = {
            position = util.vector2(p.x - total * 0.5, p.y - total * 0.5),
            size = util.vector2(total, total),
        },
        content = ui.content(content),
        events = events,
    }
end

-- Quad for one exterior cell; unit for territory/ownership overlays.
local function cell(gridX, gridY, color, alpha)
    -- North-west corner: cell's low x, high y.
    local p = view.worldToCanvas(gridX * config.CELL_SIZE,
                                 (gridY + 1) * config.CELL_SIZE)
    local side = config.CELL_SIZE * view.zoom + 1
    return quad(p.x, p.y, side, side, color, alpha)
end

return {
    whiteTexture = whiteTexture,
    invisible = invisible,
    quad = quad,
    cell = cell,
    marker = marker,
}
