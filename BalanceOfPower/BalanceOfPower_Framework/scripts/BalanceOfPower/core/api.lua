-- The public interface, exposed to other mods as 
-- require('openmw.interfaces').BalanceOfPower from any global script.
--
-- This is the whole contract. A content pack should never require a file
-- under scripts/BalanceOfPower/core/ -- the merged VFS would let it, but
-- internals change without notice, and during alpha so does this file
-- (see `version`). Anything a pack needs and can't get here is a gap.

local config = require('scripts.BalanceOfPower.core.config')
local driver = require('scripts.BalanceOfPower.core.driver')
local events = require('scripts.BalanceOfPower.core.events')
local frontier = require('scripts.BalanceOfPower.core.frontier')
local hostility = require('scripts.BalanceOfPower.core.hostility')
local log = require('scripts.BalanceOfPower.core.log')
local mapdump = require('scripts.BalanceOfPower.core.mapdump')
local patrol = require('scripts.BalanceOfPower.core.patrol')
local power = require('scripts.BalanceOfPower.core.power')
local registry = require('scripts.BalanceOfPower.core.registry')
local resolve = require('scripts.BalanceOfPower.core.resolve')
local state = require('scripts.BalanceOfPower.core.state')

local M = {
    -- Closed alpha: nothing here is stable.
    version = 0,

    -- Event name constants, so listeners don't hardcode the strings.
    events = events,

    -- World units per exterior cell, as the engine defines it.
    CELL_SIZE = config.CELL_SIZE,
}

--------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------

function M.registerLandmass(def)
    local landmass = registry.registerLandmass(def)
    state.fillDefaults(registry)
    return landmass
end

--- Derive a landmass's frontier grid from its registered settlements.
-- Call after registerLandmass, once the settlements are in.
--
-- Only ground within reach of some settlement becomes territory, so the
-- map's size follows from the content rather than from a bounding box.
-- See core/frontier.lua for the options.
-- @return number of frontier territories created
function M.generateFrontier(def)
    local created = frontier.generate(def)
    state.fillDefaults(registry)
    return created
end

--------------------------------------------------------------------------
-- Power
--------------------------------------------------------------------------

--- Award (or subtract) power on behalf of the player's actions. The one
-- entry point content is expected to call: a quest mod, a dialogue hook
-- or a future combat hook moves a faction's standing without knowing
-- anything about propagation, batching or reactions.
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

--- How `factionId` feels about `towardId`, in roughly [-3, 3]; 0 if it
-- has no opinion. Merged from the game's records and authored tables,
-- which is why it is a function and not a table a pack can read.
--
-- This is also how far `factionId` moves when `towardId`'s power does.
function M.regardOf(factionId, towardId)
    return power.regardOf(factionId, towardId)
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

