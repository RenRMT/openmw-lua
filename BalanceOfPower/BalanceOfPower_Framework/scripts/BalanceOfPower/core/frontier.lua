-- Frontier grid generation (design doc 3.2).
--
-- The wilderness between settlements is far too fine-grained to author
-- by hand -- Vvardenfell alone is thousands of exterior cells -- so it's
-- derived instead. A content pack declares where the seats of power are.
-- This generator reads the settlements in the registry and works outward 
-- from them.
--
-- The union of every settlement's influence radius defines the grid, so
-- open ocean and deep wilderness never exist as territories rather than
-- existing and being skipped. That keeps the daily pass small by
-- construction instead of by optimization, and keeps the save file
-- proportional to the inhabited world.
--
-- The bound is a planning figure rather than a law. Projection decays but
-- never stops, so there is no distance past which ground is unclaimable;
-- what there is instead is a power at which the generator stops planning,
-- FRONTIER_GENERATION_POWER. Each seat gets the radius a faction of that
-- power could claim from it, which leaves the map room to grow into
-- without carrying territory nothing will reach for a very long time.
--
-- A faction that outgrows the figure projects past the edge of the
-- generated world. The fix is to raise it and regenerate, not to cap the
-- projection: ground that exists and is out of reach is honest, where
-- ground that cannot be reached because it was never created is not.
--
-- GLOBAL context only.

local world = require('openmw.world')

local cells = require('scripts.BalanceOfPower.core.cells')

local config = require('scripts.BalanceOfPower.core.config')
local log = require('scripts.BalanceOfPower.core.log')
local registry = require('scripts.BalanceOfPower.core.registry')

local M = {}

--------------------------------------------------------------------------
-- Cell helpers
--------------------------------------------------------------------------

local function key(a, b)
    return a .. ',' .. b
end

--- How far from a seat the generator lays down territory.
--
-- Projection no longer stops anywhere, so "as far as it reaches" is not
-- an answer. The question the generator can answer is how far a faction
-- of a given power could *claim* from this seat, which is where its
-- projection decays past MIN_CLAIM_POWER:
--
--   power * weight * 2^(-d / influenceRange) = MIN_CLAIM_POWER
--
-- solved for d. FRONTIER_GENERATION_POWER is the power it plans for, so
-- the generated map has room for factions to grow into rather than being
-- cut to the starting map's shape.
local function claimRadius(seat)
    local strength = config.FRONTIER_GENERATION_POWER * seat.weight
    if strength <= config.MIN_CLAIM_POWER or seat.influenceRange <= 0 then
        return 0
    end
    -- log2(strength / floor), in halving distances.
    return seat.influenceRange * math.log(strength / config.MIN_CLAIM_POWER) / math.log(2)
end

--- Every settlement gets frontier around it, whatever the planning power
-- says.
--
-- A small remote holding (Ashlander camp at outpost weight) can
-- have a claim radius under one cell, and would otherwise sit on the map
-- with no wilderness next to it at all. That is not a tuning outcome, it
-- is a hole: `isSurrounded()` is answered from a settlement's ring of
-- adjacent frontier, so a settlement with no ring can never be reported
-- surrounded however completely it is encircled.
--
-- So the radius has a floor of one and a half blocks, which reaches the
-- centre of every neighbouring block including the diagonals. The cells
-- it adds are ordinary contested ground -- the camp cannot claim them at
-- its own strength, and whoever can, does.
local function generationRadius(seat, blockSize)
    return math.max(claimRadius(seat), 1.5 * blockSize)
end

-- Grid key -> true for every exterior cell the loaded content defines,
-- and grid key -> region name. Both built once per session.
local existingCells = nil
local regionByCell = nil

local function indexCells()
    if existingCells then
        return
    end
    existingCells, regionByCell = {}, {}

    local count = 0
    for _, cell in ipairs(world.cells) do
        if cell.isExterior then
            local id = key(cell.gridX, cell.gridY)
            existingCells[id] = true
            -- `region` is documented as possibly nil, and its exact type
            -- isn't guaranteed across versions, so only use it when it's
            -- plainly a string.
            if type(cell.region) == 'string' and cell.region ~= '' then
                regionByCell[id] = cell.region
            end
            count = count + 1
        end
    end
    log.debug('indexed %d exterior cells from loaded content', count)
end

