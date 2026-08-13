-- Who fights whom.
--
-- The framework has no opinion about violence and does not start any.
-- What it has is the reaction table, which already encodes every
-- relationship in Morrowind, and it would be strange for every extension
-- that spawns an actor to re-derive the same answer from the same data
-- and disagree in the details.
--
-- So this file is one rule, applied to data content packs author:
--
--   a faction fights nobody, unless it is flagged hostile,
--   in which case it fights whoever it genuinely hates.
--
-- That shape was chosen over the more obvious "hostility is just the
-- reaction value" because vanilla's Great Houses dislike each other
-- without fighting in the street, and a framework that put Redoran and
-- Telvanni guards at each other's throats by default would be wrong
-- about the game it is modelling. The flag is what says "this faction is
-- the kind that fights"; the reaction table is what says "and these are
-- the people it fights".
--
-- The payoff is that three separate features collapse into one
-- threshold. A hostile invader, a per-faction enemies list, and a
-- "everyone fights everyone" toggle are the same rule read at different
-- settings -- none of them is a code path of its own.
--
-- GLOBAL context only.

local config = require('scripts.BalanceOfPower.core.config')
local power = require('scripts.BalanceOfPower.core.power')
local registry = require('scripts.BalanceOfPower.core.registry')

local M = {}

--- Whether a faction fights at all: its own flag, or the global override.
function M.isBelligerent(factionId)
    if config.ALL_FACTIONS_HOSTILE then
        return registry.factions[factionId] ~= nil
    end
    local faction = registry.factions[factionId]
    return faction ~= nil and faction.hostile == true
end

--- Whether `factionId` attacks the player on sight.
--
-- The one relationship the reaction table cannot answer, because the
-- player is not a faction and has no row. Carrying it on the same flag
-- rather than as a second field is deliberate: a faction that fights its
-- enemies but waves the player through is a distinction no content has
-- asked for, and inventing the field now would mean every pack author
-- has to decide something they don't have an opinion about.
function M.isHostileToPlayer(factionId)
    return M.isBelligerent(factionId)
end

--- Whether `factionId` attacks `towardId` on sight.
--
-- Asymmetric on purpose. A flagged faction attacks a peaceful one, and
-- the peaceful one does not go looking for the fight -- it just ends up
-- in one. Use willFight() for the symmetric question.
function M.isHostile(factionId, towardId)
    if factionId == towardId then
        return false
    end
    if not registry.factions[towardId] then
        return false
    end
    if not M.isBelligerent(factionId) then
        return false
    end
    return power.regardOf(factionId, towardId) <= config.HOSTILITY_REACTION_THRESHOLD
end

--- Whether these two come to blows, from either side's initiative.
-- The question a spawn rule actually has, which is not "who started it".
function M.willFight(factionId, otherId)
    return M.isHostile(factionId, otherId) or M.isHostile(otherId, factionId)
end

--- Every registered faction the given one attacks on sight, sorted.
-- Diagnostic: the list is short and its being empty is the failure worth
-- seeing, since a hostile faction with nobody to fight looks identical
-- to a working one until you watch it ignore a rival patrol.
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
