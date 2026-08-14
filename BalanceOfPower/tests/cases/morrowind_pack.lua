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
local hostility = require('scripts.BalanceOfPower.core.hostility')
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
    expect.truthy(registry.factions['sixth house'], 'the Sixth House is an ordinary faction')
end

function M.registersEveryHoldingAsASettlementOrPowerCentre()
    loadPack()
    -- 36 settlements out of 63 holdings, per the build script.
    expect.equal(#registry.settlementIds, 36, 'settlements')
    -- And every one of their cells is a territory of its own.
    expect.greater(#registry.settlementCellIds, 36, 'settlements span more cells than that')
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

    for _, territoryId in ipairs(registry.settlementCellIds) do
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

    -- Every settlement cell's centroid is that cell's middle, measured in
    -- the framework's cell size. Checked across all of them, since a wrong
    -- constant shows up as a proportional error a cell near the origin
    -- could hide.
    for _, id in ipairs(registry.settlementCellIds) do
        local territory = registry.territories[id]
        local gridX, gridY = cells.parse(territory.cells[1])
        expect.near(territory.centroid.x, gridX * size + size / 2, 1e-6, id .. ' centroid x')
        expect.near(territory.centroid.y, gridY * size + size / 2, 1e-6, id .. ' centroid y')
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
-- directions -- with the four exceptions vanilla itself leaves out.
--
-- Being unwired is silent in play: a faction with no row of its own is
-- never moved by anything, and a faction nobody names moves nobody, and
-- neither shows up as an error. The check is therefore against a named
-- list rather than a count, so that a faction *arriving* in this state
-- fails, while the four the game genuinely leaves outside its politics
-- go on passing.
--
-- This runs against an empty record stub, which is the worst case: if it
-- passes here, the authored rows alone are enough, and whatever the
-- game's records add in play is a bonus.
function M.wiresEveryFactionIntoThePoliticsBothWays()
    loadPack()

    -- Vanilla's own gaps. The Morag Tong and the Talos Cult have an
    -- empty reaction row and an empty column; the Nerevarine reacts to
    -- nobody though Redoran and the Temple react to it; the Twin Lamps
    -- hate House Telvanni and are beneath everyone else's notice.
    local movesNobody = { ['morag tong'] = true, ['talos cult'] = true, ['twin lamps'] = true }
    local movedByNobody = { ['morag tong'] = true, ['talos cult'] = true, nerevarine = true }

    local mute, deaf = {}, {}
    for _, row in ipairs(power.reactionAudit()) do
        if row.moves == 0 and not movesNobody[row.id] then
            mute[#mute + 1] = row.id
        end
        if row.movedBy == 0 and not movedByNobody[row.id] then
            deaf[#deaf + 1] = row.id
        end
    end

    expect.count(mute, 0, 'factions that move nobody: ' .. table.concat(mute, ', '))
    expect.count(deaf, 0, 'factions nobody reacts to: ' .. table.concat(deaf, ', '))
end

--- The invasion's whole economy, and the reason it needs no special
-- casing: nearly everyone hates the Sixth House, so its growth is
-- automatically their loss.
--
-- Driven off each faction's own regard rather than a list, which makes
-- this a test of the wiring instead of a restatement of the data: every
-- faction that has an opinion must move by it, and the handful vanilla
-- leaves indifferent must not move at all. It also pins the direction --
-- were the table read backwards, what moved here would be the factions
-- the Sixth House has opinions *about*, which is very nearly but not
-- quite the same set.
function M.makesTheSixthHouseEveryonesProblem()
    loadPack()

    local others, before = {}, {}
    for _, id in ipairs(registry.sortedFactionIds()) do
        if id ~= 'sixth house' then
            others[#others + 1] = id
            before[id] = power.getLive(id)
        end
    end

    power.apply('sixth house', 20)

    local moved = 0
    for _, id in ipairs(others) do
        if power.regardOf(id, 'sixth house') < 0 then
            expect.greater(before[id], power.getLive(id),
                id .. ' loses standing when the Sixth House grows')
            moved = moved + 1
        else
            expect.equal(power.getLive(id), before[id],
                id .. ' has no opinion, so it does not move')
        end
    end

    expect.greater(moved, 15, 'and it is most of the world, not a handful')
end

--- Authored faction fields have to survive the trip through build.lua,
-- which assembles the registration call. They did not: it copied a
-- hand-listed set of fields and dropped patrolRoster on the floor, so
-- the roster validated at registration, appeared in the data file, and
-- never reached the registry. Nothing anywhere reported it.
--
-- The general assertion rather than one about rosters, because the next
-- field to be added would have gone exactly the same way.
function M.carriesAuthoredFactionFieldsThroughToTheRegistry()
    loadPack()

    local sixth = registry.factions['sixth house']
    expect.greater(#sixth.patrolRoster, 0, 'the roster arrived')
    expect.truthy(sixth.hostile, 'and so did the hostility flag')
    expect.greater(sixth.growthPerDay, 0, 'and the growth rate')
end

--- The Sixth House is the pack's only hostile faction, and it is the
-- one whose failure mode is invisible: a hostile faction with nobody it
-- hates enough looks exactly like a working one until you watch its
-- patrols stroll past a rival's. So the enemy list is pinned to the real
-- data rather than assumed from the flag.
--
-- Hostility reads how the Sixth House feels about each faction, which is
-- its own row. Reading the other faction's row instead would produce a
-- list of the same length made of nearly the same factions, which is why
-- the two -2 entries below are worth having in the fixture at all.
function M.theSixthHouseFightsEveryoneItHates()
    loadPack()

    expect.truthy(hostility.isHostileToPlayer('sixth house'), 'hostile to the player')

    local enemies = {}
    for _, id in ipairs(hostility.enemiesOf('sixth house')) do
        enemies[id] = true
    end

    expect.truthy(enemies.hlaalu, 'the houses')
    expect.truthy(enemies.redoran, 'the houses')
    expect.truthy(enemies.telvanni, 'the houses')
    expect.truthy(enemies.temple, 'and the Temple')
    expect.truthy(enemies['imperial legion'], 'and the Empire')
    expect.truthy(enemies.ashlanders, 'and the Ashlanders, who fight it in the ash')

    -- Vanilla puts the Camonna Tong at -1, alone on a row of -3s: a
    -- smuggling ring is no threat to what Dagoth Ur wants back. It is
    -- the only faction on Vvardenfell the Sixth House walks past, and
    -- the one entry here that would vanish if the threshold moved.
    expect.falsy(enemies['camonna tong'], 'the Camonna Tong are beneath its notice')
    -- Not because it likes them -- because vanilla never gave it an
    -- opinion. The distinction matters: an absent pair reads as 0.
    expect.falsy(enemies['morag tong'], 'and it has no opinion of the Morag Tong')
end

--- Nobody else is flagged, so the Great Houses go on tolerating each
-- other exactly as they do in vanilla. This is the assertion that would
-- catch a well-meaning future edit flagging a house as hostile because
-- its reaction row looked angry enough.
function M.noVanillaFactionFightsAnother()
    loadPack()

    for _, a in ipairs(registry.sortedFactionIds()) do
        for _, b in ipairs(registry.sortedFactionIds()) do
            if a ~= 'sixth house' and b ~= 'sixth house' then
                expect.falsy(hostility.willFight(a, b), a .. ' vs ' .. b)
            end
        end
    end
end

--------------------------------------------------------------------------
-- Geography
--------------------------------------------------------------------------

function M.placesKnownSettlementsInTheRightCells()
    loadPack()

    expect.equal(registry.territoryForCell('#-3,-2').settlement, 'balmora', 'Balmora')
    expect.equal(registry.territoryForCell('#-2,6').settlement, 'ald_ruhn', 'Ald-Ruhn')
    expect.equal(registry.territoryForCell('#18,4').settlement, 'sadrith_mora', 'Sadrith Mora')
    expect.equal(registry.territoryForCell('#-17,25').settlement, 'raven_rock', 'Raven Rock')
end

--- Vivec is fifteen cells, each ownable on its own, all tagged as one
-- settlement. The tag is what holds the city together now that the
-- territory is no longer the city.
function M.keepsMultiCellSettlementsTogether()
    loadPack()
    resolve.assignInitialControl()

    local vivec = registry.settlements.vivec
    expect.truthy(vivec, 'Vivec registered')
    expect.count(vivec.cells, 15, 'all fifteen cells')
    expect.count(vivec.territoryIds, 15, 'fifteen territories')
    expect.equal(vivec.tier, 'metropolis', 'tier')

    expect.equal(registry.territoryForCell('#3,-9').settlement, 'vivec', 'northern district')
    expect.equal(registry.territoryForCell('#4,-14').settlement, 'vivec', 'southern district')

    -- Separately ownable, but the garrison floor applies across the whole
    -- footprint, so in practice they move together or not at all.
    for _, id in ipairs(vivec.territoryIds) do
        expect.equal(state.getOwner(id), 'temple', id .. ' is Temple')
    end
end

function M.assignsSolstheimToItsOwnLandmass()
    loadPack()

    expect.equal(registry.settlements.raven_rock.landmass, 'solstheim', 'Raven Rock')
    expect.equal(registry.settlements.skaal.landmass, 'solstheim', 'Skaal Village')
    expect.equal(registry.settlements.balmora.landmass, 'vvardenfell', 'Balmora')
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

    local function holder(settlementId)
        return resolve.settlementOwner(registry.settlements[settlementId])
    end

    local owned = {}
    for _, id in ipairs(registry.settlementIds) do
        local owner = holder(id)
        if owner then
            owned[owner] = (owned[owner] or 0) + 1
        end
    end

    -- Lore placement, derived rather than authored.
    expect.equal(holder('balmora'), 'hlaalu', 'Balmora is Hlaalu')
    expect.equal(holder('ald_ruhn'), 'redoran', 'Ald-Ruhn is Redoran')
    expect.equal(holder('sadrith_mora'), 'telvanni', 'Sadrith Mora is Telvanni')
    expect.equal(holder('vivec'), 'temple', 'Vivec is the Temple')
    expect.equal(holder('raven_rock'), 'east empire company', 'Raven Rock is the EEC')
    expect.equal(holder('skaal'), 'skaal', 'Skaal Village is the Skaal')

    expect.greater(owned.hlaalu or 0, 0, 'Hlaalu hold something')
    expect.greater(owned.redoran or 0, 0, 'Redoran hold something')
    expect.greater(owned.telvanni or 0, 0, 'Telvanni hold something')
end

--- Red Mountain, derived rather than authored. There is no `defaultOwner`
-- anywhere in this pack now: the Sixth House holds its seat because it
-- has a power centre there and nobody else reaches it, which is the same
-- reason Hlaalu hold Balmora.
function M.leavesRedMountainWithTheSixthHouse()
    loadPack()
    resolve.assignInitialControl()

    expect.equal(resolve.settlementOwner(registry.settlements.dagoth_ur), 'sixth house',
        'Red Mountain')

    for _, id in ipairs(registry.settlementCellIds) do
        expect.isNil(registry.territories[id].defaultOwner,
            id .. ' has no authored owner')
    end
end

--- A settlement's ring is what `isSurrounded` reads, and packs can't name
-- generated cells themselves. If this regresses, no settlement can ever
-- be reported as surrounded and an extension built on that goes quiet.
function M.givesSettlementsARing()
    loadPack()

    local ringless = {}
    for _, id in ipairs(registry.settlementIds) do
        if #registry.settlements[id].adjacentFrontier == 0 then
            ringless[#ringless + 1] = id
        end
    end
    expect.count(ringless, 0, 'settlements with no surrounding frontier: '
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

    local total = #registry.settlementCellIds + #registry.frontierIds
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
