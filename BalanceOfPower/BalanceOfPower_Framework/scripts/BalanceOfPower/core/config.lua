-- Every tunable number in the framework lives here.
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

-- The anchor the derived starting power is expressed against: a faction
-- with the average holdings starts here.
--
-- Only ratios matter mechanically, so this number is arbitrary -- but six
-- other constants are calibrated against it (SEAT_FLOOR, MIN_CLAIM_POWER,
-- PROJECTION_HORIZON_POWER, FRONTIER_GENERATION_POWER, and the two patrol
-- power steps). Changing it means changing all of them.
M.DEFAULT_BASE_POWER = 50

-- Starting power is derived from a faction's seats rather than authored.
-- Its score is summed per region, taking the strongest seat there plus a
-- share of the rest -- the same "strongest single projection, never the
-- sum" rule the map itself uses, so a plantation belt reads as presence
-- rather than as a second city.
--
--   score = sum over regions( strongest weight + DEPTH_SHARE * the rest )
--   power = DEFAULT_BASE_POWER * (FLOOR_SHARE + (1 - FLOOR_SHARE) * score / mean)
--
-- A second holding in a region you already hold is worth a quarter of a
-- first one. At 0 the farms count for nothing; at 1 a dozen of them
-- outweigh a city.
M.POWER_DEPTH_SHARE = 0.25

-- What a faction with no ground starts with, as a share of an average
-- landholder. Also the compression knob: raising it narrows the spread
-- between the strongest faction and the weakest.
M.POWER_FLOOR_SHARE = 0.30

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
-- Ambient growth
--------------------------------------------------------------------------

-- Power a faction gains every resolved day with no player involvement,
-- when its definition doesn't say otherwise.
--
-- Zero by default: factions growing on their own should be defined by
-- content packs. The Sixth House is an obvious contender and that
-- can be defined in a pack's faction table.
M.DEFAULT_GROWTH_PER_DAY = 0

-- Whether ambient growth drags other factions along the reaction table
-- the way an awarded change does. Should almost always be false.
-- With propagation turned on, a faction with negative relations to all
-- others like the sixth house will bleed out other factions passively.
-- Factions with ambient growth are better considered an outside threat
-- instead of a contended in the balance of power between factions.
M.GROWTH_PROPAGATES = false

--------------------------------------------------------------------------
-- Hostility
--------------------------------------------------------------------------

-- Hostility is opt-in per faction (`hostile = true` in a pack's faction
-- definition) and defaults to nobody.
--
-- A flagged faction is hostile to the player, and fights any faction it
-- regards at or below this threshold. -3 is vanilla's "hated enemy"
-- value, so the rule reads as: a hostile faction attacks the people it
-- genuinely hates, and tolerates everyone else.
M.HOSTILITY_REACTION_THRESHOLD = -3

-- Treat every faction as though it carried `hostile = true`.
--
-- Off by default, and not a small switch. Against Morrowind's full
-- reaction matrix -3 is commoner than it looks -- the vampire clans
-- alone bring a dozen, and Telvanni/Mages Guild and Thieves Guild/Camonna
-- Tong are mutual -- so this is closer to a general war than to a handful
-- of feuds.
M.ALL_FACTIONS_HOSTILE = false

--------------------------------------------------------------------------
-- Settlements
--------------------------------------------------------------------------

-- The tier ladder, smallest to largest. This is the ranking: a pack
-- naming a tier is placing its holding on this scale and nothing else,
-- and every number below follows the order.
M.SETTLEMENT_TIER_ORDER = {
    'minor location',
    'outpost',
    'village',
    'town',
    'small city',
    'large city',
    'metropolis',
    'megalopolis',
}

-- Per-tier fallbacks, so a farm needs an id and a cell and nothing else.
--
--   weight          how strongly it projects, and what scales SEAT_FLOOR
--   influenceRange  the halving distance: how far projection travels
--                   before it drops to half strength
--   cooldownDays    how long its cells are immune after changing hands
--
-- **influenceRange is not a limit.** Projection halves every one of them
-- and never reaches zero, so how far a faction reaches is decided by how
-- much power it has, not by a boundary drawn here. The number sets the
-- exchange rate between the two: every doubling of a faction's power
-- pushes its border out by exactly one influenceRange.
--
-- Scale matters more than it looks. An exterior cell is CELL_SIZE units
-- across -- 8192 -- so a halving distance of 10000 means a faction at the
-- default base power claims out to roughly four cells, and needs twice
-- that power to reach the fifth.
--
-- A settlement is the only thing that projects, so the ladder is the
-- whole of the map's shape. Two tiers sharing a weight makes the two
-- indistinguishable in play, which is what the previous split did to
-- Vivec and Balmora -- both landed on one "capital" tier and projected
-- identically, and no amount of tuning could tell them apart.
M.SETTLEMENT_TIERS = {
    -- Farms, shacks, mines, minor manors. At the default base power one
    -- of these claims its own cell and very little else -- weight enters
    -- the reach calculation logarithmically, so a small holding is
    -- genuinely small. What makes a plantation belt read as somebody's is
    -- a dozen of them each holding their own ground, not any one of them
    -- reaching across the region.
    ['minor location'] = { weight = 0.15, influenceRange = 2500, cooldownDays = 5 },
    outpost            = { weight = 0.25, influenceRange = 3000, cooldownDays = 10 },
    village            = { weight = 0.35, influenceRange = 4000, cooldownDays = 15 },
    town               = { weight = 0.50, influenceRange = 6000, cooldownDays = 25 },
    ['small city']     = { weight = 0.75, influenceRange = 8000, cooldownDays = 40 },
    ['large city']     = { weight = 1.00, influenceRange = 10000, cooldownDays = 60 },
    metropolis         = { weight = 1.25, influenceRange = 12000, cooldownDays = 90 },
    -- Nothing in Morrowind is one. It exists so a pack for a larger
    -- landmass has somewhere to put its imperial capital without having
    -- to redefine what a metropolis means everywhere else.
    megalopolis        = { weight = 1.50, influenceRange = 14000, cooldownDays = 120 },
}

