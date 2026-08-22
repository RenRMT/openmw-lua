-- Cell boundaries layer; requires no land data.

local config = require('scripts.PixelMap.core.config')
local draw = require('scripts.PixelMap.core.draw')

local function drawGrid(view)
    local spacing = config.CELL_SIZE * view.zoom
    -- Grid lines become denser than their width; cull to prevent grey canvas.
    if spacing < config.GRID_MIN_SPACING then
        return {}
    end

    local minX, minY, maxX, maxY = view.bounds()
    local out = {}

    -- Per-axis budget: prevents wide canvas from drawing only one axis.
    local drawn = 0
    local cellX = math.floor(minX / config.CELL_SIZE)
    while cellX * config.CELL_SIZE <= maxX and drawn < config.GRID_MAX_LINES do
        local p = view.worldToCanvas(cellX * config.CELL_SIZE, 0)
        out[#out + 1] = draw.quad(p.x, 0, 1, view.canvasSize.y, config.COLOR_GRID, 0.5)
        cellX = cellX + 1
        drawn = drawn + 1
    end

    drawn = 0
    local cellY = math.floor(minY / config.CELL_SIZE)
    while cellY * config.CELL_SIZE <= maxY and drawn < config.GRID_MAX_LINES do
        local p = view.worldToCanvas(0, cellY * config.CELL_SIZE)
        out[#out + 1] = draw.quad(0, p.y, view.canvasSize.x, 1, config.COLOR_GRID, 0.5)
        cellY = cellY + 1
        drawn = drawn + 1
    end

    return out
end

return {
    key = 'grid',
    name = 'Cell grid',
    order = 20,
    draw = drawGrid,
}
