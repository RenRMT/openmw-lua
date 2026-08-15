-- Strain: the crossing events, the state it records, and the two
-- feedback knobs that ship at zero.

local expect = require('support.expect')

local core = require('openmw.core')

local config = require('scripts.BalanceOfPower.core.config')
local patrol = require('scripts.BalanceOfPower.core.patrol')
local power = require('scripts.BalanceOfPower.core.power')
local registry = require('scripts.BalanceOfPower.core.registry')
local resolve = require('scripts.BalanceOfPower.core.resolve')
local state = require('scripts.BalanceOfPower.core.state')

local M = {}

--------------------------------------------------------------------------
-- Fixtures
--------------------------------------------------------------------------

-- One faction over a six-cell city, so its strain is set by whatever
-- power it is given: 6 cells on 5 power is 120, well over the default
-- threshold. The garrison floor holds the cells whatever the power, so
-- nothing is released underneath the test.
local function sixCellsOnWhateverPower()
    registry.registerLandmass({
        id = 'testland',
        factions = { { id = 'alpha' } },
        territories = {
            { id = 'city', tier = 'large city', region = 'here', faction = 'alpha',
              cells = { '#0,0', '#1,0', '#2,0', '#3,0', '#4,0', '#5,0' } },
        },
    })
    state.fillDefaults(registry)
    resolve.assignInitialControl()
end

-- Two equal factions projecting 12.5 each onto one frontier cell that
-- beta holds. An even contest is a coin toss, so a rigged 0.6 fails --
-- and succeeds the moment the defender is penalised.
local function evenContest()
    registry.registerLandmass({
        id = 'testland',
        factions = { { id = 'alpha' }, { id = 'beta' } },
        territories = {
            { id = 'alpha_seat', tier = 'large city', faction = 'alpha',
              cells = { '#0,0' }, centroid = { x = 0, y = 0 }, influenceRange = 10000 },
            { id = 'beta_seat', tier = 'large city', faction = 'beta',
              cells = { '#4,0' }, centroid = { x = 40000, y = 0 }, influenceRange = 10000 },
        },
        frontier = {
            { id = 'middle', centroid = { x = 20000, y = 0 } },
        },
    })
    state.fillDefaults(registry)
    power.set('alpha', 50)
    power.set('beta', 50)
    state.setOwner('beta_seat_4_0', 'beta')
    state.setOwner('middle', 'beta')
    -- Beta holds two cells on 50 power, so a threshold of 4 strains it
    -- and nothing else about the fixture has to move.
    config.STRAIN_EVENT_THRESHOLD = 4
    resolve.setRandom(function() return 0.6 end)
end

--------------------------------------------------------------------------
-- Crossings
--------------------------------------------------------------------------

--- Fires on the crossing, not every day the condition holds -- the same
-- contract as being surrounded.
function M.crossingTheThresholdIsAnnouncedOnce()
    sixCellsOnWhateverPower()
    power.set('alpha', 5)
    core._test.reset()

    resolve.run(1)
    expect.equal(state.get().strainedSince.alpha, 1, 'records the day it started')
    expect.count(core._test.eventsNamed('BoP_FactionStrained'), 1, 'announced once')

    resolve.run(2)
    expect.count(core._test.eventsNamed('BoP_FactionStrained'), 1, 'not repeated daily')
    expect.equal(state.get().strainedSince.alpha, 1, 'and the day does not drift')
end

--- Growing into the ground is the way out, and it is news too.
function M.fallingBackUnderTheThresholdIsAnnounced()
    sixCellsOnWhateverPower()
    power.set('alpha', 5)
    resolve.run(1)
    core._test.reset()

    power.set('alpha', 100)
    resolve.run(2)

    expect.isNil(state.get().strainedSince.alpha, 'cleared')
    expect.count(core._test.eventsNamed('BoP_FactionRelieved'), 1, 'and announced')
end

function M.aFactionWithinItsMeansIsNeverAnnounced()
    sixCellsOnWhateverPower()
    power.set('alpha', 100)
    core._test.reset()

    resolve.run(1)

    expect.isNil(state.get().strainedSince.alpha, 'not strained')
    expect.count(core._test.eventsNamed('BoP_FactionStrained'), 0, 'and nothing was said')
end

--------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------

function M.theRecordedDaySurvivesASaveAndLoad()
    sixCellsOnWhateverPower()
    power.set('alpha', 5)
    resolve.run(7)

    state.deserialize(state.serialize())

    expect.equal(state.get().strainedSince.alpha, 7, 'round-tripped')
end

--- The reason STATE_VERSION does not move for a new section: a save
-- written before it existed has to load without migration.
function M.aSaveFromBeforeTheSectionLoadsClean()
    state.deserialize({ version = 1, power = { alpha = 50 }, ownership = {} })

    expect.truthy(type(state.get().strainedSince) == 'table', 'the section exists')
    expect.isNil(next(state.get().strainedSince), 'and is empty')
    expect.equal(state.get().power.alpha, 50, 'without disturbing what was saved')
end

--------------------------------------------------------------------------
-- Defence penalty
--------------------------------------------------------------------------

function M.theDefencePenaltyIsOffByDefault()
    evenContest()
    resolve.run(1)

    expect.equal(state.getOwner('middle'), 'beta', 'an even contest stays even')
end

function M.aStrainedFactionDefendsWorseWhenTurnedOn()
    evenContest()
    config.STRAIN_DEFENCE_PENALTY = 0.5

    resolve.run(1)

    expect.equal(state.getOwner('middle'), 'alpha', 'the strained defender lost a roll it had held')
end

--- The penalty is not a global difficulty setting: a faction within its
-- means defends exactly as it did.
function M.thePenaltyTouchesNobodyElse()
    evenContest()
    config.STRAIN_EVENT_THRESHOLD = 1000
    config.STRAIN_DEFENCE_PENALTY = 0.5

    resolve.run(1)

    expect.equal(state.getOwner('middle'), 'beta', 'held')
end

--------------------------------------------------------------------------
-- Patrol penalty
--------------------------------------------------------------------------

function M.thePatrolPenaltyIsOffByDefault()
    sixCellsOnWhateverPower()
    power.set('alpha', 5)

    expect.equal(patrol.sizeFor(120, 'alpha'), 4, 'the full group')
end

function M.aStrainedFactionFieldsFewerWhenTurnedOn()
    sixCellsOnWhateverPower()
    power.set('alpha', 5)
    config.STRAIN_PATROL_PENALTY = 0.5

    expect.equal(patrol.sizeFor(120, 'alpha'), 2, 'halved')
    expect.equal(patrol.sizeFor(0, 'alpha'), 1, 'never below one on the road')
end

function M.aFactionWithinItsMeansFieldsItsFullGroup()
    sixCellsOnWhateverPower()
    power.set('alpha', 500)
    config.STRAIN_PATROL_PENALTY = 0.5

    expect.equal(patrol.sizeFor(120, 'alpha'), 4, 'unpenalised')
end

return M
