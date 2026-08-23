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
-- Only ratios matter mechanically, so this number is arbitrary -- but
-- five other constants are calibrated against it (SEAT_FLOOR,
-- MIN_CLAIM_POWER, PROJECTION_HORIZON_POWER, FRONTIER_GENERATION_POWER
-- and POWER_PER_HELD_SCORE). Changing it means changing all of them.
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

-- The same damping, for ground a faction actually holds rather than the
-- seats it was built with. Held cells carry no individual weight the way
-- settlements do, so depth is damped with an exponent instead of a
-- share:
--
--   heldScore = sum over regions( cells held there ^ DEPTH_EXPONENT )
--
-- Below 1 the curve is concave, which is the whole point: the tenth cell
-- in a region is worth much less than the first, so breadth beats depth
-- and the strongest faction cannot compound its way across the map. At 1
-- it is a plain cell count and the feedback loop has no brake at all.
M.POWER_DEPTH_EXPONENT = 0.5

-- What one unit of held score is worth in power, on top of the seat
-- baseline. This is the gain on the territory feedback loop: raise it and
-- winning ground matters more, until borders latch to whoever moved
-- first; lower it and territory stops being worth fighting over.
M.POWER_PER_HELD_SCORE = 5

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
-- Drift
--------------------------------------------------------------------------
--
-- The loop that makes territory worth holding. Power decides who takes
-- ground; drift runs the arrow back the other way, so ground held raises
-- the standing that took it and ground lost lowers it. Without it power
-- only ever moves when something outside the framework awards it, and a
-- map that has finished resolving never moves again.
--
-- The target is a faction's CAPACITY -- what its holdings support --
-- displaced by its FORTUNE, a slow curve derived from its id and the day
-- index. Power is not set to the target but tracked toward it, so the
-- system has a lag and cannot oscillate on its own.

-- The master switch. Off, power moves only when awarded: growth, quest
-- hooks and console commands still work, and nothing drifts.
M.DRIFT_ENABLED = true

-- What fraction of the remaining gap a faction closes each day. An
-- exponential approach, so this is a rate and not a step: 0.02 is
-- roughly a five-week half-life, which is slow enough that a border
-- moving is felt over a season rather than a week.
--
-- Zero switches the whole subsystem off, fortune included -- reversion
-- is the carrier for both, and a fortune that displaced a target nothing
-- ever moved toward would do nothing at all.
M.POWER_REVERSION_RATE = 0.02

-- How far fortune carries a faction's target above or below its
-- capacity, as a fraction of DEFAULT_BASE_POWER. This is the amplitude
-- of the curve, not a per-day step: a faction spends months on the good
-- side of it and months on the bad.
--
-- Bounded by construction, which is the property that keeps a long game
-- stable. Fortune displaces the TARGET rather than being added to power
-- each day; an integrated daily nudge is a random walk and wanders off
-- over a few thousand days, while a bounded target tracked with a lag
-- cannot go anywhere the target does not.
M.FORTUNE_SWING = 0.20

-- How many octaves of value noise the fortune curve sums. Each octave
-- doubles the frequency and halves the amplitude, so more octaves means
-- a rougher curve with the same range -- the layers are normalized
-- against their own total.
M.FORTUNE_OCTAVES = 3

-- The period of the slowest octave, in days. A faction's luck holds a
-- direction for roughly half of this, so it wants to be seasons rather
-- than weeks: a curve that turns over every fortnight reads as noise
-- rather than as fortune.
M.FORTUNE_PERIOD_DAYS = 120

-- Per-faction multiplier on fortune's amplitude, when a pack's faction
-- definition doesn't say otherwise. A pack raises it for a faction whose
-- fortunes should swing (a smuggling ring, a cult) and sets it to 0 for
-- one that should sit exactly where its ground puts it.
M.DEFAULT_VOLATILITY = 1

-- Whether drift drags other factions along the reaction table the way an
-- awarded change does. Off, for the reason GROWTH_PROPAGATES is off, only
-- more so: growth touches the handful of factions a pack gave a rate,
-- and drift touches every faction every day.
M.DRIFT_PROPAGATES = false

--------------------------------------------------------------------------
-- Invaders
--------------------------------------------------------------------------
--
-- A faction registered with `type = 'invader'` is an outside threat
-- rather than a participant in the politics. Three differences, and they
-- all follow from that one idea:
--
--   * it does not drift -- no capacity target, no fortune, so its ramp
--     is its growth and nothing pulls back against it;
--   * it takes no part in the reaction table in either direction;
--   * it fights everyone, without needing the `hostile` flag.
--
-- The payoff is that a setback dealt by content is PERMANENT. An award
-- against an ordinary faction decays back toward its capacity; an
-- invader has no target to decay toward, so the ramp simply resumes from
-- lower down.

M.FACTION_TYPE_INVADER = 'invader'

