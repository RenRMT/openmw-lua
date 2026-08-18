# TravelNetwork — implementation plan

*Name is a placeholder.* A travel mod that treats Morrowind's transport as one
directed graph instead of a set of unrelated dialogue menus: plan a multi-leg
route from anywhere, see where you can transfer between silt strider, boat and
guild guide, and book the whole journey in one go.

**Finish line.** Press a key anywhere and get the route from your current
position to any named stop — legs, transfers, distance, estimated arrival time.
Stand next to an operator, press book, and be taken the whole way, with time
advanced and fare deducted per leg. Nothing else. When that works, the mod is
done.

**Explicit anti-goal.** No framework/content split, no pack API, no extension
points. The mode table is a Lua file in this mod that names silt striders. If
this mod ever grows a `core/` that knows nothing about Morrowind, it has caught
what BalanceOfPower has.

---

## 1. Can the networks actually be combined?

Yes, and it is the whole reason the mod is worth building. The engine does not
model "networks" at all — there is no transport-mode concept anywhere in the
data. What it has is:

- `NpcRecord.servicesOffered` — a map including a `Travel` boolean
  (`types.lua:1188`). `CreatureRecord` carries the same field (`types.lua:887`).
- `NpcRecord.travelDestinations` — a list of `TravelDestination`, each with
  `cellId`, `position` and `rotation` (`types.lua:1196-1199`).
- `world.getCellById(cellId)` to resolve the destination cell.

So every stop in the game is discoverable as a destination of *some* operator,
with an exact position. The union of all destination lists is the node set, and
it does not care which vehicle serves it. Silt strider and boat stops land in
the same table because nothing in the data distinguishes them.

**Mode is inferred, not read.** Nothing on the record says "boat". The usable
signal is `NpcRecord.class` (`types.lua:1179`). The ESM dump (§2a) settles what
those classes actually are: `Caravaner`, `Shipmaster`, `Guild Guide` and
`Gondolier` cover 34 of the 38 operators in the game. That mapping is content
knowledge, so it lives in one table in this mod:

```lua
-- data/modes.lua
return {
    classes = {
        ['caravaner']   = { id = 'strider',   label = 'Silt strider' },
        ['shipmaster']  = { id = 'boat',      label = 'Boat' },
        ['guild guide'] = { id = 'guide',     label = 'Guild guide' },
        ['gondolier']   = { id = 'gondola',   label = 'Gondola' },
    },
    -- Four operators have a class that says nothing about what they drive.
    -- Three are boats: the Holamayan pair and Molag Mar's captain.
    overrides = {
        ['blatta hateria'] = 'boat',
        ['vevrana aryon']  = 'boat',
        ['rindral dralor'] = 'boat',
    },
    -- Bethesda's test NPC, in a debug cell reachable from nowhere.
    exclude = { ['todd'] = true },
}
```

Any class not in the table gets mode `unknown` and still forms edges — an
unrecognised operator degrades the labelling, never the routing. That matters
for mods: a Tamriel Rebuilt caravaner is handled by class, an invented class is
handled as `unknown`.

**Transfers fall out for free.** Once each edge carries a mode, a transfer stop
is just a node whose incident edges use more than one mode. "List possible
transfers for each destination" is a one-line query over the node's edge set;
it needs no extra data and no authoring. The interesting output — which towns
are genuine interchanges and which are dead ends on a single line — is a
property of the shipped data that nobody has looked at, because nothing has ever
assembled the two networks into one structure.

**The graph is directed.** Vanilla routes are not reliably reciprocal; some
stops are reachable from a place that cannot be reached from it. Model edges as
one-way from the start and let the data show you where the asymmetries are.

### The one thing that had to be verified first — it holds

Destinations give you the *far* end of every edge. The *near* end is wherever
the operator happens to stand, and records do not carry position — instance
placement lives in the cell. So the graph builder needs to walk cells and find
the operators:

```lua
for _, cell in ipairs(world.cells) do
    for _, npc in ipairs(cell:getAll(types.NPC)) do ... end
end
```

`Cell:getAll(type)` is documented as global-scripts-only (`core.lua:338-346`)
and says nothing about the cell needing to be active. That silence was the
project risk. **It is not a problem: `getAll` returns objects from cells the
player has never loaded, with readable positions** (§2b). The mod reads only
what the game shipped, and the offline placement data stays what it was meant
to be — a test fixture.

---

## 2. Verified API surface

