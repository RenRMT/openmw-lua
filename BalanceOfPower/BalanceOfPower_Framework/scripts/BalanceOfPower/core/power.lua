-- Faction power: the scalar every other system reads from and writes
-- to
--
-- Two things here are load-bearing beyond "store a number per faction".
--
-- 1. Reaction propagation. A faction's power change drags every other
--    faction along with it, scaled by how that *other* faction feels
--    about the one that moved. The numbers come from the game's faction
--    records and from nowhere else -- see buildReactions.
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

-- Every faction's reactions, read from the game's own faction records.
--
--   reactions[A][B] = how A feels about B, in roughly [-3, 3]
--
-- Two statements that sound contradictory and are both true. Separating
-- them is how this shipped backwards through three phases:
--
--   * STORAGE IS OUTBOUND. A row belongs to the faction holding the
--     opinions, exactly as the ESM stores it. Nothing here transposes.
--   * THE QUERY IS INBOUND. "Who moves when B moves" is B's *column* --
--     every other faction's row, indexed by B. See M.apply.
--
-- The engine's documentation calls the map inbound and is wrong for ESM3;
-- openmw-lua-api-notes.md carries the evidence.
--
-- Built once per registry generation; the data is static for a session.
local reactions = nil
-- How many factions each one can push, and how many can push it.
local movesCount = nil
local movedByCount = nil
local reactionsGeneration = -1

--------------------------------------------------------------------------
-- Reactions
--------------------------------------------------------------------------

-- Registered faction ids by their lowercased record id. One index serving
-- both ends: which record a faction reads, and which faction a name
-- inside that record resolves to.
local function indexByRecordId(ids)
    local index = {}
    for _, id in ipairs(ids) do
        local key = string.lower(registry.factions[id].recordId or id)
        -- Two factions on one record: the loser is wired in one direction
        -- only, which reads exactly like a faction nobody has heard of.
        if index[key] then
            log.warn('factions "%s" and "%s" both read faction record "%s" -- "%s" will be '
                .. 'named by nobody. Give one of them its own recordId.',
                index[key], id, key, id)
        else
            index[key] = id
        end
    end
    return index
end

local function buildReactions()
    reactions, movesCount, movedByCount = {}, {}, {}
    local ids = registry.sortedFactionIds()
    local byRecordId = indexByRecordId(ids)
    local rows = registry.recordRows()

    for _, id in ipairs(ids) do
        reactions[id] = {}
        movesCount[id] = 0
        movedByCount[id] = 0
    end

    -- Filtered to registered factions: a vanilla record names dozens this
    -- simulation doesn't model.
    local missing = {}
    for _, id in ipairs(ids) do
        local recordId = string.lower(registry.factions[id].recordId or id)
        local row = rows[recordId]
        if not row then
            missing[#missing + 1] = string.format('%s (record "%s")', id, recordId)
        end
        for otherRecordId, value in pairs(row or {}) do
            local otherId = byRecordId[otherRecordId]
            if otherId and otherId ~= id then
                reactions[id][otherId] = value
            end
        end
    end

    -- A reaction of zero wires nobody to anybody, and vanilla rows carry
    -- explicit zeros -- counting entries instead would report every
    -- faction as fully wired and this diagnostic would go quiet exactly
    -- when it matters.
    local mute, deaf = {}, {}
    for _, id in ipairs(ids) do
        for otherId, value in pairs(reactions[id]) do
            if value ~= 0 then
                movedByCount[id] = movedByCount[id] + 1
                movesCount[otherId] = movesCount[otherId] + 1
            end
        end
    end
    for _, id in ipairs(ids) do
        if movedByCount[id] == 0 then
            deaf[#deaf + 1] = id
        end
        if movesCount[id] == 0 then
            mute[#mute + 1] = id
        end
    end

    -- The whole symptom of a mistyped id: the faction registers, holds
    -- ground, and sits outside the politics forever.
    if #missing > 0 then
        log.warn('no faction record found for: %s. Check the ids against the content '
            .. 'files, or set recordId if they differ.', table.concat(missing, ', '))
    end

    -- A faction with nothing it reacts to. The failure that hides: it
    -- looks fine, moves other factions around -- and never moves itself.
    if #deaf > 0 then
        log.warn('these factions react to nothing, so nothing in the simulation moves '
            .. 'them: %s. Their power will only ever change through a direct award.',
            table.concat(deaf, ', '))
    end

    -- The other direction: a faction nobody has an opinion about, whose
    -- power therefore moves nobody.
    if #mute > 0 then
        log.warn('no faction has an opinion about: %s, so a change to their power '
            .. 'propagates to nobody', table.concat(mute, ', '))
    end

    reactionsGeneration = registry.generation
end

local function ensureReactions()
    if reactions == nil or reactionsGeneration ~= registry.generation then
        buildReactions()
    end
end

--- How `factionId` feels about `towardId`, in roughly [-3, 3], and so how
-- far it moves when towardId's power does. 0 if it has no opinion, or for
-- a faction's regard for itself.
function M.regardOf(factionId, towardId)
    if factionId == towardId then
        return 0
    end
    ensureReactions()
    local row = reactions[factionId]
    return row and row[towardId] or 0
end

--- How the reaction wiring actually resolved, per faction: `moves` is
-- how many factions it can push, `movedBy` how many can push it, counting
-- only opinions that aren't zero. A zero in either column is a faction
-- sitting outside the politics in one direction, which is exactly the
-- thing that's invisible in play.
-- @return list of { id, moves, movedBy }, in stable order
function M.reactionAudit()
    ensureReactions()

    local rows = {}
    for _, id in ipairs(registry.sortedFactionIds()) do
        rows[#rows + 1] = {
            id = id,
            moves = movesCount[id] or 0,
            movedBy = movedByCount[id] or 0,
        }
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
        -- Who reacts is the column, not the row: every faction whose own
        -- row has an opinion about the one that moved.
        --
        -- Every registered faction is considered, land-holding or not. A
        -- guild that can't own a single cell still gains or loses
        -- standing when a Great House does, and that standing is the
        -- input other systems read. Whether a faction appears on the map
        -- is a separate question, answered by `territorial`.
        ensureReactions()
        for otherId, row in pairs(reactions) do
            local coefficient = allyCoefficient(row[factionId])
            if coefficient ~= 0 then
                changes[otherId] = (changes[otherId] or 0) + delta * coefficient
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
