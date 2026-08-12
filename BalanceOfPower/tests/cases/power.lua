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
function M.propagatesAlongRecordReactions()
    core.factions.records.hlaalu = { reactions = { redoran = 3 } }
    threeFactions()

    power.apply('hlaalu', 10)

    expect.near(power.getLive('redoran'), 50 + 10 * config.INFLUENCE_STRENGTH, 1e-6, 'ally')
    expect.equal(power.getLive('telvanni'), 50, 'faction with no opinion')
end

function M.authoredReactionsBeatRecords()
    core.factions.records.hlaalu = { reactions = { redoran = 3 } }
    threeFactions({ hlaalu = { reactions = { redoran = -3 } } })

    power.apply('hlaalu', 10)

    expect.near(power.getLive('redoran'), 50 - 10 * config.INFLUENCE_STRENGTH, 1e-6, 'authored wins')
end

function M.clampsExtremeReactionValues()
    threeFactions({ hlaalu = { reactions = { redoran = 99 } } })

    power.apply('hlaalu', 10)

    -- 99 must behave as the maximum, not as 33x the maximum.
    expect.near(power.getLive('redoran'), 50 + 10 * config.INFLUENCE_STRENGTH, 1e-6, 'clamped')
end

function M.skipsNonTerritorialFactions()
    threeFactions({
        hlaalu = { reactions = { redoran = 3 } },
        redoran = { territorial = false },
    })

    power.apply('hlaalu', 10)

    expect.equal(power.getLive('redoran'), 50, 'flavor-only faction is not dragged along')
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