| Fact | Source |
|---|---|
| `servicesOffered.Travel`, `travelDestinations` on NPC and Creature records | `types.lua:887-888, 1188-1189` |
| `TravelDestination` = `cellId`, `position`, `rotation` | `types.lua:1196-1199` |
| `NpcRecord.class` is the only operator-type signal | `types.lua:1179` |
| `world.getCellById`, `world.getCellByName`, `world.cells` | `world.lua:73, 87`; repo notes §3 |
| `Cell:getAll(type)`, global scripts only | `core.lua:338-346` |
| `world.advanceTime(hours)` — advances time, weather and AI, **not** regeneration | `world.lua:228` |
| `nearby.actors` for finding the operator you're standing next to | `nearby.lua:15` |
| `storage.playerSection` for settings that outlive the save | `storage.lua:39` |

**Not exposed, and shaping the design:** vanilla's fare calculation. The engine
computes travel price internally and offers nothing to read or override it. The
mod therefore cannot quote a vanilla price honestly, which is why booking is
implemented as a separate transaction with its own fare formula rather than as a
tweak to the dialogue menu (§4, phase 3).

---

## 2a. What the ESM says (dumped 2026-08-18)

`sources/build_travel_fixture.py` dumps NPC/CREA records and cell references
with `esmtool` and writes `tests/fixtures/vanilla_travel.lua`. It answers the
questions that did not need the game running.

**The whole network is 38 operators and 117 destinations** — 34 in
Morrowind.esm, 4 in Bloodmoon.esm, and **none in Tribunal.esm**. Mournhold is
off the network entirely; it is reached by a scripted dialogue teleport, which no
amount of graph building will find. Say so in the planner rather than letting a
player conclude the mod missed it.

**Discovery must key off `travelDestinations`, not `servicesOffered.Travel`.**
The ESM's AI services bitmask has no travel bit — 35 of the 38 operators leave
the mask empty, and the three that set bits are selling potions or training.
Whatever `servicesOffered.Travel` is derived from at runtime, it is not a stored
flag, and a non-empty destination list is the signal that cannot be wrong.

**Creature travel is vestigial.** Zero CREA records in any of the three files
carry a destination. Supporting them costs one extra loop, so keep it, but no
test can be written against shipped data.

**Guild guides have their own class,** `Guild Guide`, and so do Vivec's
gondoliers — a fourth mode the plan had not accounted for. Their destinations are
the only ones that are reliably interior.

**96 of 117 destinations are exterior, and the ESM names none of them.** An
interior destination carries its cell name; an exterior one carries a position
and nothing else. Naming those nodes means resolving position → exterior cell,
so the fixture ships an `exteriorNames` index of the 126 named exterior cells
(`'-3,6' = 'Ald-ruhn'`). Vivec's districts are named exterior cells, which is
also why one town legitimately holds several nodes.

**One operator is placed nowhere.** `wind_in_his_hair` is a Shipmaster no cell
references — cut content. The builder must skip an operator it cannot locate
rather than assume every record has a position.

**One operator is a test dummy.** `todd`, in the `ToddTest` debug cell, travels
to `ToddTest`. Excluded by id in `data/modes.lua`.

---

## 2b. What the runtime says (probed 2026-08-18)

A throwaway probe mod answered phase 0 on OpenMW 0.51 and was deleted once its
answers were recorded — the answers are the artefact, not the code. The engine
facts are in [openmw-lua-notes.md](../openmw-lua-notes.md) §3, §4 and §8. What
they mean here:

**The sweep works and matches the ESM exactly** — 37 operators, 116
destinations, 0 creature operators, no `getAll` failure in 2887 cells, every
position readable. Phase 1 can be written against the fixture with confidence
that the runtime will agree, because it just did.

**A full sweep costs ~600 ms.** Acceptable once at startup, not acceptable in a
frame. Build the graph on first need or spread across frames, and never rebuild
it on cell change.

**Everything is lowercased at runtime except names.** Record ids, cell ids and
`class` all come back lowercase (`caravaner`, `ald-ruhn, guild of mages`), while
`Cell.name` keeps its authored capitalisation. So: **ids are keys, names are
labels**, and the mode table keys on the lowercase class, as written in §1.

