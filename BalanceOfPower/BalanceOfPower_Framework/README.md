# Balance of Power — Framework

The engine half of the Balance of Power project. It tracks faction power and
territory control, and exposes an interface that content packs register data
against. It ships **no factions and no territories** — on its own it loads,
reports an empty world, and does nothing. That's the design: see
[the design document](../balance-of-power-design-doc.md), section 2.

Load order: this mod must load **before** any pack that registers data against it.

## Status

Phases 1–3 of [the implementation plan](../implementation-plan.md); see
[next-steps.md](../next-steps.md) for what comes next. The simulation logic has
unit tests — see [tests/](../tests/README.md).

For content, enable [BalanceOfPower_Morrowind](../BalanceOfPower_Morrowind/README.md).
For hotkeys and on-screen readouts over whatever content is loaded, add
[BalanceOfPower_Debug](../BalanceOfPower_Debug/README.md) on top — it
registers nothing of its own, so it composes with any content pack.

What exists:

- registration API with cross-pack faction merging
- faction power, reaction-driven propagation, atomic per-pass batching
- persistent state with central default-fill for save compatibility
- the in-game day tick driver
- territory resolution: projection maths, derived initial control, frontier
  rolls
- frontier grid generation from registered settlements
- the event bus, including the `BoP_DayResolved` scheduling hook

What doesn't exist yet: patrol spawning (phase 4) and player hooks (phase 5).

**What will never exist here:** sieges, invasion, corruption, spawning. Those
are mechanics, and this framework's remit is influence and ownership. They
belong to extensions, which read ownership, projection and `isSurrounded`
through the interface, write through `awardPower`, run off `BoP_DayResolved`,
and keep their own state. See [glossary.md](../glossary.md).

## How territory works

Every settlement projects influence that **halves every `influenceRange`** and
never reaches zero. A faction's strength at a place is its **strongest single
projection** there, never the sum — so a faction can't out-project a rival by
accumulating farms.

Because the decay has no floor, how far a faction reaches is decided by how much
power it has rather than by a boundary drawn per settlement. Ground it cannot
claim today becomes claimable if it grows, and **no cell is permanently beyond
everybody**. The growth is deliberately slow: distance costs a fixed fraction
per unit, so *every doubling of a faction's power pushes its border out by
exactly one `influenceRange`* — ten times the power buys a bit over three, not
ten.

Whoever projects most at a territory is who ends up holding it. Not instantly:
taking ground off an existing owner is a daily roll whose odds are the two
sides' share of projected strength, so a strong claimant wins reliably rather
than immediately and a front creeps instead of snapping. Ground nobody holds
needs no roll at all, only enough projection to clear `MIN_CLAIM_POWER`.

A consequence worth internalising: **while the current owner is also the
strongest projector, no rival roll happens.** Rolls decide how long a takeover
takes, not who wins it. Ownership only moves when the projection ordering
changes — which happens when faction power moves.

The starting map is derived the same way. A pack that authors no `defaultOwner`
gets ownership assigned from its settlements on the first tick, which is what
makes a procedurally generated frontier grid viable. An authored `defaultOwner`
overrides that, for a pack that wants a specific starting owner somewhere.

Frontier cells are contestable regardless of what is next to them — proximity
decay is already the adjacency rule, since a faction with no foothold nearby
projects nothing and cannot win.

**Settlements hold themselves, and there is no rule saying so.** Every cell in
the world goes through the same ownership logic, wilderness and city alike.
What keeps a settlement with whoever built it is `SEAT_FLOOR`: a faction is
never weaker at a cell its own settlement occupies than that settlement's
garrison value, scaled by weight.

A number rather than a rule, deliberately. "A settlement cannot change owner"
needs exceptions the moment you look at the awkward cases — a holding with no
faction behind it, a farm too small to be worth defending — and each exception
is a branch someone has to remember. A floor needs none: weight 0 gives a floor
of 0, and a derelict tower behaves like open ground.

