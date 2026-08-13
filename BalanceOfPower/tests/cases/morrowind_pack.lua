-- The real Morrowind content pack, loaded exactly as the engine would.
--
-- These tests require the pack's own main.lua against a stubbed
-- openmw.interfaces, so what runs here is the shipping code path: the
-- real settlement data, the real faction list, the real registration
-- order, and the real frontier generation. Anything that would blow up
-- on a live load should blow up here first.

local expect = require('support.expect')

local world = require('openmw.world')

local power = require('scripts.BalanceOfPower.core.power')
local registry = require('scripts.BalanceOfPower.core.registry')
local resolve = require('scripts.BalanceOfPower.core.resolve')
local state = require('scripts.BalanceOfPower.core.state')

local M = {}

-- A generous rectangle covering both Vvardenfell and Solstheim at its
-- Anthology position. Real content defines far fewer cells than this --
-- most of the sea has no cell record at all -- so anything measured
-- against this grid is a worst case, not an estimate.
local function loadPack()
    world._test.defineExteriorGrid(-22, 22, -18, 36)
    require('scripts.BalanceOfPowerMorrowind.main')
    state.fillDefaults(registry)
end

--------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------

function M.loadsWithoutError()
    loadPack()
    expect.truthy(registry.landmasses.vvardenfell, 'vvardenfell registered')
    expect.truthy(registry.landmasses.solstheim, 'solstheim registered')
    expect.truthy(registry.invasions.sixth_house, 'sixth house registered')
end

