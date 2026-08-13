-- Who fights whom, and the ambient growth that makes a faction worth
-- fighting in the first place.

local expect = require('support.expect')

local core = require('openmw.core')

local config = require('scripts.BalanceOfPower.core.config')
local driver = require('scripts.BalanceOfPower.core.driver')
local hostility = require('scripts.BalanceOfPower.core.hostility')
local power = require('scripts.BalanceOfPower.core.power')
local registry = require('scripts.BalanceOfPower.core.registry')
local state = require('scripts.BalanceOfPower.core.state')

local M = {}

--------------------------------------------------------------------------
-- Fixtures
--------------------------------------------------------------------------

--- Three ordinary houses that dislike each other the way vanilla's do,
-- and an invader everyone hates.
--
-- **Read the rows carefully.** Authored reactions are inbound: an entry
-- on a faction's row is how the *named* faction feels about the one
-- whose row it is. So "the invader hates Hlaalu" is written on Hlaalu's
-- row, not the invader's.
--
-- The relationships below, stated plainly:
--
--   invader -> hlaalu, redoran   -3   it attacks them
--   invader -> telvanni          -1   it walks past them
--   telvanni -> invader          -3   they attack it
--
-- That last asymmetry is the fixture's whole purpose. A hostility rule
-- reading the wrong direction would spare Hlaalu and attack Telvanni,
-- and every symmetric pair in the table would go on passing.
local function morrowind(overrides)
    local factions = {
        {
            id = 'hlaalu',
            basePower = 50,
            reactions = { redoran = -2, telvanni = -1, invader = -3 },
        },
        {
            id = 'redoran',
            basePower = 50,
            reactions = { hlaalu = -2, telvanni = -1, invader = -3 },
        },
        {
            id = 'telvanni',
            basePower = 50,
            reactions = { hlaalu = -1, redoran = -1, invader = -1 },
        },
        {
            id = 'invader',
            basePower = 30,
            reactions = { hlaalu = -3, redoran = -3, telvanni = -3 },
        },
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
-- The flag
--------------------------------------------------------------------------

--- The default, and the one that matters most: Morrowind's Great Houses
-- dislike each other without brawling in the street. A framework that
-- shipped hostility as "reaction below a threshold" would have them
-- fighting on sight everywhere the player looked.
function M.factionsAreNotHostileByDefault()
    morrowind()

    expect.falsy(hostility.isHostile('hlaalu', 'redoran'), 'houses tolerate each other')
    expect.falsy(hostility.isHostile('hlaalu', 'invader'), 'even a hated faction')
    expect.falsy(hostility.isHostileToPlayer('hlaalu'), 'and nobody attacks the player')
end

function M.aFlaggedFactionFightsWhoeverItHates()
    morrowind({ invader = { hostile = true } })

    expect.truthy(hostility.isHostile('invader', 'hlaalu'), 'hated at -3')
    expect.truthy(hostility.isHostile('invader', 'redoran'), 'hated at -3')
    expect.truthy(hostility.isHostileToPlayer('invader'), 'and the player')
end

--- The threshold is a real filter, not decoration. The invader regards
-- Telvanni at only -1, so it walks past them.
function M.aFlaggedFactionToleratesWhatItMerelyDislikes()
    morrowind({ invader = { hostile = true } })

    expect.falsy(hostility.isHostile('invader', 'telvanni'), 'disliked, not hated')
    expect.equal(#hostility.enemiesOf('invader'), 2, 'two enemies, not three')
end

--- The direction trap, pinned. Hostility asks how the *aggressor* feels
-- about the target, which is stored on the target's row. Reading the
-- aggressor's row instead would spare Hlaalu and Redoran -- who feel -3
-- about the invader -- and attack Telvanni, who does not.
function M.readsRegardInTheOutboundDirection()
    morrowind({ invader = { hostile = true }, telvanni = { hostile = true } })

    expect.equal(power.regardOf('invader', 'telvanni'), -1, 'invader mildly dislikes telvanni')
    expect.equal(power.regardOf('telvanni', 'invader'), -3, 'telvanni hates the invader')

    expect.falsy(hostility.isHostile('invader', 'telvanni'), 'the invader lets them be')
    expect.truthy(hostility.isHostile('telvanni', 'invader'), 'telvanni does not')
end

--- Being attacked is not the same as attacking, but a spawn rule only
-- cares that there will be a fight.
function M.willFightIsSymmetricWhereIsHostileIsNot()
    morrowind({ invader = { hostile = true } })

    expect.truthy(hostility.isHostile('invader', 'hlaalu'), 'the invader starts it')
    expect.falsy(hostility.isHostile('hlaalu', 'invader'), 'hlaalu does not go looking')
    expect.truthy(hostility.willFight('hlaalu', 'invader'), 'but there is still a fight')
end

function M.nobodyFightsThemselves()
    morrowind({ invader = { hostile = true } })
    expect.falsy(hostility.isHostile('invader', 'invader'), 'no self-hostility')
end

--- Switching every faction on is meant to be playable rather than a
-- massacre: -3 is rare between vanilla factions, so what emerges is the
-- handful of genuine blood feuds, not a general war. The houses here sit
-- at -1 and -2 and stay peaceful.
function M.theGlobalToggleOnlyReleasesTheRealFeuds()
    config.ALL_FACTIONS_HOSTILE = true
    morrowind()

    expect.truthy(hostility.isHostile('hlaalu', 'invader'), 'the feud is on')
    expect.falsy(hostility.isHostile('hlaalu', 'redoran'), 'ordinary dislike is not')
    expect.truthy(hostility.isHostileToPlayer('redoran'), 'everyone is belligerent now')
end

function M.unregisteredFactionsAreNeverHostile()
    morrowind({ invader = { hostile = true } })
    expect.falsy(hostility.isHostile('invader', 'no such faction'), 'unknown target')
    expect.falsy(hostility.isHostile('no such faction', 'hlaalu'), 'unknown aggressor')
end

--------------------------------------------------------------------------
-- Ambient growth
--------------------------------------------------------------------------

function M.growthIsZeroForEveryoneByDefault()
    morrowind()
    expect.equal(power.applyDailyGrowth(), 0, 'nobody grows')
    expect.equal(power.getLive('invader'), 30, 'power is untouched')
end

function M.growthAccruesEveryResolvedDay()
    morrowind({ invader = { growthPerDay = 1.5 } })

    driver.forceDays(4)

    expect.near(power.getLive('invader'), 30 + 4 * 1.5, 1e-6, 'four days of growth')
end

--- The finding that made GROWTH_PROPAGATES default to false. Every
-- faction sits at -3 toward the invader, so propagated growth is a daily
-- drain on all of them at once -- and unlike a one-off award it never
-- stops. At the pack's own numbers the whole political map reaches
-- MIN_POWER within an in-game year, every projection falls under
-- MIN_CLAIM_POWER, and the world quietly empties.
function M.growthDoesNotDragTheRestOfTheWorldDown()
    morrowind({ invader = { growthPerDay = 1.5 } })

    driver.forceDays(30)

    expect.equal(power.getLive('hlaalu'), 50, 'the houses are untouched')
    expect.equal(power.getLive('telvanni'), 50, 'all of them')
end

--- Kept honest in the other direction: the drain is real when the knob
-- is turned on, so the default is a decision rather than an oversight.
function M.growthPropagatesWhenAskedTo()
    config.GROWTH_PROPAGATES = true
    morrowind({ invader = { growthPerDay = 1.5 } })

    driver.forceDays(10)

    local drain = 10 * 1.5 * config.INFLUENCE_STRENGTH
    expect.near(power.getLive('hlaalu'), 50 - drain, 1e-6, 'ten days of bleeding')
end

--- Growth lands before the batch opens, so the day's rolls resolve
-- against the power the faction has today. Applying it inside the batch
-- would leave every decision one day stale -- invisible in play, and
-- exactly the kind of off-by-one that never gets found.
function M.growthIsVisibleToTheSameDaysResolution()
    morrowind({ invader = { growthPerDay = 10 } })

    local seen = nil
    core.sendGlobalEvent = function(name, data)
        if name == 'BoP_DayResolved' then
            seen = power.getLive('invader')
        end
        return nil, data
    end

    driver.forceDays(1)
    expect.equal(seen, 40, 'the day that resolved saw the grown value')
end

--------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------

function M.rejectsANonNumericGrowthRate()
    expect.raises(function()
        registry.registerLandmass({
            id = 'bad',
            factions = { { id = 'x', growthPerDay = 'fast' } },
        })
    end, 'growthPerDay', 'says which field')
end

--- Growth and hostility are base configuration, like basePower: whichever
-- pack registers a faction first owns them. A second pack extending the
-- faction to add power centres must not be able to make it hostile,
-- because which pack won would depend on load order.
function M.extendingPacksCannotChangeGrowthOrHostility()
    morrowind()
    registry.registerLandmass({
        id = 'solstheim',
        factions = { { id = 'invader', extend = true, hostile = true, growthPerDay = 99 } },
    })

    expect.falsy(registry.factions.invader.hostile, 'flag unchanged')
    expect.equal(registry.factions.invader.growthPerDay, 0, 'rate unchanged')
end

return M
