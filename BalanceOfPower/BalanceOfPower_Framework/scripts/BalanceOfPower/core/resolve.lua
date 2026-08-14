-- Territory resolution: who holds what, and how that changes (design
-- doc 3.2 and 3.4).
--
-- The model in one paragraph. Every settlement projects influence that
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
-- win.
--
-- Settlements are not contestable at all. The competition this framework
-- models is non-violent -- influence shifting, borders breathing -- and
-- Morrowind has nowhere to put the consequences of a city changing
-- hands. A settlement is claimed once and then held. Anything that wants
-- to take one owns that mechanic itself, reading ownership, projection
-- and isSurrounded() through the interface.
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

--- How much of a settlement's projection survives a given distance:
-- halved once per `influenceRange`, and never reaching zero.
--
--   d = 0                  1.0
--   d = influenceRange     0.5
--   d = 2 * influenceRange 0.25
--
-- The tail matters more than the curve. Because the factor is only ever
-- small and never zero, how far a faction can *reach* is a consequence of
-- how much power it has rather than a separate limit: ground it cannot
-- claim today becomes claimable if it grows enough, and no cell is
-- permanently beyond everybody.
--
-- Halving is what makes that growth well-behaved. Distance costs a fixed
-- fraction per unit, so power buys distance logarithmically:
--
--   **every doubling of a faction's power pushes its border out by
--   exactly one influenceRange.**
--
-- Ten times the power is therefore a bit over three influenceRanges
-- further, not ten times further, and the diminishing returns need no
-- special casing to produce -- they are what an exponential is.
function M.proximityFactor(distance, influenceRange)
    if influenceRange <= 0 then
        return 0
    end
    return 2 ^ (-distance / influenceRange)
end

--------------------------------------------------------------------------
-- Projection cache
--------------------------------------------------------------------------

-- How far a faction reaches into a territory is fixed: it depends only
-- on the distance from its settlements and their ranges, none of which
-- move. Only the faction's *power* changes from day to day, and that's a
-- single multiplication.
--
-- So the geometry is computed once and cached as a static factor per
-- (territory, faction) pair, and the daily pass does no square roots at
-- all. The cache also yields, for free, the list of factions that can
-- reach a given territory -- usually one or two out of a dozen, which is
-- what keeps a large map cheap to resolve.
--
-- territoryId -> {
--   ids     = {sorted factionIds},
--   factors = {factionId -> f},     -- power is multiplied by this
--   floors  = {factionId -> n},     -- and can never fall below this
-- }
local projections = nil
local projectionGeneration = -1

local EMPTY = { ids = {}, factors = {}, floors = {} }

