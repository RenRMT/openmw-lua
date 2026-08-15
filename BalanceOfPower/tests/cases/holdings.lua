-- Seat scoring: breadth, depth, and the starting power they produce.

local expect = require('support.expect')

local config = require('scripts.BalanceOfPower.core.config')
local holdings = require('scripts.BalanceOfPower.core.holdings')
local registry = require('scripts.BalanceOfPower.core.registry')

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

return M