At the shipped `SEAT_FLOOR = 250` a settlement is immovable by ordinary
politics and takeable only by roughly ten times a faction's starting standing.
That threshold is the knob, not a hole — lower it and cities fall to a strong
enough invader; raise it and nothing ever takes one.

The framework also publishes the fact an extension needs:
`isSurrounded(settlementId)` reports whether rivals hold `SURROUND_SHARE` of a
settlement's ring, and `surroundedSince(settlementId)` gives the day it
started. Both are observed; nothing here acts on them.

### Territories are cells

**Every territory is exactly one exterior cell.** A settlement is a *group* of
them — Vivec is one settlement over fifteen separately ownable cells, all
tagged with the same `settlement` id. `getSettlement`, `settlementIds` and
`getSettlementOwner` work with the named places; `territoryIds` works with
cells.

Interior cells belong to a settlement but are never territories: an interior
has no grid position to project onto or from. `getTerritoryForCell` still
resolves one, to its settlement's first exterior cell.

### Scale

Influence ranges are in world units, and **an exterior cell is 8192 units
across**. That is the ESM3 grid the engine works in, not a Morrowind-specific
number — it is the same for Tamriel Rebuilt, Project Cyrodiil and Skyrim Home
of the Nords.

The tier defaults are halving distances from 2500 (`minor location`) to 14000
(`megalopolis`), which at the default base power put a farm's claim at its own
cell and a metropolis's at about five. Since the range is what a doubling of
power buys, it is also the knob for *how fast* a growing faction expands: short
ranges make a faction's borders tight and hard to push, long ones make power
translate quickly into ground.

A pack that places anything by grid coordinate should read the constant from
the interface as `BoP.CELL_SIZE` rather than writing 8192 down again — its
geometry has to agree with the grid `generateFrontier` lays down.

## Using it from a content pack

```lua
local I = require('openmw.interfaces')

I.BalanceOfPower.registerLandmass({
    id = 'vvardenfell',
    factions = {
        {
            id = 'hlaalu',                       -- matches the vanilla faction record id
            patrolRoster = { 'hlaalu guard' },   -- record ids, never inspected
        },
    },
    territories = {                            -- settlements: named places
        {
            id = 'balmora',
            displayName = 'Balmora',
            tier = 'small city',
            faction = 'hlaalu',                -- whose seat it is, so whose power it projects
            -- One territory per exterior cell: balmora_-3_-2 and
            -- balmora_-2_-2. The interior belongs to the settlement but
            -- is not a territory of its own.
            cells = { 'Balmora', '#-3,-2', '#-2,-2' },
            adjacentFrontier = { 'west_gash_a4', 'west_gash_a5' },
        },
    },
    frontier = {                               -- frontier cells: wilderness
        {
            id = 'west_gash_a4',
            centroid = { x = -30000, y = -8000 },
            cells = { '#-4,-1' },
            adjacentFrontier = { 'west_gash_a5' },
            adjacentSettlements = { 'balmora' },
            defaultOwner = 'hlaalu',
        },
    },
})
```

Call it from your pack's own `GLOBAL` script body. Script bodies run in
`.omwscripts` load order, before any engine handler, so the interface is
available as long as your pack loads after the framework.

### Field reference

Anything with a default may be omitted.

**Faction** — `id` (required), `recordId` (defaults to `id`, see below),
`growthPerDay` (default 0, see below), `hostile` (default `false`, see below),
`landmass`, `patrolRoster` (see below).

**A pack does not create factions.** The framework registers every faction the
game's own records describe (see below), so an entry here is *tuning* — the
handful of numbers neither the records nor the map can supply. Most factions
need no entry at all. Declaring one the records don't cover still works; it
simply has no politics.

Four fields are derived and setting any of them is an error:

| Field | Where it comes from |
|---|---|
| `reactions` | the record's reaction row |
| `displayName` | the record's name |
| `territorial` | whether any settlement names the faction |
| `basePower` | the faction's seats — see *Starting power* below |

A faction declares no geography of its own. It holds whatever settlements name
it, which the registry hands it as `seats`.

