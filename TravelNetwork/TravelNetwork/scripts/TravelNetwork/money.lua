-- Gold, in the one place that knows what gold is.
--
-- Kept out of adapter.lua because both contexts need it and the adapter is
-- global-only -- it requires `openmw.world`, which a player script may not.
-- Reading what the player holds happens player-side, so the window can refuse
-- a journey it can see is unaffordable rather than opening a round trip to be
-- told; taking it happens global-side, because only a global script may remove
-- an object.
--
-- `gold_001` is the id a purse is expected to be counted under -- the engine
-- is believed to fold every denomination onto it as coin enters a container,
-- though that is not established here (repo notes §12). If it turns out to be
-- wrong the mod under-counts, which shows up as a journey refused rather than
-- one wrongly charged for, and `take` below stops at what it actually found.
-- Content knowledge, like data/modes.lua, and this mod is allowed to have it.

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
--
-- Written as a loop over stacks rather than one call on the first: nothing
-- promises a purse is a single stack, and a mod that put a second one there
-- should not make a journey free.
--
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
