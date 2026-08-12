-- Every tunable number in the framework lives here, named and in one
-- place. Design doc section 7 calls this out explicitly as a risk: none
-- of these values are known to be right until the thing has been
-- played, so none of them should be buried inside logic.
--
-- Data packs never edit this file -- per-faction and per-territory
-- overrides are authored in the pack's own definitions, and the values
-- here are only the fallbacks used when a definition leaves a field out.

local M = {}

--------------------------------------------------------------------------
-- Diagnostics
--------------------------------------------------------------------------

-- Verbose logging of registration, save/load and default-fill.
M.DEBUG = true

-- One line of faction standings printed per in-game day. Separate from
-- DEBUG because it fires forever, not just at startup.
M.DEBUG_DAILY_SUMMARY = true

-- validateReferences() stops listing individual dangling ids after this
-- many, so a data pack with a broken frontier grid doesn't produce a
-- thousand log lines.
M.MAX_REPORTED_PROBLEMS = 20

--------------------------------------------------------------------------
-- Power
--------------------------------------------------------------------------

-- Used when a faction definition omits basePower.
M.DEFAULT_BASE_POWER = 50

-- Power is clamped to this floor. powerRoll (phase 2) divides by the sum
-- of two power scores, so a negative score would silently invert the
-- odds rather than just making a faction weak.
M.MIN_POWER = 0

-- How strongly a faction's power change drags other factions along with
-- it. A reacting faction at the maximum +3 opinion moves by
-- delta * INFLUENCE_STRENGTH; one at -3 moves the same distance the
-- other way.
M.INFLUENCE_STRENGTH = 0.15

-- Vanilla reaction values are nominally within [-3, 3], but nothing
-- guarantees third-party ESM data respects that, so clamp before
-- scaling. Also the divisor that normalizes a reaction to [-1, 1].
M.REACTION_CLAMP = 3

-- Power changes smaller than this neither fire BoP_PowerChanged nor get
-- logged. Propagation to a barely-interested faction otherwise produces
-- a lot of events carrying a delta of 0.0003.
M.POWER_EVENT_EPSILON = 0.01

--------------------------------------------------------------------------
-- Power centers
--------------------------------------------------------------------------

-- Per-tier fallbacks for a power center's projection strength and the
-- distance at which its contribution decays to zero (world units).
-- Design doc 3.2: minor holdings should be authorable without individual
-- tuning, so an outpost only needs an id and coords.
--
-- Scale matters more than it looks. A Morrowind exterior cell is 8192
-- units across, so the design document's illustrative 6000 would not
-- reach even the neighbouring cell -- a capital would project onto
-- nothing but itself, and no frontier cell would ever be contested. The
-- doc's figure predates the anchor/frontier split; these are sized in
-- cells instead: roughly 5, 3 and 1.5 cells of reach.
M.POWER_CENTER_DEFAULTS = {
    capital  = { weight = 1.00, influenceRange = 40000 },
    regional = { weight = 0.50, influenceRange = 24000 },
    outpost  = { weight = 0.25, influenceRange = 12000 },
}

M.DEFAULT_POWER_CENTER_TIER = 'regional'

--------------------------------------------------------------------------
-- Territory
--------------------------------------------------------------------------

M.DEFAULT_ANCHOR_TIER = 'town'

-- Per-tier fallbacks for anchors. defenseMultiplier scales the current
-- owner's effective power during a siege roll; the city value is
-- deliberately steep enough that ordinary faction politics can't take a
-- city, leaving real city flips to the invasion subsystem (doc 3.4).
M.ANCHOR_DEFAULTS = {
    town = { siegeThreshold = 3, cooldownDays = 20, defenseMultiplier = 2.0 },
    city = { siegeThreshold = 8, cooldownDays = 60, defenseMultiplier = 8.0 },
}

-- Frontier cells are the layer that's meant to visibly creep, so they
-- recover from a flip far faster than a settlement does.
M.FRONTIER_COOLDOWN_DAYS = 3

--------------------------------------------------------------------------
-- Resolution
--------------------------------------------------------------------------

-- The floor for taking ground nobody holds. An unowned territory has no
-- defender to roll against, so projection alone decides it -- this stops
-- a faction claiming distant ground it barely reaches, and is what keeps
-- the edges of the map empty until someone actually reaches them.
--
-- For scale: a capital-tier center on a faction at the default base
-- power of 50 projects the full 50 at its own seat, and about 40 one
-- cell away.
M.MIN_CLAIM_POWER = 5

-- What share of an anchor's adjacent frontier a rival must hold before
-- the anchor counts as surrounded and its siege streak starts climbing.
M.SURROUND_SHARE = 0.6

--------------------------------------------------------------------------
-- Daily tick
--------------------------------------------------------------------------

-- The driver polls this often (in-game hours) and resolves whenever the
-- day index has advanced, rather than firing on a fixed 24h period.
-- Polling survives sleep, fast travel and any other jump in game time,
-- where a plain 24h repeating timer would drift or be skipped.
M.TICK_POLL_HOURS = 1

-- Upper bound on days resolved in one catch-up burst, so a player who
-- sleeps through a month doesn't stall the frame resolving thirty days
-- of territory rolls at once.
M.MAX_CATCHUP_DAYS = 7

return M
