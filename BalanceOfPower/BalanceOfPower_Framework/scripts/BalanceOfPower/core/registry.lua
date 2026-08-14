-- The registry: authored, immutable-after-load data from every content
-- pack, normalized into one shape (design doc 3.8).
--
-- The rule this file exists to protect: data packs depend on the
-- framework, never the reverse. Nothing here knows what a landmass is
-- called or which factions exist -- it only knows the *shape* of a
-- landmass definition. The day this file needs an `if id == "cyrodiil"`
-- branch, the abstraction has failed.
--
-- Two properties are deliberate:
--
-- * Validation is loud and fatal. These functions are called from a data
--   pack's own script, so an error() here kills that pack's script and
--   leaves the framework running -- exactly the blast radius you want.
--   The author gets a message naming their field, and a third-party pack
--   with a typo can't half-register and produce a world that's subtly
--   wrong ten hours into a save.
--
-- * Registration is two-phase. Everything is validated and normalized
--   into a staging table first, and committed only once the whole
--   definition has passed. A pack with a bad last frontier cell
--   registers nothing at all, rather than leaving the simulation running
--   on half a landmass that no retry can complete (the retry would trip
--   over the factions the failed attempt had already inserted).

local cells = require('scripts.BalanceOfPower.core.cells')
local config = require('scripts.BalanceOfPower.core.config')
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
-- grid, not a tunable, so computing this here rather than making every
-- pack pass it is safe -- see the constant's comment.
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
-- Validation helpers
--------------------------------------------------------------------------

-- Level 0: report the message as-is, without prefixing this file's line
-- number. The useful location is the data pack's, not ours.
local function fail(context, message)
    error(string.format('BalanceOfPower: %s: %s', context, message), 0)
end

local function checkTable(value, context, what)
    if type(value) ~= 'table' then
        fail(context, what .. ' must be a table, got ' .. type(value))
    end
    return value
end

local function checkString(value, context, what)
    if type(value) ~= 'string' or value == '' then
        fail(context, what .. ' must be a non-empty string')
    end
    return value
end

local function checkNumber(value, context, what, default)
    if value == nil then
        return default
    end
    if type(value) ~= 'number' then
        fail(context, what .. ' must be a number, got ' .. type(value))
    end
    return value
end

local function checkPositive(value, context, what, default)
    local number = checkNumber(value, context, what, default)
    if number == nil then
        fail(context, what .. ' is required')
    end
    if number <= 0 then
        fail(context, what .. ' must be greater than zero')
    end
    return number
end

local function checkCoords(value, context, what)
    checkTable(value, context, what)
    if type(value.x) ~= 'number' or type(value.y) ~= 'number' then
        fail(context, what .. ' needs numeric x and y fields')
    end
    -- z is accepted and carried, but the simulation is horizontal:
    -- distance math ignores it, so a tower and its courtyard aren't
    -- treated as far apart.
    return { x = value.x, y = value.y, z = checkNumber(value.z, context, what .. '.z', 0) }
end

-- Copies a list of ids, rejecting anything that isn't a string. Returns
-- a new table so a pack can't mutate registered data by holding on to
-- the table it passed in.
local function copyStrings(value, context, what)
    if value == nil then
        return {}
    end
    checkTable(value, context, what)
    local out = {}
    for i, entry in ipairs(value) do
        if type(entry) ~= 'string' then
            fail(context, string.format('%s[%d] must be a string, got %s', what, i, type(entry)))
        end
        out[i] = entry
    end
    return out
end

--- A faction's patrol roster: record ids the framework never interprets,
-- each carrying the tier at which it becomes available.
--
-- Two authoring forms, and the plain one is not a shortcut to be
-- migrated away from. `'hlaalu guard'` is a tier-1 entry and reads
-- better than `{ id = 'hlaalu guard', tier = 1 }` for the many factions
-- whose patrols are all the same calibre; the table form is for the
-- faction that fields something worse or better as its projection
-- changes.
--
-- Tiers are numbers rather than names on purpose. A name is content --
-- one pack's "veteran" is another's "housecarl" -- and the framework
-- would then be storing a vocabulary it can't check and doesn't use.
local function normalizeRoster(value, context)
    if value == nil then
        return {}
    end
    checkTable(value, context, 'patrolRoster')

    local out = {}
    for index, entry in ipairs(value) do
        local what = string.format('patrolRoster[%d]', index)
        if type(entry) == 'string' then
            out[index] = { id = checkString(entry, context, what), tier = 1 }
        elseif type(entry) == 'table' then
            local tier = checkNumber(entry.tier, context, what .. '.tier', 1)
            if tier < 1 then
                fail(context, what .. '.tier must be 1 or greater')
            end
            out[index] = {
                id = checkString(entry.id, context, what .. '.id'),
                tier = math.floor(tier),
            }
        else
            fail(context, string.format(
                '%s must be a record id or { id = ..., tier = ... }, got %s',
                what, type(entry)))
        end
    end
    return out
