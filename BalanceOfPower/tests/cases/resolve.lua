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

-- The halving distance, chosen so the line below lands on exact powers
-- of two and the arithmetic can be read rather than computed.
local HALVING = 10000
local SPAN = 40000

-- Two equal factions facing each other across 40000 units, with frontier
-- cells strung along the line between them. Projection at each cell:
--
--   x        0      10000    20000    30000    40000
--   alpha   50.0     25.0     12.5      6.25     3.125
--   beta     3.125    6.25    12.5     25.0     50.0
--
-- so alpha holds the near cells, beta the far ones, and 20000 is an
-- exact tie that the sorted-id rule has to break the same way each time.
--
-- Note the far column. Alpha's projection at beta's doorstep is small but
-- **not zero**, which is the property this whole model turns on: there is
-- no distance at which a faction is shut out, only a distance at which it
-- would need more power than it has.
--
-- Each seat is a settlement, since that is the only thing that projects.
-- Both carry an explicit centroid: the arithmetic above wants a seat at
-- exactly x=0 and one at exactly x=40000, where a derived centroid would
-- land in the middle of whichever cell contains it.
local function twoFactionLine(overrides)
    overrides = overrides or {}
    registry.registerLandmass({
        id = 'testland',
        factions = {
            { id = 'alpha', basePower = overrides.alphaPower or 50 },
            { id = 'beta', basePower = overrides.betaPower or 50 },
        },
        territories = {
            { id = 'alpha_seat', tier = 'large city', faction = 'alpha',
              cells = { '#0,0' }, centroid = { x = 0, y = 0 }, influenceRange = HALVING },
            { id = 'beta_seat', tier = 'large city', faction = 'beta',
              cells = { '#4,0' }, centroid = { x = SPAN, y = 0 }, influenceRange = HALVING },
        },
        frontier = {
            { id = 'cell_0', centroid = { x = 0, y = 0 } },
            { id = 'cell_10k', centroid = { x = 10000, y = 0 } },
            { id = 'cell_20k', centroid = { x = 20000, y = 0 } },
            { id = 'cell_30k', centroid = { x = 30000, y = 0 } },
            { id = 'cell_40k', centroid = { x = SPAN, y = 0 } },
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

--- Halving per influenceRange, and the thing worth pinning: it never
-- reaches zero. A factor of zero anywhere would be ground that no amount
-- of power could ever claim.
function M.proximityHalvesPerInfluenceRange()
    expect.equal(resolve.proximityFactor(0, 1000), 1, 'at the seat')
    expect.equal(resolve.proximityFactor(1000, 1000), 0.5, 'one halving out')
    expect.equal(resolve.proximityFactor(2000, 1000), 0.25, 'two')
    expect.equal(resolve.proximityFactor(3000, 1000), 0.125, 'three')
end

--- Far away is small, not nothing. Twenty halvings is a factor of about a
-- millionth -- unreachable in practice at any sane power, and still not a
-- wall.
function M.proximityNeverReachesZero()
    expect.greater(resolve.proximityFactor(20000, 1000), 0, 'still positive at 20 halvings')
    expect.greater(1e-5, resolve.proximityFactor(20000, 1000), 'but negligible')
end

function M.effectivePowerFallsOffWithDistance()
    twoFactionLine()
    expect.near(resolve.effectivePower('alpha', registry.territories.cell_0), 50, 1e-6, 'at seat')
    expect.near(resolve.effectivePower('alpha', registry.territories.cell_10k), 25, 1e-6, 'one halving')
    expect.near(resolve.effectivePower('alpha', registry.territories.cell_30k), 6.25, 1e-6, 'three')
    -- Four halvings out, on beta's doorstep, and still projecting.
    expect.near(resolve.effectivePower('alpha', registry.territories.cell_40k), 3.125, 1e-6,
        'small, but never nothing')
end

--- The property the whole model exists for: a faction that grows reaches
-- further, and does so with diminishing returns. Each doubling of power
-- buys exactly one more halving distance of ground, so ten times the
-- power is a bit over three of them, not ten.
function M.reachGrowsWithPowerAndDiminishes()
    twoFactionLine()

    -- The furthest cell alpha projects above the claim floor.
    local line = { 'cell_0', 'cell_10k', 'cell_20k', 'cell_30k', 'cell_40k' }
    local function edge()
        local furthest = nil
        for _, id in ipairs(line) do
            local at = resolve.effectivePower('alpha', registry.territories[id])
            if at >= config.MIN_CLAIM_POWER then
                furthest = id
            end
        end
        return furthest
    end

    power.set('alpha', 50)
    expect.equal(edge(), 'cell_30k', 'at base power alpha reaches three halvings out')

    -- One doubling, one more halving distance -- and 10000 units is
    -- exactly the gap between these cells.
    power.set('alpha', 100)
    expect.equal(edge(), 'cell_40k', 'doubling its power buys exactly one cell more')
end

--- Doc 3.2: a faction's strength somewhere is its strongest single
-- foothold, never the sum. Summing would let anyone out-project a rival
-- by scattering cheap outposts, which is the opposite of the intent.
function M.effectivePowerTakesStrongestNotSum()
    registry.registerLandmass({
        id = 'testland',
        factions = { { id = 'alpha', basePower = 50 } },
        territories = {
            { id = 'near', tier = 'large city', faction = 'alpha',
              cells = { '#0,0' }, centroid = { x = 0, y = 0 }, influenceRange = HALVING },
            { id = 'also_near', tier = 'large city', faction = 'alpha',
              cells = { '#1,0' }, centroid = { x = 1000, y = 0 }, influenceRange = HALVING },
            { id = 'third', tier = 'large city', faction = 'alpha',
              cells = { '#2,0' }, centroid = { x = 2000, y = 0 }, influenceRange = HALVING },
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
    expect.near(resolve.effectivePower('alpha', registry.territories.cell_10k), 50, 1e-6, 'doubled')
end

--- Power without geography projects nothing. A faction is territorial
-- exactly when a settlement names it, so a guild with all the standing in
-- the world still reaches nowhere.
function M.nonTerritorialFactionsProjectNothing()
    registry.registerLandmass({
        id = 'testland',
        factions = { { id = 'blades', basePower = 100 } },
        frontier = { { id = 'cell', centroid = { x = 0, y = 0 } } },
    })
    state.fillDefaults(registry)

    expect.falsy(registry.factions.blades.territorial, 'no seats')
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
            { id = 'alpha', basePower = 50 },
        },
        territories = {
            { id = 'seat', tier = 'large city', faction = 'alpha',
              cells = { '#0,0' }, centroid = { x = 0, y = 0 }, influenceRange = HALVING },
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
    -- At 10000 -- one halving out -- alpha projects half its power. Drop
    -- it so that lands just under the floor.
    power.set('alpha', (config.MIN_CLAIM_POWER / 0.5) * 0.9)
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
            { id = 'alpha', basePower = 500 },
            { id = 'sixth house', basePower = 10 },
        },
        territories = {
            { id = 'seat', tier = 'large city', faction = 'alpha',
              cells = { '#0,0' }, centroid = { x = 0, y = 0 }, influenceRange = HALVING },
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

    -- Alpha at 400 projects 0.125 * 400 = 50 at cell_30k, against beta's
    -- 0.5 * 50 = 25. Alpha is now the strongest there.
    power.set('alpha', 400)
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
            { id = 'alpha', basePower = 50 },
            { id = 'beta', basePower = 50 },
        },
        territories = {
            { id = 'alpha_seat', tier = 'large city', faction = 'alpha',
              cells = { '#0,0' }, centroid = { x = 0, y = 0 }, influenceRange = HALVING },
            { id = 'beta_seat', tier = 'large city', faction = 'beta',
              cells = { '#4,0' }, centroid = { x = SPAN, y = 0 }, influenceRange = HALVING },
            {
                -- The town is alpha's seat and alpha's ground in one
                -- entry, which is the whole point of the merge: standing
                -- in it is what makes it alpha's and keeps it that way.
                id = 'town',
                tier = 'town',
                faction = 'alpha',
                -- Cell #2,0 spans 16384..24576, so its middle is 20480 --
                -- close enough to the midpoint between the two seats that
                -- projection alone would be a near tie here.
                cells = { '#2,0' },
                -- A city's reach and weight on a town-tier place, so the
                -- geometry stays exactly what these tests were written
                -- against while the tier still sets the cooldown.
                weight = 1.0,
                influenceRange = HALVING,
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
