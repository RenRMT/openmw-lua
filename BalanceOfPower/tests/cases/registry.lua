-- Registration, validation and cross-pack merging.

local expect = require('support.expect')

local registry = require('scripts.BalanceOfPower.core.registry')
local state = require('scripts.BalanceOfPower.core.state')

local M = {}

--------------------------------------------------------------------------
-- Fixtures
--------------------------------------------------------------------------

local function hlaalu(overrides)
    local faction = {
        id = 'hlaalu',
        displayName = 'House Hlaalu',
        basePower = 50,
        patrolRoster = { 'hlaalu guard' },
        powerCenters = {
            { id = 'balmora', tier = 'capital', coords = { x = 0, y = 0 } },
        },
    }
    for key, value in pairs(overrides or {}) do
        faction[key] = value
    end
    return faction
end

local function minimalLandmass(overrides)
    local def = {
        id = 'vvardenfell',
        factions = { hlaalu() },
        territories = {
            {
                id = 'balmora',
                tier = 'city',
                cells = { '#-3,-2' },
                centroid = { x = 0, y = 0 },
                adjacentFrontier = { 'west_gash' },
                defaultOwner = 'hlaalu',
            },
        },
        frontier = {
            {
                id = 'west_gash',
                centroid = { x = 8192, y = 0 },
                cells = { '#-4,-2' },
                adjacentSettlements = { 'balmora' },
            },
        },
    }
    for key, value in pairs(overrides or {}) do
        def[key] = value
    end
    return def
end

--------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------