end

--------------------------------------------------------------------------
-- Settlements
--------------------------------------------------------------------------

--- The tier ladder as a lookup, with a readable error when a pack misses.
local function tierDefaultsFor(tier, ctx)
    local defaults = config.SETTLEMENT_TIERS[tier]
    if not defaults then
        fail(ctx, string.format('unknown tier "%s" -- expected one of: %s',
            tostring(tier), table.concat(config.SETTLEMENT_TIER_ORDER, ', ')))
    end
    return defaults
end

--------------------------------------------------------------------------
-- Factions
--------------------------------------------------------------------------

local function defineFaction(def, context, fallbackLandmass)
    local id = def.id
    local ctx = string.format('%s faction "%s"', context, id)
    local landmass = def.landmass or fallbackLandmass

    local basePower = checkNumber(def.basePower, ctx, 'basePower', config.DEFAULT_BASE_POWER)
    if basePower < config.MIN_POWER then
        fail(ctx, string.format('basePower must be at least %d', config.MIN_POWER))
    end

    return {
        id = id,
        displayName = def.displayName or id,
        -- Whether this faction appears on the map at all. `false` makes
        -- it a power-only faction: it has a power score, it reacts to
        -- everyone else through the reaction table, and other systems
        -- can read its standing -- but it holds no ground, projects no
        -- influence, and can never be recorded as owning a territory.
        --
        -- That's the split between a Great House and a guild. The
        -- Fighters Guild is a real political force whose fortunes rise
        -- and fall with its allies'; it just doesn't own Balmora.
        --
        -- A faction that shouldn't participate at all is simply not
        -- registered.
        territorial = def.territorial ~= false,
        basePower = basePower,
        -- Power gained per resolved day with nobody doing anything. A
        -- knob on an ordinary faction rather than a mode: the faction
        -- that grows on its own is the same shape as every other one,
        -- and differs by a number.
        growthPerDay = checkNumber(def.growthPerDay, ctx, 'growthPerDay',
            config.DEFAULT_GROWTH_PER_DAY),
        -- Opt in to fighting. A hostile faction attacks the player, and
        -- attacks any faction it regards at or below
        -- HOSTILITY_REACTION_THRESHOLD. Nothing in the framework acts on
        -- this -- see core/hostility.lua for what it means and
        -- core/patrol.lua for who reads it.
        hostile = def.hostile == true,
        landmass = landmass,
        -- Filled in by registerLandmass from the settlements that name
        -- this faction. A faction has no geography of its own: it holds
        -- seats, and a seat is a settlement.
        seats = {},
        patrolRoster = normalizeRoster(def.patrolRoster, ctx),
        -- Authored reactions: how this faction feels about others, the
        -- same direction the game's own records use. Merged over the
        -- record row where there is one -- see core/power.lua.
        reactions = def.reactions and checkTable(def.reactions, ctx, 'reactions') or nil,
    }
end

-- Validate an extension without touching the faction it extends.
--
-- A faction like Hlaalu legitimately spans several packs -- Balmora on
-- Vvardenfell, Bal Foyen once a Tamriel Rebuilt pack loads -- and both
-- seats have to project at once. That now needs nothing merged: the
-- settlements are registered against their own landmass and name the
-- faction, so the second pack's seats arrive on their own. What is left
-- to merge is the faction's own content, its roster and its reactions.
local function prepareExtension(faction, def, context)
    local ctx = string.format('%s faction "%s" (extend)', context, faction.id)

    -- Whichever pack registered first owns the base config. Redefining
    -- it from an extending pack is a load-order-dependent bug, so say so
    -- rather than silently picking a winner.
    for _, field in ipairs({ 'basePower', 'displayName', 'territorial',
                             'growthPerDay', 'hostile' }) do
        if def[field] ~= nil then
            log.warn('%s: ignoring %s -- it belongs to the pack that registered this faction first',
                ctx, field)
        end
    end

    return {
        patrolRoster = normalizeRoster(def.patrolRoster, ctx),
        reactions = def.reactions and checkTable(def.reactions, ctx, 'reactions') or nil,
    }
end

