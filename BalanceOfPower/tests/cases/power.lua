-- Faction power: propagation through reactions, and batching.

local expect = require('support.expect')

local core = require('openmw.core')
local world = require('openmw.world')

local config = require('scripts.BalanceOfPower.core.config')
local power = require('scripts.BalanceOfPower.core.power')
local registry = require('scripts.BalanceOfPower.core.registry')
local state = require('scripts.BalanceOfPower.core.state')

local M = {}

--------------------------------------------------------------------------
-- Fixtures
--------------------------------------------------------------------------

--- Three factions, no territory. Reaction data is supplied per-test.
local function threeFactions(overrides)
    local factions = {
        { id = 'hlaalu', basePower = 50 },
        { id = 'redoran', basePower = 50 },
        { id = 'telvanni', basePower = 50 },
    }
    for _, faction in ipairs(factions) do
        for key, value in pairs(overrides and overrides[faction.id] or {}) do
            faction[key] = value
        end
    end
    registry.registerLandmass({ id = 'vvardenfell', factions = factions })
    state.fillDefaults(registry)
end

--------------------------------------------------------------------------
-- Seeding and clamping
--------------------------------------------------------------------------

function M.seedsBasePowerFromDefinitions()
    threeFactions()
    expect.equal(power.getLive('hlaalu'), 50, 'seeded power')
end

function M.clampsAtMinimum()
    threeFactions()
    power.set('hlaalu', -100)
    expect.equal(power.getLive('hlaalu'), config.MIN_POWER, 'clamped power')
end

--- A negative score would invert the odds in powerRoll rather than just
-- making a faction weak, so the floor has to hold through apply() too.
function M.clampsThroughApply()
    threeFactions()
    power.apply('hlaalu', -1000, { noPropagate = true })
    expect.equal(power.getLive('hlaalu'), config.MIN_POWER, 'clamped through apply')
end

--------------------------------------------------------------------------
-- Propagation
--------------------------------------------------------------------------

--- The direction that matters: reactions[X] is how X feels about the
-- faction whose row it is. An ally moves with it, an enemy against it.
function M.propagatesAlongAuthoredReactions()
    threeFactions({
        hlaalu = { reactions = { redoran = 3, telvanni = -3 } },
    })

    power.apply('hlaalu', 10)

    local expected = 10 * config.INFLUENCE_STRENGTH
    expect.near(power.getLive('hlaalu'), 60, 1e-6, 'subject')
    expect.near(power.getLive('redoran'), 50 + expected, 1e-6, 'ally moves with it')
    expect.near(power.getLive('telvanni'), 50 - expected, 1e-6, 'rival moves against it')
end

--- Factions with no authored table fall back to the game's own faction
-- records. Same maths either way -- that fallback is the seam that lets
-- a Tamriel Rebuilt house or a Lua-only invader behave like a vanilla
-- faction without one.
--
-- Note where the record row sits: records read *outbound*, so "redoran
-- moves when hlaalu moves" is stored on redoran's record as its opinion
-- of hlaalu, not on hlaalu's.
function M.propagatesAlongRecordReactions()
    core.factions.records.redoran = { reactions = { hlaalu = 3 } }
    threeFactions()

    power.apply('hlaalu', 10)

    expect.near(power.getLive('redoran'), 50 + 10 * config.INFLUENCE_STRENGTH, 1e-6, 'ally')
    expect.equal(power.getLive('telvanni'), 50, 'faction with no opinion')
end

--- Both sources naming the same ordered pair, from the opposite ends
-- their conventions put it: the record on redoran (outbound), the
-- authored table on hlaalu (inbound). Authored wins.
function M.authoredReactionsBeatRecords()
    core.factions.records.redoran = { reactions = { hlaalu = 3 } }
    threeFactions({ hlaalu = { reactions = { redoran = -3 } } })

    power.apply('hlaalu', 10)

    expect.near(power.getLive('redoran'), 50 - 10 * config.INFLUENCE_STRENGTH, 1e-6, 'authored wins')
end

