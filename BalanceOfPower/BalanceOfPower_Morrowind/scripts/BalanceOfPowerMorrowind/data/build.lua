-- Turns the settlement list into what the framework's registration API
-- wants.
--
-- Every holding in the list becomes a power center for its faction --
-- that's what makes a region belong to somebody. Holdings above the minor
-- tier additionally become settlements: named, ownable territory. A farm
-- shapes who the Ascadian Isles belong to without itself being a place on
-- the map.
--
-- Note the vocabulary mismatch, which the source file's name invites: the
-- list is every *holding*, and only some of them are settlements in the
-- sense glossary.md uses. Minor locations are power centers and nothing
-- else.
--
-- This transform lives in the content pack, not the framework,
-- deliberately: "Minor location" and "Small City" are Morrowind's
-- vocabulary, and the framework must not learn it. What the framework
-- provides is frontier generation, which works off power centers alone
-- and knows nothing about any of this.

local M = {}

local function cellName(gridX, gridY)
    return string.format('#%d,%d', gridX, gridY)
end

local function cellCentre(gridX, gridY, cellSize)
    return gridX * cellSize + cellSize / 2, gridY * cellSize + cellSize / 2
end

--- The middle of a settlement's footprint.
-- Vivec covers fifteen cells; projecting from the mean rather than from
-- whichever cell happened to be listed first is the difference between
-- the city radiating outward and radiating off one corner.
local function centroidOf(cells, cellSize)
    local sumX, sumY = 0, 0
    for _, cell in ipairs(cells) do
        local x, y = cellCentre(cell[1], cell[2], cellSize)
        sumX, sumY = sumX + x, sumY + y
    end
    return { x = sumX / #cells, y = sumY / #cells }
end

local function cellNames(cells)
    local names = {}
    for i, cell in ipairs(cells) do
        names[i] = cellName(cell[1], cell[2])
    end
    return names
end

--- Group the settlement list by landmass, producing settlements and power
-- centers.
--
-- @param cellSize world units per exterior cell. Comes from the
--        framework (`BoP.CELL_SIZE`) rather than being written down here
--        as well: the centroids computed below have to land in the same
--        places the framework's frontier generator expects, and two
--        copies of one number is how that quietly stops being true.
-- @return { [landmassId] = { territories = {...}, centers = { [factionId] = {...} } } }
function M.plan(settlements, cellSize)
    if type(cellSize) ~= 'number' or cellSize <= 0 then
        error('BalanceOfPowerMorrowind: build.plan needs the framework cell size', 0)
    end

    local byLandmass = {}

    local function landmass(id)
        byLandmass[id] = byLandmass[id] or { territories = {}, centers = {} }
        return byLandmass[id]
    end

    for _, settlement in ipairs(settlements) do
        local entry = landmass(settlement.landmass)
        local centroid = centroidOf(settlement.cells, cellSize)
        local names = cellNames(settlement.cells)
        local id = M.idFor(settlement.name)

        -- Unaffiliated holdings still exist on the map, but project
        -- nothing and start unowned.
        if settlement.faction then
            entry.centers[settlement.faction] = entry.centers[settlement.faction] or {}
            local centers = entry.centers[settlement.faction]
            centers[#centers + 1] = {
                id = id,
                tier = settlement.centerTier,
                coords = centroid,
                landmass = settlement.landmass,
                -- The ground it physically stands on. The framework gives
                -- its faction a floor on its projection in these cells,
                -- which is what keeps a settlement with whoever built it
                -- -- and, for a minor holding, is the whole of its
                -- footprint on the map.
                cells = names,
            }
        end

        if settlement.settlementTier then
            entry.territories[#entry.territories + 1] = {
                id = id,
                displayName = settlement.name,
                tier = settlement.settlementTier,
                region = settlement.region,
                cells = names,
                centroid = centroid,
                -- No defaultOwner except where the framework must not be
                -- allowed to derive one -- see main.lua. Initial control
                -- comes from projection, so the starting map is a
                -- consequence of where the seats of power are rather than
                -- a second list to keep in step with the first.
            }
        end
    end

    return byLandmass
end

--- A stable territory/power-center id from a settlement name.
--
-- "Tel Aruhn" becomes tel_aruhn, "Ald-Ruhn" becomes ald_ruhn, "Big
-- Head's Shack" becomes big_heads_shack. Apostrophes close up because
-- they're inside a word; every other punctuation mark separates, because
-- dropping it outright would run words together.
function M.idFor(name)
    local id = string.lower(name)
    id = string.gsub(id, "'", "")
    id = string.gsub(id, "[^%w]+", "_")
    id = string.gsub(id, "^_+", "")
    id = string.gsub(id, "_+$", "")
    return id
end

--- Build the faction list for one landmass's registerLandmass call.
--
-- A faction is defined by the first landmass that mentions it and
-- extended by every later one -- the Empire holds forts on Vvardenfell
-- and Fort Frostmoth on Solstheim, and both have to project at once.
-- @param definitions the faction table from data/factions.lua
-- @param centers { [factionId] = { powerCenter, ... } } for this landmass
-- @param defined set of faction ids already registered by an earlier call
function M.factionsFor(definitions, centers, defined, landmassId)
    local out = {}

    for _, definition in ipairs(definitions) do
        local id = definition.id
        local powerCenters = centers[id]
        local isPowerOnly = definition.territorial == false

        -- A land-holding faction is only worth registering here if it
        -- actually holds something on this landmass. A power-only faction
        -- has no geography at all, so it belongs to the first call only.
        local relevant = powerCenters ~= nil or (isPowerOnly and not defined[id])

        if relevant then
            if defined[id] then
                out[#out + 1] = {
                    id = id,
                    extend = true,
                    landmass = landmassId,
                    powerCenters = powerCenters,
                }
            else
                -- Everything the author wrote, with only the two fields
                -- this file is responsible for laid over the top.
                --
                -- Deliberately a copy rather than a hand-listed set of
                -- fields. The list version silently dropped patrolRoster
                -- for as long as the field has existed: it validated, it
                -- was documented, and it never arrived. Any field the
                -- framework grows would have gone the same way, and
                -- nothing would have said so.
                local faction = {}
                for key, value in pairs(definition) do
                    faction[key] = value
                end
                faction.landmass = landmassId
                faction.powerCenters = powerCenters

                out[#out + 1] = faction
                defined[id] = true
            end
        end
    end

    return out
end

return M
