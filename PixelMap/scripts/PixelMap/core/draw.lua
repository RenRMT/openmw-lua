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

--- A stroke clamped to a third of the cell it is drawn on.
--
-- A cell zoomed down to a few pixels must stay a coloured mark rather than
-- becoming a solid block of border, and a stroke narrower than a pixel is
-- invisible, so anything positive rounds up to one.
local function strokeWidth(width, side)
    local clamped = math.min(width, math.floor(side / 3))
    if clamped < 1 then
        return width > 0 and 1 or 0
    end
    return clamped
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
    local outlineWidth = opts.outline or config.MARKER_OUTLINE

    -- Wrapper at full size; inset body avoids clipping outline.
    local total = size + outlineWidth * 2

    -- Off-canvas markers are dropped rather than returned, so a layer can hand
    -- over everything it has and let the view decide. Culled by the marker's
    -- own extent, since it is sized in screen pixels and a marker whose centre
    -- is just outside still has half of itself on screen. `cull = false` for a
    -- caller that has already done its own.
    if opts.cull ~= false then
        if p.x + total < 0 or p.y + total < 0
            or p.x - total > view.canvasSize.x or p.y - total > view.canvasSize.y then
            return nil
        end
    end

    local content = {}
    if outlineWidth > 0 then
        content[#content + 1] = quad(0, 0, total, total,
            opts.outlineColor or config.COLOR_MARKER_OUTLINE, opts.alpha)
    end
    content[#content + 1] = {
        type = ui.TYPE.Image,
        props = {
            resource = opts.resource or whiteTexture,
            color = opts.color or config.COLOR_PLAYER,
            alpha = opts.alpha,
            position = util.vector2(outlineWidth, outlineWidth),
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
-- opts: gridX, gridY, color, alpha, tooltip, border, borderColor
--
-- With a tooltip or a border it becomes a widget wrapping the quad, since
-- events go to widgets rather than bare images and a border needs a
-- second quad behind the fill. The hover area is then the cell itself,
-- which is the point: an ownership overlay wants the whole square to
-- answer, not a fixed-size marker in the middle of it. Hover needs
-- `interactive = true` on the layer, as markers do.
--
-- For a whole grid rather than one cell, `cells` and `outline` below do the
-- cull and the loop as well.
local function cell(opts)
    local gridX, gridY = opts.gridX, opts.gridY
    local color, alpha, tooltipText = opts.color, opts.alpha, opts.tooltip
    local border, borderColor = opts.border, opts.borderColor

    local x, y, side = view.cellRect(gridX, gridY)

    if not tooltipText and not border then
        return quad(x, y, side, side, color, alpha)
    end

    local inner = {}
    if border and border > 0 then
        -- Border first, fill inset over it: one quad behind another is
        -- cheaper than four edge strips and cannot leave a seam at the
        -- corners.
        local width = strokeWidth(border, side)
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
            position = util.vector2(x, y),
            size = util.vector2(side, side),
        },
        content = ui.content(inner),
        events = events,
    }
end


--- Do two colours paint the same pixels?
--
-- Compared by component rather than by identity: a caller that builds a fresh
-- Color per cell still gets its runs merged, and a nil on either side means a
-- gap, which never merges with anything.
local function sameColor(a, b, alphaA, alphaB)
    if a == nil or b == nil then
        return false
    end
    return a.r == b.r and a.g == b.g and a.b == b.b and alphaA == alphaB
end

