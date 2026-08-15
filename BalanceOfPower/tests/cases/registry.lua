-- Registration, validation and cross-pack merging.

local expect = require('support.expect')

local core = require('openmw.core')

local registry = require('scripts.BalanceOfPower.core.registry')
local state = require('scripts.BalanceOfPower.core.state')

local M = {}

--------------------------------------------------------------------------
-- Fixtures
--------------------------------------------------------------------------

-- The record supplies the display name. No reactions, so it does not
-- auto-register and the pack's entry is what lands.
local function hlaaluRecord()
    core._test.setFactionRecords({ hlaalu = { name = 'House Hlaalu', reactions = {} } })
end

local function hlaalu(overrides)
    hlaaluRecord()
    local faction = {
        id = 'hlaalu',
        basePower = 50,
        patrolRoster = { 'hlaalu guard' },
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
                tier = 'small city',
                faction = 'hlaalu',
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
                tier = 'small city',
                faction = 'hlaalu',
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

    -- One tier now supplies all three: how far the place reaches, how
    -- hard it is to shift, and how strongly it projects.
    local seat = registry.factions.hlaalu.seats[1]
    expect.equal(seat.id, 'balmora', 'the settlement is the seat')
    expect.greater(seat.influenceRange, 0, 'influenceRange default')
    expect.equal(seat.weight, 0.75, 'small city weight default')

    local city = registry.territories['balmora_-3_-2']
    expect.greater(city.cooldownDays, 0, 'cooldownDays default')

    -- Tier also has to survive registration as metadata: an extension
    -- needs to know Balmora is a city without counting cells.
    expect.equal(city.tier, 'small city', 'tier is carried')
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

--- One id twice in one definition is an authoring mistake; the same id
-- from two packs is ordinary and merges.
function M.rejectsTheSameFactionTwiceInOneDefinition()
    expect.raises(function()
        registry.registerLandmass(minimalLandmass({
            factions = { hlaalu(), hlaalu() },
        }))
    end, 'twice in the same definition', 'duplicate faction')
end

function M.rejectsUnknownTier()
    expect.raises(function()
        registry.registerLandmass(minimalLandmass({
            territories = { { id = 'x', tier = 'imaginary', cells = { '#0,0' } } },
        }))
    end, 'unknown tier', 'bad settlement tier')
end

--- The error has to name the ladder. A tier is a word off a fixed list,
-- and "unknown tier" alone leaves a pack author guessing at spelling.
function M.namesTheTiersWhenRejectingOne()
    expect.raises(function()
        registry.registerLandmass(minimalLandmass({
            territories = { { id = 'x', tier = 'imaginary', cells = { '#0,0' } } },
        }))
    end, 'megalopolis', 'lists the valid tiers')
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

--- A faction spanning two packs holds seats in both, and needs no
-- declaration to do it: a settlement names its faction, so the second
-- landmass's holdings attach themselves. A second entry adds roster.
function M.aFactionGainsSeatsFromEveryPack()
    registry.registerLandmass(minimalLandmass())
    registry.registerLandmass({
        id = 'tamriel_rebuilt',
        factions = {
            { id = 'hlaalu', patrolRoster = { 'hlaalu guard', 'hlaalu councilor' } },
        },
        territories = {
            { id = 'bal_foyen', tier = 'town', faction = 'hlaalu', cells = { '#12,0' } },
        },
    })

    local faction = registry.factions.hlaalu
    expect.count(faction.seats, 2, 'seats from both packs')
    -- Appended, not replaced: the original city must survive.
    expect.equal(faction.seats[1].id, 'balmora', 'original seat')
    expect.equal(faction.seats[2].id, 'bal_foyen', 'added seat')
    -- Roster merge de-duplicates rather than appending blindly.
    expect.count(faction.patrolRoster, 2, 'merged roster')
end

--- Which pack won would otherwise depend on load order.
function M.theFirstPackToSetAScalarKeepsIt()
    registry.registerLandmass(minimalLandmass())
    registry.registerLandmass({
        id = 'tamriel_rebuilt',
        factions = { { id = 'hlaalu', basePower = 999, growthPerDay = 7 } },
    })

    local faction = registry.factions.hlaalu
    expect.equal(faction.basePower, 50, 'basePower stays with the first pack')
    -- Nobody set growthPerDay first, so the second pack's value lands.
    expect.equal(faction.growthPerDay, 7, 'an unclaimed field is still settable')
end

--- `extend` is obsolete. An entry carrying it still registers, because
-- silently dropping a pack's faction would be worse than ignoring a flag.
function M.toleratesTheObsoleteExtendFlag()
    registry.registerLandmass(minimalLandmass())
    registry.registerLandmass({
        id = 'tamriel_rebuilt',
        factions = { { id = 'hlaalu', extend = true, patrolRoster = { 'hlaalu councilor' } } },
    })

    expect.count(registry.factions.hlaalu.patrolRoster, 2, 'roster still merged')
end

--------------------------------------------------------------------------
-- Factions from the game's records
--------------------------------------------------------------------------

--- The framework registers what the records describe; a pack declaring a
-- faction list is adding tuning, not creating factions.
function M.registersFactionsFromTheGameRecords()
    core._test.setFactionRecords({
        Hlaalu = { name = 'Great House Hlaalu', reactions = { Redoran = -1 } },
        Redoran = { name = 'Great House Redoran', reactions = { Hlaalu = -1 } },
    })
    registry.registerLandmass({ id = 'vvardenfell' })

    expect.equal(registry.countFactions(), 2, 'both records registered')
    expect.equal(registry.factions.hlaalu.displayName, 'Great House Hlaalu', 'name from the record')
    expect.falsy(registry.factions.hlaalu.territorial, 'no seats, so power-only')
end

--- Content files keep dead ids alive so old saves load. Tamriel Data
-- ships a dozen, all named "<Deprecated>" with an empty row and no
-- column; without the filter every one appears in the standings.
function M.skipsRecordsNobodyHasAnOpinionAboutOrFrom()
    core._test.setFactionRecords({
        Hlaalu = { name = 'Great House Hlaalu', reactions = { Redoran = -1 } },
        Redoran = { name = 'Great House Redoran', reactions = { Hlaalu = -1 } },
        T_Mw_HouseHlaalu = { name = '<Deprecated>', reactions = {} },
        -- A row of nothing but zeros is not participation either.
        Bystander = { name = 'Bystander', reactions = { Hlaalu = 0 } },
    })
    registry.registerLandmass({ id = 'vvardenfell' })

    expect.equal(registry.countFactions(), 2, 'only the two with real opinions')
    expect.isNil(registry.factions.t_mw_househlaalu, 'the tombstone was skipped')
    expect.isNil(registry.factions.bystander, 'an all-zero row is not participation')
end

--- A faction named by somebody, with no row of its own, still takes part.
-- The Nerevarine is the vanilla case: its record carries no reactions at
-- all while Redoran and the Temple carry large ones toward it.
function M.registersARecordThatOnlyOthersHaveOpinionsAbout()
    core._test.setFactionRecords({
        Redoran = { name = 'Great House Redoran', reactions = { Nerevarine = -4 } },
        Nerevarine = { name = 'Nerevarine', reactions = {} },
    })
    registry.registerLandmass({ id = 'vvardenfell' })

    expect.truthy(registry.factions.nerevarine, 'registered from its column alone')
end

--- The filter is a default for what the records supply, never a veto on
-- a pack. The Morag Tong has no politics at all and still needs to exist.
function M.anExplicitEntryBeatsTheParticipationFilter()
    core._test.setFactionRecords({
        ['Morag Tong'] = { name = 'Morag Tong', reactions = {} },
    })
    registry.registerLandmass({
        id = 'vvardenfell',
        factions = { { id = 'morag tong', basePower = 20 } },
    })

    expect.truthy(registry.factions['morag tong'], 'the pack registered it anyway')
    expect.equal(registry.factions['morag tong'].displayName, 'Morag Tong', 'name from the record')
end

--- A faction the game has never heard of. A pack modelling something
-- with no record still gets a faction, it just has no politics.
function M.registersAFactionWithNoRecordBehindIt()
    core._test.setFactionRecords({})
    registry.registerLandmass({
        id = 'vvardenfell',
        factions = { { id = 'invented', basePower = 40 } },
    })

    local faction = registry.factions.invented
    expect.truthy(faction, 'registered')
    expect.equal(faction.displayName, 'invented', 'falls back to the id')
end

--- Derived, not authored: a faction is territorial once something names
-- it, and a later pack's settlements can promote one.
function M.territorialIsDerivedFromSeats()
    registry.registerLandmass({
        id = 'vvardenfell',
        factions = { { id = 'hlaalu', basePower = 50 } },
    })
    expect.falsy(registry.factions.hlaalu.territorial, 'no seats yet')

    registry.registerLandmass({
        id = 'tamriel_rebuilt',
        territories = {
            { id = 'bal_foyen', tier = 'town', faction = 'hlaalu', cells = { '#12,0' } },
        },
    })
    expect.truthy(registry.factions.hlaalu.territorial, 'a seat made it territorial')
end

function M.rejectsFieldsTheRecordsOwn()
    for _, field in ipairs({ 'displayName', 'territorial', 'reactions' }) do
        expect.raises(function()
            registry.registerLandmass({
                id = 'vvardenfell_' .. field,
                factions = { { id = 'hlaalu', [field] = field == 'territorial' and false or {} } },
            })
        end, field, 'authored ' .. field)
    end
end

--- Two packs claiming one settlement id is a collision whichever pack
-- got there first, and it has to be an error rather than a silent
-- overwrite: the loser's cells would keep pointing at a place that no
-- longer describes them.
function M.rejectsDuplicateSettlementAcrossPacks()
    registry.registerLandmass(minimalLandmass())

    expect.raises(function()
        registry.registerLandmass({
            id = 'tamriel_rebuilt',
            factions = { { id = 'hlaalu', extend = true } },
            territories = {
                { id = 'balmora', tier = 'town', faction = 'hlaalu', cells = { '#12,0' } },
            },
        })
    end, 'already registered', 'duplicate settlement id across packs')
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
