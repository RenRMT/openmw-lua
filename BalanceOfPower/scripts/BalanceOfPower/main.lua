-- Balance of Power -- framework global script.
--
-- Owns the save/load boundary and exports the interface;
-- the clock lives in core/driver.lua and the simulation in
-- the other core modules, so each later phase adds a call inside
-- driver.runDay() rather than growing this file.
--
-- Its territory comes from the game rather than from an authored list:
-- core/survey.lua reads the world's named exterior cells at load and
-- registers whoever has armed men standing in them. A content pack is
-- for tuning the records cannot express, not for listing places.

local core = require('openmw.core')
local interfaces = require('openmw.interfaces')
local types = require('openmw.types')

local api = require('scripts.BalanceOfPower.core.api')
local cells = require('scripts.BalanceOfPower.core.cells')
local driver = require('scripts.BalanceOfPower.core.driver')
local events = require('scripts.BalanceOfPower.core.events')
local gold = require('scripts.BalanceOfPower.core.gold')
local holdings = require('scripts.BalanceOfPower.core.holdings')
local config = require('scripts.BalanceOfPower.core.config')
local log = require('scripts.BalanceOfPower.core.log')
local power = require('scripts.BalanceOfPower.core.power')
local registry = require('scripts.BalanceOfPower.core.registry')
local settings = require('scripts.BalanceOfPower.core.settings')
local state = require('scripts.BalanceOfPower.core.state')
local survey = require('scripts.BalanceOfPower.core.survey')
local tribute = require('scripts.BalanceOfPower.core.tribute')

--------------------------------------------------------------------------
-- The world, surveyed
--------------------------------------------------------------------------
--
-- At file scope rather than in onInit, because registration has to be
-- complete before the framework seeds state -- and world.cells is fully
-- populated this early, which is the one thing that makes reading the
-- world here legal at all.
--
-- Frontier generation runs in a second pass: it works outward from the
-- settlements already in the registry, so every landmass has to be
-- registered before any of them fills in its wilderness.

local surveyed = survey.plan()
local landmassIds = {}
local tuningEmitted = false

