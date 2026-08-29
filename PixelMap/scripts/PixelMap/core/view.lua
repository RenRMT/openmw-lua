-- Map view state and world<->canvas conversions.

local util = require('openmw.util')

local config = require('scripts.PixelMap.core.config')

local view = {
    --- World x,y drawn at the centre of the canvas.
    center = util.vector2(0, 0),
    --- Canvas pixels per world unit.
    zoom = config.ZOOM_DEFAULT,
    --- Size of the drawing area in pixels, set on open and resize.
    canvasSize = util.vector2(config.CANVAS_MIN_WIDTH, config.CANVAS_MIN_HEIGHT),
    --- Exterior worldspace being drawn, or nil in an interior.
    worldSpaceId = nil,
    --- Exterior cell in current worldspace (for land queries).
    cell = nil,
}

-- World +y is north, canvas +y is down.
function view.worldToCanvas(wx, wy)
    return util.vector2(
        view.canvasSize.x * 0.5 + (wx - view.center.x) * view.zoom,
        view.canvasSize.y * 0.5 - (wy - view.center.y) * view.zoom)
end

function view.canvasToWorld(cx, cy)
    return util.vector2(
        view.center.x + (cx - view.canvasSize.x * 0.5) / view.zoom,
        view.center.y - (cy - view.canvasSize.y * 0.5) / view.zoom)
end

--- The exterior cell one world point falls in.
-- @return gridX, gridY
function view.worldToCell(wx, wy)
    return math.floor(wx / config.CELL_SIZE), math.floor(wy / config.CELL_SIZE)
end

--- The world position at the centre of one exterior cell.
function view.cellToWorld(gridX, gridY)
    return util.vector2((gridX + 0.5) * config.CELL_SIZE,
                        (gridY + 0.5) * config.CELL_SIZE)
end

--- The world rectangle currently on screen, for layers to cull against.
-- @return minX, minY, maxX, maxY
function view.bounds()
    local halfW = view.canvasSize.x * 0.5 / view.zoom
    local halfH = view.canvasSize.y * 0.5 / view.zoom
    return view.center.x - halfW, view.center.y - halfH,
           view.center.x + halfW, view.center.y + halfH
end

--- The visible cell range, for a layer that paints per cell.
--
-- nil where there is no exterior to draw on, which is the same test
-- `view.cell` answers -- returned here so a layer's first line can be a
-- single guard rather than two.
--
-- `margin` widens the range by that many cells either way. A marker is sized
-- in screen pixels and so can spill outside the cell it belongs to, which is
-- what a margin of 1 covers.
--
-- @return fromX, fromY, toX, toY
function view.cellBounds(margin)
    if not view.cell then
        return nil
    end
    margin = margin or 0
    local minX, minY, maxX, maxY = view.bounds()
    local fromX, fromY = view.worldToCell(minX, minY)
    local toX, toY = view.worldToCell(maxX, maxY)
    return fromX - margin, fromY - margin, toX + margin, toY + margin
end

--- One exterior cell as a canvas rectangle.
--
-- The side carries a one-pixel overlap so that abutting cells cannot leave a
-- seam between them at fractional zooms. Layers that draw over a cell fill --
-- an outline, a border -- must use this rather than computing the side
-- themselves, or they will not line up with the fill underneath.
--
-- @return x, y, side
function view.cellRect(gridX, gridY)
    -- North-west corner: the cell's low x, high y.
    local corner = view.worldToCanvas(gridX * config.CELL_SIZE,
                                      (gridY + 1) * config.CELL_SIZE)
    return corner.x, corner.y, config.CELL_SIZE * view.zoom + 1
end

function view.setZoom(zoom)
    view.zoom = math.max(config.ZOOM_MIN, math.min(config.ZOOM_MAX, zoom))
end

function view.zoomBy(factor)
    view.setZoom(view.zoom * factor)
end

function view.centerOn(wx, wy)
    view.center = util.vector2(wx, wy)
end

function view.setCanvasSize(size)
    view.canvasSize = size
end

return view
