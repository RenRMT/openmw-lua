-- Holdings: seat scoring and the starting power it produces, then the
-- live index over held territory and the standings built on it.

local expect = require('support.expect')

local config = require('scripts.BalanceOfPower.core.config')
local holdings = require('scripts.BalanceOfPower.core.holdings')
local power = require('scripts.BalanceOfPower.core.power')
local registry = require('scripts.BalanceOfPower.core.registry')
local state = require('scripts.BalanceOfPower.core.state')

local M = {}

--- Settlements for one faction, as { tier, region } pairs.
local function seats(factionId, entries, landmassId)
    local territories = {}
    for index, entry in ipairs(entries) do
        territories[index] = {
            id = string.format('%s_%d', factionId, index),
            tier = entry[1],
            region = entry[2],
            faction = factionId,
            cells = { string.format('#%d,%d', index, 0) },
        }
    end
    registry.registerLandmass({
        id = landmassId or ('land_' .. factionId),
        factions = { { id = factionId } },
        territories = territories,
    })
end

--------------------------------------------------------------------------
-- Breadth and depth
--------------------------------------------------------------------------

--- A region contributes its strongest seat, not the sum -- the same rule
-- the projection maths uses, so a plantation belt reads as presence in
-- one region rather than as several cities.
function M.aRegionContributesItsStrongestSeatPlusAShareOfTheRest()
    seats('house', { { 'town', 'a' }, { 'village', 'a' } })

    local town = config.SETTLEMENT_TIERS.town.weight
    local village = config.SETTLEMENT_TIERS.village.weight
    expect.near(holdings.seatProfile('house').score,
        town + config.POWER_DEPTH_SHARE * village, 1e-6, 'strongest plus a share')
end

--- The case this exists for. Eleven farms in one region must not outweigh
-- a spread of real holdings, because they project nothing beyond their
-- own cells however many there are.
function M.aFarmBeltCountsFarLessThanTheSameWeightSpreadOut()
    seats('deep', {
        { 'village', 'a' }, { 'minor location', 'a' }, { 'minor location', 'a' },
        { 'minor location', 'a' }, { 'minor location', 'a' },
    })
    seats('broad', {
        { 'village', 'p' }, { 'minor location', 'q' }, { 'minor location', 'r' },
        { 'minor location', 's' }, { 'minor location', 't' },
    })

    expect.truthy(holdings.seatProfile('broad').score > holdings.seatProfile('deep').score,
        'the same seats spread over five regions outscore five in one')
    expect.equal(holdings.seatProfile('deep').regions, 1, 'one region')
    expect.equal(holdings.seatProfile('broad').regions, 5, 'five regions')
    -- Both hold the same number of seats, so seat count alone says nothing.
    expect.equal(holdings.seatProfile('deep').seats, 5, 'same seat count')
    expect.equal(holdings.seatProfile('broad').seats, 5, 'same seat count')
end

--- Depth still counts for something, or a farm belt would be worth
-- nothing at all and holding one would be indistinguishable from holding
-- open ground.
function M.depthCountsButLessThanBreadth()
    seats('one', { { 'town', 'a' } })
    seats('two', { { 'town', 'a' }, { 'town', 'a' } })

    local single = holdings.seatProfile('one').score
    local double = holdings.seatProfile('two').score
    expect.truthy(double > single, 'a second holding is worth something')
    expect.truthy(double < 2 * single, 'but less than a first one')
end

--- Region is the game's own, and it can be missing. Falling back to a
-- unique key would make every region-less seat its own region, inflating
-- exactly the scattered holdings the depth share is there to damp.
function M.seatsWithNoRegionFallBackToTheirLandmass()
    seats('nameless', { { 'town' }, { 'town' }, { 'town' } })

    expect.equal(holdings.seatProfile('nameless').regions, 1,
        'all three landed in one bucket, not three')
end

--------------------------------------------------------------------------
-- Starting power
--------------------------------------------------------------------------

