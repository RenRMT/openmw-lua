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

local config = require('scripts.BalanceOfPower.core.config')
local log = require('scripts.BalanceOfPower.core.log')

local M = {}

M.factions = {}      -- factionId   -> normalized faction
M.landmasses = {}    -- landmassId  -> { id, displayName, factionIds, territoryIds }
M.territories = {}   -- territoryId -> normalized territory (anchors and frontier both)
M.anchorIds = {}     -- registration-ordered list of anchor ids
M.frontierIds = {}   -- registration-ordered list of frontier cell ids
M.invasions = {}     -- invasionId  -> normalized invasion
M.cellIndex = {}     -- cell name (interior name or "#x,y") -> territoryId

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

--------------------------------------------------------------------------
-- Power centers
--------------------------------------------------------------------------

-- @param seen table set of power center ids already claimed by this
--        faction, including any staged in the current call
local function normalizePowerCenter(def, context, seen, fallbackLandmass)
    checkTable(def, context, 'powerCenter')
    local id = checkString(def.id, context, 'powerCenter.id')
    local ctx = string.format('%s power center "%s"', context, id)

    if seen[id] then
        fail(ctx, 'duplicate power center id on this faction')
    end
    seen[id] = true

    local tier = def.tier or config.DEFAULT_POWER_CENTER_TIER
    local tierDefaults = config.POWER_CENTER_DEFAULTS[tier]
    if not tierDefaults then
        fail(ctx, 'unknown tier "' .. tostring(tier) .. '"')
    end

    return {
        id = id,
        tier = tier,
        coords = checkCoords(def.coords, ctx, 'coords'),
        landmass = def.landmass or fallbackLandmass,
        weight = checkNumber(def.weight, ctx, 'weight', tierDefaults.weight),
        influenceRange = checkPositive(def.influenceRange, ctx, 'influenceRange',
            tierDefaults.influenceRange),
    }
end

local function normalizePowerCenters(defs, context, existing, fallbackLandmass)
    local seen = {}
    for _, center in ipairs(existing or {}) do
        seen[center.id] = true
    end

    local out = {}
    for _, def in ipairs(defs or {}) do
        out[#out + 1] = normalizePowerCenter(def, context, seen, fallbackLandmass)
    end
    return out
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
        -- Flavor-only factions opt out of the territory/power loop but
        -- still exist in the registry, so a pack can declare one without
        -- it silently becoming a combatant.
        territorial = def.territorial ~= false,
        basePower = basePower,
        landmass = landmass,
        powerCenters = normalizePowerCenters(def.powerCenters, ctx, nil, landmass),
        patrolRoster = copyStrings(def.patrolRoster, ctx, 'patrolRoster'),
        -- Authored reaction table, for factions with no ESM faction
        -- record to read reactions from. nil means "look the faction up
        -- in the game data instead" -- see power.reactionsFor.
        reactions = def.reactions and checkTable(def.reactions, ctx, 'reactions') or nil,
        invading = def.invading or false,
    }
end

-- Validate an extension without touching the faction it extends.
-- Merging rather than overwriting is the point: a faction like Hlaalu
-- legitimately spans several packs (Balmora on Vvardenfell, Bal Foyen
-- once a Tamriel Rebuilt pack loads), and both seats have to project
-- influence at once.
local function prepareExtension(faction, def, context)
    local ctx = string.format('%s faction "%s" (extend)', context, faction.id)

    -- Whichever pack registered first owns the base config. Redefining
    -- it from an extending pack is a load-order-dependent bug, so say so
    -- rather than silently picking a winner.
    for _, field in ipairs({ 'basePower', 'displayName', 'territorial' }) do
        if def[field] ~= nil then
            log.warn('%s: ignoring %s -- it belongs to the pack that registered this faction first',
                ctx, field)
        end
    end

    return {
        powerCenters = normalizePowerCenters(def.powerCenters, ctx, faction.powerCenters,
            def.landmass or faction.landmass),
        patrolRoster = copyStrings(def.patrolRoster, ctx, 'patrolRoster'),
        reactions = def.reactions and checkTable(def.reactions, ctx, 'reactions') or nil,
    }
end

