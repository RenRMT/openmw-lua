-- Frontier grid generation (design doc 3.2).
--
-- The wilderness between settlements is far too fine-grained to author
-- by hand -- Vvardenfell alone is thousands of exterior cells -- so it's
-- derived instead. A content pack declares where the seats of power are;
-- this turns that into the grid they contest.
--
-- The generator is landmass-agnostic on purpose, and has to stay that
-- way. It knows nothing about Morrowind, cell naming conventions or
-- which factions exist: it reads the power centers already in the
-- registry and works outward from them. A pack supplies data, never
-- behaviour.
--
-- **Only ground somebody can actually reach becomes a territory.** The
-- union of every power center's influence radius defines the grid, so
-- open ocean and deep wilderness never exist as territories rather than
-- existing and being skipped. That keeps the daily pass small by
-- construction instead of by optimization, and keeps the save file
-- proportional to the inhabited world.
--
-- Note that the union is bounded by influence range, not by power:
-- influence decays to exactly zero at a center's range, so no amount of
-- power reaches past it. That makes the ceiling real but harmless -- the
-- ground left ungenerated is ground nobody could ever have held anyway.
-- FRONTIER_GENERATION_MARGIN exists for packs that add power centers at
-- runtime, where the reachable region genuinely can grow, and defaults
-- to zero for everyone else.
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

--- Generate frontier territories around a landmass's power centers.
--
-- @param def table
--   landmass              string, required; only centers on it are used
--   cellSize              world units per exterior cell
--   cellsPerUnit          exterior cells per territory, per axis (1 = one each)
--   margin                extra world units beyond each center's range
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
    -- 1. Claim every block within reach of a power center.
    ----------------------------------------------------------------------

    local blocks, order, centerCount = {}, {}, 0

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
            for _, centre in ipairs(faction.powerCenters) do
                if centre.landmass == landmassId then
                    centerCount = centerCount + 1
                    local reach = centre.influenceRange + margin
                    local minX = math.floor((centre.coords.x - reach) / blockSize)
                    local maxX = math.floor((centre.coords.x + reach) / blockSize)
                    local minY = math.floor((centre.coords.y - reach) / blockSize)
                    local maxY = math.floor((centre.coords.y + reach) / blockSize)

                    for blockX = minX, maxX do
                        for blockY = minY, maxY do
                            -- Against the disc itself, not its bounding
                            -- box, so the generated region is round.
                            local dx = (blockX + 0.5) * blockSize - centre.coords.x
                            local dy = (blockY + 0.5) * blockSize - centre.coords.y
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

    if centerCount == 0 then
        log.warn('generateFrontier("%s"): no power centers on this landmass, nothing generated',
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

    log.info('generated %d frontier cells for "%s" from %d power centers '
        .. '(%d blocks already settled, %d settlements given a ring)',
        #definitions, landmassId, centerCount, skipped, wired)
    return #definitions
end

return M
