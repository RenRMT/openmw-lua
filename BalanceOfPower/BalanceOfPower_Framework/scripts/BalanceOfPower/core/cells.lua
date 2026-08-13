-- Exterior cell naming. Shared so the two places that need to move
-- between grid coordinates and the "#x,y" strings territories are keyed
-- by agree on the format.

local M = {}

--- The name an exterior cell is registered under.
function M.name(gridX, gridY)
    return string.format('#%d,%d', gridX, gridY)
end

--- Grid coordinates from a cell name.
-- @return gridX, gridY -- or nil for an interior name, which has none
function M.parse(cellName)
    local x, y = string.match(cellName, '^#(%-?%d+),(%-?%d+)$')
    if not x then
        return nil
    end
    return tonumber(x), tonumber(y)
end

return M