**Exterior destinations resolve to real cells, which removes a chunk of §3.**
An exterior destination's `cellId` is `Esm3ExteriorCell:<gridX>:<gridY>`, and
`world.getCellById` turns it into a cell whose `name` is the town — "Balmora",
"Khuul", "Gnisis". Nothing has to bucket positions into a grid, and node names
come from the engine instead of from a shipped table. The fixture's
`exteriorNames` index is now only for tests that work offline.

**`servicesOffered.Travel` is true after all**, derived by the engine from the
destination list rather than read from the (empty) ESM mask. Keying off
`travelDestinations` remains correct and is what §4 phase 1 does — but the flag
is not a trap, so either is defensible.

---

## 3. Data model

```
Node   = { key, cellId, position, name, isExterior }
Edge   = { from = nodeKey, to = nodeKey, mode, operator = recordId, distance }
Graph  = { nodes = {[key] = Node}, edges = {[fromKey] = {Edge, ...}} }
Route  = { legs = {Edge, ...}, transfers = n, distance, fare, hours }
```

**Keying by `cellId` plus a bucketed position does not work, and the shipped
data says so.** Measured over the fixture:

- Same-town stops sit **up to 10896 units apart** (Molag Mar's strider platform
  and its dock; Khuul 7492; Vivec Foreign Quarter 7282 — each pair straddling a
  grid boundary).
- Different-town stops come **as close as 4192 units** (Vivec ↔ Vivec, Foreign
  Quarter).

The ranges overlap, so no radius separates them: one wide enough to join Molag
Mar fuses Vivec's cantons. Worse, **interior positions are cell-local** — the
Caldera and Sadrith Mora mages' guilds are 564 units apart in raw coordinates
and in different worldspaces entirely. A blind radius merge would join them.

The rule that does work, in order:

1. **Interior destination** — key on `cellId` alone. Never compare a position
   across cells; the numbers are not in the same space.
2. **Exterior cell with a name** — key on the name. This is what unifies the
   grid-straddling towns, because both of Molag Mar's grid squares are called
   "Molag Mar", while "Vivec" and "Vivec, Foreign Quarter" stay the separate
   places they are.
3. **Exterior cell with no name** — merge into the nearest existing node within
   `NODE_MERGE_RADIUS`, else stand alone. **Run this as a second pass**, after
   every named node exists: done inline, Daynas Darys is processed before Tel
   Aruhn's node is created and becomes a spurious 32nd node. Order-dependent
   merging is the kind of bug the count target in phase 1 is there to catch.

Only rule 3 needs the radius, and only three points in the whole game reach it:
Daynas Darys stands 396 units outside Tel Aruhn's named cell, and the Holamayan
boat lands in an unnamed cell where the two ends of the run are 183 units apart
— a node the game never named, which the mod must therefore name itself
(`Cell.region` plus the grid is the obvious fallback).

That fixes the radius between **396 and 4192**; take the middle, not the edges.

Node `name` comes from `world.getCellById(id).name`, not from anything shipped
(§2b) — but note it is **not unique** (Sadrith Mora spans two named grid cells,
which rule 2 merges by design), so it labels a node and never keys one.

The graph is **derived, never saved.** It is rebuilt from records on every load,
like BalanceOfPower's frontier generation. Nothing about it needs to survive a
save, which keeps this mod free of the whole `fillDefaults` problem.

---

## 4. Phases

**Phase 0 — probe `cell:getAll`. Done, 2026-08-18.** All three questions
passed: `getAll` sees unvisited cells, `servicesOffered.Travel` is derived and
true, and exterior destinations carry a resolvable `cellId`. Findings in §2b,
engine facts in the repo notes §3, §4 and §8. The mod is buildable as designed,
and the probe mod has been deleted — if a question ever needs re-running, the
three above say what to ask.

**Phase 1 — build and dump the graph.** Walk records for a non-empty
`travelDestinations` (not the services flag — §2a), walk cells for the
operators, merge into nodes by the three rules in §3, emit edges. Expose
`dumpGraph()` through the mod's interface for console inspection. Deliverable:
a log dump listing every stop and its incident modes.

Targets to hit, all measured rather than guessed: **37 operators, 116
destinations, 4 modes, and 31 nodes** once merging is applied (32 labels less
`ToddTest`). Anything else means the merge rules are wrong or the walk missed
something. Build once and cache — a full sweep is ~600 ms (§2b).

**Phase 2 — routing.** Dijkstra over the directed graph with a configurable cost
mixing distance and a per-transfer penalty, plus a mode-change penalty so a
route does not bounce between boat and strider to save 30 units. Pure Lua over
the graph table, so the entire phase is unit-testable against a fixture. Ship
`route(fromKey, toKey)` and `transfersAt(nodeKey)` on the interface.

