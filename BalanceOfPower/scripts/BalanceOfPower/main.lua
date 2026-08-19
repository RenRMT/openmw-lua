-- Balance of Power -- framework global script.
--
-- Owns the save/load boundary and exports the interface;
-- the clock lives in core/driver.lua and the simulation in
-- the other core modules, so each later phase adds a call inside
-- driver.runDay() rather than growing this file.
--
-- On its own this mod will register nothing and report an empty
-- world. It requires content packs.

local core = require('openmw.core')
local interfaces = require('openmw.interfaces')
local types = require('openmw.types')

local api = require('scripts.BalanceOfPower.core.api')
local driver = require('scripts.BalanceOfPower.core.driver')
local events = require('scripts.BalanceOfPower.core.events')
local gold = require('scripts.BalanceOfPower.core.gold')
local holdings = require('scripts.BalanceOfPower.core.holdings')
local log = require('scripts.BalanceOfPower.core.log')
local power = require('scripts.BalanceOfPower.core.power')
local registry = require('scripts.BalanceOfPower.core.registry')
local settings = require('scripts.BalanceOfPower.core.settings')
local state = require('scripts.BalanceOfPower.core.state')
local tribute = require('scripts.BalanceOfPower.core.tribute')

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
        [events.PAY_TRIBUTE] = onPayTribute,
    },
}