--- Authored values merge over the record instead of replacing it. This
-- is what lets a pack teach a vanilla faction about a faction that has
-- no ESM record, without discarding the vanilla row to do it -- the
-- Empire's record cannot name the East Empire Company, and before the
-- merge there was no way to say so that didn't cost the Empire every
-- real relationship it has.
function M.authoredReactionsMergeOverRecordsRatherThanReplacingThem()
    core.factions.records.redoran = { reactions = { hlaalu = 3 } }
    threeFactions({ hlaalu = { reactions = { telvanni = -3 } } })

    power.apply('hlaalu', 10)

    local step = 10 * config.INFLUENCE_STRENGTH
    expect.near(power.getLive('redoran'), 50 + step, 1e-6, 'the record row survived')
    expect.near(power.getLive('telvanni'), 50 - step, 1e-6, 'and the authored row was added')
end

--- A reaction naming a faction nobody registered is dead weight and far
-- more often a typo. It must not reach the propagation table.
function M.ignoresReactionsTowardUnregisteredFactions()
    threeFactions({ hlaalu = { reactions = { redoran = 3, ['no such house'] = 3 } } })

    local row = power.reactionsFor('hlaalu')
    expect.equal(row.redoran, 3, 'the registered one survived')
    expect.isNil(row['no such house'], 'the unregistered one was dropped')
    -- And it must not throw on the way past.
    power.apply('hlaalu', 10)
    expect.near(power.getLive('redoran'), 50 + 10 * config.INFLUENCE_STRENGTH, 1e-6, 'still works')
end

--------------------------------------------------------------------------
-- Which way round the record data reads
--------------------------------------------------------------------------

--- Settled in-game on 2026-08-13 against the Telvanni / Twin Lamps pair:
-- a record row is "how I feel about everyone else", so the propagation
-- table is its transpose. This shipped the other way round for three
-- phases, propagating every asymmetric vanilla pair backwards, which is
-- why the direction is asserted here rather than left implied by the
-- behavioural tests.
function M.readsRecordRowsAsOutboundByDefault()
    expect.falsy(config.RECORD_REACTIONS_ARE_INBOUND, 'settled: records read outbound')

    -- This says hlaalu feels +3 about redoran, which tells us nothing
    -- about how redoran responds to hlaalu...
    core.factions.records.hlaalu = { reactions = { redoran = 3 } }
    -- ...and this says telvanni feels -3 about hlaalu, which does.
    core.factions.records.telvanni = { reactions = { hlaalu = -3 } }
    threeFactions()

    power.apply('hlaalu', 10)

    expect.equal(power.getLive('redoran'), 50, 'hlaalu own opinion moves nobody')
    expect.near(power.getLive('telvanni'), 50 - 10 * config.INFLUENCE_STRENGTH, 1e-6,
        'the faction with an opinion about hlaalu is the one that moves')
end

--- The flag survives because ESM4 content is read through a different
-- code path and may not share ESM3's convention. Setting it uses each
-- row as-is instead of transposing.
function M.readsRecordRowsAsInboundWhenTheFlagIsSet()
    config.RECORD_REACTIONS_ARE_INBOUND = true

    core.factions.records.hlaalu = { reactions = { redoran = 3 } }
    threeFactions()

    power.apply('hlaalu', 10)
    expect.near(power.getLive('redoran'), 50 + 10 * config.INFLUENCE_STRENGTH, 1e-6,
        'the row now reads as redoran feeling +3 about hlaalu')
end

--- Authored tables mean one fixed thing regardless of the flag. The
-- record convention is the engine's and varies by format; ours is not,
-- and making both configurable would mean every pack's data changed
-- meaning when the flag moved.
function M.authoredTablesAreAlwaysInbound()
    config.RECORD_REACTIONS_ARE_INBOUND = true
    threeFactions({ hlaalu = { reactions = { redoran = 3 } } })

    power.apply('hlaalu', 10)
    expect.near(power.getLive('redoran'), 50 + 10 * config.INFLUENCE_STRENGTH, 1e-6,
        'authored rows are unaffected by the record flag')
end

--------------------------------------------------------------------------
-- The audit
--------------------------------------------------------------------------

--- The failure this exists to catch: a faction that moves others and is
-- moved by nobody. It looks entirely healthy from every other angle --
-- it has a reaction table, it propagates, it appears in the standings --
-- and its power can only ever change through a direct award.
function M.auditReportsFactionsNobodyReactsTo()
    threeFactions({
        hlaalu = { reactions = { redoran = 3, telvanni = -3 } },
    })

    local byId = {}
    for _, row in ipairs(power.reactionAudit()) do
        byId[row.id] = row
    end

    expect.equal(byId.hlaalu.moves, 2, 'hlaalu moves two factions')
    expect.equal(byId.hlaalu.movedBy, 0, 'and nothing moves hlaalu')
    expect.equal(byId.redoran.moves, 0, 'redoran moves nobody')
    expect.equal(byId.redoran.movedBy, 1, 'but hlaalu moves it')