**Phase 3 — the planner UI.** Player script, keybind from settings, an MWUI
window listing reachable stops from the nearest node, sorted by cost, each
expanding to its legs and transfers. Read-only; the player still books legs
through vanilla dialogue. **This is the point at which the mod is already worth
using** — if energy runs out here, it ships.

**Phase 4 — booking.** With an operator within `BOOKING_RADIUS` (found via
`nearby.actors` filtered on `servicesOffered.Travel`), offer "travel the whole
way": deduct the summed fare, then per leg `teleport` to the destination and
`world.advanceTime(legHours)`. Note that `advanceTime` explicitly does not run
regeneration, so a long journey will not heal the player the way sleeping does —
decide deliberately whether to compensate, and write down which way you went.

**Phase 5 (optional) — fares that mean something.** Distance-scaled base fare,
modified by region and by mode. Only ever applied to mod-booked journeys; single
legs bought through vanilla dialogue keep vanilla's price, and the planner
labels mod fares as such rather than pretending to quote the engine.

---

## 5. Config constants

`NODE_MERGE_RADIUS`, `TRANSFER_PENALTY`, `MODE_CHANGE_PENALTY`,
`BOOKING_RADIUS`, `FARE_PER_UNIT`, `FARE_MODE_MULTIPLIER`, `HOURS_PER_UNIT`,
`PLANNER_KEY`, `MAX_ROUTE_LEGS`.

`NODE_MERGE_RADIUS` is the one with a measured answer rather than a taste-based
one: **above 396 and below 4192** (§3), so 1500 — verified to give the 31-node
graph the phase 1 target names.

---

## 6. Tests

The graph builder and the router take plain tables and require no `openmw.*`
package at all — keep it that way, because it is what lets both run under lupa
with nothing stubbed. Record walking and cell walking belong in a thin adapter
that hands the builder those tables.

The fixture exists: `tests/fixtures/vanilla_travel.lua`, regenerated by
`sources/build_travel_fixture.py`, holding every operator with its class,
placement and destinations, plus the named-exterior index. It is checked in, so
CI never needs Morrowind installed.

**The fixture keeps the ESM's capitalisation and the runtime does not** (§2b).
`Nevosi Hlan` and `Caravaner` in the file are `nevosi hlan` and `caravaner` in
the game. That is deliberate — a pre-lowercased fixture would hide exactly the
normalisation bugs worth testing — but it means the adapter lowercases on the
way in, and a test comparing a fixture id to a produced key must say which side
it is on.

Still to set up, and not free: the runner. `BalanceOfPower/tests/run.py` is
hardcoded to that project's directories, and CI's test job runs only that file.
This mod needs either its own copy under `tests/` or a runner that takes a
project root — plus a CI step either way.

Cases worth having on day one: a node served by two modes is reported as a
transfer; a one-way edge does not produce a return route; two operators serving
the same town within the merge radius collapse to one node; a stop reachable
only via three legs is found; an unreachable stop returns nil rather than an
empty route; an operator with no placement (`wind_in_his_hair`) is skipped
without erroring.

---

## 7. Open questions

- ~~Does `cell:getAll` see inactive cells?~~ **Yes**, with readable positions,
  and a full sweep costs ~600 ms (§2b). The project risk is closed.
- ~~What does `servicesOffered.Travel` report on an empty services mask?~~
  **`true`** — the engine derives it (§2b).
- ~~What is `cellId` on an exterior destination?~~ **`Esm3ExteriorCell:x:y`**,
  which `getCellById` resolves to a named cell (§2b).
- ~~Do any *creature* records offer Travel?~~ **No** — zero in all three content
  files (§2a). Keep the loop, expect nothing.
- ~~Are guild guides distinguishable by class?~~ **Yes** — class `Guild Guide`,
  and gondoliers likewise (§2a).
- How should a node the game never named be labelled? The Holamayan landing is
  the only one in vanilla, and `Cell.region` plus a grid reference is the
  obvious answer — but it is a player-facing string, so it is a decision, not a
  detail. (Phase 1.)
- Does `teleport` into a far interior behave, given the `onGround` finding in
  BalanceOfPower's phase 4b notes? Travel destinations carry an authored
  position, so this *should* be the safe case — but it is the same code path
  that already surprised this repo once.
