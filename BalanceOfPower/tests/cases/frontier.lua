-- Frontier grid generation.

local expect = require('support.expect')

local world = require('openmw.world')

local config = require('scripts.BalanceOfPower.core.config')
local frontier = require('scripts.BalanceOfPower.core.frontier')
local registry = require('scripts.BalanceOfPower.core.registry')
local resolve = require('scripts.BalanceOfPower.core.resolve')
local state = require('scripts.BalanceOfPower.core.state')

local M = {}

local CELL = config.CELL_SIZE

--------------------------------------------------------------------------
-- Fixtures
--------------------------------------------------------------------------

local function cellCentre(gridX, gridY)
    return { x = gridX * CELL + CELL / 2, y = gridY * CELL + CELL / 2 }
end

--- One settlement at the origin with a two-cell reach, on a defined
-- 11x11 grid of exterior cells.
local function oneSettlement(overrides)
    overrides = overrides or {}
    world._test.defineExteriorGrid(-5, 5, -5, 5, overrides.region)

    registry.registerLandmass({
        id = 'testland',
        factions = {
            {
                id = 'alpha',
                basePower = 50,
                powerCenters = {
                    {
                        id = 'alpha_seat',
                        tier = 'capital',
                        coords = cellCentre(0, 0),
                        influenceRange = overrides.range or (2 * CELL),
                    },
                },
            },
        },
        territories = overrides.anchors,
    })
    state.fillDefaults(registry)
end

local function generate(extra)
    local def = { landmass = 'testland', margin = 0 }
    for key, value in pairs(extra or {}) do
        def[key] = value
    end
    return frontier.generate(def)
end

--------------------------------------------------------------------------
-- Shape of the generated region
--------------------------------------------------------------------------

