-- What should be standing in a cell: the decision half of the spawn
-- system, which is all of it that can be tested outside a running game.

local expect = require('support.expect')

local core = require('openmw.core')
local world = require('openmw.world')

local config = require('scripts.BalanceOfPower.core.config')
local patrol = require('scripts.BalanceOfPower.core.patrol')
local power = require('scripts.BalanceOfPower.core.power')
local registry = require('scripts.BalanceOfPower.core.registry')
local resolve = require('scripts.BalanceOfPower.core.resolve')
local state = require('scripts.BalanceOfPower.core.state')

local M = {}

local CELL = 8192

--------------------------------------------------------------------------
-- Fixtures
--------------------------------------------------------------------------

--- A house holding a town, and an invader two cells east of it whose
-- reach overlaps the house's ground. Each hates the other, written on
-- its own row.
local function twoRealms(overrides)
    world._test.defineExteriorGrid(-6, 6, -6, 6)
    core._test.setFactionRecords({
        house = { invader = -3 },
        invader = { house = -3 },
    })

    local factions = {
        {
            id = 'house',
            basePower = 50,
            patrolRoster = { 'house guard' },
        },
        {
            id = 'invader',
            basePower = 50,
            hostile = true,
            patrolRoster = {
                'cultist',
                { id = 'ash ghoul', tier = 2 },
                { id = 'ascended sleeper', tier = 3 },
            },
        },
        -- Holds ground, musters nobody. The opt-out, with no flag.
        {
            id = 'quiet',
            basePower = 50,
        },
    }
    for _, faction in ipairs(factions) do
        for key, value in pairs(overrides and overrides[faction.id] or {}) do
            faction[key] = value
        end
    end

    registry.registerLandmass({
        id = 'testland',
        factions = factions,
        -- Each town is its faction's seat as well as its ground, so the
        -- reach that puts the invader on the house's border is declared
        -- once. Ranges are explicit because these tests were written
        -- against them, not against the tier defaults.
        territories = {
            { id = 'housetown', tier = 'town', faction = 'house',
              cells = { '#-2,0' }, influenceRange = 3 * CELL },
            { id = 'invadertown', tier = 'town', faction = 'invader',
              cells = { '#2,0' }, influenceRange = 3 * CELL },
            { id = 'quietpost', tier = 'outpost', faction = 'quiet',
              cells = { '#-5,5' }, influenceRange = 2 * CELL },
        },
    })
    state.fillDefaults(registry)
    require('scripts.BalanceOfPower.core.frontier').generate({
        landmass = 'testland', margin = 0,
    })
    resolve.assignInitialControl()
end

--- The territory id for an exterior cell, so tests can name ground the
-- way a reader thinks about it.
local function at(gridX, gridY)
    local territory = registry.territoryForCell(string.format('#%d,%d', gridX, gridY))
    expect.truthy(territory, string.format('cell #%d,%d is territory', gridX, gridY))
    return territory.id
end

--- The first day at or after `from` on which this cell plans anything.
-- Individual days are a coin toss by design; what the tests assert is
-- that a patrol turns up at all, and how it looks when it does.
local function firstPlan(territoryId, from)
    for day = from or 1, (from or 1) + 400 do
        local plan = patrol.plan(territoryId, day)
        if plan then
            return plan, day
        end
    end
    return nil
end

--- The first group `factionId` fields in this cell, and the day of it.
--
-- Distinct from firstPlan(): every candidate rolls separately, so the
-- earliest day anything happens is not necessarily a day this particular
-- faction turned out. Since projection has no cut-off, a hostile
-- neighbour can be a candidate on ground well inside its rival's country,
-- and asking only about the first plan would be asking which of two coins
-- landed first.
local function firstGroupFrom(territoryId, factionId)
    for day = 1, 400 do
        local plan = patrol.plan(territoryId, day)
        for _, group in ipairs(plan and plan.groups or {}) do
            if group.faction == factionId then
                return group, day
            end
        end
    end
    return nil
end

--------------------------------------------------------------------------
-- Who turns up
--------------------------------------------------------------------------

function M.theOwnerPatrolsItsOwnGround()
    twoRealms()
    local group = firstGroupFrom(at(-2, 0), 'house')

    expect.truthy(group, 'the house fields a patrol in its own town')
    expect.greater(group.count, 0, 'with somebody in it')
end

--- A faction with an empty roster never appears, and needs no flag to
-- say so. This is the whole opt-out: a guild that musters nobody has an
-- empty list, and every other rule goes on applying to it unchanged.
function M.aFactionWithNoRosterNeverPatrols()
    twoRealms()

    expect.equal(state.getOwner(at(-5, 5)), 'quiet', 'it does hold the ground')
    expect.isNil(firstPlan(at(-5, 5)), 'and never puts anyone on it')
end