--- Registered territory ids -- one per exterior cell. `kind` is
-- 'settlement', 'frontier', or nil for both. Registration order, copied.
-- A settlement's cells appear individually; for the named places
-- themselves, use settlementIds().
function M.territoryIds(kind)
    local out = {}
    if kind ~= 'frontier' then
        for _, id in ipairs(registry.settlementCellIds) do
            out[#out + 1] = id
        end
    end
    if kind ~= 'settlement' then
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

--- How settled a territory is: 'unclaimed', 'consolidated', 'uncontested'
-- or 'contested'. Exactly one of the four, always -- see
-- core/resolve.lua for what each means and why the partition matters.
function M.classify(territoryId)
    local territory = registry.territories[territoryId]
    return territory and resolve.classify(territory) or 'unclaimed'
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

--- A named place: { id, displayName, tier, region, landmass, cells,
-- territoryIds, interiors, centroid, adjacentFrontier }.
--
-- A settlement is a group, not a territory: its cells are ownable
-- individually and appear in territoryIds('settlement'), while the
-- settlement carries the name, the tier and the ring isSurrounded() uses.
function M.getSettlement(settlementId)
    return registry.settlements[settlementId]
end

--- Every settlement id, in registration order, copied.
function M.settlementIds()
    local out = {}
    for _, id in ipairs(registry.settlementIds) do
        out[#out + 1] = id
    end
    return out
end

--- Who holds a settlement. Its cells share an owner in practice, since
-- the same garrison floor applies across the whole footprint.
function M.getSettlementOwner(settlementId)
    local settlement = registry.settlements[settlementId]
    return settlement and resolve.settlementOwner(settlement) or nil
end

--- Whether rivals hold `SURROUND_SHARE` of a settlement's adjacent
-- frontier. Takes a settlement id, not a territory id.
--
-- The framework observes this and does nothing about it. It is here
-- because answering it needs the frontier ownership map, and every
-- extension that cares would otherwise derive it from the same data.
function M.isSurrounded(settlementId)
    local settlement = registry.settlements[settlementId]
    return settlement ~= nil and resolve.isSurrounded(settlement)
end

--- The day a settlement most recently became surrounded, or nil.
-- Subtract from getCurrentDay() for a duration; the framework
-- deliberately keeps no streak of its own.
function M.surroundedSince(settlementId)
    return state.get().surroundedSince[settlementId]
end

--------------------------------------------------------------------------
-- Hostility
--------------------------------------------------------------------------
--
-- One rule at three settings: a faction fights nobody unless its pack
-- flagged it hostile, and a flagged faction fights whoever it regards at
-- or below HOSTILITY_REACTION_THRESHOLD. The framework starts no fights
-- of its own -- it answers the question so everything spawning actors
-- answers it the same way.

--- Whether `factionId` attacks `towardId` on sight. Asymmetric: a
-- peaceful faction does not go looking for the fight it ends up in.
function M.isHostile(factionId, towardId)
    return hostility.isHostile(factionId, towardId)
end

--- Whether these two come to blows, from either side's initiative.
function M.willFight(factionId, otherId)
    return hostility.willFight(factionId, otherId)
end

--- Whether `factionId` attacks the player on sight. The player has no
-- reaction row, so this is the flag itself rather than a lookup.
function M.isHostileToPlayer(factionId)
    return hostility.isHostileToPlayer(factionId)
end

--- Every registered faction `factionId` attacks on sight, sorted. Empty
-- for a peaceful faction, and for a hostile one with nobody it hates
-- enough -- worth checking after flagging one.
function M.enemiesOf(factionId)
    return hostility.enemiesOf(factionId)
end

--------------------------------------------------------------------------
-- Patrols
--------------------------------------------------------------------------

--- What should be standing in a territory on a given day, or nil.
--
--   { territory, day, groups = { {
--       faction, projection, count, tier,
--       records = { recordId, ... },       -- exactly `count` of them
--       hostileToPlayer,
--       fights = { factionId, ... },       -- other groups in this plan
--   }, ... } }
--
-- Decisions only: this creates nothing and touches no actor. `records`
-- are the ids the faction's pack authored, in its own vocabulary; the
-- framework has never looked inside them.
--
-- Stable for a given territory and day rather than rolled fresh, so
-- re-entering a cell gives the same patrol back instead of making every
-- patrol a renewable source of whatever its records carry.
--
-- @param opts table|nil { lastSpawnedDay = number } to apply the
--        per-cell cooldown; omit if nothing has spawned here
function M.planPatrol(territoryId, day, opts)
    return patrol.plan(territoryId, day, opts)
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
-- faction standing outside the politics in one direction -- never an
-- error, close to invisible in play. A faction with no ESM record behind
-- it sits at movedBy = 0 until its pack authors its reaction row.
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

--- Resolve `count` in-game days immediately. Testing aid: this runs the
-- simulation ahead of game time, so the scheduled tick then idles until
-- real time catches up.
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
    log.info('interface v%d | day %s | %d landmass(es) | %d settlements over %d cells '
        .. '| %d frontier cells',
        M.version, tostring(data.lastResolvedDay), landmassCount,
        #registry.settlementIds, #registry.settlementCellIds, #registry.frontierIds)

    for _, id in ipairs(registry.sortedFactionIds()) do
        local faction = registry.factions[id]
        local tags = faction.territorial and '' or ' [non-territorial]'
        if (faction.growthPerDay or 0) ~= 0 then
            tags = tags .. string.format(' [%+.2f/day]', faction.growthPerDay)
        end
        if hostility.isBelligerent(id) then
            -- The enemy list, not just the flag: a hostile faction with
            -- nobody it hates enough looks like a working one until you
            -- watch it walk past a rival patrol.
            local enemies = hostility.enemiesOf(id)
            tags = tags .. ' [hostile: '
                .. (#enemies > 0 and table.concat(enemies, ', ') or 'player only') .. ']'
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
-- disagrees with ownership, the front is moving.
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
