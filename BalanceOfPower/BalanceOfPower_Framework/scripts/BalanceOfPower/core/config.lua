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

-- Which way round `core.factions.records[id].reactions` reads.
--
-- **Outbound**, settled in-game on 2026-08-13 against the asymmetric
-- Telvanni / Twin Lamps pair: a record row is "how I feel about everyone
-- else", matching the underlying ESM3 FACT record, where the ANAM/INTV
-- pairs live on the faction's own record. OpenMW's own documentation
-- describes it the other way round, and the documentation is wrong.
--
-- This shipped as `true` -- the documented reading -- through phases 1-3,
-- which propagated every asymmetric vanilla pair backwards. It failed
-- exactly as quietly as predicted: symmetric pairs behave identically
-- either way, so the world was subtly off rather than obviously broken.
--
-- The flag stays because it is not free knowledge for other content.
-- ESM4 records are a different format read through a different code
-- path, so a future Skyrim pack may well need the other setting.
--
-- Only record data is governed by this. Authored `reactions` tables in a
-- pack always mean "how everyone else feels about me", because that
-- convention is ours to define and there is no reason to leave it open.
M.RECORD_REACTIONS_ARE_INBOUND = false

-- Power changes smaller than this neither fire BoP_PowerChanged nor get
-- logged. Propagation to a barely-interested faction otherwise produces
-- a lot of events carrying a delta of 0.0003.
M.POWER_EVENT_EPSILON = 0.01

--------------------------------------------------------------------------
-- Ambient growth
--------------------------------------------------------------------------

-- Power a faction gains every resolved day with no player involvement,
-- when its definition doesn't say otherwise.
--
-- Zero for everyone is the right default: a faction that grows on its
-- own is making a claim about the world that only its own content pack
-- can justify. What it exists for is the faction whose whole story is
-- that it is getting stronger whether or not anyone is paying attention
-- -- the Sixth House being the obvious one -- and that is a number in a
-- pack's faction table, not a subsystem.
M.DEFAULT_GROWTH_PER_DAY = 0

-- Whether ambient growth drags other factions along the reaction table
-- the way an awarded change does.
--
-- **No, and this is not a small default.** Propagation models other
-- factions reacting to something that happened; a daily internal
-- build-up is not an event anyone witnesses. More practically, it
-- compounds in a way one-off awards never do. Every faction in Morrowind
-- sits at -3 toward the Sixth House, so at growthPerDay = 1.5 and
-- INFLUENCE_STRENGTH = 0.15 each of them bleeds 0.225 power per day
-- against starting standings of 25 to 50: the entire political map is at
-- MIN_POWER inside four to seven in-game months, every projection falls
-- under MIN_CLAIM_POWER, and the world empties.
--
-- The invader gains nothing from that, either, because its reach is
-- bounded by influenceRange rather than by power. The end state is an
-- empty map with one small red patch, reached quietly, with nothing in
-- the log to say what went wrong.
--
-- The Sixth House still costs everyone something -- that comes from
-- awardPower when the player or the world acts on its behalf, which is
-- an event, and where it belonged all along.
M.GROWTH_PROPAGATES = false

--------------------------------------------------------------------------
-- Hostility
--------------------------------------------------------------------------

-- Whether factions fight each other on sight, and whom.
--
-- Hostility is opt-in per faction (`hostile = true` in a pack's faction
-- definition) and defaults to nobody, because vanilla Morrowind's Great
-- Houses do not brawl in the street and a framework that made them do so
-- would be wrong about the game it is modelling.
--
-- A flagged faction is hostile to the player, and fights any faction it
-- regards at or below this threshold. -3 is vanilla's "sworn enemies"
-- value, so the rule reads as: a hostile faction attacks the people it
-- genuinely hates, and tolerates everyone else.
--
-- Note the direction. This asks how the *hostile* faction feels about
-- the other one, which is an outbound question against inbound storage
-- -- use power.regardOf rather than indexing a reaction row directly.
M.HOSTILITY_REACTION_THRESHOLD = -3

-- Treat every faction as though it carried `hostile = true`.
--
-- Off by default. Switching it on is less dramatic than it sounds: -3 is
-- rare between vanilla factions, so what emerges is the Camonna Tong and
-- the Thieves Guild going at each other rather than a general war. That
-- is the point -- the setting produces the fights that make sense, not
-- all of them.
M.ALL_FACTIONS_HOSTILE = false

--------------------------------------------------------------------------
-- Power centers
--------------------------------------------------------------------------

-- Per-tier fallbacks for a power center's projection strength and the
-- distance at which its contribution decays to zero (world units).
-- Design doc 3.2: minor holdings should be authorable without individual
-- tuning, so an outpost only needs an id and coords.
--
-- Scale matters more than it looks. An exterior cell is CELL_SIZE units
-- across -- 8192 -- so the design document's illustrative 6000 would not
-- reach even the neighbouring cell -- a capital would project onto
-- nothing but itself, and no frontier cell would ever be contested. The
-- doc's figure predates the settlement/frontier split; these are sized in
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

