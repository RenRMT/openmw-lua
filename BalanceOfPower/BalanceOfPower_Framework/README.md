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
  rolls, anchor sieges
- frontier grid generation from registered power centers
- the event bus

What doesn't exist yet: patrol spawning (phase 4), player hooks (phase 5),
invasion escalation and corruption (phase 6). `registerInvasion` accepts and
validates an invading faction, and its power and territory are simulated like
anyone else's, but nothing escalates or corrupts yet.

## How territory works

Every power center projects influence that decays linearly to zero at its
`influenceRange`. A faction's strength at a place is its **strongest single
projection** there, never the sum — so a faction can't out-project a rival by
accumulating minor outposts.

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
gets ownership assigned from its power centers on the first tick, which is what
makes a procedurally generated frontier grid viable. An authored `defaultOwner`
overrides that, which is how an invasion homeland stays with its invader.

Frontier cells are contestable regardless of what is next to them — proximity
decay is already the adjacency rule, since a faction with no foothold nearby
projects nothing and cannot win. Anchors are different: a settlement must be
surrounded (`SURROUND_SHARE` of its `adjacentFrontier` in rival hands) for
`siegeThreshold` consecutive days before it can be rolled for at all, and then
the defender's projection is multiplied by `defenseMultiplier`.

### Scale

