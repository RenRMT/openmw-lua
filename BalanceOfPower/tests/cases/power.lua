-- Faction power: propagation through reactions, and batching.

local expect = require('support.expect')

local core = require('openmw.core')
local world = require('openmw.world')

local config = require('scripts.BalanceOfPower.core.config')
local holdings = require('scripts.BalanceOfPower.core.holdings')
local power = require('scripts.BalanceOfPower.core.power')
local registry = require('scripts.BalanceOfPower.core.registry')
local state = require('scripts.BalanceOfPower.core.state')

local M = {}

--------------------------------------------------------------------------
-- Fixtures
--------------------------------------------------------------------------

--- Three factions, no territory. Reactions come from the game's records
-- and only from there, so a test that wants any installs them first with
-- `records{ ... }` before calling this.
--
-- Power is set flat afterwards. None of them holds ground, so the
-- derivation would give all three the power-only floor -- correct, and
-- a needlessly awkward number for tests about propagation.
local function threeFactions(overrides)
    local factions = {
        { id = 'hlaalu' },
        { id = 'redoran' },
        { id = 'telvanni' },
    }
    for _, faction in ipairs(factions) do
        for key, value in pairs(overrides and overrides[faction.id] or {}) do
            faction[key] = value
        end
    end
    registry.registerLandmass({ id = 'vvardenfell', factions = factions })
    state.fillDefaults(registry)
    holdings.seedPower()
    for _, faction in ipairs(factions) do
        power.set(faction.id, 50)
    end
end

local function records(rows)
    core._test.setFactionRecords(rows)
end

--------------------------------------------------------------------------
-- Seeding and clamping
--------------------------------------------------------------------------

--- A faction with no seats gets the power-only floor, whatever else is
-- in the world -- a score of zero never touches the mean it is measured
-- against.
function M.seedsThePowerOnlyFloorForFactionsWithNoSeats()
    registry.registerLandmass({ id = 'vvardenfell', factions = { { id = 'hlaalu' } } })
    state.fillDefaults(registry)
    holdings.seedPower()

    expect.near(power.getLive('hlaalu'),
        config.DEFAULT_BASE_POWER * config.POWER_FLOOR_SHARE, 1e-6, 'floor share')
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
--
-- None of the three holds ground, so this is the power-only case too:
-- standing rises and falls for a faction that cannot own a cell, which
-- is the whole reason to track one.
function M.propagatesAlongRecordReactions()
    records({
        redoran = { hlaalu = 3 },
        telvanni = { hlaalu = -3 },
    })
    threeFactions()
    expect.falsy(registry.factions.redoran.territorial, 'no seats, so power-only')

    power.apply('hlaalu', 10)

    local expected = 10 * config.INFLUENCE_STRENGTH
    expect.near(power.getLive('hlaalu'), 60, 1e-6, 'subject')
    expect.near(power.getLive('redoran'), 50 + expected, 1e-6, 'ally moves with it')
    expect.near(power.getLive('telvanni'), 50 - expected, 1e-6, 'rival moves against it')
end

--- Reactions are the game's to define, not a pack's. A table here would
-- be a second copy outranking the records, so the registry refuses it --
-- and refuses loudly, because a pack whose politics quietly did nothing
-- is the exact failure the rule exists to prevent.
function M.rejectsAuthoredReactions()
    expect.raises(function()
        threeFactions({ redoran = { reactions = { hlaalu = 3 } } })
    end, 'faction records', 'an authored reaction table')
end

--- The ESM stores record ids as they were authored -- "Sixth House",
-- "Camonna Tong" -- while a pack registers whatever ids it likes, usually
-- lowercase. Record lookup is case-insensitive in the engine, but a
-- reaction row is a plain table whose keys arrive as-is, so both ends get
-- normalized. Getting this wrong reads as an empty row and nothing else.
function M.matchesReactionKeysRegardlessOfCase()
    records({ Redoran = { HLAALU = 3 } })
    threeFactions()

    expect.equal(power.regardOf('redoran', 'hlaalu'), 3, 'both ends normalized')

    power.apply('hlaalu', 10)
    expect.near(power.getLive('redoran'), 50 + 10 * config.INFLUENCE_STRENGTH, 1e-6, 'and it propagates')
end

--- Every vanilla record carries a reaction toward itself, usually 3. It
-- is not an opinion about anybody and must not act as one -- and it has
-- to be dropped after case normalization, or a mismatch smuggles it
-- through as a relationship with a faction that happens to differ only in
-- case.
function M.stripsTheRecordsSelfReaction()
    records({ Hlaalu = { Hlaalu = 3, Redoran = -1 } })
    threeFactions()

    expect.equal(power.regardOf('hlaalu', 'hlaalu'), 0, 'no regard for itself')

    power.apply('hlaalu', 10)
    expect.near(power.getLive('hlaalu'), 60, 1e-6, 'a faction does not amplify its own change')
end

--- `recordId` is the whole of a pack's contribution to the politics: the
-- faction whose modelled identity doesn't line up with a single record,
-- like an Empire that reads the Legion's row. It has to work in both
-- directions -- the aliased faction reads its record, and everyone else's
-- rows naming that record resolve back to it.
function M.resolvesReactionsThroughRecordId()
    records({
        ['Imperial Legion'] = { hlaalu = 3 },
        redoran = { ['Imperial Legion'] = -3 },
    })
    registry.registerLandmass({
        id = 'vvardenfell',
        factions = {
            { id = 'hlaalu' },
            { id = 'redoran' },
            { id = 'empire', recordId = 'Imperial Legion' },
        },
    })
    state.fillDefaults(registry)
    holdings.seedPower()
    for _, id in ipairs({ 'hlaalu', 'redoran', 'empire' }) do
        power.set(id, 50)
    end

    expect.equal(power.regardOf('empire', 'hlaalu'), 3, 'reads its record row')
    expect.equal(power.regardOf('redoran', 'empire'), -3,
        'and is named by everyone else through the same id')

    local step = 10 * config.INFLUENCE_STRENGTH
    power.apply('empire', 10)
    expect.near(power.getLive('redoran'), 50 - step, 1e-6, 'so propagation reaches it')
