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

--- The direction that matters: a row is the faction's own opinions, so
-- "redoran moves when hlaalu moves" is written on redoran. An ally moves
-- with it, an enemy against it.
function M.propagatesAlongAuthoredReactions()
    threeFactions({
        redoran = { reactions = { hlaalu = 3 } },
        telvanni = { reactions = { hlaalu = -3 } },
    })

    power.apply('hlaalu', 10)

    local expected = 10 * config.INFLUENCE_STRENGTH
    expect.near(power.getLive('hlaalu'), 60, 1e-6, 'subject')
    expect.near(power.getLive('redoran'), 50 + expected, 1e-6, 'ally moves with it')
    expect.near(power.getLive('telvanni'), 50 - expected, 1e-6, 'rival moves against it')
end

--- Factions with no authored table fall back to the game's own faction
-- records, which are rows in the same direction. That fallback is the
-- seam that lets a Tamriel Rebuilt house or a Lua-only invader behave
-- like a vanilla faction without one.
function M.propagatesAlongRecordReactions()
    core.factions.records.redoran = { reactions = { hlaalu = 3 } }
    threeFactions()

    power.apply('hlaalu', 10)

    expect.near(power.getLive('redoran'), 50 + 10 * config.INFLUENCE_STRENGTH, 1e-6, 'ally')
    expect.equal(power.getLive('telvanni'), 50, 'faction with no opinion')
end

--- Both sources naming the same pair. Same row, same direction, so the
-- overlay is unambiguous: authored wins.
function M.authoredReactionsBeatRecords()
    core.factions.records.redoran = { reactions = { hlaalu = 3 } }
    threeFactions({ redoran = { reactions = { hlaalu = -3 } } })

    power.apply('hlaalu', 10)

    expect.near(power.getLive('redoran'), 50 - 10 * config.INFLUENCE_STRENGTH, 1e-6, 'authored wins')
end

--- Authored values merge into the record row instead of replacing it.
-- This is what lets a pack give a vanilla faction an opinion about a
-- faction that has no ESM record, without discarding the vanilla row to
-- do it -- the Empire's record cannot name the East Empire Company, and
-- without the merge there would be no way to say so that didn't cost the
-- Empire every real relationship it has.
function M.authoredReactionsMergeOverRecordsRatherThanReplacingThem()
    core.factions.records.redoran = { reactions = { hlaalu = 3, telvanni = 3 } }
    threeFactions({ redoran = { reactions = { telvanni = -3 } } })

    local step = 10 * config.INFLUENCE_STRENGTH

    power.apply('hlaalu', 10)
    expect.near(power.getLive('redoran'), 50 + step, 1e-6, 'the untouched record entry survived')

    local before = power.getLive('redoran')
    power.apply('telvanni', 10)
    expect.near(power.getLive('redoran'), before - step, 1e-6, 'and the authored one replaced its pair')
end

--- A reaction naming a faction nobody registered is dead weight and far
-- more often a typo. It must not reach the reaction table.
function M.ignoresReactionsTowardUnregisteredFactions()
    threeFactions({ hlaalu = { reactions = { redoran = 3, ['no such house'] = 3 } } })

    expect.equal(power.regardOf('hlaalu', 'redoran'), 3, 'the registered one survived')
    expect.equal(power.regardOf('hlaalu', 'no such house'), 0, 'the unregistered one was dropped')
    -- And it must not throw on the way past.
    power.apply('redoran', 10)
    expect.near(power.getLive('hlaalu'), 50 + 10 * config.INFLUENCE_STRENGTH, 1e-6, 'still works')
end

--------------------------------------------------------------------------
-- Which way round the data reads
--------------------------------------------------------------------------

--- One convention for both sources, asserted rather than left implied by
-- the behavioural tests: a row belongs to the faction holding the
-- opinions. Reading it the other way round is silent, because most pairs
-- are near-symmetric, and this framework has shipped that bug once.
function M.readsRecordRowsAsTheFactionsOwnOpinions()
    -- This says hlaalu feels +3 about redoran, which tells us nothing
    -- about how redoran responds when hlaalu moves...
    core.factions.records.hlaalu = { reactions = { redoran = 3 } }
    -- ...and this says telvanni feels -3 about hlaalu, which does.
    core.factions.records.telvanni = { reactions = { hlaalu = -3 } }
    threeFactions()

    power.apply('hlaalu', 10)

    expect.equal(power.getLive('redoran'), 50, 'hlaalu own opinion moves nobody')
    expect.near(power.getLive('telvanni'), 50 - 10 * config.INFLUENCE_STRENGTH, 1e-6,
        'the faction with an opinion about hlaalu is the one that moves')
end

