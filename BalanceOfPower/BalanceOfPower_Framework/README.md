# Balance of Power — Framework

The engine half of the Balance of Power project. It tracks faction power and
territory control, and exposes an interface that content packs register data
against. It ships **no factions and no territories** — on its own it loads,
reports an empty world, and does nothing. That's the design: see
[the design document](../balance-of-power-design-doc.md), section 2.

Load order: this mod must load **before** any pack that registers data against it.

## Status

Phases 1–2 of [the implementation plan](../implementation-plan.md); see
[next-steps.md](../next-steps.md) for what comes next. To exercise any of this
in-game, enable [BalanceOfPower_DevSandbox](../BalanceOfPower_DevSandbox/README.md)
alongside it. The simulation logic has unit tests — see [tests/](../tests/README.md).

What exists:

- registration API with cross-pack faction merging
- faction power, reaction-driven propagation, atomic per-pass batching
- persistent state with central default-fill for save compatibility
- the in-game day tick driver
- territory resolution: projection maths, derived initial control, frontier
  rolls, anchor sieges
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

Influence ranges are in world units, and **a Morrowind exterior cell is 8192
units across**. Ranges below that project onto nothing but their own cell. The
tier defaults are sized in cells: roughly 5 (capital), 3 (regional) and 1.5
(outpost).

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

**Faction** — `id` (required), `displayName`, `territorial` (default `true`;
`false` keeps the faction in the registry but out of the power loop),
`basePower` (default 50), `landmass`, `powerCenters`, `patrolRoster`,
`reactions` (only for factions with no ESM faction record — see below),
`extend` (see below).

**Power center** — `id` (required), `coords` (required, `{x=, y=}`),
`tier` (`capital` | `regional` | `outpost`, default `regional`), `weight` and
`influenceRange` (both default per tier). Tier defaults exist so a minor
holding only needs an id and coordinates.

**Anchor** (`territories`) — `id` (required), `displayName`, `tier`
(`town` | `city`, default `town`), `cells`, `adjacentFrontier`, `defaultOwner`
(omit for unclaimed), `centroid`, `siegeThreshold`, `cooldownDays`,
`defenseMultiplier` (last three default per tier).

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

### Factions with no faction record

Power propagation reads reaction values from `core.factions.records` by
default. A faction that doesn't exist as an ESM record — a Tamriel Rebuilt
House Dres, an invader that only exists in Lua — supplies its own `reactions`
table (`{ otherFactionId = -3, ... }`, meaning *how that other faction feels
about this one*). The propagation math is identical either way.

### Awarding power

```lua
I.BalanceOfPower.awardPower(factionId, baseDelta, playerRankMultiplier)
```

Also available: `getPower`, `setPower`, `getOwner`, `getTerritory`,
`getTerritoryForCell`, `getFaction`, `factionIds`, `territoryIds`,
`getEffectivePower`, `getProjection`, `getInvasion`, `getInvasionStage`,
`isCorrupted`, `getCurrentDay`, `powerSummary`, `dump`, `isDebug`.

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
  core/driver.lua    the clock: day rollover, catch-up, forced ticks
  core/api.lua       the public interface
```

Content packs should only ever touch `core/api.lua`'s surface through the
interface. The merged VFS technically lets a pack `require` a core module
directly; doing so couples it to internals that change between phases.

## Tuning

Every constant is in `core/config.lua`. `DEBUG` and `DEBUG_DAILY_SUMMARY` are
on by default during development — turn both off before shipping.
