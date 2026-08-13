-- Faction power: the scalar every other system reads from and writes
-- to (design doc 3.5).
--
-- Two things here are load-bearing beyond "store a number per faction".
--
-- 1. Reaction propagation. A faction's power change drags every other
--    faction along with it, scaled by how that *other* faction feels
--    about the one that moved. Reading the direction the right way round
--    is what makes an invader's story work for free: everyone hates
--    them, so an award in their favour is everyone else's loss, with
--    nothing anywhere special-casing them.
--
--    Ambient growth is the deliberate exception -- see applyDailyGrowth,
--    and the arithmetic on GROWTH_PROPAGATES for why a daily drip
--    through this table is not the same thing as an award.
--
-- 2. Batching. The resolution loop evaluates many rolls per pass, and
--    every roll reads power. If a flip resolved early in the pass
--    changed the numbers a later roll sees, results would depend on
--    which territory happened to resolve first -- an ordering that isn't
--    even stable once resolution is split across buckets. So a pass runs
--    inside beginBatch()/commitBatch(): reads answer from a snapshot
--    taken at the start, writes queue up, and everything lands at once
--    at the end.
--
-- GLOBAL context only.

local core = require('openmw.core')

local config = require('scripts.BalanceOfPower.core.config')
local events = require('scripts.BalanceOfPower.core.events')
local log = require('scripts.BalanceOfPower.core.log')
local registry = require('scripts.BalanceOfPower.core.registry')
local state = require('scripts.BalanceOfPower.core.state')

local M = {}

-- Frozen power values for the duration of a batch, or nil outside one.
local snapshot = nil
-- Queued deltas for the duration of a batch, or nil outside one.
local pending = nil

-- The propagation table: who moves when a faction moves.
--
--   propagation[A][B] = how B feels about A, in roughly [-3, 3]
--
-- Built once per registry generation. Reaction data is static for a
-- session, the record lookup involves a protected call into the game
-- data, and one of the two sources may need transposing -- none of which
-- is worth repeating on every propagation.
local propagation = nil
-- factionId -> how many other factions have an opinion about it, which
-- is the count the row-shaped table above can't answer directly.
local movedByCount = nil
local propagationGeneration = -1

local EMPTY = {}

--------------------------------------------------------------------------
-- Reactions
--------------------------------------------------------------------------

--- A faction's row as the game's own records give it, or nil.
local function recordReactions(factionId)
    -- Protected: indexing the record list with an id that has no faction
    -- record behind it shouldn't be able to take down the daily tick,
    -- and whether it errors or returns nil isn't something to bet the
    -- framework on.
    local ok, record = pcall(function()
        return core.factions.records[factionId]
    end)
    if ok and record and record.reactions and next(record.reactions) ~= nil then
        return record.reactions
    end
    return nil
end