M.DEFAULT_SETTLEMENT_TIER = 'town'

-- A faction is never weaker at a cell its own settlement occupies than
-- this, scaled by the settlement's weight.
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
--   megalopolis    1.50 -> 375
--   large city     1.00 -> 250   nothing plausible outranks a city
--   town           0.50 -> 125
--   minor location 0.15 ->  37   holds its own cell unless a city adjoins
--
-- Raising it makes minor holdings more stubborn, which produces more
-- one-cell islands inside a rival's country. Lowering it eventually lets
-- a strong enough faction take a settlement outright, which the design
-- deliberately avoids -- Morrowind has nowhere to put the consequences.
M.SEAT_FLOOR = 250

--------------------------------------------------------------------------
-- Territory
--------------------------------------------------------------------------

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

-- Extra reach, in world units, beyond the generation radius derived from
-- FRONTIER_GENERATION_POWER.
--
-- Flat slack on top of that, for a pack that expects settlements to
-- appear at runtime in places nothing currently reaches.
--
-- Zero by default, because FRONTIER_GENERATION_POWER is the knob that
-- actually wants turning. There is no longer such a thing as ground that
-- can never be claimed -- projection has no cap, so a cell far outside
-- everybody's reach today is claimable by whoever grows enough -- but
-- there is still such a thing as generating more territory than the
-- simulation needs to carry.
M.FRONTIER_GENERATION_MARGIN = 0

-- Only generate territory for grid positions that the loaded content
-- files actually define as cells. This is what keeps the Sea of Ghosts
-- out of the simulation. Turn it off only for testing against synthetic
-- geography with no game data behind it.
M.FRONTIER_REQUIRE_EXISTING_CELL = true

-- The faction power the frontier generator plans for, and so how much
-- room the generated map leaves for growth.
--
-- Generation needs a radius, and projection no longer supplies one: a
-- settlement's influence never reaches zero, so "everywhere it reaches"
-- is everywhere. Instead the generator asks how far a faction *at this
-- power* could claim from each seat, and generates that.
--
-- Twice the default base power: one halving distance of headroom on every
-- seat, so the map has room for every faction to double its standing
-- before anyone projects past the edge of the world.
--
-- Raising it is how a pack buys more room, and the cost is paid in
-- unclaimed ground rather than in cells that can never be held. What
-- fraction of the generated map starts unowned follows from this ratio
-- alone -- not from the tier ranges, which cancel:
--
--   unclaimed ~= 1 - (log2(base / claim floor) / log2(this / claim floor))^2
--
-- At 2x base that is a bit over a third, which is expansion room. At 5x
-- it is nearly two thirds, which reads as an empty world.
--
-- A faction that outgrows the figure projects past the edge of the
-- generated map. The answer is to raise this and regenerate, not to cap
-- the projection: ground that exists and is out of reach is honest, where
-- ground that cannot be reached because it was never created is not.
M.FRONTIER_GENERATION_POWER = 100

--------------------------------------------------------------------------
-- Resolution
--------------------------------------------------------------------------

-- The power at which the projection cache stops modelling a faction's
-- reach, however far the maths would carry it.
--
-- An infinite tail means every faction technically reaches every
-- territory, and caching all of it would turn a reach list of two into
-- one of twenty-four for no gain: at these distances the faction would
-- need absurd power for its projection to clear MIN_CLAIM_POWER at all.
-- So a (territory, faction) pair is only kept if a faction of this power
-- could claim there.
--
-- A hundred times the default base power, which is far past anything the
-- simulation produces. It is a performance bound and not a game rule --
-- if a faction ever genuinely approaches it, raise this rather than
-- wondering why its border stopped.
M.PROJECTION_HORIZON_POWER = 5000

-- The floor for taking ground nobody holds. An unowned territory has no
-- defender to roll against, so projection alone decides it -- this stops
-- a faction claiming distant ground it barely reaches, and is what keeps
-- the edges of the map empty until someone actually reaches them.
--
-- It is also, now, the thing that decides how far anybody reaches.
-- Projection has no cap: a faction claims ground wherever its power,
-- decayed by distance, still clears this number. Lowering it pushes every
-- border outward at once; raising it pulls them all in. The per-tier
-- influenceRange sets how much power it takes to move a given border,
-- and this sets where the borders start.
--
-- For scale: a large-city seat on a faction at the default base power of
-- 50 clears this out to a bit over four cells, and doubling that power
-- buys one more halving distance -- another 10000 units.
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