--- The invader appears on ground the house still owns, because it
-- projects there. This is what makes ambient growth visible long before
-- the ownership map moves: the border looks contested before it is.
function M.aBelligerentFactionPatrolsGroundItDoesNotOwn()
    twoRealms()

    local contested = at(0, 0)
    expect.equal(state.getOwner(contested), 'house', 'the house holds the middle')

    local sawInvader = false
    for day = 1, 400 do
        local plan = patrol.plan(contested, day)
        for _, group in ipairs(plan and plan.groups or {}) do
            sawInvader = sawInvader or group.faction == 'invader'
        end
    end
    expect.truthy(sawInvader, 'the invader shows up on the house border')
end

--- The mirror of the above, and the reason belligerence gates it: a
-- peaceful faction stays home. Without this the map would fill with
-- everyone's patrols wherever anyone's influence reached.
function M.aPeacefulFactionStaysOnItsOwnGround()
    twoRealms({ invader = { hostile = false } })

    local invaderGround = at(2, 0)
    expect.equal(state.getOwner(invaderGround), 'invader', 'the invader holds its town')

    local sawHouse = false
    for day = 1, 400 do
        local plan = patrol.plan(at(1, 0), day)
        for _, group in ipairs(plan and plan.groups or {}) do
            sawHouse = sawHouse or group.faction == 'house'
        end
    end
    expect.falsy(sawHouse, 'the house never patrols the invader side')
end

--------------------------------------------------------------------------
-- How they look
--------------------------------------------------------------------------

function M.patrolsGrowWithProjection()
    twoRealms()
    expect.equal(patrol.sizeFor(0), 1, 'a foothold still fields somebody')
    expect.equal(patrol.sizeFor(config.PATROL_POWER_PER_MEMBER), 2, 'one step up')
    expect.equal(patrol.sizeFor(1e9), config.PATROL_MAX_MEMBERS, 'and it is capped')
end

--- A dozen guards on one road is a performance problem and reads as an
-- army. The cap is what keeps a runaway faction from producing one.
function M.anOverwhelmingFactionStillFieldsAPatrolNotAnArmy()
    twoRealms()
    power.set('invader', 100000)
    resolve.invalidateProjections()

    local plan = firstPlan(at(2, 0))
    expect.truthy(plan, 'it patrols')
    expect.equal(plan.groups[1].count, config.PATROL_MAX_MEMBERS, 'at the cap, not beyond')
end

function M.rosterTiersUnlockWithProjection()
    twoRealms()
    local roster = registry.factions.invader.patrolRoster

    expect.equal(patrol.tierFor(0, roster), 1, 'the bottom tier is always available')
    expect.equal(patrol.tierFor(config.PATROL_POWER_PER_TIER, roster), 2, 'one step up')
    expect.equal(patrol.tierFor(1e9, roster), 3, 'capped by what the pack authored')
end

--- A pack that authored one tier gets tier 1 forever, however strong its
-- faction becomes. That is the pack having said what it fields, not a
-- limitation to work around.
function M.aSingleTierRosterNeverOutgrowsItself()
    twoRealms()
    expect.equal(patrol.tierFor(1e9, registry.factions.house.patrolRoster), 1, 'still tier 1')
end

--- Drawing only from the unlocked tier would make a strong faction's
-- patrols uniform, which reads as an honour guard. Lower tiers stay in
-- the pool.
function M.strongPatrolsStillIncludeOrdinaryTroops()
    twoRealms()
    power.set('invader', 500)
    resolve.invalidateProjections()

    local seen = {}
    for day = 1, 400 do
        local plan = patrol.plan(at(2, 0), day)
        for _, group in ipairs(plan and plan.groups or {}) do
            for _, record in ipairs(group.records) do
                seen[record] = true
            end
        end
    end

    expect.truthy(seen['ascended sleeper'], 'the top tier appears')
    expect.truthy(seen.cultist, 'and so does the bottom one')
end

--------------------------------------------------------------------------
-- Hostility
--------------------------------------------------------------------------

function M.opposedPatrolsInTheSameCellFight()
    twoRealms()

    local found = nil
    for day = 1, 400 do
        local plan = patrol.plan(at(0, 0), day)
        if plan and #plan.groups == 2 then
            found = plan
            break
        end
    end

    expect.truthy(found, 'both sides turn up in the same cell eventually')
    expect.equal(found.groups[1].fights[1], found.groups[2].faction, 'and they pair off')
    expect.equal(found.groups[2].fights[1], found.groups[1].faction, 'both ways')
end

