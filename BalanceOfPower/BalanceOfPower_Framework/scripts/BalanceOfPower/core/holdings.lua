-- What a faction holds, and what that is worth.
--
-- Two axes, and they are not the same thing:
--
--   BREADTH  how many regions a faction is present in
--   DEPTH    how much it holds within each of them
--
-- The seat side answers both from the registry, before any ownership
-- exists, and is what starting power is derived from. Held territory is
-- derived from projection, which reads power, so using it here would be
-- circular.
--
-- GLOBAL context only.

local config = require('scripts.BalanceOfPower.core.config')
local registry = require('scripts.BalanceOfPower.core.registry')

local M = {}

local seatProfiles = nil
local meanScore = nil
local seatGeneration = -1

--------------------------------------------------------------------------
-- Seats
--------------------------------------------------------------------------

-- A settlement's region, falling back to its landmass. Not to something
-- unique per seat: that would make every region-less holding its own
-- region and inflate exactly the scattered ones the depth share damps.
local function regionOf(settlement)
    return settlement.region or settlement.landmass or '?'
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

return M
