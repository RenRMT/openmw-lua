-- Territory resolution: projection maths, initial control, the garrison
-- floor, and frontier rolls.

local expect = require('support.expect')

local core = require('openmw.core')

local config = require('scripts.BalanceOfPower.core.config')
local power = require('scripts.BalanceOfPower.core.power')
local registry = require('scripts.BalanceOfPower.core.registry')
local resolve = require('scripts.BalanceOfPower.core.resolve')
local state = require('scripts.BalanceOfPower.core.state')

local M = {}

--------------------------------------------------------------------------
-- Fixtures
--------------------------------------------------------------------------

local RANGE = 40000

-- Two equal factions facing each other across 40000 units, with frontier
-- cells strung along the line between them. Projection at each cell:
--
--   x        0      10000    20000    30000    40000
--   alpha   50.0     37.5     25.0     12.5      0.0
--   beta     0.0     12.5     25.0     37.5     50.0
--
-- so alpha holds the near cells, beta the far ones, and 20000 is an
-- exact tie that the sorted-id rule has to break the same way each time.
local function twoFactionLine(overrides)
    overrides = overrides or {}
    registry.registerLandmass({
        id = 'testland',
        factions = {
            {
                id = 'alpha',
                basePower = overrides.alphaPower or 50,
                powerCenters = {
                    { id = 'alpha_seat', tier = 'capital',
                      coords = { x = 0, y = 0 }, influenceRange = RANGE },
                },
            },
            {
                id = 'beta',
                basePower = overrides.betaPower or 50,
                powerCenters = {
                    { id = 'beta_seat', tier = 'capital',
                      coords = { x = RANGE, y = 0 }, influenceRange = RANGE },
                },
            },
        },
        frontier = {
            { id = 'cell_0', centroid = { x = 0, y = 0 } },
            { id = 'cell_10k', centroid = { x = 10000, y = 0 } },
            { id = 'cell_20k', centroid = { x = 20000, y = 0 } },
            { id = 'cell_30k', centroid = { x = 30000, y = 0 } },
            { id = 'cell_40k', centroid = { x = RANGE, y = 0 } },
        },
    })
    state.fillDefaults(registry)
end

local function always(value)
    return function() return value end
end

--------------------------------------------------------------------------
-- Projection maths
--------------------------------------------------------------------------

function M.proximityDecaysLinearlyToZero()
    expect.equal(resolve.proximityFactor(0, 1000), 1, 'at the seat')
    expect.equal(resolve.proximityFactor(500, 1000), 0.5, 'halfway')
    expect.equal(resolve.proximityFactor(1000, 1000), 0, 'at the edge')
    expect.equal(resolve.proximityFactor(5000, 1000), 0, 'beyond the edge')
end

function M.effectivePowerFallsOffWithDistance()
    twoFactionLine()
    expect.near(resolve.effectivePower('alpha', registry.territories.cell_0), 50, 1e-6, 'at seat')
    expect.near(resolve.effectivePower('alpha', registry.territories.cell_10k), 37.5, 1e-6, 'near')
    expect.near(resolve.effectivePower('alpha', registry.territories.cell_30k), 12.5, 1e-6, 'far')
    expect.equal(resolve.effectivePower('alpha', registry.territories.cell_40k), 0, 'out of range')
end

--- Doc 3.2: a faction's strength somewhere is its strongest single
-- foothold, never the sum. Summing would let anyone out-project a rival
-- by scattering cheap outposts, which is the opposite of the intent.
function M.effectivePowerTakesStrongestNotSum()
    registry.registerLandmass({
        id = 'testland',
        factions = {
            {
                id = 'alpha',
                basePower = 50,
                powerCenters = {
                    { id = 'near', tier = 'capital',
                      coords = { x = 0, y = 0 }, influenceRange = RANGE },
                    { id = 'also_near', tier = 'capital',
                      coords = { x = 1000, y = 0 }, influenceRange = RANGE },
                    { id = 'third', tier = 'capital',
                      coords = { x = 2000, y = 0 }, influenceRange = RANGE },
                },
            },
        },
        frontier = { { id = 'cell', centroid = { x = 0, y = 0 } } },
    })
    state.fillDefaults(registry)

    -- Sum would be 50 + 48.75 + 47.5 = 146.25.
    expect.near(resolve.effectivePower('alpha', registry.territories.cell), 50, 1e-6, 'max only')
end

function M.effectivePowerScalesWithFactionPower()
    twoFactionLine()
    power.set('alpha', 100)
    expect.near(resolve.effectivePower('alpha', registry.territories.cell_10k), 75, 1e-6, 'doubled')
end