`growthPerDay`, `hostile` and `recordId` are base configuration: whichever pack
sets one first keeps it, and a later pack setting the same field is ignored with
a warning. Which pack won would otherwise depend on load order. Rosters merge
instead, deduplicated by record id.

**Settlement** (`territories`) — `id` (required), `cells` (required — one
territory is created per exterior cell), `faction` (whose seat it is; omit for
an unaffiliated holding that projects nothing), `displayName`, `tier`,
`region`, `adjacentFrontier`, `defaultOwner` (omit for unclaimed), `centroid`
(defaults to the middle of its own cells), `weight`, `influenceRange` and
`cooldownDays` (all three default per tier).

**Tier** is one ladder, smallest to largest:

`minor location` · `outpost` · `village` · `town` · `small city` ·
`large city` · `metropolis` · `megalopolis`

Default `town`. It is not metadata: it sets how strongly the settlement
projects, how far, and how long its cells are immune after a flip. Tier
defaults exist so a farm needs only an id and a cell.

There is **no separate category for things that project.** A settlement is the
only thing that does. A farm is a `minor location` — it reaches barely past its
own cell and holds that cell against most comers, which is what a farm should
do — and it differs from Vivec by the numbers behind its tier, not by kind.

**Frontier cell** (`frontier`) — `id` (required), `centroid` (required),
`cells`, `adjacentFrontier`, `adjacentSettlements`, `defaultOwner`, `cooldownDays`.

### How much frontier gets generated

Projection has no cut-off, so "everywhere a settlement reaches" is not a
finite answer. `generateFrontier` instead plans for a power —
`FRONTIER_GENERATION_POWER`, defaulting to twice the base — and gives each
settlement the radius a faction of that power could *claim* from it. That
leaves the map one doubling of headroom to grow into.

The fraction of the generated map that starts unowned follows from that ratio
alone, and the tier ranges cancel out of it entirely:

```
unclaimed ≈ 1 - (log2(base ÷ claim floor) ÷ log2(planned ÷ claim floor))²
```

At twice base power that is a bit over a third — expansion room. At five times
it is nearly two thirds, which reads as an empty world. A faction that outgrows
the figure projects past the edge of the generated map; raise it and regenerate
rather than capping the projection.

Every settlement is guaranteed frontier immediately around it regardless, since
`isSurrounded()` is answered from that ring and a settlement without one could
never be reported surrounded.

### Where factions come from

The framework enumerates `core.factions.records` on the first registration and
registers what it finds. A pack supplies ids and tuning; it never supplies the
roster of who exists.

**Not every record becomes a faction.** One is registered only if it takes part
in the politics — a non-zero reaction of its own, or somebody's non-zero
reaction to it. Content files keep dead ids alive so old saves still load:
Tamriel Data ships a dozen records named `<Deprecated>`, every one with an empty
row and no column, and without the filter all twelve would appear in the
standings.

The filter governs only what the *records* contribute. **A pack naming a faction
registers it regardless**, which is how the Morag Tong and the Talos Cult survive
— both have no reactions in either direction and both need to exist.

### Factions that span packs

Nothing special is needed. A faction like Hlaalu holds ground on several
landmasses because a settlement names its faction, so each pack's holdings
attach themselves wherever they are registered. No pack owns a faction, so
there is no first-registrant to defer to and no load-order hazard.

```lua
{ id = 'hlaalu', patrolRoster = { 'hlaalu councilor' } }
```

> `extend = true` is obsolete. An entry carrying it still registers, with a
> warning — silently dropping a pack's faction would be worse than ignoring a
> flag.

### Land-holding and power-only factions

`territorial` is **derived, not declared**: a faction is territorial exactly
when some settlement names it as its seat. It is recomputed after every
registration, so a later pack's settlements can promote a faction that started
with nothing.

A faction with no seats is **power-only**. It has a power score, it reacts to
everyone else through the reaction table, and other systems can read its
standing — but it holds no ground and projects nothing. That's the split between
a Great House and a guild: the Fighters Guild is a real political force whose
fortunes rise and fall with its allies'; it just doesn't own Balmora.

