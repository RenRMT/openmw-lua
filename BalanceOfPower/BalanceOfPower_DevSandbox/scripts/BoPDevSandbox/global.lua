-- Dev sandbox: a throwaway content pack that registers just enough of a
-- world to exercise the framework, plus the global half of the debug
-- console.
--
-- This is NOT the Morrowind data pack (that's phase 3). The territory
-- graph here is small and hand-written specifically so that every code
-- path in the registry gets hit and the results stay small enough to
-- read in a log line:
--
--   * two factions that exist as real ESM faction records, so reaction
--     propagation reads live game data;
--   * one faction that does NOT exist as a record, so the authored
--     reactions fallback gets exercised;
--   * anchors of both tiers, frontier cells, and an invasion whose home
--     territory is declared before the faction that owns it exists --
--     which is the deferred-reference-check path.
--
-- Coordinates are real Vvardenfell exterior cell centres, so you can
-- walk into these cells and watch the readout change. They are only
-- approximately the right settlements; nothing here is lore-accurate
-- and none of it should survive into phase 3.

local world = require('openmw.world')
local I = require('openmw.interfaces')

local BoP = I.BalanceOfPower
if not BoP then
    error('BoPDevSandbox: the BalanceOfPower framework interface is not available. '
        .. 'Check that BalanceOfPower_Framework.omwscripts loads BEFORE this mod.', 0)
end

local CELL_SIZE = 8192

local function cellId(gridX, gridY)
    return string.format('#%d,%d', gridX, gridY)
end

local function cellCentre(gridX, gridY)
    return {
        x = gridX * CELL_SIZE + CELL_SIZE / 2,
        y = gridY * CELL_SIZE + CELL_SIZE / 2,
    }
end

--------------------------------------------------------------------------
-- Toy landmass
--------------------------------------------------------------------------

BoP.registerLandmass({
    id = 'dev_sandbox',
    displayName = 'Dev Sandbox (Vvardenfell)',

    factions = {
        {
            -- Real ESM faction record: reactions come from the game data.
            id = 'hlaalu',
            displayName = 'House Hlaalu',
            basePower = 55,
            patrolRoster = { 'hlaalu guard' },
            powerCenters = {
                { id = 'balmora_seat', tier = 'capital', coords = cellCentre(-3, -2) },
            },
        },
        {
            -- Also a real record, and the id contains a space, which is
            -- worth having in the test set.
            id = 'imperial legion',
            displayName = 'Imperial Legion',
            basePower = 50,
            patrolRoster = { 'imperial guard' },
            powerCenters = {
                { id = 'seyda_neen_garrison', tier = 'regional', coords = cellCentre(-2, -9) },
            },
        },
        {
            -- No ESM record behind this one, so power.reactionsFor falls
            -- back to the authored table. Values are how each *other*
            -- faction feels about the raiders.
            id = 'dev_raiders',
            displayName = 'Sandbox Raiders',
            basePower = 25,
            patrolRoster = { 'bandit' },
            reactions = {
                hlaalu = -3,
                ['imperial legion'] = -3,
                ['sixth house'] = 1,
            },
            powerCenters = {
                { id = 'raider_camp', tier = 'outpost', coords = cellCentre(-3, -6) },
            },
        },
    },

    territories = {
        {
            id = 'dev_balmora',
            displayName = 'Balmora',
            tier = 'city',
            cells = { cellId(-3, -2) },
            centroid = cellCentre(-3, -2),
            adjacentFrontier = { 'dev_frontier_a', 'dev_frontier_b' },
            defaultOwner = 'hlaalu',
        },
        {
            id = 'dev_seyda_neen',
            displayName = 'Seyda Neen',
            tier = 'town',
            cells = { cellId(-2, -9), 'Seyda Neen, Census and Excise Office' },
            centroid = cellCentre(-2, -9),
            adjacentFrontier = { 'dev_frontier_c', 'dev_frontier_d' },
            defaultOwner = 'imperial legion',
        },
        {
            -- Invader homeland. Its defaultOwner is registered further
            -- down by registerInvasion, i.e. after this call -- which is
            -- exactly the forward reference validateReferences exists to
            -- tolerate. If it warned about this, that would be a bug.
            id = 'dev_red_mountain',
            displayName = 'Red Mountain',
            tier = 'city',
            cells = { cellId(2, 4) },
            centroid = cellCentre(2, 4),
            defaultOwner = 'sixth house',
        },
    },

    frontier = {
        {
            id = 'dev_frontier_a',
            displayName = 'West Gash approach',
            cells = { cellId(-4, -2) },
            centroid = cellCentre(-4, -2),
            adjacentFrontier = { 'dev_frontier_b' },
            adjacentAnchors = { 'dev_balmora' },
            defaultOwner = 'hlaalu',
        },
        {
            id = 'dev_frontier_b',
            displayName = 'Odai headwaters',
            cells = { cellId(-3, -3) },
            centroid = cellCentre(-3, -3),
            adjacentFrontier = { 'dev_frontier_a', 'dev_frontier_c' },
            adjacentAnchors = { 'dev_balmora' },
            defaultOwner = 'hlaalu',
        },
        {
            id = 'dev_frontier_c',
            displayName = 'Bitter Coast north',
            cells = { cellId(-2, -8) },
            centroid = cellCentre(-2, -8),
            adjacentFrontier = { 'dev_frontier_b', 'dev_frontier_d' },
            adjacentAnchors = { 'dev_seyda_neen' },
            defaultOwner = 'imperial legion',
        },
        {
            id = 'dev_frontier_d',
            displayName = 'Bitter Coast east',
            cells = { cellId(-1, -9) },
            centroid = cellCentre(-1, -9),
            adjacentFrontier = { 'dev_frontier_c' },
            adjacentAnchors = { 'dev_seyda_neen' },
            defaultOwner = 'imperial legion',
        },
    },
})

--------------------------------------------------------------------------
-- Toy invasion
--------------------------------------------------------------------------

BoP.registerInvasion({
    id = 'dev_sixth_house',
    faction = {
        id = 'sixth house',
        displayName = 'Sixth House',
        basePower = 30,
        growthPerDay = 1.5,
        homeTerritories = { 'dev_red_mountain' },
        patrolRoster = { 'ash zombie', 'ash ghoul' },
        escalationThresholds = {
            { stage = 'stirring',    power = 30 },
            { stage = 'raiding',     power = 60 },
            { stage = 'encroaching', power = 100 },
            { stage = 'overrunning', power = 150 },
        },
        powerCenters = {
            { id = 'red_mountain_seat', tier = 'capital', coords = cellCentre(2, 4) },
        },
    },
})

--------------------------------------------------------------------------
-- Debug console (global half)
--------------------------------------------------------------------------

local function report(text)
    for _, player in ipairs(world.players) do
        player:sendEvent('BoPDev_Report', { text = text })
    end
end

--- Faction standings, one per line so it stays readable on screen.
local function standings()
    local lines = {}
    for _, id in ipairs(BoP.factionIds()) do
        local faction = BoP.getFaction(id)
        lines[#lines + 1] = string.format('%s: %.1f', faction.displayName, BoP.getPower(id))
    end
    return table.concat(lines, '\n')
end

local handlers = {}

function handlers.BoPDev_Dump()
    BoP.dump()
    report(string.format('Day %s\n%s\n(full dump in openmw.log)',
        tostring(BoP.getCurrentDay()), standings()))
end

function handlers.BoPDev_Award(data)
    local before = BoP.getPower(data.faction)
    BoP.awardPower(data.faction, data.amount, data.multiplier)
    report(string.format('%s %+.0f  (%.1f -> %.1f)\nPropagation:\n%s',
        data.faction, data.amount, before, BoP.getPower(data.faction), standings()))
end

function handlers.BoPDev_ForceDay(data)
    local day = BoP.forceDay(data.count or 1)
    report(string.format('Ran %d day(s), now day %d\n%s', data.count or 1, day, standings()))
end

--- Answers "what territory am I standing in?" for the cell watcher.
function handlers.BoPDev_WhereAmI(data)
    local territory = BoP.getTerritoryForCell(data.cell)
    if not territory then
        report(string.format('%s: no registered territory', data.cell))
        return
    end
    local owner = BoP.getOwner(territory.id)
    local ownerFaction = owner and BoP.getFaction(owner)
    report(string.format('%s (%s)\nowner: %s%s',
        territory.displayName,
        territory.kind == 'anchor' and territory.tier or 'frontier',
        ownerFaction and ownerFaction.displayName or (owner or 'unclaimed'),
        BoP.isCorrupted(territory.id) and '  [CORRUPTED]' or ''))
end

--- Deliberately bad registration, to check that validation fires and
-- that a failed pack doesn't take the framework down with it.
function handlers.BoPDev_BadRegister()
    local ok, err = pcall(function()
        BoP.registerLandmass({
            id = 'dev_broken',
            factions = { { id = 'hlaalu' } },  -- already registered, no extend
        })
    end)
    if ok then
        report('ERROR: the bad registration was accepted')
        return
    end
    -- The framework should still be intact: the rejected pack must not
    -- have half-registered, and Hlaalu must still be exactly as it was.
    report(string.format('Rejected as expected:\n%s\n\nFramework still live:\n%s',
        tostring(err), standings()))
end

return {
    eventHandlers = handlers,
}
