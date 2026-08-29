-- The registry: the world the framework simulates, normalized into one
-- shape and immutable after load (design doc 3.8).
--
-- What the survey and the frontier generator produce is a named place with
-- a list of cells. What the simulation needs is one independently ownable
-- thing per cell. Turning the first into the second is most of what this
-- file does; keeping the result is the rest.
--
-- Nothing external fills this. There are no content packs: core/survey.lua
-- reads the settlements out of whatever the player actually loaded, and
-- core/frontier.lua derives the wilderness grid around them. Both hand
-- their results here, and both are this framework's own code.
--
-- That is why there is no input validation. Checking that a definition's
-- `cells` is a list of strings would be checking survey.lua against
-- itself, and a type error in our own code should surface as the Lua error
-- it is rather than as a politely worded message about a field.
--
-- What *is* checked is the other thing: collisions and dangling
-- references, which are real and come from the load order rather than from
-- us. Two landmass mods can name the same exterior cell, a faction record
-- can go missing, a settlement can point at a frontier block that was
-- never generated. None of those is a reason to refuse to load -- they are
-- warned about and worked around, because the alternative is a framework
-- that dies on somebody's modlist.
--
-- Nothing here knows what a landmass is called or which factions exist. It
-- only knows the shape of the data. The day this file needs an
-- `if id == "cyrodiil"` branch, the abstraction has failed.

local core = require('openmw.core')

local cells = require('scripts.BalanceOfPower.core.cells')
local config = require('scripts.BalanceOfPower.core.config')
local factionRecords = require('scripts.BalanceOfPower.core.factions')
local log = require('scripts.BalanceOfPower.core.log')

local M = {}

M.factions = {}          -- factionId   -> normalized faction
M.landmasses = {}        -- landmassId  -> { id, displayName, factionIds, territoryIds }

-- Every ownable thing, and every one of them is exactly one exterior
-- cell. A settlement's cells are in here individually, tagged with the
-- settlement they belong to.
M.territories = {}       -- territoryId -> normalized territory

-- The named places. Grouping and metadata; not ownable themselves.
M.settlements = {}       -- settlementId -> { id, displayName, tier, cells, territoryIds, ... }

M.settlementIds = {}     -- registration-ordered list of settlement ids
M.settlementCellIds = {} -- registration-ordered territory ids belonging to settlements
M.frontierIds = {}       -- registration-ordered list of frontier territory ids
M.cellIndex = {}         -- cell name (interior name or "#x,y") -> territoryId

-- One exterior cell's middle, in world units. CELL_SIZE is the engine's
-- grid, not a tunable, so computing it here is safe -- see the constant's
-- comment.
local function cellCentre(gridX, gridY)
    local size = config.CELL_SIZE
    return { x = gridX * size + size / 2, y = gridY * size + size / 2, z = 0 }
end

-- Bumped on every successful registration. Consumers that cache derived
-- data (power's reaction lookups, phase 2's adjacency graph) compare
-- against this instead of being explicitly invalidated, which keeps the
-- dependency arrows pointing one way.
M.generation = 0

--------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------

-- A fresh copy of a list, so nothing registered here shares a table with
-- whatever built it and can be mutated from under the simulation later.
local function copyList(value)
    local out = {}
    for i, entry in ipairs(value or {}) do
        out[i] = entry
    end
    return out
end

--------------------------------------------------------------------------
-- Settlements
--------------------------------------------------------------------------

--- The tier ladder as a lookup. The survey picks tiers off the same ladder,
-- so a miss means those two have fallen out of step with each other -- worth
-- stopping for rather than quietly defaulting.
local function tierDefaultsFor(tier, ctx)
    local defaults = config.SETTLEMENT_TIERS[tier]
    if not defaults then
        error(string.format('BalanceOfPower: %s: unknown tier "%s" -- expected one of: %s',
            ctx, tostring(tier), table.concat(config.SETTLEMENT_TIER_ORDER, ', ')), 0)
    end
    return defaults
end

--------------------------------------------------------------------------
-- Factions
--------------------------------------------------------------------------