A settlement that should project for nobody omits `faction` rather than naming
one that isn't meant to hold ground.

### Starting power

Nobody authors a starting standing. It is derived from what a faction holds,
along two axes that are not the same thing:

- **Breadth** — how many regions it is present in.
- **Depth** — how much it holds within each of them.

```
score = Σ over regions( strongest seat weight + POWER_DEPTH_SHARE × the rest )
power = DEFAULT_BASE_POWER × ( POWER_FLOOR_SHARE
                             + (1 − POWER_FLOOR_SHARE) × score ÷ mean score )
```

A region contributes its **strongest** seat plus a share of the rest — the same
rule the projection maths uses, so a plantation belt reads as presence in one
region rather than as several cities. `POWER_DEPTH_SHARE` (0.25) says a second
holding in a region you already hold is worth a quarter of a first one.

The mean is taken over land-holding factions alone; including the zeros would
drag the anchor down and compress everyone above it. Two consequences worth
knowing:

- A faction with **average** holdings gets exactly `DEFAULT_BASE_POWER`.
- A faction with **no** seats gets `POWER_FLOOR_SHARE` of it — 30% — and stays
  there whatever else is installed, because a score of zero never touches the
  mean. `POWER_FLOOR_SHARE` doubles as the compression knob: raise it to narrow
  the spread between the strongest faction and the weakest.

On the Morrowind pack this puts the Empire first on nine holdings across seven
regions, ahead of Hlaalu's seventeen concentrated in three — which a plain
weight sum would invert.

Power is seeded **once, on the driver's first tick**, because the mean is not
known until every pack has registered. A loaded save keeps its own numbers;
only factions with no power yet are seeded, so installing a pack mid-game gives
its factions a derived standing without disturbing the rest.

`region` comes from the game's own cell data and may be missing; a seat without
one falls back to its landmass rather than to something unique, which would make
every region-less holding its own region.

### Standings

Breadth and depth are measured on two sides. Seats are what a faction was built
with, and they never change; **standings** are what it holds today, and they move
with every flip.

```lua
local standing = I.BalanceOfPower.factionStanding('hlaalu')
--  { id, power, territories, settlements, regions,
--    seats, seatScore, strain, concentration }
```

| | |
|---|---|
| `territories` | exterior cells held right now |
| `settlements` | named places it holds at least one cell of — a city counts once |
| `regions` | distinct regions it holds any ground in |
| `seats` / `seatScore` | the fixed side: what the registry says it was built with |
| `strain` | territories held per 100 power |
| `concentration` | territories per region |

The last two are ratios over the fields beside them, in the API so that every
mod computes them the same way. **`strain` is the overreach signal**: a faction
whose borders have run ahead of its standing reads high, and stays high until it
either grows into the ground or loses it. On the Morrowind pack the Tribunal
Temple sits around 145 — three seats, one of them Vivec, projecting over a
quarter of the island — while the Empire sits around 40 on nine well-spread
forts. That gap is the hook: it is the difference between a faction that holds
its ground and one that is merely on it.

The rest of the surface:

```lua
I.BalanceOfPower.standings()                  -- every faction, strongest first
I.BalanceOfPower.regionsHeldBy('hlaalu')      -- sorted region names
I.BalanceOfPower.holdersOfRegion('Ascadian Isles')  -- factionId -> cell count
```

The framework publishes these and acts on none of them. Spawning extra bandits
in a strained faction's cells, thinning its patrols, or writing a rumour about
it are all extension decisions — see the `isSurrounded` contract, which works
the same way.

### Deriving the frontier

Wilderness is generated, not authored — a landmass is thousands of cells.
Register the settlements first, then:

```lua
I.BalanceOfPower.generateFrontier({ landmass = 'vvardenfell' })
```

It walks outward from every settlement registered on that landmass and
creates one territory per exterior cell within reach, skipping cells a
settlement already claims and grid positions the content files don't define
(which removes most open ocean for free). It also wires each settlement to the ring
of cells around it, since a pack can't name generated ids itself — without that
link no settlement could ever be reported as surrounded.