--- The anchor. A faction with the average holdings gets exactly
-- DEFAULT_BASE_POWER, which is what makes the number mean anything.
function M.averageHoldingsGiveExactlyTheAnchor()
    seats('alpha', { { 'town', 'a' } })
    seats('beta', { { 'town', 'b' } })

    expect.near(holdings.basePowerOf('alpha'), config.DEFAULT_BASE_POWER, 1e-6, 'on the mean')
end

--- A score of zero never touches the mean, so the floor is the one value
-- that cannot drift when another pack loads.
function M.factionsWithNoSeatsGetTheFloorShare()
    seats('landed', { { 'metropolis', 'a' } })
    registry.registerLandmass({ id = 'guilds', factions = { { id = 'guild' } } })

    local floor = config.DEFAULT_BASE_POWER * config.POWER_FLOOR_SHARE
    expect.near(holdings.basePowerOf('guild'), floor, 1e-6, 'floor share')

    -- And it stays there when the world around it grows.
    seats('newcomer', { { 'megalopolis', 'z' } }, 'later_pack')
    expect.near(holdings.basePowerOf('guild'), floor, 1e-6, 'unmoved by a later pack')
end

function M.strongerHoldingsGiveMorePower()
    seats('city', { { 'metropolis', 'a' } })
    seats('farm', { { 'minor location', 'b' } })

    expect.truthy(holdings.basePowerOf('city') > config.DEFAULT_BASE_POWER, 'above the mean')
    expect.truthy(holdings.basePowerOf('farm') < config.DEFAULT_BASE_POWER, 'below it')
end

--- The score is recomputed when a later pack registers, so a faction that
-- gains seats gains standing without anything invalidating a cache.
function M.scoresFollowLaterRegistrations()
    seats('house', { { 'town', 'a' } })
    local before = holdings.seatProfile('house').score

    seats('house_more', { { 'town', 'b' } }, 'second')
    registry.registerLandmass({
        id = 'third',
        territories = {
            { id = 'extra', tier = 'town', region = 'c', faction = 'house', cells = { '#9,9' } },
        },
    })

    expect.truthy(holdings.seatProfile('house').score > before, 'the new seat counted')
    expect.equal(holdings.seatProfile('house').regions, 2, 'in a second region')
end

--------------------------------------------------------------------------
-- Held territory
--------------------------------------------------------------------------

-- Two regions, a two-cell settlement in each, and a frontier cell each
-- side. Nothing is owned until a test says so.
local function twoRegionWorld()
    registry.registerLandmass({
        id = 'testland',
        factions = { { id = 'north' }, { id = 'south' } },
        territories = {
            { id = 'keep', tier = 'town', region = 'upper', faction = 'north',
              cells = { '#0,0', '#1,0' } },
            { id = 'port', tier = 'town', region = 'lower', faction = 'south',
              cells = { '#0,5' } },
        },
        frontier = {
            { id = 'moor', region = 'upper', centroid = { x = 0, y = 8192 } },
            { id = 'fen', region = 'lower', centroid = { x = 0, y = 32768 } },
        },
    })
end

--- A settlement is several ownable cells, so a faction holding a city
-- must not read as holding several places.
function M.countsTerritoriesRegionsAndSettlements()
    twoRegionWorld()
    state.setOwner('keep_0_0', 'north')
    state.setOwner('keep_1_0', 'north')
    state.setOwner('moor', 'north')

    local standing = holdings.factionStanding('north')
    expect.equal(standing.territories, 3, 'three cells')
    expect.equal(standing.settlements, 1, 'one named place')
    expect.equal(standing.regions, 1, 'all of it in one region')
end

function M.unclaimedGroundBelongsToNobody()
    twoRegionWorld()
    state.setOwner('moor', 'north')
    state.setOwner('moor', nil)

    expect.equal(holdings.factionStanding('north').territories, 0, 'given back')
    expect.isNil(next(holdings.holdersOfRegion('upper')), 'and nobody holds the region')
end

function M.theIndexFollowsAnOwnershipChange()
    twoRegionWorld()
    state.setOwner('moor', 'north')
    expect.equal(holdings.factionStanding('north').territories, 1, 'held')

    state.setOwner('moor', 'south')
    expect.equal(holdings.factionStanding('north').territories, 0, 'lost')
    expect.equal(holdings.factionStanding('south').territories, 1, 'gained')
