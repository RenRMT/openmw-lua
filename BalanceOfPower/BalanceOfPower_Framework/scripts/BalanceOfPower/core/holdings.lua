-- What a faction holds, and what that is worth.
--
-- Two axes, and they are not the same thing:
--
--   BREADTH  how many regions a faction is present in
--   DEPTH    how much it holds within each of them
--
-- Both are measured on two sides. SEATS are what the registry says a
-- faction was built with: fixed, known before any ownership exists, and
-- what starting power is derived from. HELD TERRITORY is what it has
-- now -- an outcome of projection, which reads power, so seeding from it
-- would be circular.
--
-- GLOBAL context only.

local config = require('scripts.BalanceOfPower.core.config')
local log = require('scripts.BalanceOfPower.core.log')
local power = require('scripts.BalanceOfPower.core.power')
local registry = require('scripts.BalanceOfPower.core.registry')
local state = require('scripts.BalanceOfPower.core.state')

local M = {}

local EMPTY = {}

local seatProfiles = nil
local meanScore = nil
local seatGeneration = -1

--------------------------------------------------------------------------
-- Seats
--------------------------------------------------------------------------

-- A settlement's or territory's region, falling back to its landmass.
-- Not to something unique: that would make every region-less holding its
-- own region and inflate exactly the scattered ones the depth share
-- damps -- and, on the held side, make every faction look broad.
local function regionOf(place)
    return place.region or place.landmass or '?'
end