--- Resolve every faction's reaction row into one propagation table.
--
-- Two sources, combined rather than one shadowing the other (doc 3.5).
-- The game's records supply the vanilla politics; an authored table
-- supplies whatever the records can't express. Authored values win where
-- both name the same pair, so a pack can correct a specific relationship
-- without discarding a faction's entire vanilla row -- and, more to the
-- point, can teach a vanilla faction how to feel about a faction that
-- has no ESM record at all. That direction is otherwise unreachable: the
-- Empire's record cannot name the East Empire Company, because the
-- Company does not exist as far as Morrowind.esm is concerned.
local function buildPropagation()
    propagation, movedByCount = {}, {}
    local ids = registry.sortedFactionIds()

    for _, id in ipairs(ids) do
        propagation[id] = {}
    end

    -- 1. Record data, normalized to "how everyone else feels about me".
    -- Rows are filtered to registered factions either way: a vanilla
    -- record names dozens of factions this simulation doesn't model.
    local inbound = config.RECORD_REACTIONS_ARE_INBOUND
    for _, id in ipairs(ids) do
        for otherId, value in pairs(recordReactions(id) or EMPTY) do
            if inbound then
                if registry.factions[otherId] then
                    propagation[id][otherId] = value
                end
            elseif propagation[otherId] then
                -- Each row is that faction's opinion *of* the others, so
                -- the table we want is its transpose.
                propagation[otherId][id] = value
            end
        end
    end

    -- 2. Authored tables on top, always read as inbound.
    for _, id in ipairs(ids) do
        for otherId, value in pairs(registry.factions[id].reactions or EMPTY) do
            if registry.factions[otherId] then
                propagation[id][otherId] = value
            elseif otherId ~= id then
                -- A reaction naming a faction nobody registered is dead
                -- weight, and is far more often a typo than an
                -- intentional forward reference.
                log.warn('faction "%s" has an authored reaction toward "%s", '
                    .. 'which is not a registered faction -- ignored',
                    id, tostring(otherId))
            end
        end
    end

    -- 3. Diagnostics, in both directions.
    local mute, deaf = {}, {}
    for _, id in ipairs(ids) do
        movedByCount[id] = 0
    end
    for _, id in ipairs(ids) do
        if next(propagation[id]) == nil then
            mute[#mute + 1] = id
        end
        for otherId in pairs(propagation[id]) do
            movedByCount[otherId] = movedByCount[otherId] + 1
        end
    end
    for _, id in ipairs(ids) do
        if movedByCount[id] == 0 then
            deaf[#deaf + 1] = id
        end
    end

    -- A faction nobody reacts to. This is the failure that hides: the
    -- faction looks fine, has a reaction table of its own, moves other
    -- people around -- and never moves itself, because no other row can
    -- name it. It is what happens to any faction with no ESM record
    -- until some pack authors the other side of the relationship.
    if #deaf > 0 then
        log.warn('no faction has an opinion about: %s. Their power will only ever '
            .. 'change through a direct award -- nothing in the simulation moves them. '
            .. 'Author the reverse side of the relationship on the factions that '
            .. 'should react to them.', table.concat(deaf, ', '))
    end

    -- The other direction, and the one that was already caught: a
    -- faction that moves nobody. A mistyped id, or a faction assumed to
    -- exist as an ESM record that doesn't.
    if #mute > 0 then
        log.warn('these factions have no reactions at all, from records or authored, '
            .. 'so they propagate power to nobody: %s', table.concat(mute, ', '))
    end

    propagationGeneration = registry.generation
end

local function ensurePropagation()
    if propagation == nil or propagationGeneration ~= registry.generation then
        buildPropagation()
    end
end

--- Who moves when this faction moves: a map of other faction id -> how
-- that other faction feels about this one, in roughly [-3, 3].
function M.reactionsFor(factionId)
    ensurePropagation()
    return propagation[factionId] or EMPTY
end

--- How `factionId` feels about `towardId`, in roughly [-3, 3]. 0 if it
-- has no opinion, or for a faction's regard for itself.
--
-- The inverse question to reactionsFor(), and worth a named function
-- rather than an index because the storage is inbound and this is an
-- outbound question: the value lives on *towardId's* row. Reading it the
-- wrong way round is silent -- most pairs are near-symmetric -- and this
-- framework has already shipped that bug once.
function M.regardOf(factionId, towardId)
    if factionId == towardId then
        return 0
    end
    ensurePropagation()
    local row = propagation[towardId]
    return row and row[factionId] or 0
end

--- How the reaction wiring actually resolved, per faction: `moves` is
-- how many factions it can push, `movedBy` how many can push it. A zero
-- in either column is a faction sitting outside the politics in one
-- direction, which is exactly the thing that's invisible in play.
-- @return list of { id, moves, movedBy }, in stable order
function M.reactionAudit()
    ensurePropagation()

    local rows = {}
    for _, id in ipairs(registry.sortedFactionIds()) do
        local moves = 0
        for _ in pairs(propagation[id]) do
            moves = moves + 1
        end
        rows[#rows + 1] = { id = id, moves = moves, movedBy = movedByCount[id] or 0 }
    end
    return rows
end

--- How far a faction moves in sympathy with a change to another faction,
-- as a fraction of that change. +1 reaction unit of maximum regard means
-- +INFLUENCE_STRENGTH of the delta; maximum hatred means the same
-- magnitude in the opposite direction.
local function allyCoefficient(reactionValue)
    if type(reactionValue) ~= 'number' then
        return 0
    end
    local clamped = math.max(-config.REACTION_CLAMP, math.min(config.REACTION_CLAMP, reactionValue))
    return (clamped / config.REACTION_CLAMP) * config.INFLUENCE_STRENGTH
end

--------------------------------------------------------------------------
-- Reading and writing
--------------------------------------------------------------------------

--- The committed power value, ignoring any open batch.
function M.getLive(factionId)
    return state.get().power[factionId] or 0
end

--- Power as the current pass should see it: the batch snapshot while a
-- batch is open, the live value otherwise.
function M.get(factionId)
    if snapshot then
        return snapshot[factionId] or 0
    end
    return M.getLive(factionId)
end

--- Write a faction's power directly. Bypasses any open batch on
-- purpose -- this is the setter for administrative changes (console
-- commands, migrations), not for simulation results, which go through
-- apply().
function M.set(factionId, value)
    local data = state.get()
    local old = data.power[factionId] or 0
    local new = math.max(config.MIN_POWER, value)
    data.power[factionId] = new

    local delta = new - old
    if math.abs(delta) >= config.POWER_EVENT_EPSILON then
        events.emit(events.POWER_CHANGED, {
            faction = factionId,
            delta = delta,
            newTotal = new,
        })
    end
    return new
end

--- Change a faction's power and propagate the change to everyone with
-- an opinion about it.
-- @param factionId string
-- @param delta number
-- @param opts table|nil { noPropagate = true } to move one faction alone
function M.apply(factionId, delta, opts)
    if type(delta) ~= 'number' or delta == 0 then
        return
    end
    opts = opts or {}

    -- Accumulate the whole change -- the faction itself plus every
    -- reaction -- before writing any of it, so a faction that appears
    -- twice (it can't today, but a future reciprocal rule could) lands
    -- one net change rather than two events.
    local changes = { [factionId] = delta }

    if not opts.noPropagate then
        -- Every registered faction reacts, land-holding or not. A guild
        -- that can't own a single cell still gains or loses standing
        -- when a Great House does, and that standing is the input other
        -- systems read. Whether a faction appears on the map is a
        -- separate question, answered by `territorial`.
        -- The propagation table is already filtered to registered
        -- factions, so the only case left to skip is a faction with an
        -- opinion about itself.
        for otherId, reactionValue in pairs(M.reactionsFor(factionId)) do
            if otherId ~= factionId then
                local coefficient = allyCoefficient(reactionValue)
                if coefficient ~= 0 then
                    changes[otherId] = (changes[otherId] or 0) + delta * coefficient
                end
            end
        end
    end

    if pending then
        for id, amount in pairs(changes) do
            pending[id] = (pending[id] or 0) + amount
        end
    else
        for id, amount in pairs(changes) do
            M.set(id, M.getLive(id) + amount)
        end
    end
end

--- Apply every faction's ambient daily growth.
--
-- Called once per resolved day, deliberately *outside* the batch: growth
-- is an input to the day rather than a result of it, the same category
-- as an award arriving from a quest, so the day's rolls should see the
-- new number rather than a number one day stale.
--
-- Growth does not propagate by default, and GROWTH_PROPAGATES carries
-- the long version of why. The short one: a daily drip through the
-- reaction table compounds until every faction that dislikes the growing
-- one is at MIN_POWER, and it empties the map without logging anything.
-- @return number of factions that grew
function M.applyDailyGrowth()
    local grown = 0
    for _, id in ipairs(registry.sortedFactionIds()) do
        local rate = registry.factions[id].growthPerDay or 0
        if rate ~= 0 then
            M.apply(id, rate, { noPropagate = not config.GROWTH_PROPAGATES })
            grown = grown + 1
        end
    end
    return grown
end

--------------------------------------------------------------------------
-- Batching
--------------------------------------------------------------------------

--- Freeze power for the duration of a resolution pass.
function M.beginBatch()
    if pending then
        log.warn('beginBatch() called with a batch already open -- discarding the open one')
    end
    snapshot = {}
    for id, value in pairs(state.get().power) do
        snapshot[id] = value
    end
    pending = {}
end

--- Apply everything queued during the batch, then unfreeze. Events fire
-- here, after the batch has closed, so a listener that reads power back
-- sees settled numbers.
function M.commitBatch()
    if not pending then
        return
    end
    local queued = pending
    pending, snapshot = nil, nil

    for id, amount in pairs(queued) do
        M.set(id, M.getLive(id) + amount)
    end
end

--- Throw away an open batch without applying it.
function M.abortBatch()
    pending, snapshot = nil, nil
end

function M.batchOpen()
    return pending ~= nil
end

--------------------------------------------------------------------------
-- Diagnostics
--------------------------------------------------------------------------

--- One-line standings for every registered faction, in stable order.
function M.summary()
    local parts = {}
    for _, id in ipairs(registry.sortedFactionIds()) do
        parts[#parts + 1] = string.format('%s=%.1f', id, M.getLive(id))
    end
    return table.concat(parts, '  ')
end

return M