--- The pair the convention was settled against, kept as a fixture. The
-- Twin Lamps run slaves out of Telvanni holdings and the vanilla records
-- carry that asymmetrically: -3 on the Twin Lamps' own row, and nothing
-- at all on House Telvanni's, who do not think about them.
--
-- Telvanni still gets a row here, naming somebody else. That is the
-- point of the fixture: the zero has to come from the *pair* being
-- absent, not from the faction having no data at all, and only a
-- genuinely asymmetric pair can tell those two apart.
function M.readsTheTwinLampsPairTheWayTheGameStoresIt()
    core.factions.records['twin lamps'] = { reactions = { telvanni = -3 } }
    core.factions.records.telvanni = { reactions = { hlaalu = -1 } }
    threeFactions()
    registry.registerLandmass({
        id = 'solstheim',
        factions = { { id = 'twin lamps', basePower = 50, territorial = false } },
    })
    state.fillDefaults(registry)

    expect.equal(power.regardOf('twin lamps', 'telvanni'), -3, 'the twin lamps hate the slavers')
    expect.equal(power.regardOf('telvanni', 'twin lamps'), 0, 'telvanni have no opinion back')
    expect.equal(power.regardOf('telvanni', 'hlaalu'), -1, 'though telvanni do have a row')

    -- And the propagation that follows, which is the half that shows in play.
    local step = 10 * config.INFLUENCE_STRENGTH
    power.apply('telvanni', 10)
    expect.near(power.getLive('twin lamps'), 50 - step, 1e-6,
        'a good day for the slavers is a bad one for the twin lamps')

    local telvanniBefore = power.getLive('telvanni')
    power.apply('twin lamps', 10)
    expect.equal(power.getLive('telvanni'), telvanniBefore, 'and it does not come back the other way')
end

--- And an authored row means the same thing a record row does. If the
-- two conventions ever diverged, a pack's data would change meaning
-- depending on whether the faction happened to have an ESM record.
function M.authoredRowsReadTheSameWayAsRecords()
    core.factions.records.redoran = { reactions = { hlaalu = 3 } }
    threeFactions({ telvanni = { reactions = { hlaalu = 3 } } })

    power.apply('hlaalu', 10)

    local step = 10 * config.INFLUENCE_STRENGTH
    expect.near(power.getLive('redoran'), 50 + step, 1e-6, 'from the record')
    expect.near(power.getLive('telvanni'), 50 + step, 1e-6, 'from the authored table')
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
        redoran = { reactions = { hlaalu = 3 } },
        telvanni = { reactions = { hlaalu = -3 } },
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

--- A reaction of zero is the absence of a relationship, not a quiet one,
-- and the audit has to agree. Vanilla reaction rows are mostly zeros, so
-- counting entries rather than opinions would report every faction as
-- fully wired in both directions and the diagnostic would go silent at
-- exactly the moment it is worth reading.
function M.auditIgnoresZeroReactions()
    threeFactions({
        redoran = { reactions = { hlaalu = 0 } },
        telvanni = { reactions = { hlaalu = -3 } },
    })

    local byId = {}
    for _, row in ipairs(power.reactionAudit()) do
        byId[row.id] = row
    end

    expect.equal(byId.redoran.movedBy, 0, 'an opinion of zero is not an opinion')
    expect.equal(byId.hlaalu.moves, 1, 'so hlaalu moves telvanni and nobody else')
end

--- The zero is still stored, though, and this is why: overriding a
-- record's value with nothing is the only way a pack can say "these two
-- have no quarrel" about a pair the game insists on.
function M.anAuthoredZeroCancelsARecordReaction()
    core.factions.records.redoran = { reactions = { hlaalu = 3 } }
    threeFactions({ redoran = { reactions = { hlaalu = 0 } } })

    power.apply('hlaalu', 10)

    expect.equal(power.getLive('redoran'), 50, 'the record value was cancelled, not merged')
end

function M.clampsExtremeReactionValues()
    threeFactions({ redoran = { reactions = { hlaalu = 99 } } })

    power.apply('hlaalu', 10)

    -- 99 must behave as the maximum, not as 33x the maximum.
    expect.near(power.getLive('redoran'), 50 + 10 * config.INFLUENCE_STRENGTH, 1e-6, 'clamped')
end

--- `territorial = false` keeps a faction off the map, not out of the
-- politics. A guild that can't own a cell still rises and falls with its
-- allies -- that standing is the whole reason to track it.
function M.propagatesToPowerOnlyFactions()
    threeFactions({
        redoran = { reactions = { hlaalu = 3 }, territorial = false },
    })

    power.apply('hlaalu', 10)

    expect.near(power.getLive('redoran'), 50 + 10 * config.INFLUENCE_STRENGTH, 1e-6,
        'power-only faction still reacts')
end

function M.noPropagateMovesOneFactionAlone()
    threeFactions({ redoran = { reactions = { hlaalu = 3 } } })

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
