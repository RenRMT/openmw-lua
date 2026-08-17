-- Stub for openmw.world, for headless tests.
--
-- The framework only uses world.players, to broadcast events to player
-- scripts. The stub ships one fake player that records what it is sent.

local M = {}

local player = {
    id = 'test_player',
    _events = {},
}

function player:sendEvent(name, data)
    self._events[#self._events + 1] = { name = name, data = data }
end

M.players = { player }
M.cells = {}

M._test = {
    player = player,
}

function M._test.reset()
    player._events = {}
    M.cells = {}
end

--- Populate world.cells with a rectangle of exterior cells, standing in
-- for the cell records a content file would define. The frontier
-- generator only creates territory where a cell actually exists, so
-- tests need something here or they generate nothing.
function M._test.defineExteriorGrid(minX, maxX, minY, maxY, region)
    for gridX = minX, maxX do
        for gridY = minY, maxY do
            M.cells[#M.cells + 1] = {
                isExterior = true,
                gridX = gridX,
                gridY = gridY,
                name = '',
                region = region,
            }
        end
    end
end

--- Events this player received, of one name, in order.
function M._test.eventsNamed(name)
    local out = {}
    for _, entry in ipairs(player._events) do
        if entry.name == name then
            out[#out + 1] = entry.data
        end
    end
    return out
end

return M
