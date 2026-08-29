-- The public interface, exposed to other mods as
-- require('openmw.interfaces').BalanceOfPower from any global script.
--
-- This is the whole contract. A content pack should never require a file
-- under scripts/BalanceOfPower/core/ -- the merged VFS would let it, but
-- internals change without notice, and during alpha so does this file
-- (see `version`). Anything a pack needs and can't get here is a gap.

local config = require('scripts.BalanceOfPower.core.config')
local drift = require('scripts.BalanceOfPower.core.drift')
local driver = require('scripts.BalanceOfPower.core.driver')
local events = require('scripts.BalanceOfPower.core.events')
local frontier = require('scripts.BalanceOfPower.core.frontier')
local holdings = require('scripts.BalanceOfPower.core.holdings')
local hostility = require('scripts.BalanceOfPower.core.hostility')
local log = require('scripts.BalanceOfPower.core.log')
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
-- has no opinion. Read from the game's own faction records, normalized
-- and filtered to registered factions -- which is why it is a function
-- and not a table a pack can index.
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
-- Standings
--------------------------------------------------------------------------
--
-- Where a faction stands, on both sides of the same two axes: the seats
-- it was built with, and the ground it holds today. This is the surface
-- a mod acting on the simulation reads -- the framework publishes the
-- numbers and does nothing about them.

--- Everything known about one faction's position, or nil if it isn't
-- registered.
--
--   { id, power, territories, settlements, regions,
--     seats, seatScore, strain, concentration }
--
-- `strain` is territories held per 100 power: a faction spread thinner
-- than its standing supports reads high. `concentration` is territories
-- per region. Both are ratios over the fields beside them, here so that
-- every mod computes them the same way.
function M.factionStanding(factionId)
    return holdings.factionStanding(factionId)
end

--- Every registered faction's standing, strongest first.
function M.standings()
    return holdings.standings()
end

--- Regions a faction holds any ground in, sorted.
function M.regionsHeldBy(factionId)
    return holdings.regionsHeldBy(factionId)
end

--- Who holds ground in a region, and how much: factionId -> territory
-- count. Region names are the game's own, as carried on the territory.
function M.holdersOfRegion(regionName)
    return holdings.holdersOfRegion(regionName)
end

--- Whether a faction's strain is at or above STRAIN_EVENT_THRESHOLD.
-- Answered live, so it does not wait for the daily pass.
function M.isStrained(factionId)
    return holdings.isStrained(factionId)
end

--- The standing a faction's holdings support -- what drift pulls its
-- power toward, before that day's fortune displaces it.
--
-- The gap between this and getPower() is the whole state of a faction's
-- trajectory: above capacity it is falling, below it is climbing. A UI
-- drawing an arrow reads exactly these two.
function M.getCapacity(factionId)
    return holdings.capacityOf(factionId)
end

--- What a faction's held ground is worth, damped for depth: breadth
-- across regions counts for more than stacking cells in one.
function M.getHeldScore(factionId)
    return holdings.heldScoreOf(factionId)
end

--- Where a faction's luck stands on a given day, in power, positive or
-- negative. Derived from the faction id and the day alone, so it is the
-- same answer every time it is asked and costs no save state.
function M.getFortune(factionId, day)
    return drift.fortuneOf(factionId, day or M.getCurrentDay())
end

--- Whether power drifts for this faction at all. False for an invader,
-- and false for everyone when the player has switched drift off.
function M.driftAppliesTo(factionId)
    return drift.appliesTo(factionId)
end

--- Whether a faction is an outside threat rather than a participant in
-- the politics: no drift, no reactions, hostile to everyone.
function M.isInvader(factionId)
    return registry.isInvader(factionId)
end

--- The day a faction most recently became strained, or nil. Subtract
-- from getCurrentDay() for a duration; as with surroundedSince, the
-- framework keeps no streak of its own.
function M.strainedSince(factionId)
    return state.get().strainedSince[factionId]
end

--------------------------------------------------------------------------
-- Hostility
--------------------------------------------------------------------------
--
-- One rule: an invader fights everyone, and nobody else fights at all.
-- The framework starts no fights of its own -- it answers the question so
-- that everything spawning actors answers it the same way. Reaction rows
-- are readable through regardOf but no longer decide this; see
-- core/hostility.lua for why.

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
-- for anything that is not an invader.
function M.enemiesOf(factionId)
    return hostility.enemiesOf(factionId)
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

    log.info('--- Balance of Power -----------------------------------')
    log.info('interface v%d | day %s | %d landmass(es) | %d settlements over %d cells '
        .. '| %d frontier cells',
        M.version, tostring(data.lastResolvedDay), landmassCount,
        #registry.settlementIds, #registry.settlementCellIds, #registry.frontierIds)

    for _, standing in ipairs(holdings.standings()) do
        local id = standing.id
        local faction = registry.factions[id]
        local tags = faction.territorial and '' or ' [non-territorial]'
        if registry.isInvader(id) then
            tags = tags .. ' [invader]'
        end
        if (faction.growthPerDay or 0) ~= 0 then
            tags = tags .. string.format(' [%+.2f/day]', faction.growthPerDay)
        end
        if hostility.isBelligerent(id) then
            -- The enemy list, not just the flag: an invader with nobody to
            -- fight reads as a working one right up until you notice it
            -- never fights anybody.
            local enemies = hostility.enemiesOf(id)
            tags = tags .. ' [hostile: '
                .. (#enemies > 0 and table.concat(enemies, ', ') or 'player only') .. ']'
        end
        -- Power against capacity is the whole of a faction's trajectory,
        -- and the pair you read while tuning drift: the arrow says which
        -- way today's number is heading and how far it has to go.
        local capacity = holdings.capacityOf(id)
        local arrow = ' '
        if drift.appliesTo(id) then
            arrow = (capacity > standing.power and '^')
                or (capacity < standing.power and 'v') or '='
        end
        log.info('  %-20s power %7.2f %s cap %7.2f  territories %4d  regions %3d  '
            .. 'strain %5.1f%s',
            faction.displayName, standing.power, arrow, capacity, standing.territories,
            standing.regions, standing.strain, tags)
    end
    log.info('--------------------------------------------------------')
end

--- Whether verbose logging is on, for packs that want to match it.
function M.isDebug()
    return config.DEBUG
end

return M