local function buildProjections()
    local cache = {}

    for territoryId, territory in pairs(registry.territories) do
        local factors, floors, ids = {}, {}, {}
        local centroid = territory.centroid
        local ownCell = territory.cells[1]

        if centroid then
            for factionId, faction in pairs(registry.factions) do
                -- Power-only factions are skipped outright: they hold no
                -- ground and project nothing, so they never appear in a
                -- territory's reach list at all.
                if faction.territorial then
                    local best, floor = 0, 0
                    for _, seat in ipairs(faction.seats) do
                        -- The strongest single seat, never the sum
                        -- (doc 3.2). Summing would let a faction
                        -- out-project a rival purely by accumulating
                        -- farms; max says a place is under the influence
                        -- of whichever holding is nearest.
                        local weighted = seat.weight * M.proximityFactor(
                            distanceBetween(centroid, seat.centroid), seat.influenceRange)
                        if weighted > best then
                            best = weighted
                        end
                        -- Standing on its own ground. A settlement
                        -- occupying this cell can't be projected out of
                        -- it, which is what stops settlements changing
                        -- hands without a rule anywhere saying they
                        -- can't.
                        for _, cellName in ipairs(seat.cells) do
                            if cellName == ownCell then
                                local floorHere = config.SEAT_FLOOR * seat.weight
                                if floorHere > floor then
                                    floor = floorHere
                                end
                            end
                        end
                    end
                    -- Only worth caching if a faction of plausible power
                    -- could ever claim here. Projection never reaches
                    -- zero, so without this every faction would appear in
                    -- every territory's reach list -- twenty-four entries
                    -- where one or two carry the answer, and the sparse
                    -- reach list is the thing that keeps the daily pass
                    -- cheap on a map this size.
                    local reachable =
                        best * config.PROJECTION_HORIZON_POWER >= config.MIN_CLAIM_POWER
                    if reachable or floor > 0 then
                        factors[factionId] = best
                        floors[factionId] = floor
                        ids[#ids + 1] = factionId
                    end
                end
            end
        end

        -- Sorted, so a tie between two equal projections resolves the
        -- same way every session rather than following table order.
        table.sort(ids)
        cache[territoryId] = { ids = ids, factors = factors, floors = floors }
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

--- Force a rebuild. Only needed if a pack mutates settlement geometry
-- after registration, which it shouldn't.
function M.invalidateProjections()
    projections = nil
end

--- How strong a faction is at a territory: its power scaled by how far
-- its nearest foothold reaches there, and never less than the garrison
-- floor of a settlement standing on this very cell.
function M.effectivePower(factionId, territory)
    local entry = M.projectionFactors(territory)
    local factor = entry.factors[factionId]
    if not factor then
        return 0
    end
    -- Batch-aware: during a resolution pass this reads the snapshot
    -- taken at the start of the day, so every territory is evaluated
    -- against the same numbers.
    return math.max(power.get(factionId) * factor, entry.floors[factionId] or 0)
end

--- The strongest projector at a territory, plus the incumbent's own
-- strength there.
-- @return strongestId, strongestValue, ownerValue
local function evaluate(territory, ownerId)
    local entry = M.projectionFactors(territory)
    local bestId, bestValue, ownerValue = nil, 0, 0

    for _, id in ipairs(entry.ids) do
        local value = math.max(power.get(id) * entry.factors[id], entry.floors[id] or 0)
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

--- How settled a territory is, right now. One of four, and exactly one:
--
--   'unclaimed'    nobody owns it
--   'consolidated' one faction is above the claim threshold, and holds it
--   'uncontested'  several are, and the owner is the strongest
--   'contested'    the owner is not the strongest, so it is changing hands
--
-- The partition is the point. `unclaimed` is exactly "no owner", so the
-- other three cover everything owned and nothing is in two states at
-- once. Anything reading this can switch on it without also having to
-- ask getOwner().
--
-- Note what `uncontested` does *not* mean: it does not mean nobody else
-- is here. Two factions can both be projecting hard onto a cell and it
-- still reads uncontested while the owner leads. The "deep interior,
-- nobody else within reach" signal is `consolidated`, which is the one
-- a spawn rule wants when deciding whether a cell is a border.
function M.classify(territory)
    if state.getOwner(territory.id) == nil then
        return 'unclaimed'
    end

    local entry = M.projectionFactors(territory)
    local above = 0
    for _, id in ipairs(entry.ids) do
        local value = math.max(power.get(id) * entry.factors[id], entry.floors[id] or 0)
        if value >= config.MIN_CLAIM_POWER then
            above = above + 1
        end
    end

    if above <= 1 then
        return 'consolidated'
    end

    local bestId = evaluate(territory, nil)
    return bestId == state.getOwner(territory.id) and 'uncontested' or 'contested'
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
    -- settlements, never against its neighbours' ownership, so
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
-- Resolution
--------------------------------------------------------------------------

--- Let go of ground nobody can hold any more.
--
-- The claim threshold governs ownership the whole way through, not only
-- at the moment of first claim. A faction whose power collapses stops
-- holding the far edges of what it reached, and those cells go back to
-- being nobody's rather than staying on the books forever.
--
-- Released only when *no* faction clears the threshold, deliberately.
-- Releasing as soon as the owner fell below would hand the cell to a
-- rival with no roll at all, and the front would snap instead of creep.
local function release(territory, owner, day)
    state.setOwner(territory.id, nil)
    events.emit(events.TERRITORY_FLIPPED, {
        territory = territory.id,
        kind = territory.kind,
        from = owner,
        to = nil,
        day = day,
    })
    log.debug('%s: %s -> unclaimed', territory.id, tostring(owner))
end

--- One rule, every cell.
--
-- Settlements go through this exactly like wilderness. What keeps a city
-- in the same hands is not a branch here but the garrison floor in its
-- projection -- see config.SEAT_FLOOR. A rule with no exceptions is
-- worth more than a rule that reads slightly more directly, because
-- every exception is a case somebody has to remember later.
local function resolveTerritory(territory, day)
    local owner = state.getOwner(territory.id)
    local bestId, bestValue, ownerValue = evaluate(territory, owner)
    local reachable = bestId ~= nil and bestValue >= config.MIN_CLAIM_POWER

    if owner == nil then
        -- Nobody to fight. Projection alone decides it, above the floor.
        if reachable then
            capture(territory, nil, bestId, day)
        end
        return
    end

    if not reachable then
        release(territory, owner, day)
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
-- Settlements
--------------------------------------------------------------------------

--- Whether enough of a settlement's surrounding frontier is in rival
-- hands. Observed and published; nothing in the framework acts on it.
--
-- @param settlement a record from registry.settlements, not a territory
function M.isSurrounded(settlement)
    local adjacent = settlement.adjacentFrontier
    local total = adjacent and #adjacent or 0
    if total == 0 then
        -- Nothing authored or generated around it. A data gap rather
        -- than a fortress, but "not surrounded" is the safe reading.
        return false
    end

    local ownerId = M.settlementOwner(settlement)
    local rivalHeld = 0
    for _, id in ipairs(adjacent) do
        local holder = state.getOwner(id)
        if holder and holder ~= ownerId then
            rivalHeld = rivalHeld + 1
        end
    end
    return (rivalHeld / total) >= config.SURROUND_SHARE
end

--- Who holds a settlement. Its cells share an owner in practice, since
-- the same garrison floor applies across the whole footprint, so the
-- first one answers for all of them.
function M.settlementOwner(settlement)
    return state.getOwner(settlement.territoryIds[1])
end

--- Record whether a settlement is surrounded, and announce the change.
local function updateSurrounded(settlement, day)
    local data = state.get()
    local was = data.surroundedSince[settlement.id] ~= nil
    local now = M.isSurrounded(settlement)

    if now == was then
        return
    end

    if now then
        data.surroundedSince[settlement.id] = day
        events.emit(events.SETTLEMENT_SURROUNDED, { territory = settlement.id, day = day })
    else
        data.surroundedSince[settlement.id] = nil
        events.emit(events.SETTLEMENT_RELIEVED, { territory = settlement.id, day = day })
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
-- Every cell goes through the same rule, in one pass. The surrounded
-- check runs after all of it, because it reads the frontier ownership
-- the pass has just settled -- doing it inline would judge each
-- settlement against a half-updated map.
function M.run(day, batch)
    if batch then
        for _, id in ipairs(batch) do
            local territory = registry.territories[id]
            if territory then
                resolveTerritory(territory, day)
            end
        end
    else
        for _, id in ipairs(registry.frontierIds) do
            resolveTerritory(registry.territories[id], day)
        end
        for _, id in ipairs(registry.settlementCellIds) do
            resolveTerritory(registry.territories[id], day)
        end
    end

    for _, id in ipairs(registry.settlementIds) do
        updateSurrounded(registry.settlements[id], day)
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