-- A faction is never weaker at a cell its own power center occupies than
-- this, scaled by the center's weight.
--
-- This is what makes settlements hold themselves, and it is deliberately
-- a number rather than a rule. "A settlement cannot change owner" would
-- need exceptions the moment you look at the awkward cases -- a holding
-- with no faction behind it, a farm too small to be worth defending --
-- and every exception is a branch in the ownership logic. A floor needs
-- none: it scales with weight, so a holding with weight 0 gets a floor
-- of 0 and behaves like open ground, which is exactly right for a
-- derelict Velothi tower.
--
-- For scale, against the tier weights above:
--
--   capital  1.00 -> 250   nothing plausible outranks a city
--   regional 0.50 -> 125
--   outpost  0.25 ->  62
--   minor    0.15 ->  37   holds its own cell unless a city is adjacent
--
-- Raising it makes minor holdings more stubborn, which produces more
-- one-cell islands inside a rival's country. Lowering it eventually lets
-- a strong enough faction take a settlement outright, which the design
-- deliberately avoids -- Morrowind has nowhere to put the consequences.
M.SEAT_FLOOR = 250

--------------------------------------------------------------------------
-- Territory
--------------------------------------------------------------------------

M.DEFAULT_SETTLEMENT_TIER = 'town'

-- Per-tier fallbacks for settlements. The tier is otherwise metadata:
-- an extension needs to know Vivec is a metropolis and Gnaar Mok is a
-- village, and it should not have to work that out from cell counts.
M.SETTLEMENT_DEFAULTS = {
    outpost    = { cooldownDays = 10 },
    village    = { cooldownDays = 15 },
    town       = { cooldownDays = 25 },
    city       = { cooldownDays = 60 },
    metropolis = { cooldownDays = 90 },
}

-- Frontier cells are the layer that's meant to visibly creep, so they
-- recover from a flip far faster than a settlement does.
M.FRONTIER_COOLDOWN_DAYS = 3

--------------------------------------------------------------------------
-- Frontier generation
--------------------------------------------------------------------------

-- World units per exterior cell.
--
-- Not a tuning value and not content knowledge: 8192 is the ESM3 grid
-- the engine itself works in, so it is the same for Vvardenfell, Tamriel
-- Rebuilt, Project Cyrodiil and Skyrim Home of the Nords alike. A pack
-- must never redeclare it -- read it from the interface as
-- `BoP.CELL_SIZE`, so a pack's own geometry and the frontier grid can't
-- drift apart.
--
-- `generateFrontier` still takes a `cellSize` override, which earns its
-- keep only for content on a different grid entirely (ESM4 cells are a
-- different size). Nothing shipping here needs it.
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

-- What share of a settlement's adjacent frontier rivals must hold before
-- it counts as surrounded.
--
-- Being surrounded has no consequence inside the framework -- it is
-- observed, recorded and published, and nothing acts on it. It is here
-- because working it out requires the frontier ownership map, which only
-- the framework has, and because every extension that cares would
-- otherwise compute the same thing from the same data.
M.SURROUND_SHARE = 0.6

--------------------------------------------------------------------------
-- Patrols
--------------------------------------------------------------------------
--
-- Patrols are the only way any of this is visible without a console. A
-- player never reads a projection number; they notice that the road out
-- of Balmora has Hlaalu guards on it and the road out of Ald-Ruhn does
-- not, and that somewhere south of Ghostgate that stopped being true.
--
-- These govern the *decision* to spawn, which is all core/patrol.lua
-- makes. Placing actors and clearing them up is a separate concern with
-- separate constants.

-- Chance that an eligible faction fields a patrol in a given cell on a
-- given day. Rolled once per faction per cell per day, not per visit --
-- see core/patrol.lua on why the roll is seeded rather than random.
M.PATROL_SPAWN_CHANCE = 0.35

-- Projection required before a faction patrols a cell it does not own.
-- Only belligerent factions do this at all; it is what makes an invader
-- appear on ground still held by somebody else, which is the visible
-- signal that a border is under pressure.
M.PATROL_MIN_PROJECTION = 5

-- Projection per additional patrol member, above the first.
M.PATROL_POWER_PER_MEMBER = 40

-- However strong a faction becomes. A dozen guards on one road is a
-- performance problem and reads as an army rather than a patrol.
M.PATROL_MAX_MEMBERS = 4

-- Projection per roster tier. Tier 1 is available everywhere a faction
-- patrols at all; each further tier unlocks at another multiple of this,
-- capped by what the faction's roster actually defines.
--
-- This is how strength scales, in preference to mutating an actor's
-- level or stats. A record's level is one number among many -- health,
-- attributes and skills do not follow it -- so scaling that way means
-- hand-rolling character generation, while a roster tier is data a pack
-- can author and read back.
M.PATROL_POWER_PER_TIER = 60

-- Days before the same cell will field another patrol.
--
-- Not primarily about density. Without it, walking out of a cell and
-- back in is an unbounded source of gear and gold, because every patrol
-- carries a vanilla record's inventory. The cooldown is what stops the
-- spawn system being a loot printer.
M.PATROL_COOLDOWN_DAYS = 3

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
