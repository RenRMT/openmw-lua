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

local log = require('scripts.BalanceOfPower.core.log')

-- Bump only for changes that need actual migration logic, not for
-- adding a section (deserialize already tolerates that).
local STATE_VERSION = 1

-- Every top-level map in the state, keyed by id. Adding one here is all
-- that's needed for it to be created, saved and restored.
local SECTIONS = {
    'power',            -- factionId    -> number
    'ownership',        -- territoryId  -> factionId
    'lastFlipped',      -- territoryId  -> game-day index of the last flip
    -- settlementId -> the day it most recently became surrounded, absent
    -- while it isn't. A fact the framework observes and publishes; what
    -- anything does about it belongs to an extension.
    'surroundedSince',
    -- factionId -> the day its strain most recently passed the
    -- threshold, absent while it hasn't. Same contract.
    'strainedSince',
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

-- Bumped on every write to ownership, whole-table replacements included.
-- Derived views cache against it rather than being invalidated by hand,
-- the same arrangement registry.generation has -- and for the same
-- reason: a cache keyed off setOwner alone silently misses a loaded save.
local ownershipGeneration = 0

--- A counter that changes whenever ownership might have.
function M.ownershipGeneration()
    return ownershipGeneration
end

--- The live state table. Callers may mutate it in place.
function M.get()
    return data
end

--- Drop everything back to an empty world. Called on new game.
function M.reset()
    data = newState()
    ownershipGeneration = ownershipGeneration + 1
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
    ownershipGeneration = ownershipGeneration + 1
end

--- Seed ownership for any registered territory that has none yet.
-- Idempotent and cheap, so the driver just calls it every tick rather
-- than tracking whether a data pack registered late.
--
-- Power is seeded separately, by holdings.seedPower -- see there for why.
-- @return number of keys seeded
-- What the last fillDefaults() ran against: the registry's generation, and the
-- state table itself. The driver calls fillDefaults every tick so a pack that
-- registers late is still seeded, and that is worth keeping -- but between
-- ticks nothing it looks at has changed unless the registry grew or the state
-- was replaced, and walking every territory once an in-game hour forever to
-- seed nothing is not what the save-compat guarantee is asking for.
--
-- The state is compared by identity rather than by a counter because reset()
-- and deserialize() both swap the whole table, which is every way it can
-- become something this has not seen.
local filledGeneration = nil
local filledData = nil

function M.fillDefaults(registry)
    if filledData == data and filledGeneration == registry.generation then
        return 0
    end

    local seeded = 0

    for id, territory in pairs(registry.territories) do
        -- A nil defaultOwner means "unclaimed", which is a legitimate
        -- authored value, so this can't distinguish missing from
        -- deliberately-empty. Ownership uses false for unclaimed
        -- internally to keep the key present either way.
        if data.ownership[id] == nil then
            data.ownership[id] = territory.defaultOwner or false
            seeded = seeded + 1
        end
    end

    -- surroundedSince needs no seeding: absent means not surrounded, and
    -- the daily pass writes it the first time one is.

    filledData, filledGeneration = data, registry.generation

    if seeded > 0 then
        log.debug('seeded %d state entries from static definitions', seeded)
        ownershipGeneration = ownershipGeneration + 1
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
    ownershipGeneration = ownershipGeneration + 1
end

return M
