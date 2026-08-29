-- Cell boundaries layer; requires no land data.

local config = require('scripts.PixelMap.core.config')
local draw = require('scripts.PixelMap.core.draw')

local function drawGrid(view)
    local spacing = config.CELL_SIZE * view.zoom
    -- Grid lines become denser than their width; cull to prevent grey canvas.
    if spacing < config.GRID_MIN_SPACING then
        return {}
    end

    local fromX, fromY, toX, toY = view.cellBounds()
    if not fromX then
        return {}
    end

    local out = {}

    -- Per-axis budget: prevents wide canvas from drawing only one axis.
    local drawn = 0
    for cellX = fromX, toX do
        if drawn >= config.GRID_MAX_LINES then
            break
        end
        -- The line is the cell's own western edge, which cellRect places.
        local x = view.cellRect(cellX, 0)
        out[#out + 1] = draw.quad(x, 0, 1, view.canvasSize.y, config.COLOR_GRID, 0.5)
        drawn = drawn + 1
    end

    drawn = 0
    for cellY = fromY, toY do
        if drawn >= config.GRID_MAX_LINES then
            break
        end
        -- cellRect's y is the cell's northern edge, so the line drawn for
        -- cell N is the boundary between N and N+1.
        local _, y = view.cellRect(0, cellY)
        out[#out + 1] = draw.quad(0, y, view.canvasSize.x, 1, config.COLOR_GRID, 0.5)
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
