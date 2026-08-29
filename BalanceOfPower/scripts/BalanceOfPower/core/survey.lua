-- Reads the world's settlements out of the game, so the framework has
-- something to simulate without anyone listing it by hand.
--
-- A settlement is a named exterior cell, and its holder is whoever has
-- armed men standing in it. Both come from content the player actually
-- loaded, which is what lets a landmass mod's towns be surveyed on the
-- same terms as Vvardenfell's with nobody writing them down.
--
-- Nothing here knows it is looking at Morrowind. Every rule below is
-- derived from the shape of the data rather than from a list of places,
-- because the first list of places is how a framework stops working on
-- the second game somebody points it at.
--
-- Ownership is read from exteriors only. Interiors are counted but never
-- entered: tallying who stands in them would move the answer on a handful
-- of settlements for six times the cells, and this runs at load. Their
-- names are free -- the walk over world.cells happens either way.

local types = require('openmw.types')
local world = require('openmw.world')

local config = require('scripts.BalanceOfPower.core.config')
local log = require('scripts.BalanceOfPower.core.log')

local M = {}

--------------------------------------------------------------------------
-- Reading the world
--------------------------------------------------------------------------

--- The settlement a cell name belongs to.
--
-- "Vivec, Temple" is a district of Vivec, and merging the nine such cells
-- is what stops one city registering as nine rival powers. "Solstheim,
-- Lake Fjalding" looks identical but is a landmark on an island, and
-- merging those invents a settlement spanning it.
--
-- What separates them is derived rather than listed: a prefix that is
-- also a cell name in its own right is a place ("Vivec" is three cells),
-- and one that never appears alone is a category ("Solstheim" is not a
-- cell). No entry in this file names either of them.
local function settlementName(cellName, standalone)
    local prefix = string.match(cellName, '^([^,]+),')
    if prefix and standalone[prefix] then
        return prefix
    end
    return cellName
end

--- The faction an NPC counts for, or nil if it counts for nobody.
--
-- getFactions rather than the record: NpcRecord carries no faction field.
-- CreatureRecord does, but no Morrowind creature populates it, which is
-- why a creature-garrisoned ruin reads as empty ground here.
local function factionOf(npc)
    local ok, factions = pcall(types.NPC.getFactions, npc)
    if not ok or not factions or #factions == 0 then
        return nil
    end
    local id = string.lower(factions[1])
    return config.FACTION_ALIASES[id] or id
end

local function tally(cell, guards, members)
    local ok, npcs = pcall(function() return cell:getAll(types.NPC) end)
    if not ok then
        return
    end
    for _, npc in ipairs(npcs) do
        -- Corpses are scenery. Morrowind dresses its ruins with bodies
        -- carrying a live faction, and counting them hands the Sixth
        -- House strongholds to the Empire.
        local alive, dead = pcall(types.Actor.isDead, npc)
        if not alive or not dead then
            local faction = factionOf(npc)
            if faction then
                members[faction] = (members[faction] or 0) + 1
                local gotRecord, record = pcall(types.NPC.record, npc)
                local class = gotRecord and record and record.class
                if class and config.SURVEY_GUARD_CLASSES[string.lower(class)] then
                    guards[faction] = (guards[faction] or 0) + 1
                end
            end
        end
    end
end

local function strongest(counts)
    local best, bestCount = nil, 0
    for key, count in pairs(counts) do
        if count > bestCount then
            best, bestCount = key, count
        end
    end
    return best, bestCount
end

--- Who holds a settlement, by weight of arms.
--
-- Guards decide it outright where there are any: this measures power, not
-- title, so a Legion fort in a Redoran town makes the town Imperial. The
-- unarmed fallback is what puts the Ashlander camps on the map at all --
-- herders and hunters, no guard class between them.
local function holderOf(guards, members)
    local faction = strongest(guards)
    if faction then
        return faction, 'guards'
    end
    faction = strongest(members)
    if faction then
        return faction, 'members'
    end
    return nil, 'none'
end

--- How big a place is, in cells, counting its doors.
--
-- See SURVEY_INTERIORS_PER_CELL for why interiors are in here at all and
-- why their contribution is capped.
local function sizeOf(cellCount, interiorCount)
    local perCell = config.SURVEY_INTERIORS_PER_CELL
    local fromDoors = perCell > 0 and math.floor(interiorCount / perCell) or 0
    local cap = math.floor(cellCount * config.SURVEY_INTERIOR_CAP_RATIO)
    return cellCount + math.min(fromDoors, cap)
end