end

--- fillDefaults writes ownership without going through setOwner, so an
-- index keyed off setOwner alone would miss a pack's authored owners.
function M.theIndexFollowsSeededDefaults()
    twoRegionWorld()
    registry.registerLandmass({
        id = 'claimed',
        territories = {
            { id = 'fort', tier = 'town', region = 'upper', faction = 'north',
              defaultOwner = 'north', cells = { '#9,9' } },
        },
    })
    -- Reads the index into existence before the write below, so this
    -- tests invalidation rather than a first build.
    expect.equal(holdings.factionStanding('north').territories, 0, 'not seeded yet')

    state.fillDefaults(registry)
    expect.equal(holdings.factionStanding('north').territories, 1, 'the authored owner counted')
end

--- The same hazard on load: deserialize replaces the ownership table
-- wholesale, and a stale index would report the previous session's map.
function M.theIndexFollowsALoadedSave()
    twoRegionWorld()
    state.setOwner('moor', 'north')
    expect.equal(holdings.factionStanding('north').territories, 1, 'held before the load')

    state.deserialize({ ownership = { moor = 'south', fen = 'south' } })

    expect.equal(holdings.factionStanding('north').territories, 0, 'gone')
    expect.equal(holdings.factionStanding('south').territories, 2, 'restored from the save')
end

--------------------------------------------------------------------------
-- Standings
--------------------------------------------------------------------------

--- The bandit hook: broad, thin control reads high. A faction holding
-- three cells on 50 power is stretched over six cells per 100.
function M.strainIsTerritoriesPerHundredPower()
    twoRegionWorld()
    state.setOwner('keep_0_0', 'north')
    state.setOwner('moor', 'north')
    state.setOwner('fen', 'north')
    power.set('north', 50)

    local standing = holdings.factionStanding('north')
    expect.near(standing.strain, 6, 1e-6, 'three cells per 50 power')
    expect.near(standing.concentration, 1.5, 1e-6, 'three cells over two regions')
end

--- Nothing held is zero rather than a division by zero, and a faction
-- with no power is not infinitely strained.
function M.ratiosAreZeroWithNothingToDivide()
    twoRegionWorld()
    power.set('north', 0)

    local standing = holdings.factionStanding('north')
    expect.equal(standing.strain, 0, 'no strain')
    expect.equal(standing.concentration, 0, 'no concentration')
end

function M.standingsAreSortedByPower()
    twoRegionWorld()
    power.set('north', 10)
    power.set('south', 90)

    local rows = holdings.standings()
    expect.count(rows, 2, 'both factions')
    expect.equal(rows[1].id, 'south', 'strongest first')
    expect.equal(rows[2].id, 'north', 'then the rest')
end

function M.anUnregisteredFactionHasNoStanding()
    twoRegionWorld()
    expect.isNil(holdings.factionStanding('nobody'), 'nil rather than an empty standing')
end

--------------------------------------------------------------------------
-- Region queries
--------------------------------------------------------------------------

function M.regionsHeldByAreSortedAndDistinct()
    twoRegionWorld()
    state.setOwner('keep_0_0', 'north')
    state.setOwner('keep_1_0', 'north')
    state.setOwner('fen', 'north')

    local regions = holdings.regionsHeldBy('north')
    expect.count(regions, 2, 'each region once, however many cells')
    expect.equal(regions[1], 'lower', 'sorted')
    expect.equal(regions[2], 'upper', 'sorted')
    expect.count(holdings.regionsHeldBy('south'), 0, 'holding nothing')
end

--- The other direction, for a rule that starts from a place rather than
-- from a faction.
function M.holdersOfRegionCountsEachFactionsGround()
    twoRegionWorld()
    state.setOwner('keep_0_0', 'north')
    state.setOwner('keep_1_0', 'north')
    state.setOwner('moor', 'south')

    local holders = holdings.holdersOfRegion('upper')
    expect.equal(holders.north, 2, 'two cells')
    expect.equal(holders.south, 1, 'one cell')
    expect.isNil(next(holdings.holdersOfRegion('nowhere')), 'an unknown region holds nobody')
end

return M
