-- Gold, in the one place that knows what gold is.
--
-- Kept out of adapter.lua because both contexts need it and the adapter is
-- global-only -- it requires `openmw.world`, which a player script may not.

local types = require('openmw.types')

local GOLD = 'gold_001'

local M = {}

--- What an actor is carrying.
function M.held(actor)
    if actor == nil then
        return 0
    end
    local inventory = types.Actor.inventory(actor)
    return inventory and inventory:countOf(GOLD) or 0
end

--- Take up to `amount` of it. GLOBAL context only: `remove` is.
-- @return how much was actually taken
function M.take(actor, amount)
    if actor == nil or amount == nil or amount <= 0 then
        return 0
    end
    local left = amount
    for _, stack in ipairs(types.Actor.inventory(actor):findAll(GOLD)) do
        if left <= 0 then
            break
        end
        local taken = math.min(stack.count, left)
        stack:remove(taken)
        left = left - taken
    end
    return amount - left
end

return M