local function build()
    seatProfiles = {}

    local total, landholders = 0, 0
    for _, id in ipairs(registry.sortedFactionIds()) do
        local faction = registry.factions[id]
        local byRegion = {}
        for _, settlement in ipairs(faction.seats) do
            local region = regionOf(settlement)
            byRegion[region] = byRegion[region] or {}
            local weights = byRegion[region]
            weights[#weights + 1] = settlement.weight or 0
        end

        local score, regions = 0, 0
        for _, weights in pairs(byRegion) do
            regions = regions + 1
            local strongest, rest = 0, 0
            for _, weight in ipairs(weights) do
                if weight > strongest then
                    rest = rest + strongest
                    strongest = weight
                else
                    rest = rest + weight
                end
            end
            score = score + strongest + config.POWER_DEPTH_SHARE * rest
        end

        seatProfiles[id] = { seats = #faction.seats, regions = regions, score = score }
        if score > 0 then
            total = total + score
            landholders = landholders + 1
        end
    end

    -- Averaged over landholders alone. Including the factions that score
    -- zero drags the anchor down and compresses everyone above it.
    meanScore = landholders > 0 and (total / landholders) or 0
    seatGeneration = registry.generation
end

local function ensure()
    if seatProfiles == nil or seatGeneration ~= registry.generation then
        build()
    end
end

local EMPTY_PROFILE = { seats = 0, regions = 0, score = 0 }

--- A faction's seats, the regions they are spread over, and the score
-- those two produce.
-- @return { seats, regions, score }
function M.seatProfile(factionId)
    ensure()
    return seatProfiles[factionId] or EMPTY_PROFILE
end

--- The mean seat score across land-holding factions.
function M.meanSeatScore()
    ensure()
    return meanScore
end

--- Starting power for a faction, from its holdings.
--
-- A faction with the average holdings gets DEFAULT_BASE_POWER exactly;
-- one with no ground gets POWER_FLOOR_SHARE of it, whatever else is
-- installed, because a score of zero never touches the mean.
function M.basePowerOf(factionId)
    ensure()
    local floor = config.POWER_FLOOR_SHARE
    local share = meanScore > 0 and (M.seatProfile(factionId).score / meanScore) or 0
    return config.DEFAULT_BASE_POWER * (floor + (1 - floor) * share)
end

--- Seed starting power for any faction that has none yet.
--
-- Called from the driver's first tick, because the mean a faction is
-- measured against isn't known until every pack has registered: seeding
-- during registration would score pack one against pack one alone.
--
-- Only fills nils, so a loaded save keeps its numbers while a newly
-- installed pack's factions still get a derived value.
-- @return number of factions seeded
function M.seedPower()
    local data = state.get()
    local seeded = 0
    for id in pairs(registry.factions) do
        if data.power[id] == nil then
            data.power[id] = math.max(config.MIN_POWER, M.basePowerOf(id))
            seeded = seeded + 1
        end
    end
    if seeded > 0 then
        log.debug('seeded starting power for %d factions', seeded)
    end
    return seeded
end

--------------------------------------------------------------------------
-- Held territory
--------------------------------------------------------------------------

local heldProfiles = nil
local regionHolders = nil
local heldRegistryGeneration = -1
local heldOwnershipGeneration = -1

local EMPTY_HELD = { territories = 0, settlements = 0, regions = 0, regionCounts = EMPTY }

local function buildHeld()
    heldProfiles, regionHolders = {}, {}

    local countedSettlements = {}
    for territoryId, owner in pairs(state.get().ownership) do
        local territory = owner and registry.territories[territoryId]
        if territory then
            local profile = heldProfiles[owner]
            if not profile then
                profile = { territories = 0, settlements = 0, regions = 0, regionCounts = {} }
                heldProfiles[owner] = profile
            end
            profile.territories = profile.territories + 1

            local region = regionOf(territory)
            if profile.regionCounts[region] == nil then
                profile.regionCounts[region] = 0
                profile.regions = profile.regions + 1
            end
            profile.regionCounts[region] = profile.regionCounts[region] + 1

            regionHolders[region] = regionHolders[region] or {}
            regionHolders[region][owner] = (regionHolders[region][owner] or 0) + 1

            -- A settlement is several ownable cells; the named place
            -- counts once however many of them this faction holds.
            if territory.settlement then
                local key = owner .. '\0' .. territory.settlement
                if not countedSettlements[key] then
                    countedSettlements[key] = true
                    profile.settlements = profile.settlements + 1
                end
            end
        end
    end

    heldRegistryGeneration = registry.generation
    heldOwnershipGeneration = state.ownershipGeneration()
end

local function ensureHeld()
    if heldProfiles == nil
        or heldRegistryGeneration ~= registry.generation
        or heldOwnershipGeneration ~= state.ownershipGeneration() then
        buildHeld()
    end
end

--------------------------------------------------------------------------
-- Standings
--------------------------------------------------------------------------

--- Everything known about where a faction stands, or nil if it isn't
-- registered.
--
-- Two of the fields are ratios over the others, here because every
-- consequence mod would otherwise derive them the same way:
--
--   strain          territories held per 100 power -- broad, thin
--                   control reads high, and stays high until the
--                   faction grows into it or loses ground
--   concentration   territories per region
--
-- @return { id, power, territories, settlements, regions, seats,
--           seatScore, strain, concentration }
function M.factionStanding(factionId)
    if not registry.factions[factionId] then
        return nil
    end
    ensureHeld()

    local held = heldProfiles[factionId] or EMPTY_HELD
    local seats = M.seatProfile(factionId)
    local live = power.getLive(factionId)

    return {
        id = factionId,
        power = live,
        territories = held.territories,
        settlements = held.settlements,
        regions = held.regions,
        seats = seats.seats,
        seatScore = seats.score,
        strain = live > 0 and (100 * held.territories / live) or 0,
        concentration = held.regions > 0 and (held.territories / held.regions) or 0,
    }
end

--- Every registered faction's standing, strongest first. Equal power
-- breaks on id, so the order is stable across sessions.
function M.standings()
    local rows = {}
    for _, id in ipairs(registry.sortedFactionIds()) do
        rows[#rows + 1] = M.factionStanding(id)
    end
    table.sort(rows, function(a, b)
        if a.power == b.power then
            return a.id < b.id
        end
        return a.power > b.power
    end)
    return rows
end

--- Regions a faction holds any ground in, sorted.
function M.regionsHeldBy(factionId)
    ensureHeld()
    local profile = heldProfiles[factionId]
    local names = {}
    for region in pairs(profile and profile.regionCounts or EMPTY) do
        names[#names + 1] = region
    end
    table.sort(names)
    return names
end

--- Who holds ground in a region, and how many territories each.
-- @return factionId -> count, a fresh table
function M.holdersOfRegion(regionName)
    ensureHeld()
    local out = {}
    for id, count in pairs(regionHolders[regionName] or EMPTY) do
        out[id] = count
    end
    return out
end

return M