local function applyExtension(faction, extension)
    -- Deduplicated by record id: two packs listing the same guard is
    -- ordinary, and the entry that arrives first keeps its tier.
    local seen = {}
    for _, entry in ipairs(faction.patrolRoster) do
        seen[entry.id] = true
    end
    for _, entry in ipairs(extension.patrolRoster) do
        if not seen[entry.id] then
            seen[entry.id] = true
            faction.patrolRoster[#faction.patrolRoster + 1] = entry
        end
    end

    if extension.reactions then
        faction.reactions = faction.reactions or {}
        for otherId, value in pairs(extension.reactions) do
            faction.reactions[otherId] = value
        end
    end
end

--- Validate a faction definition into a staged operation.
-- @param staged table ids already staged by this call, so two entries in
--        one definition collide the same way two packs would
local function prepareFaction(def, context, fallbackLandmass, staged)
    checkTable(def, context, 'faction')
    local id = checkString(def.id, context, 'faction.id')
    local existing = M.factions[id]

    if def.extend then
        if not existing then
            fail(context, string.format(
                'faction "%s" is marked extend = true but has not been registered yet '
                .. '-- the pack that defines it must load first', id))
        end
        return { id = id, target = existing, extension = prepareExtension(existing, def, context) }
    end

    if existing or staged[id] then
        fail(context, string.format(
            'faction "%s" is already registered -- set extend = true to add roster '
            .. 'entries and reactions to it instead of redefining it', id))
    end
    staged[id] = true

    return { id = id, faction = defineFaction(def, context, fallbackLandmass) }
end

--------------------------------------------------------------------------
-- Territories
--------------------------------------------------------------------------

local function prepareFrontier(def, context, landmassId, staged)
    checkTable(def, context, 'frontier')
    local id = checkString(def.id, context, 'frontier.id')
    local ctx = string.format('%s frontier "%s"', context, id)

    local clash = M.territories[id]
    if clash then
        fail(ctx, string.format('this id is already registered by landmass "%s"', clash.landmass))
    end
    if staged[id] then
        fail(ctx, 'this id appears twice in the same definition')
    end
    staged[id] = true

    if def.defaultOwner ~= nil then
        checkString(def.defaultOwner, ctx, 'defaultOwner')
    end

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
        cells = copyStrings(def.cells, ctx, 'cells'),
        centroid = checkCoords(def.centroid, ctx, 'centroid'),
        cooldownDays = checkNumber(def.cooldownDays, ctx, 'cooldownDays',
            config.FRONTIER_COOLDOWN_DAYS),
        adjacentFrontier = copyStrings(def.adjacentFrontier, ctx, 'adjacentFrontier'),
        adjacentSettlements = copyStrings(def.adjacentSettlements, ctx, 'adjacentSettlements'),
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
local function prepareSettlement(def, context, landmassId, staged, stagedSettlements)
    checkTable(def, context, 'settlement')
    local id = checkString(def.id, context, 'settlement.id')
    local ctx = string.format('%s settlement "%s"', context, id)

    if M.settlements[id] or stagedSettlements[id] then
        fail(ctx, 'this settlement id is already registered')
    end
    stagedSettlements[id] = true

    local tier = def.tier or config.DEFAULT_SETTLEMENT_TIER
    local tierDefaults = tierDefaultsFor(tier, ctx)

    if def.defaultOwner ~= nil then
        checkString(def.defaultOwner, ctx, 'defaultOwner')
    end
    if def.faction ~= nil then
        checkString(def.faction, ctx, 'faction')
    end

    local cellNames = copyStrings(def.cells, ctx, 'cells')
    if #cellNames == 0 then
        fail(ctx, 'a settlement needs at least one cell')
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
        -- The projection origin, and load-bearing: this is the point
        -- every reach calculation measures from. For a multi-cell city it
        -- should be the middle of the footprint, so Vivec radiates from
        -- the city rather than from whichever cell was listed first.
        centroid = def.centroid and checkCoords(def.centroid, ctx, 'centroid') or nil,
        weight = checkNumber(def.weight, ctx, 'weight', tierDefaults.weight),
        influenceRange = checkPositive(def.influenceRange, ctx, 'influenceRange',
            tierDefaults.influenceRange),
        adjacentFrontier = copyStrings(def.adjacentFrontier, ctx, 'adjacentFrontier'),
    }

    local cooldownDays = checkNumber(def.cooldownDays, ctx, 'cooldownDays',
        tierDefaults.cooldownDays)

    local territories = {}
    local sumX, sumY = 0, 0
    for _, cellName in ipairs(cellNames) do
        local gridX, gridY = cells.parse(cellName)
        if not gridX then
            settlement.interiors[#settlement.interiors + 1] = cellName
        else
            local territoryId = string.format('%s_%d_%d', id, gridX, gridY)
            if M.territories[territoryId] or staged[territoryId] then
                fail(ctx, string.format('cell %s is already a registered territory', cellName))
            end
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

    if #territories == 0 then
        fail(ctx, 'a settlement needs at least one exterior cell')
    end

    -- Derived from the footprint unless the pack said otherwise, so a
    -- fifteen-cell city radiates from its middle rather than from
    -- whichever cell happened to be listed first. Deriving it here rather
    -- than in every pack keeps one definition of where a cell is: a pack
    -- computing this itself has to agree with the frontier generator
    -- about the grid, and two copies of that arithmetic is how a map ends
    -- up subtly out of register with its own settlements.
    if not settlement.centroid then
        settlement.centroid = { x = sumX / #territories, y = sumY / #territories }
    end

    return settlement, territories
end

local function indexCells(territory)
    for _, cellName in ipairs(territory.cells) do
        local owner = M.cellIndex[cellName]
        if owner and owner ~= territory.id then
            -- A warning rather than an error: overlapping claims are a
            -- content problem between two packs, not a reason to refuse
            -- to load either of them.
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

--- Register a landmass: its factions, its settlements and its
-- frontier grid. Called once per content pack at world init.
function M.registerLandmass(def)
    checkTable(def, 'registerLandmass', 'definition')
    local id = checkString(def.id, 'registerLandmass', 'id')
    local context = string.format('landmass "%s"', id)

    if M.landmasses[id] then
        fail(context, 'this landmass is already registered')
    end

    -- Phase one: validate everything, mutating nothing.
    local factionOps, settlements, territories = {}, {}, {}
    local stagedFactions, stagedTerritories, stagedSettlements = {}, {}, {}

    for _, factionDef in ipairs(def.factions or {}) do
        factionOps[#factionOps + 1] = prepareFaction(factionDef, context, id, stagedFactions)
    end
    for _, settlementDef in ipairs(def.territories or {}) do
        local settlement, cellTerritories =
            prepareSettlement(settlementDef, context, id, stagedTerritories, stagedSettlements)
        settlements[#settlements + 1] = settlement
        for _, territory in ipairs(cellTerritories) do
            territories[#territories + 1] = territory
        end
    end
    for _, frontierDef in ipairs(def.frontier or {}) do
        territories[#territories + 1] = prepareFrontier(frontierDef, context, id, stagedTerritories)
    end

    -- Phase two: commit. Nothing below can fail.
    local landmass = {
        id = id,
        displayName = def.displayName or id,
        factionIds = {},
        territoryIds = {},
        settlementIds = {},
    }

    for _, op in ipairs(factionOps) do
        if op.faction then
            M.factions[op.id] = op.faction
        else
            applyExtension(op.target, op.extension)
        end
        landmass.factionIds[#landmass.factionIds + 1] = op.id
    end

    for _, settlement in ipairs(settlements) do
        M.settlements[settlement.id] = settlement
        M.settlementIds[#M.settlementIds + 1] = settlement.id
        landmass.settlementIds[#landmass.settlementIds + 1] = settlement.id
        -- Hand the settlement to the faction whose seat it is. Done here
        -- rather than in prepareSettlement because a settlement may name
        -- a faction this same call is about to register, and validation
        -- must not depend on the order the two appear in.
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
    end

    for _, territory in ipairs(territories) do
        M.territories[territory.id] = territory
        if territory.kind == 'settlement' then
            M.settlementCellIds[#M.settlementCellIds + 1] = territory.id
        else
            M.frontierIds[#M.frontierIds + 1] = territory.id
        end
        landmass.territoryIds[#landmass.territoryIds + 1] = territory.id
        indexCells(territory)
    end

    M.landmasses[id] = landmass
    M.generation = M.generation + 1

    local settlementCells = 0
    for _, settlement in ipairs(settlements) do
        settlementCells = settlementCells + #settlement.territoryIds
    end

    log.info('registered landmass "%s": %d factions, %d settlements over %d cells, '
        .. '%d frontier cells',
        id, #landmass.factionIds, #settlements, settlementCells,
        #territories - settlementCells)
    return landmass
end

--- Add frontier cells to a landmass that is already registered.
--
-- Split out from registerLandmass because the frontier grid is derived
-- from the settlements rather than authored alongside them (see
-- core/frontier.lua), so it can only be built once the landmass's
-- settlements are in the registry.
--
-- Same two-phase discipline: validate everything, then commit.
function M.registerFrontier(landmassId, definitions)
    local context = string.format('landmass "%s" frontier', landmassId)
    local landmass = M.landmasses[landmassId]
    if not landmass then
        fail(context, 'this landmass has not been registered')
    end
    checkTable(definitions, context, 'definitions')

    local staged, territories = {}, {}
    for _, def in ipairs(definitions) do
        territories[#territories + 1] = prepareFrontier(def, context, landmassId, staged)
    end

    for _, territory in ipairs(territories) do
        M.territories[territory.id] = territory
        M.frontierIds[#M.frontierIds + 1] = territory.id
        landmass.territoryIds[#landmass.territoryIds + 1] = territory.id
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
-- later pack registers -- that's the mechanism that lets a mainland
-- frontier cell sit next to a Vvardenfell one. So references can only be
-- checked once everything has loaded, which is why this is a separate
-- call the driver makes on its first tick rather than a check inside
-- registerLandmass.
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