function M.nonTerritorialFactionsProjectNothing()
    registry.registerLandmass({
        id = 'testland',
        factions = {
            {
                id = 'blades',
                basePower = 100,
                territorial = false,
                powerCenters = {
                    { id = 'seat', tier = 'capital',
                      coords = { x = 0, y = 0 }, influenceRange = RANGE },
                },
            },
        },
        frontier = { { id = 'cell', centroid = { x = 0, y = 0 } } },
    })
    state.fillDefaults(registry)

    expect.equal(resolve.effectivePower('blades', registry.territories.cell), 0, 'flavor faction')
end

--------------------------------------------------------------------------
-- Initial control
--------------------------------------------------------------------------

--- The property that makes a procedurally generated frontier grid
-- viable: a pack declares where the seats of power are, and the map
-- falls out of that with no hand-authored ownership at all.
function M.assignsInitialControlByProjection()
    twoFactionLine()
    resolve.assignInitialControl()

    expect.equal(state.getOwner('cell_0'), 'alpha', 'alpha heartland')
    expect.equal(state.getOwner('cell_10k'), 'alpha', 'alpha side')
    expect.equal(state.getOwner('cell_30k'), 'beta', 'beta side')
    expect.equal(state.getOwner('cell_40k'), 'beta', 'beta heartland')
end

function M.breaksProjectionTiesDeterministically()
    twoFactionLine()
    resolve.assignInitialControl()
    -- Exactly 25.0 each at the midpoint; sorted-id order decides.
    expect.equal(state.getOwner('cell_20k'), 'alpha', 'tie broken by sorted id')
end

function M.leavesGroundNobodyReachesUnclaimed()
    registry.registerLandmass({
        id = 'testland',
        factions = {
            {
                id = 'alpha',
                basePower = 50,
                powerCenters = {
                    { id = 'seat', tier = 'capital',
                      coords = { x = 0, y = 0 }, influenceRange = RANGE },
                },
            },
        },
        frontier = {
            { id = 'near', centroid = { x = 0, y = 0 } },
            { id = 'distant', centroid = { x = 1000000, y = 0 } },
        },
    })
    state.fillDefaults(registry)
    resolve.assignInitialControl()

    expect.equal(state.getOwner('near'), 'alpha', 'reachable')
    expect.isNil(state.getOwner('distant'), 'unreachable stays unclaimed')
end

--- Projection below the floor isn't enough to plant a flag, which is
-- what keeps the edges of the map empty rather than weakly owned.
function M.respectsMinimumClaimPower()
    twoFactionLine()
    -- At 10000 alpha projects 0.75 * power; drop power so that lands
    -- just under the floor.
    power.set('alpha', (config.MIN_CLAIM_POWER / 0.75) * 0.9)
    power.set('beta', 0)
    resolve.assignInitialControl()

    expect.isNil(state.getOwner('cell_10k'), 'below the claim floor')
end

--- An authored owner is an override, not a suggestion. Without this an
-- invasion homeland would be handed to whoever happened to project onto
-- it, which is exactly backwards.
function M.authoredOwnerSurvivesInitialAssignment()
    registry.registerLandmass({
        id = 'testland',
        factions = {
            {
                id = 'alpha',
                basePower = 500,
                powerCenters = {
                    { id = 'seat', tier = 'capital',
                      coords = { x = 0, y = 0 }, influenceRange = RANGE },
                },
            },
            { id = 'sixth house', basePower = 10 },
        },
        frontier = {
            { id = 'homeland', centroid = { x = 0, y = 0 }, defaultOwner = 'sixth house' },
        },
    })
    state.fillDefaults(registry)
    resolve.assignInitialControl()

    expect.equal(state.getOwner('homeland'), 'sixth house', 'authored owner held')
end

--------------------------------------------------------------------------
-- Frontier resolution
--------------------------------------------------------------------------

--- The central consequence of "the attacker is whoever projects most":
-- while the incumbent is also the strongest, there is nothing to roll.
-- Rolls decide how long a takeover takes, not who wins it.
function M.noRollWhileTheOwnerIsStrongest()
    twoFactionLine()
    resolve.assignInitialControl()

    local rolls = 0
    resolve.setRandom(function() rolls = rolls + 1 return 0 end)
    resolve.run(1)

    expect.equal(rolls, 0, 'rolls attempted')
    expect.equal(state.getOwner('cell_10k'), 'alpha', 'unchanged')
    expect.equal(state.getOwner('cell_30k'), 'beta', 'unchanged')
end