function M.registersEverySettlementAsAnAnchorOrPowerCentre()
    loadPack()
    -- 36 contestable settlements out of 63, per the build script.
    expect.equal(#registry.anchorIds, 36, 'anchors')
end

function M.hasNoReferenceProblems()
    loadPack()
    expect.equal(registry.validateReferences(), 0, 'reference problems')
end

--- The Empire garrisons forts across Vvardenfell and Fort Frostmoth on
-- Solstheim. Both have to project at once, which is the whole reason
-- `extend` exists.
function M.mergesFactionsAcrossLandmasses()
    loadPack()

    local empire = registry.factions['imperial legion']
    expect.truthy(empire, 'the Empire is registered')

    local landmasses = {}
    for _, centre in ipairs(empire.powerCenters) do
        landmasses[centre.landmass] = true
    end
    expect.truthy(landmasses.vvardenfell, 'holds ground on Vvardenfell')
    expect.truthy(landmasses.solstheim, 'and on Solstheim')
end

--- Guilds have standing but no geography. If one ever acquires a power
-- center, something has mis-mapped a settlement onto it.
function M.powerOnlyFactionsHoldNothing()
    loadPack()

    for _, id in ipairs({ 'fighters guild', 'mages guild', 'thieves guild',
                          'imperial cult', 'camonna tong', 'morag tong' }) do
        local faction = registry.factions[id]
        expect.truthy(faction, id .. ' is registered')
        expect.falsy(faction.territorial, id .. ' holds no land')
        expect.count(faction.powerCenters, 0, id .. ' has no power centres')
        expect.greater(power.getLive(id), 0, id .. ' still has standing')
    end
end

--- Every faction the settlement list names must exist in factions.lua,
-- or a settlement would project for nobody.
function M.everySettlementFactionIsDefined()
    loadPack()

    for _, territoryId in ipairs(registry.anchorIds) do
        local territory = registry.territories[territoryId]
        if territory.defaultOwner then
            expect.truthy(registry.factions[territory.defaultOwner],
                territoryId .. ' has a defined owner')
        end
    end
end

--------------------------------------------------------------------------
-- Geography
--------------------------------------------------------------------------

function M.placesKnownSettlementsInTheRightCells()
    loadPack()

    expect.equal(registry.territoryForCell('#-3,-2').id, 'balmora', 'Balmora')
    expect.equal(registry.territoryForCell('#-2,6').id, 'ald_ruhn', 'Ald-Ruhn')
    expect.equal(registry.territoryForCell('#18,4').id, 'sadrith_mora', 'Sadrith Mora')
    expect.equal(registry.territoryForCell('#-17,25').id, 'raven_rock', 'Raven Rock')
end

--- Vivec covers fifteen cells and must be a single anchor over all of
-- them, not fifteen adjacent ones fighting each other.
function M.keepsMultiCellSettlementsWhole()
    loadPack()

    local vivec = registry.territories.vivec
    expect.truthy(vivec, 'Vivec registered')
    expect.count(vivec.cells, 15, 'all fifteen cells')
    expect.equal(vivec.tier, 'metropolis', 'tier')
    -- Projecting from the mean of the footprint, not from a corner.
    expect.equal(registry.territoryForCell('#3,-9').id, 'vivec', 'northern district')
    expect.equal(registry.territoryForCell('#4,-14').id, 'vivec', 'southern district')
end

function M.assignsSolstheimToItsOwnLandmass()
    loadPack()

    expect.equal(registry.territories.raven_rock.landmass, 'solstheim', 'Raven Rock')
    expect.equal(registry.territories.skaal.landmass, 'solstheim', 'Skaal Village')
    expect.equal(registry.territories.balmora.landmass, 'vvardenfell', 'Balmora')
end

--------------------------------------------------------------------------
-- The derived map
--------------------------------------------------------------------------

--- The phase-3 promise: no ownership is authored anywhere except the
-- invasion homeland, and a sensible political map falls out of where the
-- settlements are.
function M.derivesAStartingMapFromSettlementsAlone()
    loadPack()
    resolve.assignInitialControl()

    local owned = {}
    for _, id in ipairs(registry.anchorIds) do
        local owner = state.getOwner(id)
        if owner then
            owned[owner] = (owned[owner] or 0) + 1
        end
    end

    -- Lore placement, derived rather than authored.
    expect.equal(state.getOwner('balmora'), 'hlaalu', 'Balmora is Hlaalu')
    expect.equal(state.getOwner('ald_ruhn'), 'redoran', 'Ald-Ruhn is Redoran')
    expect.equal(state.getOwner('sadrith_mora'), 'telvanni', 'Sadrith Mora is Telvanni')
    expect.equal(state.getOwner('vivec'), 'temple', 'Vivec is the Temple')
    expect.equal(state.getOwner('raven_rock'), 'east empire company', 'Raven Rock is the EEC')
    expect.equal(state.getOwner('skaal'), 'skaal', 'Skaal Village is the Skaal')

    expect.greater(owned.hlaalu or 0, 0, 'Hlaalu hold something')
    expect.greater(owned.redoran or 0, 0, 'Redoran hold something')
    expect.greater(owned.telvanni or 0, 0, 'Telvanni hold something')
end

--- An authored owner overrides projection. Without that, Red Mountain
-- would fall to whichever Great House happened to out-project a faction
-- starting at 30 power, which is the opposite of the intended story.
function M.leavesTheInvaderHomelandWithTheInvader()
    loadPack()
    resolve.assignInitialControl()

    expect.equal(state.getOwner('dagoth_ur'), 'sixth house', 'Red Mountain')
end

--- Sieges only work if anchors know their surrounding cells, and packs
-- can't name generated cells themselves. If this regresses, settlements
-- silently become untakeable.
function M.givesSettlementsARing()
    loadPack()

    local ringless = {}
    for _, id in ipairs(registry.anchorIds) do
        if #registry.territories[id].adjacentFrontier == 0 then
            ringless[#ringless + 1] = id
        end
    end
    expect.count(ringless, 0, 'anchors with no surrounding frontier: '
        .. table.concat(ringless, ', '))
end

--------------------------------------------------------------------------
-- Scale
--------------------------------------------------------------------------

--- The frontier grid is the thing most likely to become a performance
-- problem (design doc 7). This is a worst case: the stub defines every
-- cell in a rectangle covering both islands, where real content leaves
-- most of the sea undefined. If this number climbs a lot, the lever is
-- FRONTIER_CELLS_PER_UNIT.
function M.staysWithinAWorkableNumberOfTerritories()
    loadPack()

    local total = #registry.anchorIds + #registry.frontierIds
    expect.greater(total, 100, 'a real map was generated')
    expect.greater(4000, total, 'territory count stays workable, got ' .. total)
end

--- What actually costs time each day is evaluating factions per
-- territory. The projection cache reduces that to the factions that can
-- physically reach each cell, which should be a small number.
function M.keepsPerTerritoryReachSmall()
    loadPack()

    local worst, total = 0, 0
    for _, id in ipairs(registry.frontierIds) do
        local reach = #resolve.projectionFactors(registry.territories[id]).ids
        total = total + reach
        if reach > worst then
            worst = reach
        end
    end

    local average = total / math.max(1, #registry.frontierIds)
    expect.greater(6, average, 'average factions per cell stays low, got ' .. average)
    expect.greater(10, worst, 'worst cell stays bounded, got ' .. worst)
end

return M
