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

-- The generator plans for FRONTIER_GENERATION_POWER rather than for a
-- fixed range, so a seat's radius is however many halving distances that
-- power buys above the claim floor. These fixtures want to talk in cells,
-- so they convert -- and derive the conversion from the constants rather
-- than hard-coding it, since tuning either one otherwise silently moves
-- every expectation in this file.
local HEADROOM = math.log(config.FRONTIER_GENERATION_POWER / config.MIN_CLAIM_POWER)
    / math.log(2)

--- The halving distance whose generated radius is `cellsOut` cells, for a
-- seat of weight 1.0.
local function halvingFor(cellsOut)
    return cellsOut * CELL / HEADROOM
end

--------------------------------------------------------------------------
-- Fixtures
--------------------------------------------------------------------------

local function cellCentre(gridX, gridY)
    return { x = gridX * CELL + CELL / 2, y = gridY * CELL + CELL / 2 }
end

--- One settlement at the origin generating out to two cells, on a
-- defined 11x11 grid of exterior cells.
--- The landmass's settlements: whatever the test asked for, or a single
-- seat at the origin. Either way they are alpha's, and either way they
-- reach as far as the fixture says -- a settlement is the only thing that
-- generates a frontier, so a test supplying its own still needs one.
local function settlements(overrides)
    local list = overrides.settlements or {
        { id = 'alpha_seat', tier = 'large city', cells = { '#0,0' } },
    }
    for _, entry in ipairs(list) do
        entry.faction = entry.faction or 'alpha'
        entry.influenceRange = entry.influenceRange or overrides.range or halvingFor(2)
    end
    return list
end

local function oneSettlement(overrides)
    overrides = overrides or {}
    world._test.defineExteriorGrid(-5, 5, -5, 5, overrides.region)

    registry.registerLandmass({
        id = 'testland',
        factions = { { id = 'alpha' } },
        territories = settlements(overrides),
    })
    state.fillDefaults(registry)
    state.seedPower(registry)
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
    -- Two cells out sits exactly on the planned radius, and the disc test
    -- is strict, so it is not generated. See below.
end

--- The generated region stops at the planned radius, and everything
-- inside it is ground somebody can reach.
--
-- Note what this is *not* claiming. Nothing is unclaimable any more --
-- projection decays but never stops, so a faction that grows enough
-- reaches anywhere. The radius is how much ground the generator thinks
-- worth carrying, not a wall.
function M.generatesOnlyGroundWithinThePlannedRadius()
    oneSettlement()
    generate()

    expect.isNil(registry.territoryForCell('#2,0'), 'the planned radius')

    for _, id in ipairs(registry.frontierIds) do
        local reach = resolve.projectionFactors(registry.territories[id])
        expect.greater(#reach.ids, 0, id .. ' is reachable by somebody')
    end
end

--- Planning for more power generates more ground. This is the knob that
-- replaced the old hard range: a pack expecting its factions to grow
-- raises it rather than widening every tier.
function M.generatesFurtherWhenPlanningForMorePower()
    -- Three doublings of the planned power is three more halving
    -- distances of radius. At this fixture's scale -- two cells bought
    -- with 5.6 halvings -- that is a bit over one extra cell.
    config.FRONTIER_GENERATION_POWER = config.FRONTIER_GENERATION_POWER * 8
    oneSettlement()
    generate()

    expect.truthy(registry.territoryForCell('#2,0'), 'ground the smaller plan left out')
    expect.truthy(registry.territoryForCell('#3,0'), 'and one further still')
end

--- The whole point of generating from settlements rather than a bounding
-- box: ground nobody can reach never becomes territory at all, so the
-- daily pass is small by construction and the save stays proportional to
-- the inhabited world.
function M.leavesUnreachableGroundUngenerated()
    oneSettlement()
    generate()

    expect.isNil(registry.territoryForCell('#5,5'), 'far corner not generated')
    expect.isNil(registry.territoryForCell('#4,0'), 'beyond the planned radius')
end

--- The region is a disc, not the bounding square of one.
function M.generatesARoundRegion()
    oneSettlement({ range = halvingFor(3) })
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
            },
        },
        territories = {
            { id = 'seat', tier = 'large city', faction = 'alpha',
              cells = { '#0,0' }, influenceRange = 3 * CELL },
        },
    })
    state.fillDefaults(registry)
    state.seedPower(registry)

    local created = generate()

    -- One, not two: #0,0 is the seat's own cell and already territory, so
    -- the only cell left to generate is #1,0. Everything else the seat
    -- reaches has no cell record behind it.
    expect.equal(created, 1, 'only the defined cell that is not already the seat')
    expect.equal(registry.territoryForCell('#0,0').settlement, 'seat', 'the seat keeps its cell')
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
            },
        },
        territories = {
            { id = 'beta_seat', tier = 'large city', faction = 'beta',
              cells = { '#0,0' }, influenceRange = 4 * CELL },
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
        settlements = {
            {
                id = 'town',
                tier = 'town',
                cells = { '#0,0', '#1,0' },
                centroid = cellCentre(0, 0),
            },
        },
    })
    generate()

    expect.equal(registry.territoryForCell('#0,0').settlement, 'town',
        'settlement keeps its cell')
    expect.equal(registry.territoryForCell('#1,0').settlement, 'town', 'and its second cell')
    expect.equal(registry.settlements.town.tier, 'town', 'the settlement record survives')
end

--- Settlements are registered before the frontier exists, so a pack cannot
-- name generated cells in its own adjacentFrontier. The generator has to
-- make that link itself -- without it no settlement is ever reported as
-- surrounded, and anything built on that fact goes silently quiet.
function M.wiresSettlementsToTheirSurroundingCells()
    oneSettlement({
        settlements = {
            {
                id = 'town',
                tier = 'town',
                cells = { '#0,0' },
                centroid = cellCentre(0, 0),
            },
        },
    })
    generate()

    local ring = registry.settlements.town.adjacentFrontier
    expect.greater(#ring, 0, 'the settlement was given a ring')
    for _, id in ipairs(ring) do
        expect.truthy(registry.territories[id], 'ring member ' .. id .. ' exists')
        expect.equal(registry.territories[id].kind, 'frontier', 'ring members are frontier')
    end
end

function M.wiresFrontierCellsBackToSettlements()
    oneSettlement({
        settlements = {
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
    expect.equal(neighbour.adjacentSettlements[1], 'town', 'knows which settlement it rings')
end

--------------------------------------------------------------------------
-- Data hygiene
--------------------------------------------------------------------------

--- Cells at the edge of the generated region have neighbours that were
-- never created. Emitting those as adjacency would leave hundreds of
-- dangling references for the reference check to complain about.
function M.producesNoDanglingReferences()
    oneSettlement({
        settlements = {
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
-- Note that generated and claimable are not the same set. Generation
-- plans for FRONTIER_GENERATION_POWER, which is more than anyone starts
-- with, so the outer ring exists before anybody can hold it. That is the
-- headroom a growing faction expands into, and it is deliberate: with no
-- cap on projection, the alternative to generating it early is a map that
-- has to grow at runtime.
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