local function newFaction(id, recordId, landmass)
    return {
        id = id,
        displayName = factionRecords.nameOf(recordId or id) or id,
        -- The faction's id in the game's data, where it differs from the
        -- id registered here. For the faction whose modelled identity
        -- doesn't line up with a single record.
        recordId = recordId,
        -- Derived at the end of every registration from whether any
        -- settlement names this faction. A faction with no seats is
        -- power-only: it has standing and reacts to everyone, but holds
        -- no ground and projects nothing.
        territorial = false,
        growthPerDay = config.DEFAULT_GROWTH_PER_DAY,
        -- What kind of thing this is. nil is an ordinary participant in
        -- the politics; FACTION_TYPE_INVADER is an outside threat that
        -- drifts not at all, reacts to nobody and fights everyone.
        type = nil,
        -- How far this faction's fortunes swing, as a multiple of
        -- FORTUNE_SWING. 0 pins it to exactly what its ground supports.
        volatility = config.DEFAULT_VOLATILITY,
        landmass = landmass,
        -- Filled in by addLandmass from the settlements naming this
        -- faction. A faction holds seats; it has no geography of its own.
        seats = {},
    }
end

--- Register every faction the game's records describe.
--
-- Lazy rather than eager because records can only be read once content
-- files have loaded, and it has to happen before any settlement binds to
-- a faction. The first addLandmass triggers it.
local function ensureFactions()
    if M.factionsFromRecords then
        return 0
    end
    M.factionsFromRecords = true

    local added = 0
    for _, recordId in ipairs(factionRecords.participatingIds()) do
        if not M.factions[recordId] then
            M.factions[recordId] = newFaction(recordId, recordId, nil)
            added = added + 1
        end
    end
    if added > 0 then
        log.info('registered %d factions from the game\'s faction records', added)
    end
    return added
end

--- Register one faction id that holds ground but the reaction filter dropped.
--
-- factions.participatingIds() keeps out records nobody has an opinion about,
-- which is right for the dead ids content files carry around and wrong
-- for a real faction that simply has no politics. Bloodmoon's Skaal have
-- a village, a garrison and an empty reaction row; without this they own
-- Skaal Village at load and lose it on the first resolve, because a
-- faction that is not registered cannot hold anything.
--
-- Holding ground is participation. Only ids the game actually has a
-- record for are admitted, so this cannot conjure a faction from a typo.
-- @return true if this call registered one
local function admitHolder(factionId)
    if not factionId or M.factions[factionId] or not factionRecords.exists(factionId) then
        return false
    end
    M.factions[factionId] = newFaction(factionId, factionId, nil)
    return true
end

-- Scalars FACTION_TUNING may set. The first setter keeps it: tuning is
-- emitted once, but a faction can be reached again by a second worldspace,
-- and which one won would otherwise depend on load order.
local TUNABLE = { 'growthPerDay', 'recordId', 'landmass', 'type', 'volatility' }

local function applyTuning(faction, tuning, ctx)
    for _, field in ipairs(TUNABLE) do
        local value = tuning[field]
        if value ~= nil then
            if faction[field .. 'Authored'] then
                log.warn('%s: ignoring %s -- it is already set', ctx, field)
            else
                faction[field] = value
                faction[field .. 'Authored'] = true
            end
        end
    end
end

--- Normalize a faction entry into a staged operation.
--
-- Nothing here defines a faction so much as tunes one: the game's records
-- supply the roster of who exists, and an entry adds the numbers the game
-- has no field for. That is FACTION_TUNING in config, and nothing else. A
-- faction with no record behind it is still registered, which is how the
-- framework models something the game does not.
local function prepareFaction(def, context, fallbackLandmass)
    return {
        id = def.id,
        landmass = def.landmass or fallbackLandmass,
        tuning = {
            growthPerDay = def.growthPerDay,
            volatility = def.volatility,
            type = def.type,
            recordId = def.recordId,
        },
        ctx = string.format('%s faction "%s"', context, def.id),
    }
end

--------------------------------------------------------------------------
-- Territories
--------------------------------------------------------------------------