**Only ground somebody can reach becomes territory.** That's what keeps the
daily pass cheap by construction: the Morrowind pack generates ~560 frontier
cells with an average of 1.2 factions able to reach each one, rather than a
rectangle full of sea.

Options: `cellsPerUnit` (cells per territory per axis — the main performance
lever), `cellSize`, `margin`, `idPrefix`, `requireExistingCell`.

### Reactions

**Every reaction value comes from `core.factions.records`, and there is nowhere
else to put one.** No mod in this ecosystem creates factions or their opinions
— the game's content files do, and so does any faction rebalance mod the player
has loaded. A table transcribed into Lua would be a second copy that silently
outranks the first, so the registry refuses a faction definition carrying a
`reactions` field.

A content pack contributes ids. That is the whole of its say in the politics.

#### `recordId`

A faction reads the record its `id` names, matched case-insensitively. Set
`recordId` when the two differ:

```lua
{ id = 'empire', recordId = 'Imperial Legion' }
```

It works in both directions — the faction reads that record's row, and every
other record naming `Imperial Legion` resolves back to `empire`. Most packs
never need it, because registering factions under their record ids costs
nothing.

#### Which way round they read

Two statements that sound contradictory and are both true:

- **Storage is outbound.** A row is the record owner's own opinions:
  `reactions[otherFactionId] = how this faction feels about that one`, which is
  also how far it moves when that other faction's power changes. Nothing is
  transposed and no setting selects a direction.
- **The propagation query is inbound.** "Who moves when X moves" is X's
  *column* — every other faction's row, indexed by X.

> **The engine's documentation says the opposite** — it describes
> `FactionRecord.reactions` as "reactions of other factions to this faction" —
> and is wrong for ESM3. This framework believed it for three phases and
> propagated every asymmetric vanilla pair backwards. See
> `openmw-lua-api-notes.md` for the evidence.

Asymmetry is the whole point of the table and the reason a wrong reading is so
hard to spot: most pairs are near-symmetric, so getting the direction backwards
changes the magnitude of a handful of relationships and never errors. When in
doubt, `regardOf(a, b)` answers "how does A feel about B".

#### When a faction has no politics

Three ways that happens, and only the first is a bug:

| | |
|---|---|
| No record found for the id | almost certainly a typo, or a missing `recordId`. Warned loudly |
| Record found, empty reaction row | the game says this faction has no opinions |
| Record row names only factions this pack doesn't register | nothing survives the filter |

`dumpReactions()` shows the wiring:

```
luag require('openmw.interfaces').BalanceOfPower.dumpReactions()
```

`moves` is how many factions this one can push; `movedBy` is how many can push
it, counting only opinions that aren't zero — a reaction of zero propagates
nothing, and vanilla rows carry explicit zeros, so counting entries would report
every faction as fully wired. **A zero in either column is a faction standing
outside the politics**, which produces no error and is close to invisible in
play.

An expansion is where this bites hardest: its factions carry rows of their own,
but the base game's records were never patched to name them back, so an
expansion faction often moves nobody. Closing a gap like that means shipping an
`.esp` that adds the FACT entries — not a table in Lua.

### Patrols

The framework decides *that* patrols happen; a content pack decides what they
are. `planPatrol(territoryId, day)` returns the decision and creates nothing:

```lua
{ territory = 'west_gash_a4', day = 412, groups = {
    { faction = 'hlaalu', projection = 61.2, count = 2, tier = 1,
      records = { 'hlaalu guard', 'hlaalu guard' },
      hostileToPlayer = false, fights = {} },
} }
```

`records` are ids the pack authored, in whatever vocabulary its content files
use. The framework has never looked inside one.

Who is eligible, and they are different questions: **the owner** patrols ground
it holds, and **a hostile faction** patrols anywhere it projects above
`PATROL_MIN_PROJECTION`, held by somebody else or not. That second rule is what
makes an invader visible on a border before it takes anything.