-- Whether an invader's power change drags other factions along the
-- reaction table. Off, and kept as a switch for the same reason
-- GROWTH_PROPAGATES is: the wiring exists and the default is a decision
-- rather than an oversight.
--
-- Turned on, the appealing half is that a blow struck against an invader
-- heartens everyone who hates it. What it costs is exactly the coupling
-- the type was introduced to remove -- an invader that climbs every day
-- drags the whole map down with it, which is the failure GROWTH_PROPAGATES
-- already ships off to avoid.
M.INVADER_MOVES_OTHERS = false

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
-- Strain
--------------------------------------------------------------------------
--
-- Strain is territories held per 100 power: how far a faction's borders
-- have run ahead of its standing. Like being surrounded, it is observed
-- and published and the framework does nothing about it -- but unlike
-- being surrounded, there are two knobs here for a game that wants it to
-- bite, both shipped off.

-- Strain at which a faction is reported strained, and at which the two
-- penalties below apply. The units make this readable: 100 is one
-- territory per point of power.
--
-- On the Morrowind map it flags the Tribunal Temple alone, which projects
-- over a quarter of the island from three seats. Redoran is the next
-- nearest at around 96.
M.STRAIN_EVENT_THRESHOLD = 100

-- How much of its projected strength a strained faction loses when
-- defending ground, as a fraction.
--
-- Off by default, and not a small switch: it makes borders
-- self-correcting, which is the interesting version of this system and
-- also the one that can oscillate. A faction loses ground, its strain
-- falls, it defends better, it takes the ground back. Turn it on with
-- FRONTIER_COOLDOWN_DAYS in mind -- the cooldown is what damps it.
M.STRAIN_DEFENCE_PENALTY = 0

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

--------------------------------------------------------------------------
-- Tribute
--------------------------------------------------------------------------
--
-- Gold a faction's own member hands over, turned into standing. The one
-- lever the player has on the simulation without a quest mod in the way.
--
-- Worth knowing what it does *not* do: an award to an ordinary faction
-- decays back toward its capacity at POWER_REVERSION_RATE, so buying a
-- house to the top of the table does not keep it there. Tribute lifts a
-- faction while it spends the standing on taking ground; ground held is
-- the only thing that makes the lift permanent. An invader has no
-- capacity to revert toward, which is exactly why a payment against one
-- sticks and a payment to one would too.

-- Power from one unit of gold, before diminishing returns and rank.
M.TRIBUTE_POWER_PER_UNIT = 0.5

-- The diminishing return. Below 1 the curve is concave, so a hundred
-- gold is worth far less than a hundred times one gold -- at 0.5 it is
-- worth ten times, because the exponent is a square root.
--
-- This is what stops tribute being a slider the player drags to win.
-- Buying a Great House one more point of standing costs more every time,
-- and the cost climbs quadratically, so there is no amount of gold that
-- makes the map stop mattering.
M.TRIBUTE_EXPONENT = 0.5

-- What a faction's own hierarchy is worth. A rank-1 member's gold counts
-- for MIN, the highest rank the faction defines counts for MAX, and the
-- ranks between interpolate.
--
-- The point is that tribute is not simply a gold sink: the same purse
-- moves more standing in the hands of someone the faction actually
-- listens to, so rising through a faction is worth something to the
-- simulation and not only to the player's inventory.
M.TRIBUTE_RANK_MULTIPLIER_MIN = 1
M.TRIBUTE_RANK_MULTIPLIER_MAX = 3

-- The amounts the tribute window offers, smallest first. Buttons rather
-- than a free entry field: MWUI has no numeric input worth the name, and
-- three fixed steps read better than a text box the player has to fight.
M.TRIBUTE_AMOUNTS = { 10, 100, 1000 }

--------------------------------------------------------------------------
-- Presentation
--------------------------------------------------------------------------

-- The l10n context, which is the directory name under l10n/. Every
-- string the player ever sees is resolved through it.
M.L10N_CONTEXT = 'BalanceOfPower'

-- The settings page key. Both groups -- the global simulation one and
-- the per-player notification one -- register onto this single page, so
-- the player finds everything the framework offers in one place.
M.SETTINGS_PAGE = 'BalanceOfPower'

-- The tribute window, in pixels.
M.WINDOW_WIDTH = 640
M.WINDOW_HEIGHT = 480

-- How many factions the standings column lists before it stops. Vanilla
-- registers 25 and a content-heavy load order will register more; a
-- window that grows without limit stops being readable long before it
-- stops fitting on the screen.
M.WINDOW_MAX_STANDINGS = 16

--------------------------------------------------------------------------
-- The survey
--------------------------------------------------------------------------

-- Classes that count as armed presence. This is the measurement: power is
-- who can hold ground rather than who holds title, so a house's guards
-- outrank its councillors and a town with a Legion fort in it reads
-- Imperial. `warrior` is deliberately broad -- it catches the Ashlander
-- and Nord fighters that carry no guard class.
M.SURVEY_GUARD_CLASSES = {
    ['guard'] = true,
    ['ordinator'] = true,
    ['buoyant armiger'] = true,
    ['warrior'] = true,
}