function M.registersFactionsAndTerritories()
    registry.registerLandmass(minimalLandmass())

    expect.equal(registry.countFactions(), 1, 'faction count')
    expect.equal(#registry.settlementIds, 1, 'settlement count')
    expect.equal(#registry.settlementCellIds, 1, 'settlement cell count')
    expect.equal(#registry.frontierIds, 1, 'frontier count')
    expect.equal(registry.factions.hlaalu.displayName, 'House Hlaalu', 'display name')
    expect.equal(registry.territories['balmora_-3_-2'].kind, 'settlement', 'settlement kind')
    expect.equal(registry.territories.west_gash.kind, 'frontier', 'frontier kind')
end

--- A settlement is a group, not a territory. Its cells are the ownable
-- things; the record is what carries the name and holds them together.
function M.expandsASettlementIntoOneTerritoryPerCell()
    registry.registerLandmass(minimalLandmass({
        territories = {
            {
                id = 'vivec',
                tier = 'metropolis',
                displayName = 'Vivec',
                cells = { '#3,-9', '#4,-9', '#3,-10' },
            },
        },
        frontier = {},
    }))

    local vivec = registry.settlements.vivec
    expect.truthy(vivec, 'the settlement record exists')
    expect.count(vivec.territoryIds, 3, 'one territory per cell')
    expect.isNil(registry.territories.vivec, 'the settlement is not itself a territory')

    for _, id in ipairs(vivec.territoryIds) do
        local territory = registry.territories[id]
        expect.equal(territory.settlement, 'vivec', id .. ' knows its settlement')
        expect.count(territory.cells, 1, id .. ' is exactly one cell')
        expect.equal(territory.tier, 'metropolis', id .. ' carries the tier')
    end
end

--- An interior has no grid position to project onto or from, so it never
-- becomes a territory -- but standing in one still has to report the
-- settlement it belongs to.
function M.keepsInteriorsOutOfTheTerritoryListButStillResolvesThem()
    registry.registerLandmass(minimalLandmass({
        territories = {
            {
                id = 'balmora',
                tier = 'city',
                cells = { '#-3,-2', 'Balmora, Eight Plates' },
            },
        },
        frontier = {},
    }))

    expect.count(registry.settlements.balmora.territoryIds, 1, 'only the exterior cell')
    expect.equal(registry.territoryForCell('Balmora, Eight Plates').settlement, 'balmora',
        'the interior resolves to its settlement')
end

function M.appliesTierDefaults()
    registry.registerLandmass(minimalLandmass())

    local centre = registry.factions.hlaalu.powerCenters[1]
    expect.greater(centre.influenceRange, 0, 'capital influenceRange default')
    expect.equal(centre.weight, 1.0, 'capital weight default')

    local city = registry.territories['balmora_-3_-2']
    expect.greater(city.cooldownDays, 0, 'city cooldownDays default')

    -- Tier is otherwise metadata, and has to survive registration: an
    -- extension needs to know Balmora is a city without counting cells.
    expect.equal(city.tier, 'city', 'tier is carried')
end

function M.indexesCellsToTerritories()
    registry.registerLandmass(minimalLandmass())

    expect.equal(registry.territoryForCell('#-3,-2').settlement, 'balmora',
        'settlement cell lookup')
    expect.equal(registry.territoryForCell('#-4,-2').id, 'west_gash', 'frontier cell lookup')
    expect.isNil(registry.territoryForCell('#99,99'), 'unknown cell lookup')
end

function M.treatsOmittedDefaultOwnerAsUnclaimed()
    registry.registerLandmass(minimalLandmass())
    state.fillDefaults(registry)

    expect.equal(state.getOwner('balmora_-3_-2'), 'hlaalu', 'authored owner')
    expect.isNil(state.getOwner('west_gash'), 'omitted owner')
end

--------------------------------------------------------------------------
-- Validation
--------------------------------------------------------------------------

function M.rejectsDuplicateFactionWithoutExtend()
    registry.registerLandmass(minimalLandmass())

    expect.raises(function()
        registry.registerLandmass(minimalLandmass({
            id = 'other',
            factions = { hlaalu() },
            territories = {},
            frontier = {},
        }))
    end, 'extend = true', 'duplicate faction')
end

function M.rejectsExtendBeforeDefinition()
    expect.raises(function()
        registry.registerLandmass(minimalLandmass({
            factions = { { id = 'telvanni', extend = true } },
        }))
    end, 'has not been registered yet', 'premature extend')
end

function M.rejectsUnknownTier()
    expect.raises(function()
        registry.registerLandmass(minimalLandmass({
            factions = { hlaalu({ powerCenters = {
                { id = 'x', tier = 'imaginary', coords = { x = 0, y = 0 } },
            } }) },
        }))
    end, 'unknown tier', 'bad power centre tier')
end

function M.rejectsFrontierCellWithoutCentroid()
    expect.raises(function()
        registry.registerLandmass(minimalLandmass({
            frontier = { { id = 'nowhere' } },
        }))
    end, 'centroid', 'frontier without centroid')
end

--- The two-phase property: a definition that fails validation partway
-- through must leave the registry exactly as it was. Otherwise the pack
-- can never be fixed and retried -- the retry trips over the factions
-- the failed attempt already inserted.
function M.failedRegistrationCommitsNothing()
    registry.registerLandmass(minimalLandmass())
    local factionsBefore = registry.countFactions()
    local settlementsBefore = #registry.settlementIds

    expect.raises(function()
        registry.registerLandmass({
            id = 'broken',
            factions = { { id = 'telvanni', basePower = 40 } },
            territories = {
                { id = 'sadrith_mora', cells = { '#18,4' }, defaultOwner = 'telvanni' },
            },
            -- Fails here, after a valid faction and a valid settlement have
            -- already been staged.
            frontier = { { id = 'azura_coast' } },
        })
    end, 'centroid', 'partially valid landmass')

    expect.equal(registry.countFactions(), factionsBefore, 'faction count after failure')
    expect.equal(#registry.settlementIds, settlementsBefore, 'settlement count after failure')
    expect.isNil(registry.factions.telvanni, 'faction from failed pack')
    expect.isNil(registry.landmasses.broken, 'landmass from failed pack')
    expect.isNil(registry.settlements.sadrith_mora, 'settlement from failed pack')
    expect.isNil(registry.territories['sadrith_mora_18_4'], 'its cells either')
end

--------------------------------------------------------------------------
-- Cross-pack merging
--------------------------------------------------------------------------

function M.extendMergesPowerCentresAndRoster()
    registry.registerLandmass(minimalLandmass())
    registry.registerLandmass({
        id = 'tamriel_rebuilt',
        factions = {
            {
                id = 'hlaalu',
                extend = true,
                patrolRoster = { 'hlaalu guard', 'hlaalu councilor' },
                powerCenters = {
                    { id = 'bal_foyen', tier = 'regional', coords = { x = 100000, y = 0 } },
                },
            },
        },
    })

    local faction = registry.factions.hlaalu
    expect.count(faction.powerCenters, 2, 'merged power centres')
    -- Appended, not replaced: the original capital must survive.
    expect.equal(faction.powerCenters[1].id, 'balmora', 'original power centre')
    expect.equal(faction.powerCenters[2].id, 'bal_foyen', 'added power centre')
    -- Roster merge de-duplicates rather than appending blindly.
    expect.count(faction.patrolRoster, 2, 'merged roster')
end

function M.extendDoesNotOverwriteBaseConfig()
    registry.registerLandmass(minimalLandmass())
    registry.registerLandmass({
        id = 'tamriel_rebuilt',
        factions = {
            { id = 'hlaalu', extend = true, basePower = 999, displayName = 'Usurped' },
        },
    })

    local faction = registry.factions.hlaalu
    expect.equal(faction.basePower, 50, 'basePower stays with the first pack')
    expect.equal(faction.displayName, 'House Hlaalu', 'displayName stays with the first pack')
end

function M.rejectsDuplicatePowerCentreOnExtend()
    registry.registerLandmass(minimalLandmass())

    expect.raises(function()
        registry.registerLandmass({
            id = 'tamriel_rebuilt',
            factions = {
                {
                    id = 'hlaalu',
                    extend = true,
                    powerCenters = { { id = 'balmora', coords = { x = 1, y = 1 } } },
                },
            },
        })
    end, 'duplicate power center', 'duplicate centre id across packs')
end

--------------------------------------------------------------------------
-- Deferred reference checking
--------------------------------------------------------------------------

--- A pack may legitimately name a faction or territory that a later pack
-- registers -- that's the mechanism that lets a mainland frontier cell
-- sit next to a Vvardenfell one. So the check has to run after
-- everything has loaded, and must be silent about references that
-- resolved in the meantime.
function M.toleratesForwardReferences()
    registry.registerLandmass(minimalLandmass({
        territories = {
            {
                id = 'red_mountain',
                cells = { '#6,6' },
                defaultOwner = 'sixth house',   -- registered below
            },
        },
        frontier = {},
    }))
    registry.registerLandmass({
        id = 'ashlands',
        factions = { { id = 'sixth house', basePower = 30 } },
    })

    expect.equal(registry.validateReferences(), 0, 'reference problems')
end

function M.reportsDanglingReferences()
    registry.registerLandmass(minimalLandmass({
        frontier = {
            {
                id = 'west_gash',
                centroid = { x = 8192, y = 0 },
                adjacentFrontier = { 'does_not_exist' },
                defaultOwner = 'nobody_faction',
            },
        },
    }))

    expect.equal(registry.validateReferences(), 2, 'reference problems')
end

return M
