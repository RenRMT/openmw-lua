-- The real Morrowind content pack, loaded exactly as the engine would.
--
-- These tests require the pack's own main.lua against a stubbed
-- openmw.interfaces, so what runs here is the shipping code path: the
-- real settlement data, the real faction list, the real registration
-- order, and the real frontier generation. Anything that would blow up
-- on a live load should blow up here first.

local expect = require('support.expect')

local world = require('openmw.world')

local api = require('scripts.BalanceOfPower.core.api')
local cells = require('scripts.BalanceOfPower.core.cells')
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

--- The pack must take the cell size from the framework, not write 8192
-- down a second time. If the two ever disagree, settlement centroids
-- land off the grid the frontier generator lays down -- a map subtly out
-- of register with its own settlements, and nothing to catch it.
function M.takesTheCellSizeFromTheFramework()
    loadPack()

    local size = api.CELL_SIZE
    expect.equal(size, 8192, 'the ESM3 grid the engine works in')

    -- Every anchor's centroid must be the mean of its cells' middles,
    -- measured in the framework's cell size. Checked across all of them,
    -- since a wrong constant shows up as a proportional error that a
    -- single-cell settlement near the origin could hide.
    for _, id in ipairs(registry.anchorIds) do
        local territory = registry.territories[id]
        local sumX, sumY = 0, 0
        for _, name in ipairs(territory.cells) do
            local gridX, gridY = cells.parse(name)
            sumX = sumX + gridX * size + size / 2
            sumY = sumY + gridY * size + size / 2
        end
        local count = #territory.cells
        expect.near(territory.centroid.x, sumX / count, 1e-6, id .. ' centroid x')
        expect.near(territory.centroid.y, sumY / count, 1e-6, id .. ' centroid y')
    end
end

--- Refusing to guess is the point: a pack that can't reach the framework
-- constant must fail loudly rather than fall back to a literal.
function M.refusesToPlanWithoutACellSize()
    expect.raises(function()
        require('scripts.BalanceOfPowerMorrowind.data.build').plan({}, nil)
    end, 'cell size', 'no silent default')
end

--------------------------------------------------------------------------
-- Politics
--------------------------------------------------------------------------

--- Every faction must be wired into the reaction table in both
-- directions. The outbound half was always visible -- a faction that
-- moves nobody produces a warning. The inbound half is the one that
-- hides: four factions here (the Company, the Skaal, the Ashlanders and
-- the Sixth House) have no ESM record, so nothing in the game's own data
-- can name them, and without an authored row on the other side their
-- standing would never move for any reason but a direct award.
--
-- This runs against an empty record stub, which is the worst case: if it
-- passes here, the authored rows alone are enough, and whatever the
-- game's records add in play is a bonus.
function M.wiresEveryFactionIntoThePoliticsBothWays()
    loadPack()

    local mute, deaf = {}, {}
    for _, row in ipairs(power.reactionAudit()) do
        if row.moves == 0 then
            mute[#mute + 1] = row.id
        end
        if row.movedBy == 0 then
            deaf[#deaf + 1] = row.id
        end
    end

    expect.count(mute, 0, 'factions that move nobody: ' .. table.concat(mute, ', '))
    expect.count(deaf, 0, 'factions nobody reacts to: ' .. table.concat(deaf, ', '))
end

--- The invasion's whole economy, and the reason it needs no special
-- casing: everyone hates the Sixth House, so its growth is automatically
-- everyone else's loss.
function M.makesTheSixthHouseEveryonesProblem()
    loadPack()

    local others = {}
    for _, id in ipairs(registry.sortedFactionIds()) do
        if id ~= 'sixth house' then
            others[#others + 1] = id
        end
    end

    local before = {}
    for _, id in ipairs(others) do
        before[id] = power.getLive(id)
    end

    power.apply('sixth house', 20)

    for _, id in ipairs(others) do
        expect.greater(before[id], power.getLive(id),
            id .. ' loses standing when the Sixth House grows')
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