end

function M.auditCoversEveryRegisteredFaction()
    threeFactions()
    expect.count(power.reactionAudit(), 3, 'one row per faction')
end

function M.clampsExtremeReactionValues()
    threeFactions({ hlaalu = { reactions = { redoran = 99 } } })

    power.apply('hlaalu', 10)

    -- 99 must behave as the maximum, not as 33x the maximum.
    expect.near(power.getLive('redoran'), 50 + 10 * config.INFLUENCE_STRENGTH, 1e-6, 'clamped')
end

--- `territorial = false` keeps a faction off the map, not out of the
-- politics. A guild that can't own a cell still rises and falls with its
-- allies -- that standing is the whole reason to track it.
function M.propagatesToPowerOnlyFactions()
    threeFactions({
        hlaalu = { reactions = { redoran = 3 } },
        redoran = { territorial = false },
    })

    power.apply('hlaalu', 10)

    expect.near(power.getLive('redoran'), 50 + 10 * config.INFLUENCE_STRENGTH, 1e-6,
        'power-only faction still reacts')
end

function M.noPropagateMovesOneFactionAlone()
    threeFactions({ hlaalu = { reactions = { redoran = 3 } } })

    power.apply('hlaalu', 10, { noPropagate = true })

    expect.equal(power.getLive('redoran'), 50, 'ally untouched')
end

--------------------------------------------------------------------------
-- Batching
--------------------------------------------------------------------------

--- The property the batch exists for. Reads inside a pass answer from a
-- snapshot, so a change applied early in the pass can't alter what a
-- later evaluation sees. Without it, results depend on which territory
-- happened to resolve first -- an order that isn't even stable once
-- resolution is split across buckets.
function M.readsAreFrozenDuringABatch()
    threeFactions()

    power.beginBatch()
    power.apply('hlaalu', 25, { noPropagate = true })
    expect.equal(power.get('hlaalu'), 50, 'read during batch sees the snapshot')
    expect.equal(power.getLive('hlaalu'), 50, 'nothing written yet')
    power.commitBatch()

    expect.equal(power.getLive('hlaalu'), 75, 'applied on commit')
end

function M.batchAccumulatesRepeatedChanges()
    threeFactions()

    power.beginBatch()
    power.apply('hlaalu', 10, { noPropagate = true })
    power.apply('hlaalu', 10, { noPropagate = true })
    power.apply('hlaalu', 10, { noPropagate = true })
    power.commitBatch()

    expect.equal(power.getLive('hlaalu'), 80, 'three changes land as one total')
end

function M.abortedBatchAppliesNothing()
    threeFactions()

    power.beginBatch()
    power.apply('hlaalu', 25, { noPropagate = true })
    power.abortBatch()

    expect.equal(power.getLive('hlaalu'), 50, 'discarded')
    expect.falsy(power.batchOpen(), 'batch closed')
end

--------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------

function M.emitsPowerChangedOnCommitOnly()
    threeFactions()
    core._test.reset()
    world._test.reset()

    power.beginBatch()
    power.apply('hlaalu', 25, { noPropagate = true })
    expect.count(core._test.eventsNamed('BoP_PowerChanged'), 0, 'events during batch')

    power.commitBatch()
    local emitted = core._test.eventsNamed('BoP_PowerChanged')
    expect.count(emitted, 1, 'events after commit')
    expect.equal(emitted[1].faction, 'hlaalu', 'event faction')
    expect.equal(emitted[1].newTotal, 75, 'event total')
end

--- Events reach player scripts too, not just global ones -- that's the
-- only route a UI mod has to react.
function M.broadcastsToPlayerScripts()
    threeFactions()
    world._test.reset()

    power.apply('hlaalu', 25, { noPropagate = true })

    expect.count(world._test.eventsNamed('BoP_PowerChanged'), 1, 'player-side events')
end

--- Propagation to a faction that barely cares produces a delta of
-- roughly nothing; firing an event for it is noise.
function M.suppressesNegligibleChanges()
    threeFactions()
    core._test.reset()

    power.set('hlaalu', 50 + config.POWER_EVENT_EPSILON / 10)

    expect.count(core._test.eventsNamed('BoP_PowerChanged'), 0, 'sub-epsilon change')
end

return M