**A faction with an empty roster fields no patrols.** That is the entire
opt-out — no flag, no `territorial` check, nothing to remember.

Size and strength both scale with projection: one more member per
`PATROL_POWER_PER_MEMBER` up to a cap, and one more roster tier per
`PATROL_POWER_PER_TIER` up to whatever the pack authored. Lower tiers stay in
the pool, so a strong faction fields its best troops alongside its ordinary
ones rather than an honour guard.

#### The roll is seeded, not random

`plan` is a pure function of `(territory, day)`. Re-entering a cell gives the
same patrol back rather than a fresh roll, which matters for three separate
reasons: patrols cannot be farmed for the gear and gold every vanilla record
carries; a patrol despawned when its cell went quiet is the same patrol when
the player returns; and a plan survives a save reload without the world
rearranging itself.

`PATROL_COOLDOWN_DAYS` handles the same risk across days — pass
`{ lastSpawnedDay = n }` from whatever tracks live actors.

### Hostility

One rule at three settings, rather than three features:

> A faction fights nobody unless its pack flagged it `hostile`. A flagged
> faction attacks the player, and fights whoever it regards at or below
> `HOSTILITY_REACTION_THRESHOLD`.

So a hostile invader, a per-faction enemies list and an everyone-fights-everyone
toggle (`ALL_FACTIONS_HOSTILE`) are the same rule read differently. None of them
is a code path of its own.

Defaulting to nobody is deliberate: Morrowind's Great Houses dislike each other
without brawling in the street, and hostility derived from reaction values
alone would have Redoran and Telvanni guards fighting everywhere the player
looked. Even with `ALL_FACTIONS_HOSTILE` on, -3 is rare between vanilla
factions — what emerges is the handful of real blood feuds, not a general war.

`isHostile(a, b)` is asymmetric: a peaceful faction does not go looking for the
fight it ends up in. `willFight(a, b)` is the symmetric question, and the one a
spawn rule wants.

The player has no reaction row, so the flag covers that relationship directly
rather than adding a second field for a distinction no content has asked for.

### Ambient growth

`growthPerDay` on a faction definition is power gained each resolved day with
nobody doing anything. Applied before the resolution batch opens, so the day's
rolls see today's number.

**It does not propagate through the reaction table**, and that default is worth
understanding before changing it. Every faction in the Morrowind pack sits at
-3 toward the Sixth House, so propagated growth at 1.5/day drains 0.225 from
each of them daily against starting standings of 25–50. The whole political map
reaches `MIN_POWER` within four to seven in-game months, every projection falls
below `MIN_CLAIM_POWER`, and the world empties — while the growing faction
gains nothing from it, since its reach is bounded by `influenceRange` rather
than by power. `GROWTH_PROPAGATES` turns it on if you want it.

### Awarding power

```lua
I.BalanceOfPower.awardPower(factionId, baseDelta, playerRankMultiplier)
```

Also available: `getPower`, `setPower`, `getOwner`, `getTerritory`,
`getTerritoryForCell`, `getFaction`, `factionIds`, `territoryIds`,
`regardOf`, `isHostile`, `willFight`, `isHostileToPlayer`, `enemiesOf`,
`planPatrol`, `getEffectivePower`, `getProjection`, `classify`, `getReach`,
`getSettlement`,
`settlementIds`, `getSettlementOwner`, `isSurrounded`, `surroundedSince`,
`factionStanding`, `standings`, `regionsHeldBy`, `holdersOfRegion`,
`getCurrentDay`, `powerSummary`, `reactionAudit`, `dumpReactions`, `dump`,
`dumpMap`, `renderMap`, `isDebug`, and the `CELL_SIZE` constant.

`classify(territoryId)` returns `'unclaimed'`, `'consolidated'`,
`'uncontested'` or `'contested'` — exactly one of the four, always, with
`unclaimed` meaning precisely "no owner". See
[glossary.md](../glossary.md) for what each means and why `uncontested` is not
the same as "nobody else is here".
`getReach(territoryId)` returns which factions can reach it at all and by what
fraction of their power — static geometry, so it's cheap and stable.