--------------------------------------------------------------------------
-- Generation
--------------------------------------------------------------------------

--- Generate frontier territories around a landmass's settlements.
--
-- @param def table
--   landmass              string, required; only seats on it are used
--   cellSize              world units per exterior cell
--   cellsPerUnit          exterior cells per territory, per axis (1 = one each)
--   margin                extra world units beyond each seat's radius
--   idPrefix              prefix for generated territory ids
--   requireExistingCell   skip grid positions with no cell record
-- @return number of frontier territories created
function M.generate(def)
    def = def or {}
    local landmassId = def.landmass
    if type(landmassId) ~= 'string' or landmassId == '' then
        error('BalanceOfPower: generateFrontier requires a landmass id', 0)
    end
    if not registry.landmasses[landmassId] then
        error(string.format(
            'BalanceOfPower: generateFrontier called for unregistered landmass "%s" '
            .. '-- register the landmass before generating its frontier', landmassId), 0)
    end

    local cellSize = def.cellSize or config.CELL_SIZE
    local block = math.max(1, math.floor(def.cellsPerUnit or config.FRONTIER_CELLS_PER_UNIT))
    local margin = def.margin or config.FRONTIER_GENERATION_MARGIN
    local prefix = def.idPrefix or (landmassId .. '_frontier')
    local requireExisting = def.requireExistingCell
    if requireExisting == nil then
        requireExisting = config.FRONTIER_REQUIRE_EXISTING_CELL
    end

    local blockSize = cellSize * block
    if requireExisting then
        indexCells()
    end

    local function blockId(blockX, blockY)
        return string.format('%s_%d_%d', prefix, blockX, blockY)
    end

    ----------------------------------------------------------------------
    -- 1. Claim every block within reach of a settlement.
    ----------------------------------------------------------------------

    local blocks, order, seatCount = {}, {}, 0

    local function claim(blockX, blockY)
        local id = key(blockX, blockY)
        if blocks[id] then
            return
        end

        local names = {}
        for offsetX = 0, block - 1 do
            for offsetY = 0, block - 1 do
                local gridX, gridY = blockX * block + offsetX, blockY * block + offsetY
                if not requireExisting or existingCells[key(gridX, gridY)] then
                    names[#names + 1] = cells.name(gridX, gridY)
                end
            end
        end
        -- Entirely undefined: open water or off the edge of the world.
        if #names == 0 then
            return
        end

        blocks[id] = { blockX = blockX, blockY = blockY, cells = names }
        order[#order + 1] = id
    end

    for _, faction in pairs(registry.factions) do
        if faction.territorial then
            for _, seat in ipairs(faction.seats) do
                if seat.landmass == landmassId then
                    seatCount = seatCount + 1
                    local reach = generationRadius(seat, blockSize) + margin
                    local minX = math.floor((seat.centroid.x - reach) / blockSize)
                    local maxX = math.floor((seat.centroid.x + reach) / blockSize)
                    local minY = math.floor((seat.centroid.y - reach) / blockSize)
                    local maxY = math.floor((seat.centroid.y + reach) / blockSize)

                    for blockX = minX, maxX do
                        for blockY = minY, maxY do
                            -- Against the disc itself, not its bounding
                            -- box, so the generated region is round.
                            local dx = (blockX + 0.5) * blockSize - seat.centroid.x
                            local dy = (blockY + 0.5) * blockSize - seat.centroid.y
                            -- Strictly inside: influence is exactly zero
                            -- at the range itself, so a cell on the
                            -- boundary could never be held by anybody.
                            if (dx * dx + dy * dy) < reach * reach then
                                claim(blockX, blockY)
                            end
                        end
                    end
                end
            end
        end
    end

    if seatCount == 0 then
        log.warn('generateFrontier("%s"): no settlements on this landmass, nothing generated',
            landmassId)
        return 0
    end

    -- Sorted, so identical content produces identical ids and
    -- registration order in every session.
    table.sort(order)

    ----------------------------------------------------------------------
    -- 2. Drop blocks a settlement already owns, and index what survives.
    ----------------------------------------------------------------------

    local planned, kept, skipped = {}, {}, 0

    for _, id in ipairs(order) do
        local entry = blocks[id]
        local occupied = registry.territories[blockId(entry.blockX, entry.blockY)] ~= nil
        if not occupied then
            for _, name in ipairs(entry.cells) do
                if registry.cellIndex[name] then
                    occupied = true
                    break
                end
            end
        end

        if occupied then
            -- A settlement already holds this ground; the
            -- wilderness grid must not fight it for the same cells.
            skipped = skipped + 1
        else
            planned[id] = blockId(entry.blockX, entry.blockY)
            kept[#kept + 1] = entry
        end
    end

    ----------------------------------------------------------------------
    -- 3. Work out which settlements each block sits next to.
    --
    -- Settlements are registered before the frontier exists, so a pack has no
    -- way to name generated cells in its own `adjacentFrontier`. The link
    -- is made here instead, in both directions -- without it no settlement
    -- would ever be reported as surrounded.
    ----------------------------------------------------------------------

    local settlementsByBlock = {}    -- blockKey -> { settlementId, ... }
    local frontierBySettlement = {}  -- settlementId -> { blockKey, ... }

    for _, settlementId in ipairs(registry.settlementIds) do
        local settlement = registry.settlements[settlementId]
        if settlement.landmass == landmassId then
            local seen = {}
            for _, name in ipairs(settlement.cells) do
                local gridX, gridY = cells.parse(name)
                if gridX then
                    -- The eight grid neighbours of every cell the
                    -- settlement occupies. For a multi-cell settlement
                    -- this traces the ring around the whole footprint,
                    -- since its own cells aren't in `planned`.
                    for offsetX = -1, 1 do
                        for offsetY = -1, 1 do
                            local neighbour = key(
                                math.floor((gridX + offsetX) / block),
                                math.floor((gridY + offsetY) / block))
                            if planned[neighbour] and not seen[neighbour] then
                                seen[neighbour] = true
                                settlementsByBlock[neighbour] = settlementsByBlock[neighbour] or {}
                                table.insert(settlementsByBlock[neighbour], settlementId)
                                frontierBySettlement[settlementId] = frontierBySettlement[settlementId] or {}
                                table.insert(frontierBySettlement[settlementId], neighbour)
                            end
                        end
                    end
                end
            end
        end
    end

    ----------------------------------------------------------------------
    -- 4. Build the definitions.
    ----------------------------------------------------------------------

    local definitions = {}
    for _, entry in ipairs(kept) do
        local id = key(entry.blockX, entry.blockY)

        -- Neighbours are filtered against what actually exists, so the
        -- edge of the generated region doesn't leave hundreds of dangling
        -- references for validateReferences to complain about.
        local neighbours = {}
        local offsets = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }
        for _, offset in ipairs(offsets) do
            local neighbourKey = key(entry.blockX + offset[1], entry.blockY + offset[2])
            if planned[neighbourKey] then
                neighbours[#neighbours + 1] = planned[neighbourKey]
            end
        end

        local region = regionByCell and regionByCell[
            key(cells.parse(entry.cells[1]))]

        definitions[#definitions + 1] = {
            id = planned[id],
            -- "Bitter Coast #-2,-8" reads better in a log than
            -- "vvardenfell_frontier_-2_-8".
            displayName = region and (region .. ' ' .. entry.cells[1]) or entry.cells[1],
            region = region,
            cells = entry.cells,
            centroid = {
                x = (entry.blockX + 0.5) * blockSize,
                y = (entry.blockY + 0.5) * blockSize,
            },
            adjacentFrontier = neighbours,
            adjacentSettlements = settlementsByBlock[id] or {},
            -- No defaultOwner. Initial control is derived from
            -- projection, which is the entire point of generating this
            -- grid rather than authoring it.
        }
    end

    registry.registerFrontier(landmassId, definitions)

    ----------------------------------------------------------------------
    -- 5. Wire the settlements back to their ring.
    ----------------------------------------------------------------------

    local wired = 0
    for settlementId, blockKeys in pairs(frontierBySettlement) do
        local settlement = registry.settlements[settlementId]
        local ring = settlement.adjacentFrontier
        for _, blockKey in ipairs(blockKeys) do
            ring[#ring + 1] = planned[blockKey]
        end
        table.sort(ring)
        wired = wired + 1
    end

    log.info('generated %d frontier cells for "%s" from %d settlements '
        .. '(%d blocks already settled, %d settlements given a ring)',
        #definitions, landmassId, seatCount, skipped, wired)
    return #definitions
end

return M