--- Shift the balance of power and the front moves: cells where the
-- other side now projects more become contested, and only those.
function M.strongerProjectorTakesContestedGround()
    twoFactionLine()
    resolve.assignInitialControl()

    -- Alpha at 200 projects 0.25 * 200 = 50 at cell_30k, against beta's
    -- 0.75 * 50 = 37.5. Alpha is now the strongest there.
    power.set('alpha', 200)
    resolve.setRandom(always(0))   -- every roll succeeds
    resolve.run(1)

    expect.equal(state.getOwner('cell_30k'), 'alpha', 'front moved')
    expect.equal(state.getOwner('cell_40k'), 'beta', 'beta heartland held')
end

function M.losingRollLeavesOwnershipAlone()
    twoFactionLine()
    resolve.assignInitialControl()
    power.set('alpha', 200)

    resolve.setRandom(always(0.999))   -- every roll fails
    resolve.run(1)

    expect.equal(state.getOwner('cell_30k'), 'beta', 'still held after a failed roll')
end

--- Without a cooldown a contested cell would change hands every single
-- day, which reads as noise rather than a shifting border.
function M.cooldownBlocksImmediateReversal()
    twoFactionLine()
    resolve.assignInitialControl()
    power.set('alpha', 200)
    resolve.setRandom(always(0))

    resolve.run(1)
    expect.equal(state.getOwner('cell_30k'), 'alpha', 'taken on day 1')

    -- Beta is no longer the strongest here, so flip the balance back and
    -- confirm the cooldown, not the projection, is what holds it.
    power.set('alpha', 50)
    resolve.run(2)
    expect.equal(state.getOwner('cell_30k'), 'alpha', 'cooldown holds it')

    resolve.run(1 + config.FRONTIER_COOLDOWN_DAYS)
    expect.equal(state.getOwner('cell_30k'), 'beta', 'contestable again once expired')
end

function M.claimsUnownedGroundDuringNormalResolution()
    twoFactionLine()
    -- Nothing assigned: every cell starts unheld.
    resolve.setRandom(always(0.999))   -- prove no roll is needed
    resolve.run(1)

    expect.equal(state.getOwner('cell_0'), 'alpha', 'claimed without a roll')
    expect.equal(state.getOwner('cell_40k'), 'beta', 'claimed without a roll')
end

--------------------------------------------------------------------------
-- Settlements
--------------------------------------------------------------------------

-- A settlement ringed by four frontier cells, at the midpoint between two
-- factions so both project onto it equally.
local function settlementRinged()
    registry.registerLandmass({
        id = 'testland',
        factions = {
            {
                id = 'alpha',
                basePower = 50,
                powerCenters = {
                    { id = 'alpha_seat', tier = 'capital',
                      coords = { x = 0, y = 0 }, influenceRange = RANGE },
                    -- Standing in the town itself. This is what makes the
                    -- town alpha's and keeps it that way.
                    { id = 'town', tier = 'capital', coords = { x = 20480, y = 0 },
                      influenceRange = RANGE, cells = { '#2,0' } },
                },
            },
            {
                id = 'beta',
                basePower = 50,
                powerCenters = {
                    { id = 'beta_seat', tier = 'capital',
                      coords = { x = RANGE, y = 0 }, influenceRange = RANGE },
                },
            },
        },
        territories = {
            {
                id = 'town',
                tier = 'town',
                -- Cell #2,0 spans 16384..24576, so its middle is 20480 --
                -- close enough to the midpoint between the two seats that
                -- projection alone would be a near tie here.
                cells = { '#2,0' },
                defaultOwner = 'alpha',
                adjacentFrontier = { 'ring_1', 'ring_2', 'ring_3', 'ring_4' },
            },
        },
        frontier = {
            { id = 'ring_1', centroid = { x = 19000, y = 0 }, defaultOwner = 'alpha' },
            { id = 'ring_2', centroid = { x = 21000, y = 0 }, defaultOwner = 'alpha' },
            { id = 'ring_3', centroid = { x = 20000, y = 1000 }, defaultOwner = 'alpha' },
            { id = 'ring_4', centroid = { x = 20000, y = -1000 }, defaultOwner = 'alpha' },
        },
    })
    state.fillDefaults(registry)
end

local function encircle(count)
    local ring = { 'ring_1', 'ring_2', 'ring_3', 'ring_4' }
    for i = 1, count do
        state.setOwner(ring[i], 'beta')
    end
end

--- The decision this framework is built around: influence competes,
-- armies don't. Morrowind has nowhere to put the consequences of a city
-- changing hands, so seats don't move however the map around them goes.
function M.settlementsHoldAgainstOrdinaryPolitics()
    settlementRinged()
    encircle(4)                     -- completely cut off
    power.set('beta', 250)          -- five times its neighbour's standing
    resolve.setRandom(always(0))    -- with every roll going against it

    for day = 1, 500 do
        resolve.run(day)
    end

    expect.equal(resolve.settlementOwner(registry.settlements.town), 'alpha', 'the seat held')