local function applyExtension(faction, extension)
    for _, center in ipairs(extension.powerCenters) do
        faction.powerCenters[#faction.powerCenters + 1] = center
    end

    local seen = {}
    for _, entry in ipairs(faction.patrolRoster) do
        seen[entry] = true
    end
    for _, entry in ipairs(extension.patrolRoster) do
        if not seen[entry] then
            seen[entry] = true
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
            'faction "%s" is already registered -- set extend = true to add power centers '
            .. 'and roster entries to it instead of redefining it', id))
    end
    staged[id] = true

    return { id = id, faction = defineFaction(def, context, fallbackLandmass) }
end

--------------------------------------------------------------------------
-- Territories
--------------------------------------------------------------------------

local function prepareTerritory(def, context, kind, landmassId, staged)
    checkTable(def, context, kind)
    local id = checkString(def.id, context, kind .. '.id')
    local ctx = string.format('%s %s "%s"', context, kind, id)

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

    local territory = {
        id = id,
        kind = kind,
        displayName = def.displayName or id,
        landmass = def.landmass or landmassId,
        -- nil is a legitimate authored value, meaning "unclaimed".
        defaultOwner = def.defaultOwner,
        cells = copyStrings(def.cells, ctx, 'cells'),
        adjacentFrontier = copyStrings(def.adjacentFrontier, ctx, 'adjacentFrontier'),
    }

    if kind == 'anchor' then
        local tier = def.tier or config.DEFAULT_ANCHOR_TIER
        local tierDefaults = config.ANCHOR_DEFAULTS[tier]
        if not tierDefaults then
            fail(ctx, 'unknown tier "' .. tostring(tier) .. '"')
        end
        territory.tier = tier
        territory.siegeThreshold = checkPositive(def.siegeThreshold, ctx, 'siegeThreshold',
            tierDefaults.siegeThreshold)
        territory.cooldownDays = checkNumber(def.cooldownDays, ctx, 'cooldownDays',
            tierDefaults.cooldownDays)
        territory.defenseMultiplier = checkPositive(def.defenseMultiplier, ctx, 'defenseMultiplier',
            tierDefaults.defenseMultiplier)
        -- Optional on anchors: a settlement is identified by its cells,
        -- but distance math still needs a point. An anchor without one
        -- projects nothing and is evaluated only through its frontier
        -- (phase 2).
        if def.centroid ~= nil then
            territory.centroid = checkCoords(def.centroid, ctx, 'centroid')
        end
    else
        territory.centroid = checkCoords(def.centroid, ctx, 'centroid')
        territory.cooldownDays = checkNumber(def.cooldownDays, ctx, 'cooldownDays',
            config.FRONTIER_COOLDOWN_DAYS)
        territory.adjacentAnchors = copyStrings(def.adjacentAnchors, ctx, 'adjacentAnchors')
    end

    return territory
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