end

--- A record row names dozens of factions this simulation doesn't model.
-- They must not reach the reaction table, and must not throw on the way
-- past.
function M.ignoresReactionsTowardUnregisteredFactions()
    records({ hlaalu = { redoran = 3, ['no such house'] = 3 } })
    threeFactions()

    expect.equal(power.regardOf('hlaalu', 'redoran'), 3, 'the registered one survived')
    expect.equal(power.regardOf('hlaalu', 'no such house'), 0, 'the unregistered one was dropped')
    power.apply('redoran', 10)
    expect.near(power.getLive('hlaalu'), 50 + 10 * config.INFLUENCE_STRENGTH, 1e-6, 'still works')
end

--- A registered faction with no record behind it. Almost always a
-- mistyped id, and the framework's only symptom for it is a warning plus
-- a faction that sits outside the politics forever -- so at minimum it
-- must not take the tick down.
function M.survivesAFactionWithNoRecord()
    records({ redoran = { hlaalu = 3 } })
    threeFactions()

    expect.equal(power.regardOf('telvanni', 'hlaalu'), 0, 'no record, no opinions')
    power.apply('hlaalu', 10)
    expect.near(power.getLive('redoran'), 50 + 10 * config.INFLUENCE_STRENGTH, 1e-6,
        'and everyone else is unaffected')
end

--------------------------------------------------------------------------
-- Which way round the data reads
--------------------------------------------------------------------------

--- The convention, against the vanilla pair it was settled on: a row
-- belongs to the faction holding the opinions. Reading it the other way
-- round is silent, because most pairs are near-symmetric, and this
-- framework shipped that bug once -- the engine's own documentation
-- describes the map as inbound and is wrong for ESM3.
--
-- The Twin Lamps run slaves out of Telvanni holdings, and the records
-- carry that asymmetrically: -3 on the Twin Lamps' own row, and nothing
-- at all on House Telvanni's, who do not think about them.
--
-- Telvanni still gets a row here, naming somebody else. That is the
-- point of the fixture: the zero has to come from the *pair* being
-- absent, not from the faction having no data at all, and only a
-- genuinely asymmetric pair can tell those two apart. It is also why
-- this covers "a faction with no opinion about the mover does not move".
function M.readsTheTwinLampsPairTheWayTheGameStoresIt()
    records({
        ['Twin Lamps'] = { Telvanni = -3 },
        Telvanni = { Hlaalu = -1 },
    })
    threeFactions()
    registry.registerLandmass({
        id = 'solstheim',
        factions = { { id = 'twin lamps' } },
    })
    state.fillDefaults(registry)
    holdings.seedPower()
    power.set('twin lamps', 50)

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

--------------------------------------------------------------------------
-- The audit
--------------------------------------------------------------------------

--- The failure this exists to catch: a faction that moves others and is
-- moved by nobody. It looks entirely healthy from every other angle --
-- it has a reaction table, it propagates, it appears in the standings --
-- and its power can only ever change through a direct award.
function M.auditReportsFactionsNobodyReactsTo()
    records({
        redoran = { hlaalu = 3 },
        telvanni = { hlaalu = -3 },
    })
    threeFactions()

    local byId = {}
    for _, row in ipairs(power.reactionAudit()) do
        byId[row.id] = row
    end

    expect.equal(byId.hlaalu.moves, 2, 'hlaalu moves two factions')
    expect.equal(byId.hlaalu.movedBy, 0, 'and nothing moves hlaalu')
    expect.equal(byId.redoran.moves, 0, 'redoran moves nobody')
    expect.equal(byId.redoran.movedBy, 1, 'but hlaalu moves it')
end

--- A reaction of zero is the absence of a relationship, not a quiet one,
-- and the audit has to agree. Vanilla rows carry explicit zeros, so
-- counting entries rather than opinions would report every faction as
-- fully wired in both directions and the diagnostic would go silent at
-- exactly the moment it is worth reading.
function M.auditIgnoresZeroReactions()
    records({
        redoran = { hlaalu = 0 },
        telvanni = { hlaalu = -3 },
    })
    threeFactions()

    local byId = {}
    for _, row in ipairs(power.reactionAudit()) do
        byId[row.id] = row
    end

    expect.equal(byId.redoran.movedBy, 0, 'an opinion of zero is not an opinion')
    expect.equal(byId.hlaalu.moves, 1, 'so hlaalu moves telvanni and nobody else')
end

--- Vanilla really does carry values past the nominal range -- the Temple
-- regards the Nerevarine at -8 -- so the clamp has to hold at use rather
-- than the data being assumed sane.
function M.clampsExtremeReactionValues()
    records({ redoran = { hlaalu = 99 } })
    threeFactions()

    power.apply('hlaalu', 10)

    -- 99 must behave as the maximum, not as 33x the maximum.
    expect.near(power.getLive('redoran'), 50 + 10 * config.INFLUENCE_STRENGTH, 1e-6, 'clamped')
end

function M.noPropagateMovesOneFactionAlone()
    records({ redoran = { hlaalu = 3 } })
    threeFactions()

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
