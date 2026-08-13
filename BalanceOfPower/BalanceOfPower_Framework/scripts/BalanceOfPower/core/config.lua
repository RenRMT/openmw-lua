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

-- Half-width, in cells, of the windowed map drawn around a position.
-- Sized to fit an in-game message box: 6 gives a 13x13 grid, which is
-- readable on screen where the full forty-by-fifty map is not.
M.MAP_WINDOW_RADIUS = 6

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
    -- Farms, shacks, mines, minor manors. Individually negligible and
    -- barely reaching past their own cell, but they cluster -- a
    -- plantation belt is a dozen of these overlapping, which is what
    -- makes a region read as belonging to somebody without any single
    -- holding being worth contesting.
    minor    = { weight = 0.15, influenceRange = 10000 },
}

M.DEFAULT_POWER_CENTER_TIER = 'regional'

--------------------------------------------------------------------------
-- Territory
--------------------------------------------------------------------------

M.DEFAULT_ANCHOR_TIER = 'town'

-- Per-tier fallbacks for anchors. defenseMultiplier scales the current
-- owner's effective power during a siege roll; the top tiers are
-- deliberately steep enough that ordinary faction politics can't take
-- them, leaving real city flips to the invasion subsystem (doc 3.4).
--
-- The ladder runs from an isolated fort or Ashlander camp, which should
-- change hands when the surrounding country does, up to Vivec, which
-- should not change hands short of catastrophe.
M.ANCHOR_DEFAULTS = {
    outpost    = { siegeThreshold = 2,  cooldownDays = 10, defenseMultiplier = 1.5 },
    village    = { siegeThreshold = 3,  cooldownDays = 15, defenseMultiplier = 2.0 },
    town       = { siegeThreshold = 4,  cooldownDays = 25, defenseMultiplier = 3.0 },
    city       = { siegeThreshold = 8,  cooldownDays = 60, defenseMultiplier = 8.0 },
    metropolis = { siegeThreshold = 12, cooldownDays = 90, defenseMultiplier = 15.0 },
}

-- Frontier cells are the layer that's meant to visibly creep, so they
-- recover from a flip far faster than a settlement does.
M.FRONTIER_COOLDOWN_DAYS = 3

--------------------------------------------------------------------------
-- Frontier generation
--------------------------------------------------------------------------

-- World units per exterior cell. 8192 for Morrowind-style content; a
-- pack for content with a different grid overrides it per call.
M.CELL_SIZE = 8192

-- Exterior cells per generated frontier territory, along each axis.
-- 1 gives one territory per cell -- the finest grain, and the most
-- territories to resolve and persist. 2 or 3 quarters or ninths that
-- count at the cost of coarser, blockier movement of the front. This is
-- the main lever on the performance risk in design doc 7.
M.FRONTIER_CELLS_PER_UNIT = 1

-- Extra reach, in world units, beyond each power center's influence
-- range when deciding which cells to generate.
--
-- Zero, and that is the right default. It is tempting to add slack "so a
-- growing faction has room to expand into", but influence decays to
-- exactly zero at influenceRange no matter how powerful the faction is
-- -- so ground beyond that range can never be claimed by anyone, and
-- generating it produces territories that are permanently dead: carried
-- in the save, iterated every day, and ownable by nobody. On the
-- Morrowind pack a one-cell margin alone produced 482 of them.
--
-- Raise it only for a pack that expects power centers to appear at
-- runtime, where the reachable region genuinely can grow.
M.FRONTIER_GENERATION_MARGIN = 0

-- Only generate territory for grid positions that the loaded content
-- files actually define as cells. This is what keeps the Sea of Ghosts
-- out of the simulation. Turn it off only for testing against synthetic
-- geography with no game data behind it.
M.FRONTIER_REQUIRE_EXISTING_CELL = true

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
