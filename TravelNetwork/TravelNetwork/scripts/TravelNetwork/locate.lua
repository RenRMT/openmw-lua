-- Which stop the player is standing at, or nearest to.
--
-- Pure. The caller says where the player is; this says which stop that is.
--
-- Three cases, and the awkward one is the middle:
--
--   * standing in a cell that *is* a stop -- a guild hall, say;
--   * standing in some other interior -- a tavern, a shop -- where the
--     player's coordinates are cell-local and cannot be compared with
--     anything outside, so the caller has to follow the doors out first
--     (walk.lua does exactly this) and ask again with what it finds;
--   * standing outdoors, where the nearest stop is a plain measurement.

local M = {}

local function planarDistance(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

--- The stop at, or nearest to, a position.
-- @param graph the built graph
-- @param where { cellId, isInterior, position }
-- @return key, distance -- or nil when nothing can be measured from here
function M.nearest(graph, where)
    if where == nil or where.position == nil then
        return nil
    end

    if where.isInterior then
        -- Only an exact cell match means anything indoors. A stop 200 units
        -- away in raw numbers may be in another building entirely.
        local key = 'cell:' .. string.lower(where.cellId or '')
        if graph.nodes[key] then
            return key, 0
        end
        return nil
    end

    local bestKey, bestDistance = nil, nil
    for _, key in ipairs(graph.order) do
        local node = graph.nodes[key]
        -- Compare against where a stop stands in the world: an interior's own
        -- position is in its own worldspace, but its anchor is out here.
        local position = node.anchor or (node.isExterior and node.position or nil)
        if position then
            local distance = planarDistance(where.position, position)
            if bestDistance == nil or distance < bestDistance then
                bestKey, bestDistance = key, distance
            end
        end
    end
    return bestKey, bestDistance
end

return M
