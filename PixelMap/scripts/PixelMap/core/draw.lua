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
--
-- Two call forms, because the positional one was here first:
--   cell(gridX, gridY, color, alpha, tooltip)
--   cell { gridX=, gridY=, color=, alpha=, tooltip=, border=, borderColor= }
--
-- With a tooltip or a border it becomes a widget wrapping the quad, since
-- events go to widgets rather than bare images and a border needs a
-- second quad behind the fill. The hover area is then the cell itself,
-- which is the point: an ownership overlay wants the whole square to
-- answer, not a fixed-size marker in the middle of it. Hover needs
-- `interactive = true` on the layer, as markers do.
local function cell(gridX, gridY, color, alpha, tooltipText)
    local border, borderColor = nil, nil
    if type(gridX) == 'table' then
        local opts = gridX
        gridX, gridY = opts.gridX, opts.gridY
        color, alpha, tooltipText = opts.color, opts.alpha, opts.tooltip
        border, borderColor = opts.border, opts.borderColor
    end

    -- North-west corner: cell's low x, high y.
    local p = view.worldToCanvas(gridX * config.CELL_SIZE,
                                 (gridY + 1) * config.CELL_SIZE)
    local side = config.CELL_SIZE * view.zoom + 1

    if not tooltipText and not border then
        return quad(p.x, p.y, side, side, color, alpha)
    end

    local inner = {}
    if border and border > 0 then
        -- Border first, fill inset over it: one quad behind another is
        -- cheaper than four edge strips and cannot leave a seam at the
        -- corners. Clamped so a cell zoomed down to a few pixels stays a
        -- coloured dot rather than becoming solid border.
        local width = math.min(border, math.floor(side / 3))
        if width > 0 then
            inner[#inner + 1] = quad(0, 0, side, side,
                borderColor or config.COLOR_CELL_BORDER, alpha)
            inner[#inner + 1] = quad(width, width,
                side - width * 2, side - width * 2, color, alpha)
        end
    end
    if #inner == 0 then
        inner[1] = quad(0, 0, side, side, color, alpha)
    end

    local events = nil
    if tooltipText then
        events = {
            focusGain = async:callback(function() tooltip.hover(tooltipText) end),
            focusLoss = async:callback(function() tooltip.unhover(tooltipText) end),
        }
    end

    return {
        type = ui.TYPE.Widget,
        props = {
            position = util.vector2(p.x, p.y),
            size = util.vector2(side, side),
        },
        content = ui.content(inner),
        events = events,
    }
end

return {
    whiteTexture = whiteTexture,
    invisible = invisible,
    quad = quad,
    cell = cell,
    marker = marker,
}
