-- Who fights whom.
--
-- The framework has no opinion about violence and does not start any. What
-- it has is one rule, so that every extension spawning an actor gets the
-- same answer instead of each deriving its own:
--
--   an invader fights everyone, and nobody else fights at all.
--
-- That is the whole of it. There is no faction-versus-faction hostility,
-- no per-faction opt-in and no global "everyone fights" switch. Morrowind's
-- reaction table can still be read through the interface -- see
-- regardOf -- but nothing here consults it, because reading hostility off
-- a reaction row gets the answer wrong in both directions: vanilla puts the
-- Camonna Tong at only -1 with the Sixth House, and never gave the Sixth
-- House any opinion of the Morag Tong at all. The guilds are meant to feud
-- in dialogue and quests, not on sight in the street.
--
-- An invader is not making that kind of judgement. It is an outside threat
-- that arrived to take the place, and it is hostile to everyone standing
-- in it, which is a fact about what it is rather than about how it feels.
--
-- GLOBAL context only.

local registry = require('scripts.BalanceOfPower.core.registry')

local M = {}

--- Whether a faction fights at all.
function M.isBelligerent(factionId)
    return registry.isInvader(factionId)
end

--- Whether `factionId` attacks the player on sight.
--
-- The player is not a faction and has no reaction row, so this could not
-- have been answered from the table even when the table was consulted. It
-- is the same question as isBelligerent: an invader fights whoever is
-- there, and the player is there.
function M.isHostileToPlayer(factionId)
    return M.isBelligerent(factionId)
end

--- Whether `factionId` attacks `towardId` on sight.
--
-- Asymmetric: an invader attacks a settled faction, and the settled faction
-- does not go looking for the fight -- it just ends up in one. Use
-- willFight() for the symmetric question a spawn rule usually has.
function M.isHostile(factionId, towardId)
    if factionId == towardId then
        return false
    end
    if not registry.factions[towardId] then
        return false
    end
    return registry.isInvader(factionId)
end

--- Whether these two come to blows, from either side's initiative.
function M.willFight(factionId, otherId)
    return M.isHostile(factionId, otherId) or M.isHostile(otherId, factionId)
end

--- Every registered faction the given one attacks on sight, sorted.
-- Diagnostic: an invader with nobody to fight looks identical to a working
-- one right up until you notice it never fights anybody.
function M.enemiesOf(factionId)
    local out = {}
    for _, id in ipairs(registry.sortedFactionIds()) do
        if M.isHostile(factionId, id) then
            out[#out + 1] = id
        end
    end
    return out
end

return M
