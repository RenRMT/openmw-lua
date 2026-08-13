-- Territory resolution: who holds what, and how that changes (design
-- doc 3.2 and 3.4).
--
-- The model in one paragraph. Every power center projects influence that
-- decays with distance; a faction's strength at a given place is its
-- strongest single projection there, never the sum, so a faction can't
-- out-project a rival by accumulating minor outposts. Whoever projects
-- most at a territory is the one who ends up holding it -- but not
-- instantly. Taking ground off an existing owner is a daily roll whose
-- odds are the two sides' share of projected strength, so the strongest
-- projector wins reliably rather than immediately, and a front creeps
-- instead of snapping. Ground nobody holds needs no roll, only enough
-- projection to clear MIN_CLAIM_POWER.
--
-- A consequence worth knowing: while the current owner is also the
-- strongest projector, no rival roll happens at all. Rolls are how long
-- a takeover takes, not who wins it. Ownership only moves when the
-- projection ordering itself changes -- which happens when faction power
-- moves, which is what the rest of the mod is about.
--
-- Frontier cells are contestable regardless of what's next to them. They
-- don't need an adjacency gate because proximity decay already is one:
-- a faction with no foothold nearby projects nothing there and cannot
-- win. Anchors are different -- a settlement has to be surrounded on the
-- frontier for several days running before it can even be rolled for.
--
-- GLOBAL context only.

local config = require('scripts.BalanceOfPower.core.config')
local events = require('scripts.BalanceOfPower.core.events')
local log = require('scripts.BalanceOfPower.core.log')
local power = require('scripts.BalanceOfPower.core.power')
local registry = require('scripts.BalanceOfPower.core.registry')
local state = require('scripts.BalanceOfPower.core.state')

local M = {}

-- Swappable so tests can drive the rolls deterministically. Seeding
-- math.random instead would tie the tests to one Lua build's generator.
local random = math.random

--- Replace the random source. Pass nil to restore math.random.
function M.setRandom(fn)
    random = fn or math.random
end

--------------------------------------------------------------------------
-- Projection maths
--------------------------------------------------------------------------

