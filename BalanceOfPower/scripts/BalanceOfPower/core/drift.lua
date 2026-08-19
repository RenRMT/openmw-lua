-- Power that moves on its own.
--
-- Everything else in the framework runs power -> territory: a faction's
-- standing decides what it projects onto, and projection decides who
-- holds what. This module is the return leg. Ground held raises the
-- standing that took it, ground lost lowers it, and the map stops being
-- a thing that resolves once and then never moves again.
--
-- Two parts, and the split is what keeps it stable:
--
--   CAPACITY  what a faction's holdings support -- see holdings.lua.
--             The anchor. Slow, and only moves when the map does.
--   FORTUNE   a bounded, slow curve derived from the faction's id and
--             the day index. The reason a settled map keeps drifting.
--
-- Power is not set to capacity + fortune; it is tracked toward it at
-- POWER_REVERSION_RATE. The lag is the point -- an exponential approach
-- cannot overshoot, so the system never oscillates on its own, and
-- because fortune displaces a bounded TARGET rather than being added to
-- power each day, a three-thousand-day game cannot random-walk away.
--
-- GLOBAL context only.

local config = require('scripts.BalanceOfPower.core.config')
local holdings = require('scripts.BalanceOfPower.core.holdings')
local power = require('scripts.BalanceOfPower.core.power')
local registry = require('scripts.BalanceOfPower.core.registry')

local M = {}

--------------------------------------------------------------------------
-- Hashing
--------------------------------------------------------------------------
--
-- Fortune stores nothing: it is a pure function of (factionId, day), so
-- it loads on any save ever written and forceDays reproduces exactly the
-- history the calendar would have. That makes the hash load-bearing, and
-- it has to be a good one.
--
-- No bitwise operators: OpenMW's Lua is 5.1, so this is modular
-- arithmetic only. Every product below stays under 2^53, where doubles
-- still hold integers exactly.

local HASH_MOD = 4194304        -- 2^22
local HASH_HALF = 2048          -- 2^11, for the half-swap
local HASH_A = 1103515245
local HASH_C = 12345

-- Two LCG rounds with the halves swapped between them.
--
-- The swap is not decoration. Two LCG rounds compose into a third, so
-- without something non-affine in the middle, consecutive inputs come
-- out as an arithmetic progression -- equidistributed, and a sawtooth
-- rather than noise once it is interpolated.
local function mix(value)
    local x = value % HASH_MOD
    x = (x * HASH_A + HASH_C) % HASH_MOD
    x = (x % HASH_HALF) * HASH_HALF + math.floor(x / HASH_HALF)
    return (x * HASH_A + HASH_C) % HASH_MOD
end

-- A faction id folded into an integer, so two factions never share a
-- curve. Ordinary polynomial string hashing; the mixer above is what
-- makes the result well distributed, not this.
local function seedOf(factionId)
    local seed = 0
    for index = 1, #factionId do
        seed = (seed * 31 + string.byte(factionId, index)) % HASH_MOD
    end
    return seed
end

-- One lattice point of one octave, in [0, 1).
--
-- Nested rather than summed, so the octave and the day index avalanche
-- through the mixer instead of being separable: seed + octave + index
-- summed flat would make octave 1 of one faction equal octave 0 of
-- another.
local function lattice(seed, octave, index)
    return mix(seed + mix(octave * 7919 + mix(index))) / HASH_MOD
end

--------------------------------------------------------------------------
-- Fortune
--------------------------------------------------------------------------

--- Where a faction's luck stands on a given day, in power, positive or
-- negative.
--
-- Value noise: a handful of octaves of interpolated lattice points,
-- each twice the frequency and half the amplitude of the last, summed
-- and normalized against their own total. Normalizing against the total
-- rather than against a constant is what makes FORTUNE_OCTAVES safe to
-- change -- another octave alters the texture and not the range.
--
-- Smoothstep between lattice points rather than a straight line, so the
-- curve has no corners and a faction's luck holds a direction for weeks.
function M.fortuneOf(factionId, day)
    local faction = registry.factions[factionId]
    local volatility = faction and faction.volatility or config.DEFAULT_VOLATILITY
    local swing = config.FORTUNE_SWING * config.DEFAULT_BASE_POWER
    if volatility == 0 or swing == 0 then
        return 0
    end

    local seed = seedOf(factionId)
    local octaves = math.max(1, math.floor(config.FORTUNE_OCTAVES))
    local period = config.FORTUNE_PERIOD_DAYS
    local amplitude = 1
    local total, weight = 0, 0

    for octave = 0, octaves - 1 do
        local position = day / period
        local index = math.floor(position)
        local fraction = position - index
        local eased = fraction * fraction * (3 - 2 * fraction)
        local from = lattice(seed, octave, index)
        local to = lattice(seed, octave, index + 1)

        total = total + amplitude * (from + (to - from) * eased)
        weight = weight + amplitude
        period = period / 2
        amplitude = amplitude / 2
    end

    -- The lattice is uniform on [0, 1); centring it on zero is what makes
    -- fortune luck rather than a handicap.
    return (2 * (total / weight) - 1) * swing * volatility
end

--------------------------------------------------------------------------
-- Reversion
--------------------------------------------------------------------------

--- Whether drift moves this faction at all.
--
-- False for an invader: its ramp is the point, and a target would cap
-- it. That is also what makes a setback dealt by content permanent --
-- with nothing to revert toward, an award never decays.
function M.appliesTo(factionId)
    if not config.DRIFT_ENABLED or config.POWER_REVERSION_RATE <= 0 then
        return false
    end
    if not registry.factions[factionId] then
        return false
    end
    return not registry.isInvader(factionId)
end

--- The standing a faction is being pulled toward on a given day, or nil
-- if drift does not apply to it.
function M.targetOf(factionId, day)
    if not M.appliesTo(factionId) then
        return nil
    end
    local target = holdings.capacityOf(factionId) + M.fortuneOf(factionId, day)
    return math.max(config.MIN_POWER, target)
end

--- Move every drifting faction one day closer to its target.
--
-- Called from the driver alongside growth, and outside the resolution
-- batch for the same reason: drift is an input to the day rather than a
-- result of it, so the day's rolls see the new number.
-- @return number of factions that moved
function M.applyDaily(day)
    local moved = 0
    for _, id in ipairs(registry.sortedFactionIds()) do
        local target = M.targetOf(id, day)
        if target then
            local delta = (target - power.getLive(id)) * config.POWER_REVERSION_RATE
            if math.abs(delta) >= config.POWER_EVENT_EPSILON then
                -- A daily drip must not travel the reaction table: the
                -- compounding argument behind GROWTH_PROPAGATES applies
                -- to drift verbatim, and drift touches every faction
                -- rather than the handful with a growth rate.
                power.apply(id, delta, { noPropagate = not config.DRIFT_PROPAGATES })
                moved = moved + 1
            end
        end
    end
    return moved
end

return M