-- Faction ids that answer to another. Morrowind splits the Empire across
-- five records that hold ground as one power; collapsing them onto the
-- Legion's own id rather than an invented `empire` keeps the reaction row
-- coming from a real record. Ids absent from a load order are inert, so
-- this costs nothing in a game that has never heard of the Legion.
M.FACTION_ALIASES = {
    ['imperial cult'] = 'imperial legion',
    ['imperial knights'] = 'imperial legion',
    ['census and excise'] = 'imperial legion',
    ['blades'] = 'imperial legion',
}

-- Tier by footprint, largest first. Footprint is the same quantity the
-- framework projects power over, so a city is a city because it covers a
-- city's worth of ground. Population deliberately does not feed in: tier
-- already scales power, and folding the garrison in as well would count
-- the same guards twice.
M.SURVEY_TIER_BY_CELLS = {
    { cells = 12, tier = 'metropolis' },
    { cells = 6, tier = 'large city' },
    { cells = 4, tier = 'small city' },
    { cells = 3, tier = 'town' },
    { cells = 2, tier = 'village' },
    { cells = 1, tier = 'outpost' },
}

-- Per-faction tuning the game's records have no field for, keyed by
-- record id. Everything else about a faction is read from the records, so
-- entries belong here only where the game cannot say it.
--
-- Unknown ids are ignored, which is what lets the framework carry
-- Morrowind's one exception without becoming a Morrowind content pack:
-- in a load order without it, this table is inert.
M.FACTION_TUNING = {
    -- The invader holding Red Mountain. `type` takes it out of the
    -- politics entirely: it grows, it fights everyone, and nothing it
    -- does moves anybody's standing along the reaction table. Escalation
    -- then comes free from projection rather than from a stage table.
    --
    -- It has no capacity to revert toward, so a setback dealt by content
    -- is permanent -- the ramp resumes from lower down.
    ['sixth house'] = {
        type = 'invader',
        -- ~3 weeks to double its standing.
        growthPerDay = 1.5,
    },
}

--------------------------------------------------------------------------
-- Map overlay
--------------------------------------------------------------------------

-- The PixelMap layer's key and its place in the stack. Above the
-- built-ins (10 terrain, 20 grid) so ownership reads over the landscape
-- rather than under it.
M.MAP_LAYER_KEY = 'BalanceOfPower_territory'
M.MAP_LAYER_ORDER = 30

-- Settlement fills are opaque: this layer answers "who holds what" at a
-- glance, and a translucent fill over relief shading makes two similar
-- faction colours impossible to tell apart.
M.MAP_FILL_ALPHA = 1.0

-- White edge on each settlement square, in canvas pixels. A per-cell
-- overlay is read as a shape before it is read as a colour, so the border
-- is what separates two adjacent owners of similar hue. Clamped against
-- the cell size when zoomed out, so a distant city stays a coloured dot
-- rather than a white one.
M.MAP_CELL_BORDER = 2

-- Ground with a name and no claimant -- a derelict tower, an
-- unaffiliated Velothi holding. Grey rather than absent, so the map
-- distinguishes "nobody holds this" from "not a settlement".
M.MAP_COLOR_UNOWNED = { 0.45, 0.45, 0.48 }

-- Faction colours, keyed by the id in the game's own records. Vanilla
-- Morrowind's holders are named here; anything else falls back to a
-- colour derived from the id, so a landmass mod's factions are still
-- told apart without this table having to know them.
--
-- Chosen to stay distinguishable side by side on the map rather than to
-- match any heraldry: the Houses are the three that most often border
-- one another, so they take the three widely separated hues.
M.MAP_COLORS = {
    ['hlaalu'] = { 0.85, 0.65, 0.20 },
    ['redoran'] = { 0.75, 0.25, 0.20 },
    ['telvanni'] = { 0.55, 0.30, 0.70 },
    ['temple'] = { 0.30, 0.65, 0.85 },
    ['imperial legion'] = { 0.85, 0.85, 0.80 },
    ['east empire company'] = { 0.55, 0.45, 0.30 },
    ['ashlanders'] = { 0.80, 0.55, 0.40 },
    ['skaal'] = { 0.60, 0.80, 0.75 },
    ['sixth house'] = { 0.40, 0.15, 0.15 },
    ['camonna tong'] = { 0.35, 0.45, 0.25 },
    ['fighters guild'] = { 0.70, 0.55, 0.25 },
    ['mages guild'] = { 0.35, 0.40, 0.75 },
    ['thieves guild'] = { 0.30, 0.30, 0.35 },
    ['morag tong'] = { 0.25, 0.35, 0.30 },
}

return M