function M.generatesCellsWithinReach()
    oneSettlement()
    local created = generate()

    expect.greater(created, 0, 'cells created')
    expect.equal(#registry.frontierIds, created, 'all registered as frontier')
    expect.truthy(registry.territoryForCell('#0,0'), 'the seat itself')
    expect.truthy(registry.territoryForCell('#1,0'), 'one cell out')
    -- Two cells out is exactly at the range, where influence is already
    -- zero -- so it is deliberately not generated. See below.
end

--- Influence decays to exactly zero at influenceRange, so a cell sitting
-- on the boundary could never be held by anybody. Generating it would
-- add a territory that is carried in every save and iterated every day
-- and ownable by no one; on the Morrowind pack that mistake accounted
-- for 482 of 904 cells.
function M.generatesNoCellNobodyCanEverHold()
    oneSettlement()
    generate()

    expect.isNil(registry.territoryForCell('#2,0'), 'the zero-influence boundary')

    for _, id in ipairs(registry.frontierIds) do
        local reach = resolve.projectionFactors(registry.territories[id])
        expect.greater(#reach.ids, 0, id .. ' is reachable by somebody')
    end
end

--- The whole point of generating from settlements rather than a bounding
-- box: ground nobody can reach never becomes territory at all, so the
-- daily pass is small by construction and the save stays proportional to
-- the inhabited world.
function M.leavesUnreachableGroundUngenerated()
    oneSettlement()
    generate()

    expect.isNil(registry.territoryForCell('#5,5'), 'far corner not generated')
    expect.isNil(registry.territoryForCell('#4,0'), 'beyond the influence range')
end

--- The region is a disc, not the bounding square of one.
function M.generatesARoundRegion()
    oneSettlement({ range = 3 * CELL })
    generate()

    expect.truthy(registry.territoryForCell('#2,0'), 'on the axis, within range')
    -- Inside the bounding box the generator scans, but outside the disc.
    expect.isNil(registry.territoryForCell('#3,3'), 'diagonal corner is out of range')
end

--- A grid position the content files don't define is open water or off
-- the edge of the world. Generating territory there would put the Sea of
-- Ghosts into the simulation.
function M.skipsCellsThatDoNotExist()
    world._test.defineExteriorGrid(0, 1, 0, 0)   -- only two cells exist
    registry.registerLandmass({
        id = 'testland',
        factions = {
            {
                id = 'alpha',
                basePower = 50,
                powerCenters = {
                    { id = 'seat', tier = 'capital',
                      coords = cellCentre(0, 0), influenceRange = 3 * CELL },
                },
            },
        },
    })
    state.fillDefaults(registry)

    local created = generate()

    expect.equal(created, 2, 'only the defined cells')
    expect.truthy(registry.territoryForCell('#1,0'), 'defined cell')
    expect.isNil(registry.territoryForCell('#0,1'), 'undefined cell')
end

function M.respectsGranularity()
    oneSettlement({ range = 4 * CELL })
    local fine = generate()

    -- A fresh registry isn't available inside one test, so compare
    -- against a second landmass generated at a coarser grain.
    expect.greater(fine, 0, 'fine grid')

    registry.registerLandmass({
        id = 'coarseland',
        factions = {
            {
                id = 'beta',
                basePower = 50,
                powerCenters = {
                    { id = 'beta_seat', tier = 'capital',
                      coords = cellCentre(0, 0), influenceRange = 4 * CELL,
                      landmass = 'coarseland' },
                },
            },
        },
    })
    local coarse = frontier.generate({
        landmass = 'coarseland', margin = 0, cellsPerUnit = 3, idPrefix = 'coarse',
    })

    expect.greater(fine, coarse, 'a coarser grid yields fewer territories')
end

--------------------------------------------------------------------------
-- Interaction with settlements
--------------------------------------------------------------------------

--- A settlement already owns its cells; the wilderness grid must not
-- register a second territory over the top of them.
function M.doesNotOverlapSettlementCells()
    oneSettlement({
        anchors = {
            {
                id = 'town',
                tier = 'town',
                cells = { '#0,0', '#1,0' },
                centroid = cellCentre(0, 0),
            },
        },
    })
    generate()

    expect.equal(registry.territoryForCell('#0,0').id, 'town', 'settlement keeps its cell')
    expect.equal(registry.territoryForCell('#1,0').id, 'town', 'and its second cell')
    expect.equal(registry.territories.town.kind, 'anchor', 'still an anchor')
end

--- Anchors are registered before the frontier exists, so a pack cannot
-- name generated cells in its own adjacentFrontier. The generator has to
-- make that link itself -- without it no anchor is ever surrounded and
-- no siege can begin, which would quietly disable half the simulation.
function M.wiresAnchorsToTheirSurroundingCells()
    oneSettlement({
        anchors = {
            {
                id = 'town',
                tier = 'town',
                cells = { '#0,0' },
                centroid = cellCentre(0, 0),
            },
        },
    })
    generate()

    local ring = registry.territories.town.adjacentFrontier
    expect.greater(#ring, 0, 'the anchor was given a ring')
    for _, id in ipairs(ring) do
        expect.truthy(registry.territories[id], 'ring member ' .. id .. ' exists')
        expect.equal(registry.territories[id].kind, 'frontier', 'ring members are frontier')
    end
end

function M.wiresFrontierCellsBackToAnchors()
    oneSettlement({
        anchors = {
            {
                id = 'town',
                tier = 'town',
                cells = { '#0,0' },
                centroid = cellCentre(0, 0),
            },
        },
    })
    generate()

    local neighbour = registry.territoryForCell('#1,0')
    expect.truthy(neighbour, 'neighbouring cell generated')
    expect.equal(neighbour.adjacentAnchors[1], 'town', 'knows which settlement it rings')
end

--------------------------------------------------------------------------
-- Data hygiene
--------------------------------------------------------------------------

--- Cells at the edge of the generated region have neighbours that were
-- never created. Emitting those as adjacency would leave hundreds of
-- dangling references for the reference check to complain about.
function M.producesNoDanglingReferences()
    oneSettlement({
        anchors = {
            {
                id = 'town',
                tier = 'town',
                cells = { '#0,0' },
                centroid = cellCentre(0, 0),
            },
        },
    })
    generate()

    expect.equal(registry.validateReferences(), 0, 'reference problems')
end

function M.carriesTheRegionName()
    oneSettlement({ region = 'Bitter Coast' })
    generate()

    local cell = registry.territoryForCell('#1,0')
    expect.equal(cell.region, 'Bitter Coast', 'region carried onto the territory')
end

function M.rejectsUnregisteredLandmass()
    expect.raises(function()
        frontier.generate({ landmass = 'nowhere' })
    end, 'unregistered landmass', 'generating before registering')
end

--------------------------------------------------------------------------
-- Downstream
--------------------------------------------------------------------------

--- Generation plus derived control is the whole phase-3 promise: a pack
-- declares where the seats of power are, and a populated, owned map falls
-- out of it with no hand-authored ownership anywhere.
--
-- Note that generated and claimable are not the same set. Influence
-- decays to exactly zero at the edge of a power center's range, and the
-- generation margin deliberately reaches a little further still, so the
-- outermost ring exists but nobody can hold it yet. That's the headroom
-- a growing faction expands into.
function M.generatedCellsAreClaimedByProjection()
    oneSettlement()
    generate()
    resolve.assignInitialControl()

    local claimable, held = 0, 0
    for _, id in ipairs(registry.frontierIds) do
        local territory = registry.territories[id]
        local owner = state.getOwner(id)
        if resolve.effectivePower('alpha', territory) >= config.MIN_CLAIM_POWER then
            claimable = claimable + 1
            expect.equal(owner, 'alpha', 'reachable cell ' .. id)
        else
            expect.isNil(owner, 'unreachable cell ' .. id .. ' stays unclaimed')
        end
        if owner == 'alpha' then
            held = held + 1
        end
    end

    expect.greater(claimable, 0, 'some cells are claimable')
    expect.equal(held, claimable, 'exactly the claimable cells are held')
end

return M