-- Horizontal only: z is carried on coordinates but ignored here, so a
-- tower and the ground beneath it aren't treated as distant.
local function distanceBetween(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

--- Linear falloff from 1 at the power center to 0 at influenceRange.
function M.proximityFactor(distance, influenceRange)
    if influenceRange <= 0 then
        return 0
    end
    return math.max(0, 1 - distance / influenceRange)
end

--------------------------------------------------------------------------
-- Projection cache
--------------------------------------------------------------------------

-- How far a faction reaches into a territory is fixed: it depends only
-- on the distance from its power centers and their ranges, none of which
-- move. Only the faction's *power* changes from day to day, and that's a
-- single multiplication.
--
-- So the geometry is computed once and cached as a static factor per
-- (territory, faction) pair, and the daily pass does no square roots at
-- all. The cache also yields, for free, the list of factions that can
-- reach a given territory -- usually one or two out of a dozen, which is
-- what keeps a large map cheap to resolve.
--
-- territoryId -> { ids = {sorted factionIds}, factors = {factionId -> f} }
local projections = nil
local projectionGeneration = -1

local EMPTY = { ids = {}, factors = {} }

local function buildProjections()
    local cache = {}

    for territoryId, territory in pairs(registry.territories) do
        local factors, ids = {}, {}
        local centroid = territory.centroid

        if centroid then
            for factionId, faction in pairs(registry.factions) do
                -- Power-only factions are skipped outright: they hold no
                -- ground and project nothing, so they never appear in a
                -- territory's reach list at all.
                if faction.territorial then
                    local best = 0
                    for _, centre in ipairs(faction.powerCenters) do
                        -- The strongest single center, never the sum
                        -- (doc 3.2). Summing would let a faction
                        -- out-project a rival purely by accumulating
                        -- minor outposts; max says a place is under the
                        -- influence of whichever foothold is nearest.
                        local weighted = centre.weight * M.proximityFactor(
                            distanceBetween(centroid, centre.coords), centre.influenceRange)
                        if weighted > best then
                            best = weighted
                        end
                    end
                    if best > 0 then
                        factors[factionId] = best
                        ids[#ids + 1] = factionId
                    end
                end
            end
        end

        -- Sorted, so a tie between two equal projections resolves the
        -- same way every session rather than following table order.
        table.sort(ids)
        cache[territoryId] = { ids = ids, factors = factors }
    end

    projections = cache
    projectionGeneration = registry.generation
end

--- The factions that can reach a territory, and by what fraction of
-- their power. Rebuilt automatically whenever a pack registers anything.
function M.projectionFactors(territory)
    if projections == nil or projectionGeneration ~= registry.generation then
        buildProjections()
    end
    return projections[territory.id] or EMPTY
end

--- Force a rebuild. Only needed if a pack mutates power center geometry
-- after registration, which it shouldn't.
function M.invalidateProjections()
    projections = nil
end

--- How strong a faction is at a territory: its power scaled by how far
-- its nearest foothold reaches there.
function M.effectivePower(factionId, territory)
    local factor = M.projectionFactors(territory).factors[factionId]
    if not factor then
        return 0
    end
    -- Batch-aware: during a resolution pass this reads the snapshot
    -- taken at the start of the day, so every territory is evaluated
    -- against the same numbers.
    return power.get(factionId) * factor
end

--- The strongest projector at a territory, plus the incumbent's own
-- strength there.
-- @return strongestId, strongestValue, ownerValue
local function evaluate(territory, ownerId)
    local entry = M.projectionFactors(territory)
    local bestId, bestValue, ownerValue = nil, 0, 0

    for _, id in ipairs(entry.ids) do
        local value = power.get(id) * entry.factors[id]
        if id == ownerId then
            ownerValue = value
        end
        -- Strict >, so the first id in sorted order wins a tie.
        if value > bestValue then
            bestId, bestValue = id, value
        end
    end
    return bestId, bestValue, ownerValue
end

--- How settled a territory is, right now.
--
--   'empty'        nobody projects hard enough to hold it
--   'consolidated' exactly one faction is above the claim floor
--   'contested'    two or more are, so it can change hands
--
-- Exposed rather than used internally: the resolution passes already
-- have the numbers in hand. It's here so a UI, a spawn rule or a future
-- staggering scheduler can ask the question without recomputing.
function M.classify(territory)
    local entry = M.projectionFactors(territory)
    local above = 0
    for _, id in ipairs(entry.ids) do
        if power.get(id) * entry.factors[id] >= config.MIN_CLAIM_POWER then
            above = above + 1
            if above > 1 then
                return 'contested'
            end
        end
    end
    return above == 1 and 'consolidated' or 'empty'
end

--- The attacker's share of the two sides' strength.
local function powerRoll(attacker, defender)
    local total = attacker + defender
    if total <= 0 then
        return false
    end
    return random() < attacker / total
end

--------------------------------------------------------------------------
-- Ownership changes
--------------------------------------------------------------------------

local function onCooldown(territory, day)
    local last = state.get().lastFlipped[territory.id]
    if last == nil then
        return false
    end
    return (day - last) < (territory.cooldownDays or 0)
end

--- Hand a territory to a faction. No cooldown, no event -- this is the
-- bare assignment, used directly only for setting up the starting map.
local function assign(territory, factionId)
    state.setOwner(territory.id, factionId)
    if territory.kind == 'anchor' then
        state.get().siegeStreak[territory.id] = 0
    end
end

--- Take a territory during play: assignment, plus the cooldown stamp
-- that protects the new owner, plus the event.
local function capture(territory, from, to, day)
    assign(territory, to)
    state.get().lastFlipped[territory.id] = day
    events.emit(events.TERRITORY_FLIPPED, {
        territory = territory.id,
        kind = territory.kind,
        from = from,
        to = to,
        day = day,
    })
    log.debug('%s: %s -> %s', territory.id, tostring(from), to)
end

--------------------------------------------------------------------------
-- Initial control
--------------------------------------------------------------------------

--- Hand every unheld territory to whoever projects most onto it.
--
-- This is what removes the need to hand-author an owner for a
-- procedurally generated frontier grid: a pack declares where the seats
-- of power are, and the map falls out of that. An authored defaultOwner
-- still wins where one is given, which is how an invasion homeland stays
-- with its invader regardless of who projects onto it.
--
-- This is not a flip, and is deliberately not treated as one. It fires
-- no events -- several hundred "territory changed hands" notifications
-- on the first tick of a new game would be noise, not news -- and it
-- stamps no cooldown, because stamping one would make the entire map
-- uncontestable for the first few days of every new game.
function M.assignInitialControl()
    local claimed = 0

    -- Order-independent: each territory is judged only against the
    -- power centres, never against its neighbours' ownership, so
    -- iteration order can't change the result.
    for id, territory in pairs(registry.territories) do
        if state.getOwner(id) == nil then
            local bestId, bestValue = evaluate(territory, nil)
            if bestId and bestValue >= config.MIN_CLAIM_POWER then
                assign(territory, bestId)
                claimed = claimed + 1
            end
        end
    end

    if claimed > 0 then
        log.info('initial control assigned by projection: %d territories claimed', claimed)
    end
    return claimed
end

--------------------------------------------------------------------------
-- Pass 1: frontier
--------------------------------------------------------------------------

local function resolveFrontier(territory, day)
    local owner = state.getOwner(territory.id)
    local bestId, bestValue, ownerValue = evaluate(territory, owner)

    if not bestId then
        return
    end

    if owner == nil then
        -- Nobody to fight. Projection alone decides it, above a floor.
        if bestValue >= config.MIN_CLAIM_POWER then
            capture(territory, nil, bestId, day)
        end
        return
    end

    -- The incumbent is still the strongest here, so nothing is contested.
    if bestId == owner then
        return
    end

    if onCooldown(territory, day) then
        return
    end

    if powerRoll(bestValue, ownerValue) then
        capture(territory, owner, bestId, day)
    end
end

--------------------------------------------------------------------------
-- Pass 2: anchors
--------------------------------------------------------------------------

--- Whether enough of an anchor's surrounding frontier is in rival hands.
local function isSurrounded(territory, ownerId)
    local adjacent = territory.adjacentFrontier
    local total = #adjacent
    if total == 0 then
        -- An anchor with no frontier authored around it can't be
        -- besieged. That's a data gap, not a fortress, but treating it
        -- as untakeable is the safe reading.
        return false
    end

    local rivalHeld = 0
    for _, id in ipairs(adjacent) do
        local holder = state.getOwner(id)
        if holder and holder ~= ownerId then
            rivalHeld = rivalHeld + 1
        end
    end
    return (rivalHeld / total) >= config.SURROUND_SHARE
end

local function resolveAnchor(territory, day)
    local owner = state.getOwner(territory.id)
    local bestId, bestValue, ownerValue = evaluate(territory, owner)

    if owner == nil then
        if bestId and bestValue >= config.MIN_CLAIM_POWER then
            capture(territory, nil, bestId, day)
        end
        return
    end

    local data = state.get()

    if not isSurrounded(territory, owner) then
        data.siegeStreak[territory.id] = 0
        return
    end

    local streak = (data.siegeStreak[territory.id] or 0) + 1
    data.siegeStreak[territory.id] = streak
    events.emit(events.ANCHOR_SIEGED, {
        territory = territory.id,
        streak = streak,
        threshold = territory.siegeThreshold,
    })

    if streak < territory.siegeThreshold then
        return
    end
    if onCooldown(territory, day) then
        return
    end
    if not bestId or bestId == owner then
        return
    end

    -- Garrison and walls. This multiplier is the whole reason a city
    -- doesn't change hands over a trade dispute -- it's set high enough
    -- that ordinary faction politics effectively can't take one, leaving
    -- real city flips to the invasion subsystem.
    if powerRoll(bestValue, ownerValue * territory.defenseMultiplier) then
        capture(territory, owner, bestId, day)
    end
end

--------------------------------------------------------------------------
-- Entry point
--------------------------------------------------------------------------

--- Resolve one day.
--
-- @param day number the in-game day index being resolved
-- @param batch list of territory ids, or nil for every registered one
--
-- The batch is explicit even though the MVP always passes nil, because
-- doc 3.4 expects resolution to be split across staggered buckets once
-- the graph is large. Keeping the parameter means that becomes a change
-- to the scheduler alone.
--
-- Frontier always resolves before anchors, within whatever batch is
-- given: the frontier is what decides whether an anchor is surrounded,
-- so evaluating anchors first would judge them on yesterday's map.
function M.run(day, batch)
    local frontier, anchors = {}, {}
    if batch then
        for _, id in ipairs(batch) do
            local territory = registry.territories[id]
            if territory then
                local bucket = territory.kind == 'anchor' and anchors or frontier
                bucket[#bucket + 1] = territory
            end
        end
    else
        for _, id in ipairs(registry.frontierIds) do
            frontier[#frontier + 1] = registry.territories[id]
        end
        for _, id in ipairs(registry.anchorIds) do
            anchors[#anchors + 1] = registry.territories[id]
        end
    end

    for _, territory in ipairs(frontier) do
        resolveFrontier(territory, day)
    end
    for _, territory in ipairs(anchors) do
        resolveAnchor(territory, day)
    end
end

--------------------------------------------------------------------------
-- Queries
--------------------------------------------------------------------------

--- Who projects most onto a territory, and how strongly.
-- @return factionId|nil, value
function M.strongestProjector(territory)
    local bestId, bestValue = evaluate(territory, nil)
    return bestId, bestValue
end

return M
