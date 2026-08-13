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
local frontier = require('scripts.BalanceOfPower.core.frontier')
local log = require('scripts.BalanceOfPower.core.log')
local mapdump = require('scripts.BalanceOfPower.core.mapdump')
local power = require('scripts.BalanceOfPower.core.power')
local registry = require('scripts.BalanceOfPower.core.registry')
local resolve = require('scripts.BalanceOfPower.core.resolve')
local state = require('scripts.BalanceOfPower.core.state')

local M = {
    -- Bumped when this interface changes in a way a pack could notice.
    -- Packs should check it rather than assuming a function exists.
    --
    -- v2 added CELL_SIZE, reactionAudit and dumpReactions.
    version = 2,

    -- Event name constants, so listeners don't hardcode the strings.
    events = events,

    -- World units per exterior cell, as the engine defines it.
    --
    -- Exposed because a pack that places anything by grid coordinate has
    -- to agree with the frontier generator about where a cell is, and
    -- the only alternative is for the pack to write 8192 down a second
    -- time. Two copies of a constant that must match is exactly the kind
    -- of drift that produces a map subtly out of register with its own
    -- settlements, with nothing to catch it.
    CELL_SIZE = config.CELL_SIZE,
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

--- Derive a landmass's frontier grid from the power centers registered
-- on it. Call after registerLandmass, once the settlements are in.
--
-- Only ground within reach of some power center becomes territory, so
-- the size of the resulting map follows from the content rather than
-- from a bounding box. See core/frontier.lua for the options.
-- @return number of frontier territories created
function M.generateFrontier(def)
    local created = frontier.generate(def)
    state.fillDefaults(registry)
    return created
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

--- How settled a territory is: 'empty', 'consolidated' or 'contested'.
function M.classify(territoryId)
    local territory = registry.territories[territoryId]
    return territory and resolve.classify(territory) or 'empty'
end

--- Which factions can reach a territory at all, and by what fraction of
-- their power. Static geometry, so this is cheap and stable.
-- @return { ids = {sorted factionIds}, factors = {factionId -> 0..1} }
function M.getReach(territoryId)
    local territory = registry.territories[territoryId]
    if not territory then
        return { ids = {}, factors = {} }
    end
    return resolve.projectionFactors(territory)
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

--- How the reaction wiring resolved, per faction: `moves` is how many
-- factions it can push, `movedBy` how many can push it.
--
-- Worth reading after adding a faction. A zero in either column is a
-- faction standing outside the politics in one direction, which never
-- shows up as an error and is close to invisible in play -- a faction
-- with no ESM record behind it sits at movedBy = 0 until some pack
-- authors the other side of the relationship.
-- @return list of { id, moves, movedBy }, sorted by id
function M.reactionAudit()
    return power.reactionAudit()
end

--- The same audit, printed.
function M.dumpReactions()
    log.info('--- reaction wiring ------------------------------------')
    log.info('  %-24s %6s %8s', 'faction', 'moves', 'moved by')
    for _, row in ipairs(power.reactionAudit()) do
        log.info('  %-24s %6d %8d%s', row.id, row.moves, row.movedBy,
            (row.moves == 0 or row.movedBy == 0) and '   <-- outside the politics' or '')
    end
    log.info('--------------------------------------------------------')
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

--- Draw the political map to the log, one character per exterior cell.
--
--   dumpMap()                                  every landmass, ownership
--   dumpMap({ landmass = 'vvardenfell' })      just one
--   dumpMap({ mode = 'projection' })           who *will* hold each cell
--   dumpMap({ mode = 'contest' })              where the fronts are
--
-- 'projection' is the one to read while tuning influence ranges: where it
-- disagrees with the ownership map, the front is moving.
function M.dumpMap(opts)
    mapdump.dump(opts)
end

--- The same map as a list of text lines, for a caller that wants to put
-- it somewhere other than the log.
function M.renderMap(opts)
    return mapdump.render(opts)
end

--- Whether verbose logging is on, for packs that want to match it.
function M.isDebug()
    return config.DEBUG
end

return M
