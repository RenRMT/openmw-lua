-- Faction power: the scalar every other system reads from and writes
-- to (design doc 3.5).
--
-- Two things here are load-bearing beyond "store a number per faction".
--
-- 1. Reaction propagation. A faction's power change drags every other
--    faction along with it, scaled by how that *other* faction feels
--    about the one that moved. Reading the direction the right way round
--    is what makes the Sixth House story work for free: everyone hates
--    them, so their growth is everyone else's loss, with no special
--    casing anywhere in the invasion code.
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

-- Resolved reaction tables, keyed by faction id. Reaction data is static
-- for a session, and the lookup involves a protected call into the game
-- records, so it isn't worth repeating on every propagation.
local reactionCache = {}
local reactionCacheGeneration = -1

--------------------------------------------------------------------------
-- Reactions
--------------------------------------------------------------------------

--- The reaction table for a faction: a map of other faction id -> how
-- that other faction feels about this one, in roughly [-3, 3].
--
-- The indirection is the point (doc 3.5). Vanilla factions read straight
-- from the game's own records; a faction with no ESM record behind it
-- -- a future House Dres, a Skyrim faction, an invader that exists only
-- in Lua -- supplies an authored table in its definition instead. The
-- propagation math downstream can't tell the difference.
function M.reactionsFor(factionId)
    if reactionCacheGeneration ~= registry.generation then
        reactionCache = {}
        reactionCacheGeneration = registry.generation
    end

    local cached = reactionCache[factionId]
    if cached then
        return cached
    end

    local faction = registry.factions[factionId]
    local reactions = faction and faction.reactions

    if not reactions then
        -- Protected: indexing the record list with an id that has no
        -- faction record behind it shouldn't be able to take down the
        -- daily tick, and whether it errors or returns nil isn't
        -- something to bet the framework on.
        local ok, record = pcall(function()
            return core.factions.records[factionId]
        end)
        if ok and record then
            reactions = record.reactions
        end
    end

    if not reactions or next(reactions) == nil then
        -- Neither an authored table nor a faction record with reactions.
        -- The faction will simply never move anyone else's power, which
        -- is a silent and very easy failure to miss -- a mistyped id, or
        -- a faction that doesn't exist as an ESM record and was assumed
        -- to. Say so once, then carry on with an empty table.
        log.warn('faction "%s" has no reactions: not found in core.factions.records, '
            .. 'and no `reactions` table was authored for it. It will not propagate '
            .. 'power to anyone.', tostring(factionId))
        reactions = {}
    end

    reactionCache[factionId] = reactions
    return reactions
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
        for otherId, reactionValue in pairs(M.reactionsFor(factionId)) do
            local other = registry.factions[otherId]
            if otherId ~= factionId and other then
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
