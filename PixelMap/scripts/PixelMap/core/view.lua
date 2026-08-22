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

--- The world rectangle currently on screen, for layers to cull against.
-- @return minX, minY, maxX, maxY
function view.bounds()
    local halfW = view.canvasSize.x * 0.5 / view.zoom
    local halfH = view.canvasSize.y * 0.5 / view.zoom
    return view.center.x - halfW, view.center.y - halfH,
           view.center.x + halfW, view.center.y + halfH
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