--- Paint a colour over every visible cell that has one.
--
-- The loop, the cull and the budget in one call, because every per-cell layer
-- needs all three and getting the cull wrong is what makes a map stutter: the
-- range is the viewport, so the cost follows what is on screen rather than the
-- size of the caller's world.
--
-- Runs of the same colour along a row are merged into one quad. A faction
-- holding a contiguous province becomes a handful of widgets instead of one
-- per cell, which is the difference between a wash that is free and one that
-- is not.
--
-- opts:
--   at(gridX, gridY) -> color, alpha   -- nil colour leaves the cell unpainted
--   margin  cells added either way, default 0
--   budget  most quads to emit, default config.CELLS_MAX_QUADS
--
-- Merged quads are plain images and take no events. A layer that needs cells
-- to answer the cursor wants `cell{ tooltip = }` per cell, or this for the
-- fill with an interactive layer of hover targets over it.
local function cells(opts)
    local fromX, fromY, toX, toY = view.cellBounds(opts.margin)
    if not fromX then
        return {}
    end

    local at = opts.at
    local budget = opts.budget or config.CELLS_MAX_QUADS
    local out = {}

    for gridY = fromY, toY do
        -- One row at a time so a run can only ever be horizontal, which is the
        -- direction a quad can span without leaving the cells it covers.
        local runFrom, runColor, runAlpha = nil, nil, nil

        local function flush(untilX)
            if not runFrom then
                return
            end
            local x, y, side = view.cellRect(runFrom, gridY)
            out[#out + 1] = quad(x, y, side + (untilX - runFrom) * (side - 1), side,
                                 runColor, runAlpha)
            runFrom, runColor, runAlpha = nil, nil, nil
        end

        for gridX = fromX, toX do
            local color, alpha = at(gridX, gridY)
            if runFrom and not sameColor(runColor, color, runAlpha, alpha) then
                flush(gridX - 1)
            end
            if color and not runFrom then
                runFrom, runColor, runAlpha = gridX, color, alpha
            end
            if #out >= budget then
                flush(gridX)
                return out
            end
        end
        flush(toX)
    end

    return out
end

--- The perimeter of every region on the visible grid.
--
-- An edge is drawn only where the neighbour belongs to a different region, so
-- a fifteen-cell city reads as one shape rather than fifteen squares. What
-- counts as the same region is the caller's: `group` returns any value that
-- compares equal for cells that belong together, which lets a territory layer
-- group by owner *and* place at once -- a city taken in halves is two shapes,
-- because that is what it is.
--
-- The interior is left unpainted on purpose. An outline says where something
-- is without hiding the ground it stands on; put a fill underneath with
-- `cells` if you want both.
--
-- opts:
--   group(gridX, gridY) -> id         -- nil means the cell is in no region
--   color(id, gridX, gridY) -> color  -- or a plain Color for all of them
--   width    stroke, clamped per cell, default config.OUTLINE_WIDTH
--   alpha    default 1
--   margin   cells added either way, default 0
--   tooltip(id, gridX, gridY) -> text -- optional; adds a hover target over
--                                        the whole cell, interior included
--
-- With `tooltip` the layer needs `interactive = true`, as markers do.
local function outline(opts)
    local fromX, fromY, toX, toY = view.cellBounds(opts.margin)
    if not fromX then
        return {}
    end

    local group = opts.group
    local colorFor = opts.color
    if type(colorFor) ~= 'function' then
        local fixed = colorFor or config.COLOR_CELL_BORDER
        colorFor = function() return fixed end
    end
    local alpha = opts.alpha or 1
    local out = {}

    for gridX = fromX, toX do
        for gridY = fromY, toY do
            local id = group(gridX, gridY)
            if id ~= nil then
                local x, y, side = view.cellRect(gridX, gridY)
                local width = strokeWidth(opts.width or config.OUTLINE_WIDTH, side)
                local color = colorFor(id, gridX, gridY)

                local function edge(dx, dy, w, h)
                    out[#out + 1] = quad(x + dx, y + dy, w, h, color, alpha)
                end

                -- Canvas y grows southward, so the northern neighbour is the
                -- one drawn against the top of the cell.
                if group(gridX, gridY + 1) ~= id then
                    edge(0, 0, side, width)
                end
                if group(gridX, gridY - 1) ~= id then
                    edge(0, side - width, side, width)
                end
                if group(gridX - 1, gridY) ~= id then
                    edge(0, 0, width, side)
                end
                if group(gridX + 1, gridY) ~= id then
                    edge(side - width, 0, width, side)
                end

                -- Last, so it sits over the edges it shares a cell with: an
                -- invisible full-cell widget is what makes the empty middle of
                -- an outlined region answer the cursor.
                if opts.tooltip then
                    out[#out + 1] = cell {
                        gridX = gridX,
                        gridY = gridY,
                        color = color,
                        alpha = 0,
                        tooltip = opts.tooltip(id, gridX, gridY),
                    }
                end
            end
        end
    end

    return out
end

return {
    whiteTexture = whiteTexture,
    invisible = invisible,
    quad = quad,
    cell = cell,
    cells = cells,
    outline = outline,
    marker = marker,
}
