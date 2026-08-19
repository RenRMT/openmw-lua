-- What a purse of gold is worth to a faction that counts you a member.
--
-- Pure arithmetic, deliberately: no engine package, no state, no events.
-- Both halves of the tribute feature need this answer and they run in
-- different contexts -- the window has to show the player what a payment
-- will buy *before* they make it, and the global script has to compute
-- what it actually bought. A single function both can call is the only
-- way those two numbers cannot disagree.
--
-- ANY context.

local config = require('scripts.BalanceOfPower.core.config')

local M = {}

--- What a member's rank is worth as a multiplier, from MIN at the bottom
-- of a faction's ladder to MAX at the top.
--
-- @param rank number 1-based; 0 or nil means not a member
-- @param rankCount number how many ranks the faction defines
function M.rankMultiplier(rank, rankCount)
    rank = tonumber(rank) or 0
    if rank < 1 then
        -- Not a member. Nothing to multiply: tribute is a thing you pay
        -- to your own people, and the caller should not have got here.
        return 0
    end

    local top = math.max(1, math.floor(tonumber(rankCount) or 1))
    local minimum = config.TRIBUTE_RANK_MULTIPLIER_MIN
    local maximum = config.TRIBUTE_RANK_MULTIPLIER_MAX
    if top <= 1 then
        -- A faction with a single rank has no ladder to climb, so every
        -- member speaks with the same weight.
        return minimum
    end

    -- Clamped rather than trusted: a save edited by another mod, or a
    -- faction whose ranks a patch shortened, can hand back a rank past
    -- the end of the ladder.
    local position = math.min(math.max(rank, 1), top)
    local share = (position - 1) / (top - 1)
    return minimum + (maximum - minimum) * share
end

--- Power bought by `gold`, paid by a member at `rank` of `rankCount`.
--
-- Concave in gold by TRIBUTE_EXPONENT, so ten times the purse is far
-- less than ten times the standing.
function M.powerFor(gold, rank, rankCount)
    gold = math.floor(tonumber(gold) or 0)
    if gold <= 0 then
        return 0
    end
    local scaled = config.TRIBUTE_POWER_PER_UNIT * (gold ^ config.TRIBUTE_EXPONENT)
    return scaled * M.rankMultiplier(rank, rankCount)
end

return M
