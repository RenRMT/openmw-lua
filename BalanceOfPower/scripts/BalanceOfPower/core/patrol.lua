-- What should be standing in this cell, and why.
--
-- The framework decides that patrols happen; a content pack decides what
-- they are. Everything here works in faction ids, counts and opaque
-- record ids -- it never learns that 'hlaalu guard' is a Dunmer with a
-- spear, and it must not.
--
-- This file makes decisions and creates nothing. Placing actors, giving
-- them AI packages and clearing them up afterwards touches world,
-- nearby and the AI interface, none of which exist outside a running
-- game -- so that lives in its own module and this one stays pure. The
-- split is not tidiness: every judgement that can be wrong is in here,
-- under test, and the layer that cannot be tested is left with no
-- branches worth arguing about.
--
-- The one thing worth understanding before reading on is why the roll is
-- seeded rather than random. See M.plan.
--
-- GLOBAL context only.

local config = require('scripts.BalanceOfPower.core.config')
local holdings = require('scripts.BalanceOfPower.core.holdings')
local hostility = require('scripts.BalanceOfPower.core.hostility')
local registry = require('scripts.BalanceOfPower.core.registry')
local resolve = require('scripts.BalanceOfPower.core.resolve')
local state = require('scripts.BalanceOfPower.core.state')

local M = {}

--------------------------------------------------------------------------
-- Seeded rolls
--------------------------------------------------------------------------

-- A Lehmer generator. Deliberately not math.random: the resolution loop
-- owns that, tests replace it, and a spawn decision reaching for the
-- same source would make both harder to reason about.
--
-- 16807 and 2^31-1 are the classic MINSTD constants, chosen here because
-- the largest intermediate product stays under 2^53 and so is exact in a
-- double. A bigger multiplier would silently lose precision in Lua 5.1,
-- which has no integers, and the failure would look like a subtly biased
-- world rather than an error.
local MODULUS = 2147483647

local function hashed(text)
    local value = 5381
    for index = 1, #text do
        value = (value * 33 + string.byte(text, index)) % MODULUS
    end
    -- Zero is a fixed point of the generator: it would make every cell
    -- unlucky forever, and only for the one id that happened to hash
    -- there.
    return value == 0 and 1 or value
end

--- The seed for one cell on one day.
--
-- **The day goes first, and that is not arbitrary.** djb2 folds each
-- character in by multiplying what came before, so an early character
-- moves the result by a huge scrambled amount and a late one barely
-- moves it at all. Seeding on "territory@day" put the day last: the hash
-- came out very nearly linear in it, one generator step preserved that,
-- and consecutive days landed about 0.000008 apart. A cell was then
-- lucky or unlucky for several hundred days in a row -- most of them
-- unlucky, so the map simply had no patrols on it.
--
-- Nothing about that looks wrong from the inside. The roll is uniform
-- across cells, it is stable per day as intended, and every individual
-- number is plausible; only the correlation between one day and the next
-- is broken, and the only symptom is a world that stays empty.
local function seedFor(territoryId, day)
    return hashed(tostring(day) .. '@' .. territoryId)
end

local function nextRoll(seed)
    local advanced = (16807 * seed) % MODULUS
    return advanced, advanced / MODULUS
end

--------------------------------------------------------------------------
-- Candidates
--------------------------------------------------------------------------

--- Every faction that might field a patrol here, with the projection
-- that decides how big and how well armed it would be.
--
-- Two ways onto the list, and they are different questions. The owner
-- patrols its own ground because it holds it. A belligerent faction
-- patrols wherever it projects at all, held by somebody else or not --
-- which is what makes an invader visible on a border before it takes
-- anything, and gives ambient growth something to show for itself long
-- before the ownership map moves.
local function candidates(territory)
    local out, seen = {}, {}

    local function add(factionId)
        if not factionId or seen[factionId] then
            return
        end
        local faction = registry.factions[factionId]
        -- A faction with no roster fields no patrols. That is the whole
        -- opt-out, and it needs no flag: a guild that holds no ground and
        -- musters nobody simply has an empty list.
        if not faction or #faction.patrolRoster == 0 then
            return
        end
        seen[factionId] = true
        out[#out + 1] = {
            faction = factionId,
            projection = resolve.effectivePower(factionId, territory),
        }
    end

    add(state.getOwner(territory.id))

    local reach = resolve.projectionFactors(territory)
    for _, factionId in ipairs(reach.ids) do
        if hostility.isBelligerent(factionId)
            and resolve.effectivePower(factionId, territory) >= config.PATROL_MIN_PROJECTION then
            add(factionId)
        end
    end

    return out
end