`getProjection(territoryId)` returns the faction that projects most onto a
territory and how strongly — i.e. who will end up holding it. If that differs
from `getOwner`, the territory is actively contested.

`forceDay(count)` resolves days immediately instead of waiting for the game
calendar. It's a testing aid, and it runs the simulation *ahead* of game time —
the scheduled tick then idles until real time catches up, so a forced day is a
real day rather than an extra one.

### Events

Fired both as global events and to every player script, so a listener handles
them in whichever context it runs in. Names are on `I.BalanceOfPower.events`.

| Event | Payload |
|---|---|
| `BoP_TerritoryFlipped` | `territory`, `kind`, `from`, `to`, `day` |
| `BoP_SettlementSurrounded` / `BoP_SettlementRelieved` | `territory`, `day` |
| `BoP_PowerChanged` | `faction`, `delta`, `newTotal` |
| `BoP_DayResolved` | `day` |

`BoP_DayResolved` is the scheduling hook for anything built on top. An
extension that acts once a day runs from this rather than keeping a timer that
drifts against the framework's own pass.

Delivery is queued rather than synchronous, so a listener acts on the day
*after* the one it hears about. That is invisible in play, but an extension
needing strict ordering should poll `getCurrentDay()` instead — the pattern the
driver itself uses.

## Layout

```
scripts/BalanceOfPower/
  main.lua           GLOBAL script: save/load boundary, interface export
  core/config.lua    every tunable constant
  core/log.lua       prefixed logging
  core/events.lua    event names + broadcast
  core/state.lua     per-save state, serialization, default-fill
  core/registry.lua  authored data from packs, validation, merging
  core/power.lua     power, reaction propagation, batching
  core/resolve.lua   projection maths, initial control, frontier flips
  core/frontier.lua  derives the wilderness grid from settlements
  core/cells.lua     exterior cell naming
  core/mapdump.lua   the text map
  core/driver.lua    the clock: day rollover, catch-up, forced ticks
  core/api.lua       the public interface
```

Content packs should only ever touch `core/api.lua`'s surface through the
interface. The merged VFS technically lets a pack `require` a core module
directly; doing so couples it to internals that change between phases.

## The text map

`dumpMap()` draws the political map to `openmw.log`, one character per
exterior cell, north at the top. Uppercase is a settlement, lowercase the
wilderness around it. From the in-game console:

```
luag require('openmw.interfaces').BalanceOfPower.dumpMap()
luag require('openmw.interfaces').BalanceOfPower.dumpMap({ mode = 'projection' })
luag require('openmw.interfaces').BalanceOfPower.dumpMap({ mode = 'contest' })
luag require('openmw.interfaces').BalanceOfPower.dumpMap({ landmass = 'solstheim' })
```

```
   16 -------                .----.
   15 ------.                .-----
    5    .------###---.        .-------.
    4    ----#--###-#--         -------.
    3    ------#####.-.         .---###
legend: # contested   - consolidated   . nobody reaches
```

Three modes:

- **`owner`** (default) — who holds each cell now.
- **`projection`** — who *will* hold it, given time and no change in anyone's
  power. Where this disagrees with the ownership map, a front is moving. This
  is the view to read while tuning influence ranges, because it shows the
  consequence of a range change immediately rather than after days of rolls.
- **`contest`** — where the fronts are, ignoring who holds what.

Pass `centreCell = '#x,y'` (with an optional `radius`, default 6) to draw a
window around a position instead of everything. The full map is forty columns by
fifty rows — fine in a log, useless in a message box — so anything rendering to
the screen wants the windowed form.

`renderMap(opts)` returns the same thing as a list of lines, for a caller that
wants to put it somewhere other than the log.

## Tuning

Every constant is in `core/config.lua`. `DEBUG` and `DEBUG_DAILY_SUMMARY` are
on by default during development — turn both off before shipping.
