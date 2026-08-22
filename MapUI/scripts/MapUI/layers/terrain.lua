-- Terrain fills; merges runs by drawn colour to reduce quad count.

local draw = require('scripts.MapUI.core.draw')
local profile = require('scripts.MapUI.core.profile')
local terrain = require('scripts.MapUI.core.terrain')

local function drawTerrain(view)
    local ctx = terrain.context(view)
    if not ctx then
        return {}
    end

    local step = ctx.step
    local zoom = view.zoom
    local originX = terrain.originX(view)
    -- One pixel overlap: quads land on fractional pixel boundaries; seams show as hairlines without it.
    local rowHeight = step * zoom + 1

    local out = {}
    local y = ctx.startY
    while y <= ctx.maxY do
        local rowTop = view.worldToCanvas(ctx.startX, y + step).y
        local runKey, runStart, runColor = nil, nil, nil

        -- One step past edge; key reads nil to flush the last run.
        local x = ctx.startX
        while x <= ctx.maxX + step do
            local band = (x <= ctx.maxX) and terrain.bandAt(ctx, x, y) or nil
            local key = terrain.mergeKey(band)
            if key ~= runKey then
                if runKey then
                    out[#out + 1] = draw.quad(originX + runStart * zoom, rowTop,
                        (x - runStart) * zoom + 1, rowHeight, runColor)
                end
                runKey, runStart = key, x
                runColor = band and terrain.colorFor(band) or nil
            end
            x = x + step
        end
        y = y + step
    end

    profile.count('fill', #out)
    return out
end

return {
    key = 'terrain',
    name = 'Terrain',
    order = 10,
    draw = drawTerrain,
}