--------------------------------------------------------------------------
-- Sizing
--------------------------------------------------------------------------

--- How many, from how hard the faction is projecting here. One member
-- is the floor: a faction that holds ground at all can put somebody on
-- the road.
--
-- A strained faction fields STRAIN_PATROL_PENALTY fewer, down to that
-- floor -- thin control that looks thin. Zero by default, and skipped
-- entirely then, so an omitted factionId costs nothing.
function M.sizeFor(projection, factionId)
    local count = 1 + math.floor(projection / config.PATROL_POWER_PER_MEMBER)
    if config.STRAIN_PATROL_PENALTY > 0 and factionId and holdings.isStrained(factionId) then
        count = math.max(1, math.floor(count * (1 - config.STRAIN_PATROL_PENALTY)))
    end
    return math.min(count, config.PATROL_MAX_MEMBERS)
end

--- The highest tier this projection unlocks, capped by what the roster
-- actually offers. A pack that authored one tier gets tier 1 forever,
-- which is the correct behaviour rather than a limitation -- it said
-- what it fields.
function M.tierFor(projection, roster)
    local available = 1
    for _, entry in ipairs(roster) do
        if entry.tier > available then
            available = entry.tier
        end
    end
    local earned = 1 + math.floor(projection / config.PATROL_POWER_PER_TIER)
    return math.min(earned, available)
end

--- Pick `count` records from the entries at or below `tier`.
--
-- At or below, not exactly at: a faction that unlocks its best troops
-- should still field the ordinary ones alongside them. Drawing only from
-- the top tier would make a strong faction's patrols uniform, which
-- reads as an honour guard rather than a garrison.
local function draw(roster, tier, count, seed)
    local eligible = {}
    for _, entry in ipairs(roster) do
        if entry.tier <= tier then
            eligible[#eligible + 1] = entry.id
        end
    end
    if #eligible == 0 then
        return {}, seed
    end

    local picked = {}
    for index = 1, count do
        local value
        seed, value = nextRoll(seed)
        picked[index] = eligible[math.floor(value * #eligible) + 1]
    end
    return picked, seed
end

--------------------------------------------------------------------------
-- Planning
--------------------------------------------------------------------------

--- What should be standing in this cell today, or nil for nothing.
--
-- The roll is seeded on the territory and the day rather than taken from
-- a live random source, and that is load-bearing in three ways at once.
-- A player crossing a cell boundary back and forth gets the same answer
-- instead of a fresh roll each time, so patrols cannot be farmed. A
-- patrol despawned when its cell went quiet is the same patrol when the
-- player returns, so the world is stable within a day. And a plan can be
-- recomputed after a save reload without the world quietly rearranging
-- itself.
--
-- @param territoryId string
-- @param day number the resolved day to plan for
-- @param opts table|nil { lastSpawnedDay = number } from whatever tracks
--        live actors; omitted means the cell is off cooldown
-- @return table|nil {
--     territory, day,
--     groups = { { faction, count, tier, records = {...},
--                  hostileToPlayer, fights = { factionId, ... } }, ... }
--   }
function M.plan(territoryId, day, opts)
    local territory = registry.territories[territoryId]
    if not territory then
        return nil
    end

    opts = opts or {}
    local since = opts.lastSpawnedDay
    if since and day - since < config.PATROL_COOLDOWN_DAYS then
        return nil
    end

    local seed = seedFor(territoryId, day)
    local groups = {}

    for _, candidate in ipairs(candidates(territory)) do
        local chance
        seed, chance = nextRoll(seed)
        if chance < config.PATROL_SPAWN_CHANCE then
            local faction = registry.factions[candidate.faction]
            local tier = M.tierFor(candidate.projection, faction.patrolRoster)
            local count = M.sizeFor(candidate.projection, candidate.faction)
            local records
            records, seed = draw(faction.patrolRoster, tier, count, seed)

            if #records > 0 then
                groups[#groups + 1] = {
                    faction = candidate.faction,
                    projection = candidate.projection,
                    count = #records,
                    tier = tier,
                    records = records,
                    hostileToPlayer = hostility.isHostileToPlayer(candidate.faction),
                    fights = {},
                }
            end
        end
    end

    if #groups == 0 then
        return nil
    end

    -- Who fights whom, among the groups that actually turned up. Left as
    -- ids rather than resolved to actors because this file has none --
    -- the layer that creates them pairs these up.
    for i = 1, #groups do
        for j = 1, #groups do
            if i ~= j and hostility.willFight(groups[i].faction, groups[j].faction) then
                local fights = groups[i].fights
                fights[#fights + 1] = groups[j].faction
            end
        end
    end

    return { territory = territoryId, day = day, groups = groups }
end

return M