--- willFight is symmetric, so the house fights back without being
-- flagged. It never starts anything -- it just ends up in a fight.
function M.theDefenderFightsBackWithoutBeingHostile()
    twoRealms()
    expect.falsy(registry.factions.house.hostile, 'the house is peaceful')

    for day = 1, 400 do
        local plan = patrol.plan(at(0, 0), day)
        if plan and #plan.groups == 2 then
            for _, group in ipairs(plan.groups) do
                expect.equal(#group.fights, 1, group.faction .. ' is in the fight')
            end
            return
        end
    end
    expect.truthy(false, 'the two sides never met')
end

function M.onlyHostileFactionsAttackThePlayer()
    twoRealms()

    for day = 1, 400 do
        local plan = patrol.plan(at(0, 0), day)
        for _, group in ipairs(plan and plan.groups or {}) do
            expect.equal(group.hostileToPlayer, group.faction == 'invader',
                group.faction .. ' stance toward the player')
        end
    end
end

--------------------------------------------------------------------------
-- The seeded roll
--------------------------------------------------------------------------

--- The property the whole design rests on. A player crossing a cell
-- boundary back and forth must get the same answer, or patrols become a
-- source of infinite gear and gold -- every one of them carries a vanilla
-- record's inventory.
function M.thePlanForACellAndDayIsStable()
    twoRealms()
    local territoryId = at(-2, 0)

    local first = firstPlan(territoryId)
    for _ = 1, 20 do
        local again = patrol.plan(territoryId, first.day)
        expect.equal(again.groups[1].faction, first.groups[1].faction, 'same faction')
        expect.equal(again.groups[1].count, first.groups[1].count, 'same size')
        expect.equal(again.groups[1].records[1], first.groups[1].records[1], 'same records')
    end
end

function M.differentDaysGiveDifferentPatrols()
    twoRealms()
    local territoryId = at(-2, 0)

    local seen = {}
    for day = 1, 60 do
        seen[patrol.plan(territoryId, day) and 'yes' or 'no'] = true
    end
    expect.truthy(seen.yes and seen.no, 'some days have a patrol and some do not')
end

--- The bug this file found, and the reason it is worth a test of its
-- own: consecutive days must not be correlated.
--
-- Seeding on "territory@day" made the hash very nearly linear in the
-- day, so one day's roll landed about 0.000008 from the next. Every
-- individual number was still uniform and still stable per day -- the
-- two properties the design actually asks for -- while a cell stayed
-- lucky or unlucky for several hundred days running. Most stayed
-- unlucky, so the map simply had no patrols on it and nothing anywhere
-- said why.
--
-- Sampling the run lengths catches that where sampling the values does
-- not.
function M.consecutiveDaysAreNotCorrelated()
    twoRealms()
    local territoryId = at(-2, 0)

    local runs, current, previous = 0, 0, nil
    for day = 1, 300 do
        local planned = patrol.plan(territoryId, day) ~= nil
        if planned == previous then
            current = current + 1
        else
            runs = runs + 1
            current = 1
            previous = planned
        end
        expect.greater(60, current, 'no run of 60 identical days')
    end

    -- At a 0.35 chance, 300 independent days give well over fifty runs.
    -- The broken version gave two.
    expect.greater(runs, 20, 'the outcome changes often')
end

--- Two cells must not roll in lockstep, which is what a seed built from
-- the day alone would do -- the whole map would spawn on the same days
-- and stand empty between them.
function M.differentCellsRollIndependently()
    twoRealms()

    local differences = 0
    for day = 1, 60 do
        local a = patrol.plan(at(-2, 0), day) ~= nil
        local b = patrol.plan(at(-1, 0), day) ~= nil
        if a ~= b then
            differences = differences + 1
        end
    end
    expect.greater(differences, 0, 'the two cells disagree on some days')
end

--------------------------------------------------------------------------
-- Cooldown
--------------------------------------------------------------------------

function M.aRecentlyPatrolledCellStaysQuiet()
    twoRealms()
    local territoryId = at(-2, 0)
    local plan, day = firstPlan(territoryId)
    expect.truthy(plan, 'a patrol to start from')

    expect.isNil(patrol.plan(territoryId, day, { lastSpawnedDay = day }),
        'not the same day')
    expect.isNil(patrol.plan(territoryId, day + config.PATROL_COOLDOWN_DAYS - 1,
        { lastSpawnedDay = day }), 'not before the cooldown is up')
end

function M.theCooldownExpires()
    twoRealms()
    local territoryId = at(-2, 0)
    local _, day = firstPlan(territoryId)

    local after = day + config.PATROL_COOLDOWN_DAYS
    local resumed = firstPlan(territoryId, after)
    expect.truthy(resumed, 'patrols resume once the cooldown is up')
    expect.truthy(patrol.plan(territoryId, resumed.day, { lastSpawnedDay = day }) ~= nil,
        'and the cooldown no longer blocks it')
end

--------------------------------------------------------------------------
-- Edges
--------------------------------------------------------------------------

function M.unknownTerritoriesPlanNothing()
    twoRealms()
    expect.isNil(patrol.plan('no such place', 1), 'no error, no plan')
end

function M.unclaimedGroundNobodyReachesIsQuiet()
    twoRealms()
    -- Strip everyone's power, so nothing projects anywhere and no cell
    -- has an owner to patrol it.
    for _, id in ipairs(registry.sortedFactionIds()) do
        power.set(id, 0)
    end
    resolve.invalidateProjections()
    resolve.run(1)

    expect.isNil(firstPlan(at(0, 0)), 'empty ground stays empty')
end

return M