end

--- And the honest other half: the floor is a number, not an absolute. A
-- faction strong enough does take a settlement, which is the knob rather
-- than a hole -- SEAT_FLOOR decides how strong "enough" is. Pinning the
-- figure here means retuning it can't quietly change what the design
-- promises.
function M.aSettlementFallsOnlyToOverwhelmingPower()
    settlementRinged()
    local cell = registry.settlements.town.territoryIds[1]
    local reach = resolve.projectionFactors(registry.territories[cell]).factors.beta

    -- What it takes to out-project a capital-tier garrison from one cell
    -- away: about ten times the standing either faction starts with.
    local needed = config.SEAT_FLOOR / reach
    expect.greater(needed, 8 * 50, 'a settlement is not casually taken')

    power.set('beta', needed * 1.01)
    resolve.setRandom(always(0))
    resolve.run(1)

    expect.equal(state.getOwner(cell), 'beta', 'overwhelming force does take it')
end

--- The one thing that still happens to a settlement: a first claim, for
-- one nobody reached when the world was made.
function M.unownedSettlementsAreStillClaimed()
    settlementRinged()
    local cell = registry.settlements.town.territoryIds[1]
    state.setOwner(cell, nil)

    resolve.run(1)

    expect.equal(state.getOwner(cell), 'alpha', 'claimed by its strongest projector')
end

--- The floor, and why it is a number rather than a rule. A holding with
-- no weight behind it gets a floor of zero and behaves like open ground,
-- which is what makes an unaffiliated ruin claimable without a single
-- exception anywhere in the ownership logic.
function M.theFloorAppliesOnlyWhereAFactionStands()
    settlementRinged()
    local town = registry.settlements.town
    local cell = registry.territories[town.territoryIds[1]]

    -- A capital-tier seat: the floor is SEAT_FLOOR scaled by weight 1.0.
    expect.near(resolve.effectivePower('alpha', cell), config.SEAT_FLOOR, 1e-6,
        'alpha stands on its own ground, so the floor decides')
    expect.near(resolve.effectivePower('beta', cell),
        power.getLive('beta') * resolve.projectionFactors(cell).factors.beta, 1e-6,
        'beta has no footing here, so plain projection decides')
end

--- Surrounded is a fact the framework publishes and does not act on.
function M.reportsSurroundedAndRelieved()
    settlementRinged()
    -- Alpha out-projects beta on the ring cells, so without a rigged
    -- roll it takes them back and this becomes a coin toss.
    resolve.setRandom(always(0.999))
    core._test.reset()

    encircle(3)                     -- 3 of 4 clears the 0.6 share
    resolve.run(1)
    expect.equal(state.get().surroundedSince.town, 1, 'records the day it started')
    expect.count(core._test.eventsNamed('BoP_SettlementSurrounded'), 1, 'announced once')

    -- Still surrounded: a fact that has not changed is not news.
    resolve.run(2)
    expect.count(core._test.eventsNamed('BoP_SettlementSurrounded'), 1, 'not repeated daily')
    expect.equal(state.get().surroundedSince.town, 1, 'and the day does not drift')

    state.setOwner('ring_1', 'alpha')   -- broken: 2 of 4
    resolve.run(3)
    expect.isNil(state.get().surroundedSince.town, 'cleared on relief')
    expect.count(core._test.eventsNamed('BoP_SettlementRelieved'), 1, 'and announced')
end

function M.notSurroundedBelowTheShare()
    settlementRinged()
    resolve.setRandom(always(0.999))
    encircle(2)   -- 2 of 4 = 0.5, under the 0.6 share

    resolve.run(1)

    expect.falsy(resolve.isSurrounded(registry.settlements.town), 'not surrounded')
    expect.isNil(state.get().surroundedSince.town, 'nothing recorded')
end

--------------------------------------------------------------------------
-- Ordering
--------------------------------------------------------------------------

--- The frontier decides whether a settlement is surrounded, so resolving
-- settlements first would judge them against yesterday's map.
function M.frontierResolvesBeforeSettlements()
    settlementRinged()
    -- Beta will take the ring cells this pass; the settlement must see the
    -- new ownership in the same pass, not the next one.
    power.set('beta', 400)
    resolve.setRandom(always(0))
    resolve.run(1)

    expect.equal(state.getOwner('ring_1'), 'beta', 'ring taken')
    expect.equal(state.get().surroundedSince.town, 1, 'surrounded the same day')
end

return M