Influence ranges are in world units, and **an exterior cell is 8192 units
across**. That is the ESM3 grid the engine works in, not a Morrowind-specific
number — it is the same for Tamriel Rebuilt, Project Cyrodiil and Skyrim Home
of the Nords. Ranges below it project onto nothing but their own cell. The tier
defaults are sized in cells: roughly 5 (capital), 3 (regional) and 1.5
(outpost).

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
            id = 'hlaalu',                    -- matches the vanilla faction record id
            displayName = 'House Hlaalu',
            basePower = 50,
            patrolRoster = { 'hlaalu guard' },
            powerCenters = {
                { id = 'balmora', tier = 'capital', coords = { x = -22000, y = -14000 } },
                { id = 'caldera_holdings', tier = 'outpost', coords = { x = -12000, y = 12000 } },
            },
        },
    },
    territories = {                            -- anchors: settlements
        {
            id = 'balmora',
            displayName = 'Balmora',
            tier = 'city',
            cells = { 'Balmora', '#-3,-2', '#-2,-2' },
            adjacentFrontier = { 'west_gash_a4', 'west_gash_a5' },
            defaultOwner = 'hlaalu',
        },
    },
    frontier = {                               -- frontier cells: wilderness
        {
            id = 'west_gash_a4',
            centroid = { x = -30000, y = -8000 },
            cells = { '#-4,-1' },
            adjacentFrontier = { 'west_gash_a5' },
            adjacentAnchors = { 'balmora' },
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

**Faction** — `id` (required), `displayName`, `territorial` (default `true`,
see below), `basePower` (default 50), `landmass`, `powerCenters`,
`patrolRoster`, `reactions` (only for factions with no ESM faction record —
see below), `extend` (see below).

**Power center** — `id` (required), `coords` (required, `{x=, y=}`),
`tier` (`capital` | `regional` | `outpost` | `minor`, default `regional`),
`weight` and `influenceRange` (both default per tier). Tier defaults exist so a
minor holding only needs an id and coordinates.

**Anchor** (`territories`) — `id` (required), `displayName`, `tier`
(`outpost` | `village` | `town` | `city` | `metropolis`, default `town`),
`cells`, `region`, `adjacentFrontier`, `defaultOwner` (omit for unclaimed),
`centroid`, `siegeThreshold`, `cooldownDays`, `defenseMultiplier` (last three
default per tier).

**Frontier cell** (`frontier`) — `id` (required), `centroid` (required),
`cells`, `adjacentFrontier`, `adjacentAnchors`, `defaultOwner`, `cooldownDays`.

**Invasion** — `registerInvasion({ id = ..., faction = { ... } })`, where the
faction adds `homeTerritories`, `growthPerDay`, and `escalationThresholds`
(a list of `{ stage = ..., power = ... }`, which must ascend by power).

### Factions that span packs

A faction like Hlaalu holds ground on more than one landmass. The second and
every later pack marks its entry `extend = true`:

```lua
{ id = 'hlaalu', extend = true, powerCenters = { { id = 'bal_foyen', ... } } }
```

Power centers and roster entries are merged in; `basePower`, `displayName` and
`territorial` stay owned by whichever pack registered the faction first, and an
extending pack that tries to set them gets a warning. Redefining an id without
`extend` is an error rather than a silent overwrite.

### Land-holding and power-only factions

`territorial` decides whether a faction appears on the map at all:

- `true` (default) — it owns ground, projects influence from its power centers,
  and can be recorded as a territory's owner.
- `false` — a **power-only** faction. It has a power score, it reacts to
  everyone else through the reaction table, and other systems can read its
  standing — but it holds no ground and projects nothing.

That's the split between a Great House and a guild. The Fighters Guild is a
real political force whose fortunes rise and fall with its allies'; it just
doesn't own Balmora. A faction that shouldn't participate at all is simply not
registered.

### Deriving the frontier

Wilderness is generated, not authored — a landmass is thousands of cells.
Register the settlements first, then:

```lua
I.BalanceOfPower.generateFrontier({ landmass = 'vvardenfell' })
```

It walks outward from every power center registered on that landmass and
creates one territory per exterior cell within reach, skipping cells a
settlement already claims and grid positions the content files don't define
(which removes most open ocean for free). It also wires each anchor to the ring
of cells around it, since a pack can't name generated ids itself — without that
link no settlement could ever be besieged.

**Only ground somebody can reach becomes territory.** That's what keeps the
daily pass cheap by construction: the Morrowind pack generates ~560 frontier
cells with an average of 1.2 factions able to reach each one, rather than a
rectangle full of sea.

Options: `cellsPerUnit` (cells per territory per axis — the main performance
lever), `cellSize`, `margin`, `idPrefix`, `requireExistingCell`.

### Reactions, and which way round they read

A faction's reaction row answers one question: **when this faction's power
moves, who moves with it?** Both sources are read as

```lua
reactions[otherFactionId] = how that other faction feels about this one
```

Values come from `core.factions.records` where a faction has an ESM record,
and from an authored `reactions` table in the faction definition otherwise —
a Tamriel Rebuilt House Dres, an invader that only exists in Lua.

**The two are merged, not swapped.** Authored values win where both name the
same pair, but the rest of the record survives. That matters more than it
sounds: a vanilla faction's record can only name factions that exist in the
ESM, so teaching the Empire how to feel about a Lua-only faction is *only*
possible from the authored side — and before the merge, doing so would have
cost the Empire every real relationship it has.

#### Both directions have to be wired

A faction with no ESM record is invisible to every other faction's record row.
Authoring its own table makes it move other factions; it does **not** make
anything move *it*. That half has to be authored on the other side, as an
entry on each faction that should react to it.

The framework warns at load about both failures, and `dumpReactions()` shows
the wiring:

```
luag require('openmw.interfaces').BalanceOfPower.dumpReactions()
```

`moves` is how many factions this one can push; `movedBy` is how many can push
it. **A zero in either column is a faction standing outside the politics**,
which produces no error and is close to invisible in play.

#### One unverified assumption

Whether `core.factions.records[id].reactions` really reads inbound (*"how
everyone else feels about me"*, which is how OpenMW documents it) or outbound
(*"how I feel about everyone else"*, which is how the underlying ESM3 `FACT`
record is conventionally read) has not been confirmed against a running game.

`config.RECORD_REACTIONS_ARE_INBOUND` selects it, so settling the question is a
one-line change rather than an audit. Authored tables are unaffected — their
convention is fixed at inbound. See the comment on that constant for the
console command that answers it.

### Awarding power

```lua
I.BalanceOfPower.awardPower(factionId, baseDelta, playerRankMultiplier)
```

Also available: `getPower`, `setPower`, `getOwner`, `getTerritory`,
`getTerritoryForCell`, `getFaction`, `factionIds`, `territoryIds`,
`getEffectivePower`, `getProjection`, `classify`, `getReach`, `getInvasion`,
`getInvasionStage`, `isCorrupted`, `getCurrentDay`, `powerSummary`, `dump`, `dumpMap`,
`renderMap`, `isDebug`.

`classify(territoryId)` returns `'empty'`, `'consolidated'` or `'contested'`.
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
| `BoP_AnchorSieged` | `territory`, `streak`, `threshold` |
| `BoP_PowerChanged` | `faction`, `delta`, `newTotal` |
| `BoP_InvasionEscalated` | `invasion`, `oldStage`, `newStage` |
| `BoP_TerritoryCorrupted` / `BoP_TerritoryLiberated` | `territory`, `invasion` |

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
  core/resolve.lua   projection maths, initial control, flips and sieges
  core/frontier.lua  derives the wilderness grid from power centers
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
