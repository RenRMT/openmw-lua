-- The public interface, exposed to other mods as
-- require('openmw.interfaces').BalanceOfPower from any global script.
--
-- This is the whole contract. A content pack should never need to
-- require a file under scripts/BalanceOfPower/core/ -- the merged VFS
-- would technically let it, but reaching past this file couples a pack
-- to internals that are expected to change between phases. Anything a
-- pack legitimately needs and can't get here is a gap in this file.

local config = require('scripts.BalanceOfPower.core.config')
local driver = require('scripts.BalanceOfPower.core.driver')
local events = require('scripts.BalanceOfPower.core.events')
local log = require('scripts.BalanceOfPower.core.log')
local power = require('scripts.BalanceOfPower.core.power')
local registry = require('scripts.BalanceOfPower.core.registry')
local resolve = require('scripts.BalanceOfPower.core.resolve')
local state = require('scripts.BalanceOfPower.core.state')

local M = {
    -- Bumped when this interface changes in a way a pack could notice.
    -- Packs should check it rather than assuming a function exists.
    version = 1,

    -- Event name constants, so listeners don't hardcode the strings.
    events = events,
}

--------------------------------------------------------------------------
-- Registration (design doc 3.8)
--------------------------------------------------------------------------

function M.registerLandmass(def)
    local landmass = registry.registerLandmass(def)
    state.fillDefaults(registry)
    return landmass
end

function M.registerInvasion(def)
    local invasion = registry.registerInvasion(def)
    state.fillDefaults(registry)
    return invasion
end

--------------------------------------------------------------------------
-- Power
--------------------------------------------------------------------------

--- Award (or subtract) power on behalf of the player's actions.
-- The one entry point content is expected to call: a quest mod, a
-- dialogue hook or a future combat hook can move a faction's standing
-- without knowing anything about propagation, batching or reactions.
-- @param factionId string
-- @param baseDelta number the unscaled change
-- @param playerRankMultiplier number|nil scales baseDelta; defaults to 1
function M.awardPower(factionId, baseDelta, playerRankMultiplier)
    if not registry.factions[factionId] then
        log.warn('awardPower for unregistered faction "%s" -- ignored', tostring(factionId))
        return
    end
    power.apply(factionId, baseDelta * (playerRankMultiplier or 1))
end

function M.getPower(factionId)
    return power.getLive(factionId)
end

function M.setPower(factionId, value)
    return power.set(factionId, value)
end

--------------------------------------------------------------------------
-- Queries
--------------------------------------------------------------------------

function M.getFaction(factionId)
    return registry.factions[factionId]
end

function M.getTerritory(territoryId)
    return registry.territories[territoryId]
end

--- The territory a cell belongs to, or nil. Interior cells are keyed by
-- name, exterior cells by their "#x,y" grid id.
function M.getTerritoryForCell(cellName)
    return registry.territoryForCell(cellName)
end

--- Current owner of a territory, or nil if unclaimed.
function M.getOwner(territoryId)
    return state.getOwner(territoryId)
end

--- Every registered faction id, sorted. A fresh table each call, so a
-- caller iterating it can't disturb the registry.
function M.factionIds()
    return registry.sortedFactionIds()
end

--- Registered territory ids. `kind` is 'anchor', 'frontier', or nil for
-- both. Registration order, copied.
function M.territoryIds(kind)
    local out = {}
    if kind ~= 'frontier' then
        for _, id in ipairs(registry.anchorIds) do
            out[#out + 1] = id
        end
    end
    if kind ~= 'anchor' then
        for _, id in ipairs(registry.frontierIds) do
            out[#out + 1] = id
        end
    end
    return out
end

--- How strongly a faction projects onto a territory. 0 if it doesn't
-- reach, isn't territorial, or the territory has no centroid.
function M.getEffectivePower(factionId, territoryId)
    local territory = registry.territories[territoryId]
    if not territory then
        return 0
    end
    return resolve.effectivePower(factionId, territory)
end

--- Who projects most onto a territory, and how strongly. This is the
-- faction that will end up holding it, given time and no change in
-- anyone's power.
-- @return factionId|nil, value
function M.getProjection(territoryId)
    local territory = registry.territories[territoryId]
    if not territory then
        return nil, 0
    end
    return resolve.strongestProjector(territory)
end

function M.getInvasion(invasionId)
    return registry.invasions[invasionId]
end

function M.getInvasionStage(invasionId)
    return state.get().invasionStage[invasionId]
end

function M.isCorrupted(territoryId)
    return state.get().corrupted[territoryId] ~= nil
end

--------------------------------------------------------------------------
-- Diagnostics
--------------------------------------------------------------------------

--- One-line faction standings.
function M.powerSummary()
    return power.summary()
end

--- The in-game day the simulation has resolved up to.
function M.getCurrentDay()
    return state.get().lastResolvedDay
end

--- Resolve `count` in-game days immediately instead of waiting for the
-- calendar. Testing aid: this runs the simulation ahead of game time,
-- so the scheduled tick then idles until real time catches up.
function M.forceDay(count)
    return driver.forceDays(count)
end

--- Dump the whole simulation to the log. Safe to call at any time; the
-- intended use is from the in-game console while testing.
function M.dump()
    local data = state.get()

    local landmassCount = 0
    for _ in pairs(registry.landmasses) do
        landmassCount = landmassCount + 1
    end

    -- One pass over ownership, rather than re-scanning it per faction.
    local held = {}
    for territoryId, owner in pairs(data.ownership) do
        if owner and registry.territories[territoryId] then
            held[owner] = (held[owner] or 0) + 1
        end
    end

    log.info('--- Balance of Power -----------------------------------')
    log.info('interface v%d | day %s | %d landmass(es) | %d anchors | %d frontier cells',
        M.version, tostring(data.lastResolvedDay), landmassCount,
        #registry.anchorIds, #registry.frontierIds)

    for _, id in ipairs(registry.sortedFactionIds()) do
        local faction = registry.factions[id]
        local tags = ''
        if not faction.territorial then
            tags = tags .. ' [non-territorial]'
        end
        if faction.invading then
            tags = tags .. ' [invader ' .. tostring(data.invasionStage[faction.invasionId]) .. ']'
        end
        log.info('  %-20s power %7.2f  territories %4d%s',
            faction.displayName, power.getLive(id), held[id] or 0, tags)
    end
    log.info('--------------------------------------------------------')
end

--- Whether verbose logging is on, for packs that want to match it.
function M.isDebug()
    return config.DEBUG
end

return M