local function prepareFrontier(def, context, landmassId, staged)
    local id = def.id

    -- Two landmass mods can occupy the same worldspace coordinates, so a
    -- generated id can collide with one already registered. Skipped rather
    -- than fatal: the ground is already claimed by somebody, and refusing to
    -- load the rest of the world over it helps nobody.
    local clash = M.territories[id] or staged[id]
    if clash then
        log.warn('frontier "%s" is already registered -- skipping the duplicate', id)
        return nil
    end
    staged[id] = true

    return {
        id = id,
        kind = 'frontier',
        displayName = def.displayName or id,
        landmass = def.landmass or landmassId,
        -- The game's own region name, where there is one. Carried but
        -- never acted on: it's the kind of detail a UI, a spawn rule or a
        -- future region-scoped mechanic will want, and it costs nothing
        -- to keep hold of it now.
        region = type(def.region) == 'string' and def.region or nil,
        -- nil is a legitimate authored value, meaning "unclaimed".
        defaultOwner = def.defaultOwner,
        cells = copyList(def.cells),
        centroid = def.centroid,
        cooldownDays = def.cooldownDays or config.FRONTIER_COOLDOWN_DAYS,
        adjacentFrontier = copyList(def.adjacentFrontier),
        adjacentSettlements = copyList(def.adjacentSettlements),
    }
end

