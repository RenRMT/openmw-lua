-- Gold, in the one place that knows what gold is.
--
-- Split from the scripts that use it because the two halves of a payment
-- run in different contexts: a player script counts what the player has
-- so the window can grey out what they cannot afford, and only a global
-- script can actually take it -- `remove` is global-only.
--
-- ANY context; `take` is GLOBAL only.

local types = require('openmw.types')

-- The vanilla gold record. Every gold pile in the game stacks onto it.
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

--- Take up to `amount` of it. GLOBAL context only.
--
-- Walks the stacks rather than assuming one: a player's gold is usually
-- a single stack and is not guaranteed to be.
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