local function tierFor(cellCount, interiorCount)
    local size = sizeOf(cellCount, interiorCount or 0)
    local ladder = config.SURVEY_TIER_BY_SIZE
    for _, step in ipairs(ladder) do
        if size >= step.size then
            return step.tier
        end
    end
    return ladder[#ladder].tier
end

--- A stable settlement id from a name and its worldspace.
--
-- Worldspace-qualified because two landmasses may both hold an "Ald
-- Velothi", and a collision would silently drop one of them.
local function idFor(name, landmassId)
    local id = string.lower(landmassId .. '_' .. name)
    id = string.gsub(id, "'", '')
    id = string.gsub(id, '[^%w]+', '_')
    id = string.gsub(id, '^_+', '')
    id = string.gsub(id, '_+$', '')
    return id
end

local function landmassIdFor(worldSpaceId)
    local id = string.lower(tostring(worldSpaceId or 'exterior'))
    id = string.gsub(id, '[^%w]+', '_')
    id = string.gsub(id, '^_+', '')
    id = string.gsub(id, '_+$', '')
    return id ~= '' and id or 'exterior'
end

--------------------------------------------------------------------------
-- The survey
--------------------------------------------------------------------------

--- Survey the world and group what it finds by landmass.
--
-- Cost is dominated by cell:getAll, which forces each cell it touches out
-- of its unloaded state; everything before it is a name comparison. Only
-- named exteriors are touched -- 126 of 2791 cells in vanilla, a few
-- hundred with a landmass mod -- so the filter does nearly all the work.
--
-- @return { [landmassId] = { id, displayName, territories = {...} } },
--         ready for registerLandmass, plus the settlement count.
function M.plan()
    -- Two passes: the set of standalone names has to be complete before
    -- any "X, Y" cell can be judged a district of X or a place of its own.
    local standalone = {}
    local named = {}
    local interiorNames = {}
    for _, cell in ipairs(world.cells) do
        if cell.name and cell.name ~= '' then
            if cell.isExterior then
                named[#named + 1] = cell
                if not string.find(cell.name, ',', 1, true) then
                    standalone[cell.name] = true
                end
            else
                interiorNames[#interiorNames + 1] = cell.name
            end
        end
    end

    -- Doors, by the settlement whose name they carry. Counted by name
    -- alone rather than per landmass: an interior belongs to no
    -- worldspace, so two landmasses that both hold an "Ald Velothi" would
    -- share the tally. Harmless -- it can only make a duplicated name
    -- read one tier large, and the same collision already has the pair
    -- sharing a display name on the map.
    local interiors = {}
    for _, interiorName in ipairs(interiorNames) do
        local prefix = string.match(interiorName, '^([^,]+),') or interiorName
        interiors[prefix] = (interiors[prefix] or 0) + 1
    end

    local found, order = {}, {}
    for _, cell in ipairs(named) do
        local name = settlementName(cell.name, standalone)
        local landmassId = landmassIdFor(cell.worldSpaceId)
        local key = landmassId .. '\0' .. name
        local entry = found[key]
        if not entry then
            entry = {
                name = name,
                landmassId = landmassId,
                worldSpaceId = cell.worldSpaceId,
                cells = {},
                regions = {},
                guards = {},
                members = {},
            }
            found[key] = entry
            order[#order + 1] = key
        end
        entry.cells[#entry.cells + 1] = string.format('#%d,%d', cell.gridX, cell.gridY)
        if cell.region then
            entry.regions[cell.region] = (entry.regions[cell.region] or 0) + 1
        end
        tally(cell, entry.guards, entry.members)
    end

    local plan, settlementCount = {}, 0
    for _, key in ipairs(order) do
        local entry = found[key]
        local faction = holderOf(entry.guards, entry.members)
        -- Ground nobody stands on is scenery, not a seat of power. Most
        -- named cells are ruins and landmarks; admitting them would bury
        -- the settlements under empty territory.
        if faction then
            local landmass = plan[entry.landmassId]
            if not landmass then
                landmass = {
                    id = entry.landmassId,
                    displayName = tostring(entry.worldSpaceId or entry.landmassId),
                    territories = {},
                }
                plan[entry.landmassId] = landmass
            end
            local territories = landmass.territories
            territories[#territories + 1] = {
                id = idFor(entry.name, entry.landmassId),
                displayName = entry.name,
                tier = tierFor(#entry.cells, interiors[entry.name] or 0),
                region = (strongest(entry.regions)),
                cells = entry.cells,
                -- Whose seat it is, and so whose power it projects.
                faction = faction,
                -- ...and who holds the ground on day one. The two are the
                -- same faction here and set separately on purpose: an
                -- authored list could only say whose seat a place was and
                -- would have to let projection work out who held it, but a
                -- survey has watched armed men stand in the cell. That is
                -- an observation, not an inference, so the map is correct
                -- the moment it loads rather than after the first
                -- resolve.
                defaultOwner = faction,
            }
            settlementCount = settlementCount + 1
        end
    end

    log.info('surveyed %d settlements across %d named exterior cells',
        settlementCount, #named)
    return plan, settlementCount
end

return M