--- A settlement is a *named group of cells*, and each of those cells is
-- an ownable territory in its own right.
--
-- Vivec is one settlement over fifteen territories, not one territory
-- over fifteen cells. That distinction is what lets a city sit on the
-- map at the same granularity as the wilderness around it, so every cell
-- in the world is resolved by exactly one rule with no special case for
-- the named places. What holds a city together is the `settlement` tag
-- its cells share, not a privileged kind of territory.
--
-- Interior cell names are carried on the settlement, and resolve to its
-- first exterior territory, but never become territories themselves: an
-- interior has no position on the grid to project onto or from.
local function prepareSettlement(def, context, landmassId, staged)
    local id = def.id
    local ctx = string.format('%s settlement "%s"', context, id)

    -- Committed as soon as it is prepared, so the registry itself is the
    -- record of what has been claimed already.
    if M.settlements[id] then
        log.warn('settlement "%s" is already registered -- skipping the duplicate', id)
        return nil
    end

    local tier = def.tier or config.DEFAULT_SETTLEMENT_TIER
    local tierDefaults = tierDefaultsFor(tier, ctx)

    -- The survey only emits a settlement for a cell it found somebody
    -- standing in, so an empty footprint means the two have fallen out of
    -- step. Nothing downstream can do anything with it.
    local cellNames = copyList(def.cells)
    if #cellNames == 0 then
        log.warn('settlement "%s" has no cells -- skipping it', id)
        return nil
    end

    local settlement = {
        id = id,
        displayName = def.displayName or id,
        tier = tier,
        landmass = def.landmass or landmassId,
        region = type(def.region) == 'string' and def.region or nil,
        cells = cellNames,
        territoryIds = {},
        interiors = {},
        -- Whose seat this is, and so whose power it projects. Not the
        -- same question as who owns the ground: ownership is derived and
        -- can flip, while a settlement goes on projecting for the faction
        -- that built it. A settlement with no faction -- a derelict
        -- tower, an unaffiliated Velothi holding -- projects nothing and
        -- is ordinary ground with a name.
        faction = def.faction,
        -- The projection origin. Derived from the footprint below when a
        -- definition does not give one; see there for what else rides on it.
        centroid = def.centroid,
        weight = def.weight or tierDefaults.weight,
        influenceRange = def.influenceRange or tierDefaults.influenceRange,
        adjacentFrontier = copyList(def.adjacentFrontier),
    }

    local cooldownDays = def.cooldownDays or tierDefaults.cooldownDays

    local territories = {}
    local sumX, sumY = 0, 0
    for _, cellName in ipairs(cellNames) do
        local gridX, gridY = cells.parse(cellName)
        if not gridX then
            settlement.interiors[#settlement.interiors + 1] = cellName
        else
            local territoryId = string.format('%s_%d_%d', id, gridX, gridY)
            if M.territories[territoryId] or staged[territoryId] then
                -- The same cell listed twice, or two mods sharing a name.
                -- The first claim stands; see indexCells for the same rule
                -- applied across settlements.
                log.warn('%s: cell %s is already a territory -- ignoring the repeat',
                    ctx, cellName)
            else
                staged[territoryId] = true
                settlement.territoryIds[#settlement.territoryIds + 1] = territoryId

                local cellCentroid = cellCentre(gridX, gridY)
                sumX, sumY = sumX + cellCentroid.x, sumY + cellCentroid.y

                territories[#territories + 1] = {
                    id = territoryId,
                    kind = 'settlement',
                    settlement = id,
                    -- "Vivec #3,-9" rather than "vivec_3_-9": a city's cells
                    -- have to stay legible as parts of one place.
                    displayName = string.format('%s %s', settlement.displayName, cellName),
                    landmass = settlement.landmass,
                    region = settlement.region,
                    defaultOwner = def.defaultOwner,
                    cells = { cellName },
                    centroid = cellCentroid,
                    cooldownDays = cooldownDays,
                    tier = tier,
                    adjacentFrontier = {},
                }
            end
        end
    end

    -- Every cell was an interior, or every one of them was already claimed.
    -- Either way there is no ground here to own.
    if #territories == 0 then
        log.warn('settlement "%s" has no exterior cell of its own -- skipping it', id)
        return nil
    end

    -- The middle of the footprint, and load-bearing twice over: it is the
    -- point every reach calculation measures from, and it is what decides
    -- which cell carries the settlement's mark on the map. Both want the
    -- geometric middle, which is why one field answers both -- move it and
    -- the label moves with the projection.
    --
    -- Derived here rather than by whatever supplies the definition, so
    -- there is one definition of where a cell is. A second copy of this
    -- arithmetic has to agree with the frontier generator about the grid,
    -- and that is how a map ends up subtly out of register with its own
    -- settlements. The survey never supplies one, so in practice this is
    -- always the derived value.
    if not settlement.centroid then
        settlement.centroid = { x = sumX / #territories, y = sumY / #territories }
    end

    return settlement, territories
end

-- Grid coordinates for every exterior cell a territory holds, flat:
-- x1, y1, x2, y2, ... Worked out here because a territory's cells never
-- change after registration, and the alternative is re-parsing every cell
-- name out of its "#x,y" string each time something asks for the map --
-- which for a frontier block is thousands of strings per request.
--
-- Flat rather than a table per cell for the same reason the territory event
-- is: this is the shape it ends up being sent in.
local function indexGrid(territory)
    local grid = {}
    for _, cellName in ipairs(territory.cells) do
        local gridX, gridY = cells.parse(cellName)
        if gridX then
            grid[#grid + 1] = gridX
            grid[#grid + 1] = gridY
        end
    end
    territory.grid = grid
end

local function indexCells(territory)
    for _, cellName in ipairs(territory.cells) do
        local owner = M.cellIndex[cellName]
        if owner and owner ~= territory.id then
            -- A warning rather than an error: two landmass mods can name
            -- the same exterior cell, and that is not a reason to refuse to
            -- load either of them.
            log.warn('cell "%s" is claimed by both "%s" and "%s" -- keeping "%s"',
                cellName, owner, territory.id, owner)
        else
            M.cellIndex[cellName] = territory.id
        end
    end
end

--------------------------------------------------------------------------
-- Public registration
--------------------------------------------------------------------------

--- Recompute which factions hold ground. Called after every registration,
-- because a later worldspace's settlements can make a power-only faction
-- territorial.
local function deriveTerritorial()
    for _, faction in pairs(M.factions) do
        faction.territorial = #faction.seats > 0
    end
end

--- Add a surveyed worldspace: its factions, its settlements and, later,
-- its frontier grid. Called once per worldspace at world init.
--
-- `add` rather than `register`: nothing external calls this. The survey
-- hands over what it found and this is where it becomes the world.
function M.addLandmass(def)
    local id = def.id
    local context = string.format('landmass "%s"', id)

    if M.landmasses[id] then
        log.warn('%s is already registered -- ignoring the second one', context)
        return M.landmasses[id]
    end

    -- Before anything binds to a faction id.
    ensureFactions()

    local landmass = {
        id = id,
        displayName = def.displayName or id,
        factionIds = {},
        territoryIds = {},
        settlementIds = {},
    }

    -- Committed as we go. There is no staging pass because there is no
    -- abort to protect: anything unusable is skipped where it is found,
    -- having said so in the log. The order below is the real constraint --
    -- factions before the settlements that name them, and a settlement
    -- before the frontier ring that points at it.

    -- Territories are staged only within a settlement: a settlement's cells
    -- are prepared together and committed together, so until that happens
    -- M.territories cannot answer for them.
    local staged = {}

    for _, factionDef in ipairs(def.factions or {}) do
        local op = prepareFaction(factionDef, context, id)
        local faction = M.factions[op.id]
        if not faction then
            faction = newFaction(op.id, op.tuning.recordId, op.landmass)
            M.factions[op.id] = faction
        end
        applyTuning(faction, op.tuning, op.ctx)
        faction.landmass = faction.landmass or op.landmass
        landmass.factionIds[#landmass.factionIds + 1] = op.id
    end

    local function addTerritory(territory)
        M.territories[territory.id] = territory
        if territory.kind == 'settlement' then
            M.settlementCellIds[#M.settlementCellIds + 1] = territory.id
        else
            M.frontierIds[#M.frontierIds + 1] = territory.id
        end
        landmass.territoryIds[#landmass.territoryIds + 1] = territory.id
        indexGrid(territory)
        indexCells(territory)
    end

    local settlementCount, settlementCells, admitted = 0, 0, 0

    for _, settlementDef in ipairs(def.territories or {}) do
        local settlement, territories =
            prepareSettlement(settlementDef, context, id, staged)
        if settlement then
            -- The reaction filter keeps out records nobody has an opinion
            -- about, which is wrong for a faction that holds ground and
            -- simply has no politics. Admitted here, before its seat binds.
            if admitHolder(settlement.faction) then
                admitted = admitted + 1
            end

            M.settlements[settlement.id] = settlement
            M.settlementIds[#M.settlementIds + 1] = settlement.id
            landmass.settlementIds[#landmass.settlementIds + 1] = settlement.id

            local faction = settlement.faction and M.factions[settlement.faction]
            if faction then
                faction.seats[#faction.seats + 1] = settlement
            elseif settlement.faction then
                -- Not fatal: the settlement is still ground, it simply
                -- projects for nobody. Dangling ids are reported in full by
                -- validateReferences().
                log.warn('settlement "%s" names faction "%s", which is not registered '
                    .. '-- it will project nothing', settlement.id, tostring(settlement.faction))
            end

            -- An interior has no grid position, so it is not a territory. It
            -- still has to resolve to somewhere, or standing inside Balmora
            -- would report no territory at all.
            for _, interior in ipairs(settlement.interiors) do
                M.cellIndex[interior] = settlement.territoryIds[1]
            end

            for _, territory in ipairs(territories) do
                addTerritory(territory)
            end
            settlementCount = settlementCount + 1
            settlementCells = settlementCells + #settlement.territoryIds
        end
    end

    local frontierCells = 0
    for _, frontierDef in ipairs(def.frontier or {}) do
        local territory = prepareFrontier(frontierDef, context, id, staged)
        if territory then
            addTerritory(territory)
            frontierCells = frontierCells + 1
        end
    end

    M.landmasses[id] = landmass
    M.generation = M.generation + 1
    deriveTerritorial()

    if admitted > 0 then
        log.info('registered %d factions that hold ground but have no reactions', admitted)
    end
    log.info('registered landmass "%s": %d factions, %d settlements over %d cells, '
        .. '%d frontier cells',
        id, #landmass.factionIds, settlementCount, settlementCells, frontierCells)
    return landmass
end

--- Add frontier cells to a landmass that is already in the registry.
--
-- Split out from addLandmass because the frontier grid is derived
-- from the settlements rather than authored alongside them (see
-- core/frontier.lua), so it can only be built once the landmass's
-- settlements are in the registry.
--
-- Committed as it goes, as addLandmass is.
function M.addFrontier(landmassId, definitions)
    local context = string.format('landmass "%s" frontier', landmassId)
    local landmass = M.landmasses[landmassId]
    if not landmass then
        -- The generator is handed a landmass id it just finished surveying,
        -- so this means the two have fallen out of step rather than that
        -- the world is odd.
        error(string.format('BalanceOfPower: %s: this landmass has not been registered',
            context), 0)
    end

    local staged, territories = {}, {}
    for _, def in ipairs(definitions) do
        local territory = prepareFrontier(def, context, landmassId, staged)
        if territory then
            territories[#territories + 1] = territory
        end
    end

    for _, territory in ipairs(territories) do
        M.territories[territory.id] = territory
        M.frontierIds[#M.frontierIds + 1] = territory.id
        landmass.territoryIds[#landmass.territoryIds + 1] = territory.id
        indexGrid(territory)
        indexCells(territory)
    end

    M.generation = M.generation + 1
    return #territories
end

--------------------------------------------------------------------------
-- Queries
--------------------------------------------------------------------------

--- Faction ids, sorted, so log output and iteration order are stable
-- across sessions (pairs() order over string keys is not).
function M.sortedFactionIds()
    local ids = {}
    for id in pairs(M.factions) do
        ids[#ids + 1] = id
    end
    table.sort(ids)
    return ids
end

--- Whether a faction is an outside threat rather than a participant in
-- the politics. One place for the comparison, so nothing else has to
-- know the type is spelled as a string.
function M.isInvader(factionId)
    local faction = M.factions[factionId]
    return faction ~= nil and faction.type == config.FACTION_TYPE_INVADER
end

function M.countFactions()
    local count = 0
    for _ in pairs(M.factions) do
        count = count + 1
    end
    return count
end

--- The territory containing a cell, or nil if the cell is unclaimed.
-- @param cellName string interior cell name, or "#x,y" for exterior grid
function M.territoryForCell(cellName)
    local id = M.cellIndex[cellName]
    return id and M.territories[id] or nil
end

--------------------------------------------------------------------------
-- Deferred reference validation
--------------------------------------------------------------------------

-- Adjacency and ownership references can legitimately point at things a
-- later worldspace registers -- that's the mechanism that lets a mainland
-- frontier cell sit next to a Vvardenfell one. So references can only be
-- checked once everything has loaded, which is why this is a separate
-- call the driver makes on its first tick rather than a check inside
-- addLandmass.
function M.validateReferences()
    local problems = 0

    local function report(fmt, ...)
        problems = problems + 1
        if problems <= config.MAX_REPORTED_PROBLEMS then
            log.warn(fmt, ...)
        end
    end

    local function checkTerritoryRefs(ownerId, field, ids)
        for _, refId in ipairs(ids) do
            if not M.territories[refId] then
                report('%s.%s references unknown territory "%s"', ownerId, field, refId)
            end
        end
    end

    local function checkSettlementRefs(ownerId, field, ids)
        for _, refId in ipairs(ids) do
            if not M.settlements[refId] then
                report('%s.%s references unknown settlement "%s"', ownerId, field, refId)
            end
        end
    end

    for id, territory in pairs(M.territories) do
        if territory.defaultOwner and not M.factions[territory.defaultOwner] then
            report('territory "%s" defaults to unknown faction "%s"', id, territory.defaultOwner)
        end
        checkTerritoryRefs(id, 'adjacentFrontier', territory.adjacentFrontier)
        if territory.adjacentSettlements then
            -- Names a settlement record, not a territory: the ring around
            -- a city points at the city, not at one of its cells.
            checkSettlementRefs(id, 'adjacentSettlements', territory.adjacentSettlements)
        end
    end

    for id, settlement in pairs(M.settlements) do
        checkTerritoryRefs(id, 'adjacentFrontier', settlement.adjacentFrontier)
    end

    if problems > config.MAX_REPORTED_PROBLEMS then
        log.warn('... and %d more reference problems', problems - config.MAX_REPORTED_PROBLEMS)
    end
    if problems == 0 then
        log.debug('reference check passed: %d factions, %d settlements, %d frontier cells',
            M.countFactions(), #M.settlementIds, #M.frontierIds)
    end
    return problems
end

return M
