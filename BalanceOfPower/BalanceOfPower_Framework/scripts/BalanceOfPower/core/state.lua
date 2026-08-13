-- Mutable per-save simulation state, and the save/load boundary for it
-- (design doc 3.3).
--
-- This is deliberately the *only* mutable state in the framework: the
-- registry holds authored data that never changes after load, and every
-- other module reads and writes through here. That's what makes
-- serialization a single small table rather than a scavenger hunt.
--
-- Persistence uses the global script's own onSave/onLoad rather than
-- openmw.storage: this state is per-save by nature (a different save is
-- a different world), and a plain Lua table gives us one obvious place
-- to do version reconciliation.
--
-- The save-compat hazard the doc flags is handled by two rules, both
-- enforced here rather than by every data pack:
--   * deserialize() starts from a fresh, fully-shaped state and copies
--     known sections in, so a save written before a section existed
--     loads without erroring on the missing key;
--   * fillDefaults() seeds any faction/territory the registry knows
--     about but the save doesn't, so a content update that adds a
--     faction works on an existing save.

local config = require('scripts.BalanceOfPower.core.config')
local log = require('scripts.BalanceOfPower.core.log')

-- Bump only for changes that need actual migration logic, not for
-- adding a section (deserialize already tolerates that).
local STATE_VERSION = 1

-- Every top-level map in the state, keyed by id. Adding one here is all
-- that's needed for it to be created, saved and restored.
local SECTIONS = {
    'power',          -- factionId   -> number
    'ownership',      -- territoryId -> factionId
    'siegeStreak',    -- settlementId    -> consecutive surrounded-day count
    'lastFlipped',    -- territoryId -> game-day index of the last flip
    'corrupted',      -- territoryId -> invasionId (nil = not overrun)
    'invasionStage',  -- invasionId  -> stage name
}

local M = {}

local function newState()
    local fresh = {
        version = STATE_VERSION,
        -- nil until the first tick establishes a baseline; the driver
        -- treats nil as "start counting from today" rather than
        -- resolving every day since the epoch.
        lastResolvedDay = nil,
    }
    for _, section in ipairs(SECTIONS) do
        fresh[section] = {}
    end
    return fresh
end

local data = newState()

--- The live state table. Callers may mutate it in place.
function M.get()
    return data
end

--- Drop everything back to an empty world. Called on new game.
function M.reset()
    data = newState()
end

--- @return table to hand to the engine from onSave
function M.serialize()
    return data
end

--- Restore from a save, tolerating any shape an older version wrote.
function M.deserialize(saved)
    local fresh = newState()

    if type(saved) == 'table' then
        for _, section in ipairs(SECTIONS) do
            if type(saved[section]) == 'table' then
                for key, value in pairs(saved[section]) do
                    fresh[section][key] = value
                end
            end
        end
        if type(saved.lastResolvedDay) == 'number' then
            fresh.lastResolvedDay = saved.lastResolvedDay
        end
        if saved.version ~= nil and saved.version ~= STATE_VERSION then
            log.info('loaded state version %s into version %d (sections reconciled)',
                tostring(saved.version), STATE_VERSION)
        end
    elseif saved ~= nil then
        log.warn('saved state was %s, not a table -- starting fresh', type(saved))
    end

    data = fresh
end

--- Seed any registered entity that has no state yet, from its static
-- definition. Idempotent and cheap, so the driver just calls it every
-- tick rather than tracking whether a data pack registered late.
-- @return number of keys seeded
function M.fillDefaults(registry)
    local seeded = 0

    for id, faction in pairs(registry.factions) do
        if data.power[id] == nil then
            data.power[id] = math.max(config.MIN_POWER, faction.basePower)
            seeded = seeded + 1
        end
    end

    for id, territory in pairs(registry.territories) do
        -- A nil defaultOwner means "unclaimed", which is a legitimate
        -- authored value, so this can't distinguish missing from
        -- deliberately-empty. Ownership uses false for unclaimed
        -- internally to keep the key present either way.
        if data.ownership[id] == nil then
            data.ownership[id] = territory.defaultOwner or false
            seeded = seeded + 1
        end
        if territory.kind == 'settlement' and data.siegeStreak[id] == nil then
            data.siegeStreak[id] = 0
            seeded = seeded + 1
        end
    end

    -- Every invasion starts dormant regardless of its basePower; the
    -- escalation check (phase 6) promotes it on the first tick if its
    -- power already clears a threshold, which also fires the
    -- BoP_InvasionEscalated event that jumping straight to a stage here
    -- would swallow.
    for id in pairs(registry.invasions) do
        if data.invasionStage[id] == nil then
            data.invasionStage[id] = 'dormant'
            seeded = seeded + 1
        end
    end

    if seeded > 0 then
        log.debug('seeded %d state entries from static definitions', seeded)
    end
    return seeded
end

--- Current owner of a territory, or nil if unclaimed/unknown.
function M.getOwner(territoryId)
    local owner = data.ownership[territoryId]
    if owner == false then
        return nil
    end
    return owner
end

--- Set (or clear, with nil) a territory's owner.
function M.setOwner(territoryId, factionId)
    data.ownership[territoryId] = factionId or false
end

return M