--- Register a landmass: its factions, its settlement anchors and its
-- frontier grid. Called once per content pack at world init.
function M.registerLandmass(def)
    checkTable(def, 'registerLandmass', 'definition')
    local id = checkString(def.id, 'registerLandmass', 'id')
    local context = string.format('landmass "%s"', id)

    if M.landmasses[id] then
        fail(context, 'this landmass is already registered')
    end

    -- Phase one: validate everything, mutating nothing.
    local factionOps, territories = {}, {}
    local stagedFactions, stagedTerritories = {}, {}

    for _, factionDef in ipairs(def.factions or {}) do
        factionOps[#factionOps + 1] = prepareFaction(factionDef, context, id, stagedFactions)
    end
    for _, anchorDef in ipairs(def.territories or {}) do
        territories[#territories + 1] = prepareTerritory(anchorDef, context, 'anchor', id,
            stagedTerritories)
    end
    for _, frontierDef in ipairs(def.frontier or {}) do
        territories[#territories + 1] = prepareTerritory(frontierDef, context, 'frontier', id,
            stagedTerritories)
    end

    -- Phase two: commit. Nothing below can fail.
    local landmass = {
        id = id,
        displayName = def.displayName or id,
        factionIds = {},
        territoryIds = {},
    }

    for _, op in ipairs(factionOps) do
        if op.faction then
            M.factions[op.id] = op.faction
        else
            applyExtension(op.target, op.extension)
        end
        landmass.factionIds[#landmass.factionIds + 1] = op.id
    end

    local anchorCount = 0
    for _, territory in ipairs(territories) do
        M.territories[territory.id] = territory
        if territory.kind == 'anchor' then
            M.anchorIds[#M.anchorIds + 1] = territory.id
            anchorCount = anchorCount + 1
        else
            M.frontierIds[#M.frontierIds + 1] = territory.id
        end
        landmass.territoryIds[#landmass.territoryIds + 1] = territory.id
        indexCells(territory)
    end

    M.landmasses[id] = landmass
    M.generation = M.generation + 1

    log.info('registered landmass "%s": %d factions, %d anchors, %d frontier cells',
        id, #landmass.factionIds, anchorCount, #territories - anchorCount)
    return landmass
end

--- Register an invading faction (design doc 4.2).
-- The invader is registered as an ordinary faction as well, so power
-- tracking, reaction propagation and (later) territory rolls treat it
-- like any other participant. Only its growth source and what happens
-- when it wins a territory differ.
function M.registerInvasion(def)
    checkTable(def, 'registerInvasion', 'definition')
    local id = checkString(def.id, 'registerInvasion', 'id')
    local context = string.format('invasion "%s"', id)

    if M.invasions[id] then
        fail(context, 'this invasion is already registered')
    end

    local factionDef = checkTable(def.faction, context, 'faction')
    local op = prepareFaction({
        id = factionDef.id or id,
        displayName = factionDef.displayName,
        territorial = true,
        basePower = factionDef.basePower,
        landmass = factionDef.landmass,
        powerCenters = factionDef.powerCenters,
        patrolRoster = factionDef.patrolRoster,
        reactions = factionDef.reactions,
        invading = true,
    }, context, factionDef.landmass, {})

    if not op.faction then
        fail(context, 'an invading faction cannot use extend = true')
    end

    local stages = {}
    for i, stage in ipairs(factionDef.escalationThresholds or {}) do
        local what = string.format('escalationThresholds[%d]', i)
        checkTable(stage, context, what)
        local entry = {
            stage = checkString(stage.stage, context, what .. '.stage'),
            power = checkNumber(stage.power, context, what .. '.power'),
        }
        if entry.power == nil then
            fail(context, what .. '.power is required')
        end
        -- Ascending order is a correctness requirement, not a style
        -- preference: the stage lookup walks the list and takes the last
        -- threshold the invader's current power clears.
        local previous = stages[i - 1]
        if previous and entry.power <= previous.power then
            fail(context, string.format(
                'escalationThresholds must ascend by power ("%s" at %g does not exceed "%s" at %g)',
                entry.stage, entry.power, previous.stage, previous.power))
        end
        stages[i] = entry
    end

    local invasion = {
        id = id,
        factionId = op.id,
        homeTerritories = copyStrings(factionDef.homeTerritories, context, 'homeTerritories'),
        growthPerDay = checkNumber(factionDef.growthPerDay, context, 'growthPerDay', 0),
        stages = stages,
    }

    -- Commit.
    M.factions[op.id] = op.faction
    -- Back-reference, so code holding a faction can find its escalation
    -- config and current stage without scanning M.invasions.
    op.faction.invasionId = id
    M.invasions[id] = invasion
    M.generation = M.generation + 1

    log.info('registered invasion "%s" (faction "%s"): %d home territories, %d stages',
        id, op.id, #invasion.homeTerritories, #stages)
    return invasion
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

    for id, territory in pairs(M.territories) do
        if territory.defaultOwner and not M.factions[territory.defaultOwner] then
            report('territory "%s" defaults to unknown faction "%s"', id, territory.defaultOwner)
        end
        checkTerritoryRefs(id, 'adjacentFrontier', territory.adjacentFrontier)
        if territory.adjacentAnchors then
            checkTerritoryRefs(id, 'adjacentAnchors', territory.adjacentAnchors)
        end
    end

    for id, invasion in pairs(M.invasions) do
        checkTerritoryRefs(id, 'homeTerritories', invasion.homeTerritories)
    end

    if problems > config.MAX_REPORTED_PROBLEMS then
        log.warn('... and %d more reference problems', problems - config.MAX_REPORTED_PROBLEMS)
    end
    if problems == 0 then
        log.debug('reference check passed: %d factions, %d anchors, %d frontier cells',
            M.countFactions(), #M.anchorIds, #M.frontierIds)
    end
    return problems
end

return M