--- The tuning entries, emitted once by the first landmass to register.
--
-- Factions themselves come from the game's records; this carries only
-- what the records have no field for. Emitted once rather than per
-- landmass because which landmass "owns" a faction is not a question the
-- survey can answer -- the Sixth House holds ground on one and threatens
-- every other.
local function tuningFor(landmassId)
    if tuningEmitted then
        return {}
    end
    tuningEmitted = true

    local out = {}
    for factionId, tuning in pairs(config.FACTION_TUNING) do
        local faction = { id = factionId, landmass = landmassId }
        for key, value in pairs(tuning) do
            faction[key] = value
        end
        out[#out + 1] = faction
    end
    return out
end

for landmassId, landmass in pairs(surveyed) do
    api.registerLandmass({
        id = landmassId,
        displayName = landmass.displayName,
        factions = tuningFor(landmassId),
        territories = landmass.territories,
    })
    landmassIds[#landmassIds + 1] = landmassId
end

for _, landmassId in ipairs(landmassIds) do
    api.generateFrontier({ landmass = landmassId })
end

if #landmassIds == 0 then
    log.warn('the survey found no settlements -- nothing to simulate. This means '
        .. 'no named exterior cell in the load order had a factioned NPC standing in it.')
end

local function onInit()
    state.reset()
    state.fillDefaults(registry)
    driver.reset()
    log.info('framework initialized (interface v%d)', api.version)
end

local function onLoad(saved)
    state.deserialize(saved)
    state.fillDefaults(registry)
    driver.reset()
    log.debug('state restored, resuming from day %s', tostring(state.get().lastResolvedDay))
end

local function onSave()
    return state.serialize()
end

--------------------------------------------------------------------------
-- Events in
--------------------------------------------------------------------------
--
-- The interface is global-context only, so a player script -- a quest
-- watcher, a UI -- cannot reach it. These two handlers are the way in,
-- and both treat their payload as hostile: a third-party mod sending
-- nonsense should be inert, not fatal to the simulation.

--- Move a faction's standing, on behalf of something the player did.
local function onAwardPower(data)
    if type(data) ~= 'table' then
        return
    end
    if type(data.faction) ~= 'string' or type(data.delta) ~= 'number' then
        return
    end
    local multiplier = data.rankMultiplier
    if multiplier ~= nil and type(multiplier) ~= 'number' then
        return
    end
    api.awardPower(data.faction, data.delta, multiplier)
end

--- Answer with everything a script would need to draw the world.
--
-- Every other event fires on change only, so without this a script that
-- starts mid-game has no way to learn where things stand until something
-- moves.
local function onRequestSnapshot(data)
    data = type(data) == 'table' and data or {}

    local factions = {}
    for _, id in ipairs(registry.sortedFactionIds()) do
        local faction = registry.factions[id]
        factions[#factions + 1] = {
            id = id,
            displayName = faction.displayName,
            power = power.getLive(id),
            capacity = holdings.capacityOf(id),
            territories = holdings.factionStanding(id).territories,
            strained = holdings.isStrained(id),
            type = faction.type,
            -- The id in the game's own records, which is what a player
            -- script has to match against when it asks the engine what
            -- the player is a member of. Usually the same string; for
            -- the faction whose modelled identity does not line up with
            -- one record, it is not.
            recordId = faction.recordId or id,
        }
    end

    -- Most of the game world is not territory, so a cell that resolves
    -- to nothing is an ordinary answer rather than an error.
    local territory
    local record = type(data.cell) == 'string'
        and registry.territoryForCell(data.cell) or nil
    if record then
        territory = {
            id = record.id,
            owner = state.getOwner(record.id),
            kind = record.kind,
            region = record.region,
            settlement = record.settlement,
        }
    end

    events.emit(events.SNAPSHOT, {
        day = state.get().lastResolvedDay,
        factions = factions,
        territory = territory,
    })
end

--- The name a faction is shown under, or nil if it holds nothing.
local function displayNameOf(factionId)
    local faction = factionId and registry.factions[factionId] or nil
    return faction and faction.displayName or nil
end

--- The cell nearest the middle of a settlement's footprint.
--
-- The mean of the footprint is not itself a cell -- a settlement wrapped
-- around a bay has its centre of mass in the water -- so this takes the
-- member cell closest to that mean. Whatever draws one mark per
-- settlement needs a cell to put it in, and picking it here rather than
-- in the map keeps every consumer agreeing on which one it is.
local function middleCell(grid)
    local sumX, sumY = 0, 0
    for _, entry in ipairs(grid) do
        sumX, sumY = sumX + entry.gridX, sumY + entry.gridY
    end
    local meanX, meanY = sumX / #grid, sumY / #grid

    local best, bestDistance = grid[1], nil
    for _, entry in ipairs(grid) do
        local dx, dy = entry.gridX - meanX, entry.gridY - meanY
        local distance = dx * dx + dy * dy
        if not bestDistance or distance < bestDistance then
            best, bestDistance = entry, distance
        end
    end
    return best
end

--- Where every settlement stands, for whatever is drawing a map.
--
-- Walks settlements rather than the whole territory table so the frontier
-- -- which is most of the map and changes hands constantly -- stays out
-- of the payload. A caller wanting that too asks for it with
-- REQUEST_TERRITORY rather than having this grow into a full world dump.
local function onRequestMap()
    local rows = {}
    local places = {}

    for _, settlementId in ipairs(registry.settlementIds) do
        local settlement = registry.settlements[settlementId]
        local mine = {}
        for _, territoryId in ipairs(settlement.territoryIds) do
            local territory = registry.territories[territoryId]
            local gridX, gridY = cells.parse(territory.cells[1])
            if gridX then
                local owner = state.getOwner(territoryId)
                local row = {
                    gridX = gridX,
                    gridY = gridY,
                    settlement = settlement.displayName,
                    settlementId = settlementId,
                    owner = owner,
                    ownerName = displayNameOf(owner),
                }
                rows[#rows + 1] = row
                mine[#mine + 1] = row
            end
        end

        -- A settlement whose every cell is interior has no footprint to
        -- put a mark in, and is left out rather than placed at nowhere.
        if #mine > 0 then
            local centre = middleCell(mine)
            places[#places + 1] = {
                id = settlementId,
                name = settlement.displayName,
                tier = settlement.tier,
                gridX = centre.gridX,
                gridY = centre.gridY,
                owner = centre.owner,
                ownerName = centre.ownerName,
            }
        end
    end

    events.emit(events.MAP, {
        day = state.get().lastResolvedDay,
        cells = rows,
        settlements = places,
    })
end

--- Who controls every cell in the world, frontier included.
--
-- Grouped by faction and flattened to bare coordinates. See the event's
-- comment for why: this is the whole generated map, and at one table per
-- cell it would be thousands of them crossing the global/player boundary
-- on every request.
local function onRequestTerritory()
    local byFaction = {}
    local order = {}

    local function add(territoryId)
        local owner = state.getOwner(territoryId)
        if not owner then
            return
        end
        local bucket = byFaction[owner]
        if not bucket then
            bucket = {
                faction = owner,
                factionName = displayNameOf(owner),
                cells = {},
            }
            byFaction[owner] = bucket
            order[#order + 1] = bucket
        end
        for _, cellName in ipairs(registry.territories[territoryId].cells) do
            local gridX, gridY = cells.parse(cellName)
            if gridX then
                local flat = bucket.cells
                flat[#flat + 1] = gridX
                flat[#flat + 1] = gridY
            end
        end
    end

    for _, territoryId in ipairs(registry.settlementCellIds) do
        add(territoryId)
    end
    for _, territoryId in ipairs(registry.frontierIds) do
        add(territoryId)
    end

    events.emit(events.TERRITORY, {
        day = state.get().lastResolvedDay,
        owners = order,
    })
end

--- Take a member's gold and turn it into their faction's standing.
--
-- Everything the window checked is checked again here. The window runs
-- in player context and any mod can send this event, so its arithmetic
-- is a convenience for the player rather than a source of truth -- and
-- the gold is taken before the power is awarded, so a payment that
-- cannot complete cannot pay out either.
local function onPayTribute(data)
    local function refuse(reason, faction)
        if data and data.player then
            data.player:sendEvent(events.TRIBUTE_PAID,
                { ok = false, reason = reason, faction = faction })
        end
    end

    if type(data) ~= 'table' or data.player == nil then
        return
    end
    if type(data.faction) ~= 'string' or not registry.factions[data.faction] then
        return refuse('faction', data.faction)
    end

    local amount = math.floor(tonumber(data.gold) or 0)
    if amount <= 0 then
        return refuse('amount', data.faction)
    end

    -- Rank is read here rather than taken from the payload: it decides
    -- how much standing the gold buys, so trusting the sender would let
    -- a forged event buy a Hortator's worth at a novice's price.
    local recordId = registry.factions[data.faction].recordId or data.faction
    local rank = types.NPC.getFactionRank(data.player, recordId) or 0
    if rank < 1 then
        return refuse('rank', data.faction)
    end
    local record = core.factions.records[recordId]
    local rankCount = record and record.ranks and #record.ranks or 1

    -- Counted before any of it is taken. Taking first and refunding on a
    -- shortfall means inventing gold to hand back, which is a worse bug
    -- than the one it fixes.
    if gold.held(data.player) < amount then
        return refuse('gold', data.faction)
    end
    local paid = gold.take(data.player, amount)
    if paid <= 0 then
        return refuse('gold', data.faction)
    end

    local gained = tribute.powerFor(paid, rank, rankCount)
    power.apply(data.faction, gained)
    log.info('tribute: %d gold to %s at rank %d -> %+.2f power',
        paid, data.faction, rank, gained)

    data.player:sendEvent(events.TRIBUTE_PAID, {
        ok = true,
        faction = data.faction,
        gold = paid,
        power = gained,
    })
end

-- Script bodies run once per session, before any handler, so this
-- starts the tick exactly once. The first poll lands after onInit or
-- onLoad has set up state.
driver.start()

-- Before the first tick, so the day the simulation resolves already runs
-- on whatever the player has chosen. Declines quietly in a game whose
-- built-in settings scripts are missing.
settings.register(interfaces)
settings.subscribe(settings.sync)
settings.sync()

return {
    interfaceName = 'BalanceOfPower',
    interface = api,
    engineHandlers = {
        onInit = onInit,
        onLoad = onLoad,
        onSave = onSave,
    },
    eventHandlers = {
        [events.AWARD_POWER] = onAwardPower,
        [events.REQUEST_SNAPSHOT] = onRequestSnapshot,
        [events.REQUEST_MAP] = onRequestMap,
        [events.REQUEST_TERRITORY] = onRequestTerritory,
        [events.PAY_TRIBUTE] = onPayTribute,
    },
}
