# TravelNetwork — implementation plan

*Name is a placeholder.* A travel mod that treats Morrowind's transport as one
directed graph instead of a set of unrelated dialogue menus: plan a multi-leg
route from anywhere, see where you can transfer between silt strider, boat and
guild guide, and book the whole journey in one go.

**Finish line.** Talk to a silt strider driver, shipmaster, gondolier or guild
guide, press the planner key, and get the route from their stop to any named
stop — legs, transfers, distance, estimated arrival time. Press book and be
taken the whole way, with the fare deducted and the clock advanced by the length
of the journey. Nothing else. When that works, the mod is done.

*Revised 2026-08-19.* This began as "press a key anywhere and plan from where
you are standing". Reading a route out of thin air in the middle of a street is
a menu, not a journey; asking the person who drives the thing is the same
information with a reason to be there. It also makes the origin exact rather
than the nearest guess.

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
tweak to the dialogue menu (§4, phase 3). The *scale* underneath that
calculation is readable, though — `core.getGMST('fTravelMult')` — and phase 4c
puts the mod on it.

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

## 2c. Doors, and what they join (2026-08-18)

Travel records describe vehicles and nothing else, so the guide network came out
of phase 1 as an island: five guild halls connected to each other and to nothing
else, because in the world you walk through a door and no travel record says so.

**Teleport doors say so.** `types.Door.destCell` and `destPosition` name where a
door opens onto, and `getAll(types.Door)` reads them from cells the player has
never loaded. Every vanilla guild hall reaches the street in at most two doors:

| Hall | Doors | Opens onto | Already a stop? |
|---|---|---|---|
| Balmora, Guild of Mages | 1 | Balmora | yes |
| Ald-ruhn, Guild of Mages | 1 | Ald-ruhn | yes |
| Caldera, Guild of Mages | 1 | Caldera | **no** — Caldera has no vehicle at all |
| Vivec, Guild of Mages | 2, via the Foreign Quarter Plaza | Vivec, Foreign Quarter | yes |
| Sadrith Mora, Wolverine Hall: Mage's Guild | 2, via Wolverine Hall | Wolverine Hall | **no** |

Three of the five need no new rule beyond the door: the doorstep lands in the
same named exterior cell as the existing stop, 3.2k–4k units away, and name
keying already merges them. The other two add a stop.

**The decision, 2026-08-18: doors only.** No authored pairs, no proximity links.
A walk leg costs its distance for routing and carries no fare. It is not a
conceptual seam the player is left to cross on foot: booking teleports it like
any other leg, and charges the time (phase 4).

**What that costs, honestly:** Sadrith Mora's guide lets you out at Wolverine
Hall, 11593 units from the boats, in a differently named cell. No door connects
two exteriors, so the graph keeps them apart and the planner will send you to
Sadrith Mora by boat when guide-plus-a-short-walk would have been faster. That
is a real quality gap, and it is one stop in the whole game. Revisit it when the
planner exists and it can be judged as a player rather than as a table.

**Walking counts as changing, decided 2026-08-18 after seeing the graph in
game.** `isTransfer` asks what is reachable on foot, so Ald-ruhn and Balmora
join the list: their guild halls are one door from the silt strider, and a
player makes that change without thinking about it. `modesAt` stays the narrower
fact — what meets on this exact spot — so Khuul and Balmora remain
distinguishable, and `interchanges()` marks which is which with `onFoot`.

**A junction is a place, not a stop.** Both ends of a walk link qualify, so
counting stops would report Balmora twice and make Vivec's guild hall a separate
junction from the canton it opens onto. `interchanges()` folds each
walk-connected group into one entry, named after whichever of its stops the most
vehicles reach: five places, eight stops.

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

**Phase 1 — build and dump the graph. Done, 2026-08-18.** The mod is
`TravelNetwork/TravelNetwork/`: `graph.lua` builds and queries, `adapter.lua`
walks cells and records, `main.lua` caches and exposes the interface. Its README
carries the API and the console commands.

Every target was hit against the fixture: **36 operators used** (37 placed less
the excluded test dummy), **115 legs**, **31 stops**, 4 modes, 1 unplaced record
skipped. Built once and cached; the sweep behind it is ~600 ms (§2b).

Walk links followed the same day (§2c), joining the guide network to the rest
through the doors of the buildings it runs between: **33 stops, 125 legs**, ten
of them on foot.

**The result worth the exercise: the whole game has five interchanges.** Khuul,
Molag Mar and Vivec's Foreign Quarter, where two vehicles meet on the spot; plus
Ald-ruhn and Balmora, where the guild hall is a short walk from the silt strider
(§2c). Five places in a province, for four modes of transport — a far smaller
number than the network suggests, and nobody could have known it without
assembling the graph.

Still no UI, no routing, no gameplay.

**Phase 2 — routing. Done, 2026-08-19.** `route.lua`, pure like the rest.
Dijkstra over **(stop, mode) pairs** rather than stops alone, because what a leg
costs depends on how you arrived — staying on one silt strider is free where
changing to a boat is not, and a search that only remembered its position could
not tell those apart. 33 stops and five modes make that cheap.

Cost is distance plus `TRANSFER_PENALTY` per change and `MODE_CHANGE_PENALTY`
when the kind of vehicle changes, all in game units, so a penalty reads as
"worth this much of a detour". `MAX_ROUTE_LEGS` bounds the search.

On the interface: `route(from, to)`, `destinations(from)` (everywhere reachable,
cheapest first — what phase 3's list needs), `transfersAt(key)`, plus
`dumpRoute` and `dumpDestinations` for the console.

**Routing found a bug in phase 1's distances.** A leg between two interiors was
measured across two cell-local coordinate systems: Balmora to Ald-ruhn by guild
guide read as 3406 units, because that is how far apart the two halls sit inside
their own cells. Guides looked nearly free and the router sent everyone through
them. Stops now carry an `anchor` — for a stop indoors, the position of the
street its walk link opens onto — and `graph.remeasure` re-measures every
vehicle leg against those. The guide leg between Balmora and Ald-ruhn now reads
73046 units, to the unit the same as the silt strider leg between the same two
towns. Walk legs keep their measured distance; they were never taken across a
seam.

**Phase 3 — the planner UI. Done, 2026-08-19.** `player.lua` holds the keybind,
the settings page and the window; `plan.lua` holds everything it decides and is
pure, which keeps the untestable part down to drawing.

- **The planner belongs to a conversation.** Talking to an operator fetches the
  plan and offers it; the key opens it; leaving dialogue withdraws it. Pressed
  anywhere else the key explains itself rather than doing nothing, since a
  silent keybind reads as a broken one.
- **Lua cannot add a dialogue topic** — topics are DIAL records and live in
  content files, which a script-only mod has none of. What it can do is notice
  the conversation: `UiModeChanged` reports `newMode = 'Dialogue'` with `arg`
  set to the actor, and `graph.stopOf` turns that actor into their stop.
- **The origin is the operator's own stop**, not the nearest thing to where the
  player happens to be standing. Exact, and it needs no measuring.
- **The keybind is a registered trigger** bound through the `inputBinding`
  settings renderer. Nothing is bound by default: any key this mod chose would
  be one some other mod had already taken.
- **`plan.build` is the whole of what crosses between contexts.** The graph
  lives in the global script because only global scripts walk cells; the window
  lives in the player script because only local scripts draw. What travels
  between them is names and numbers, nothing needing the engine to read.
- No UI mode juggling: the window only ever opens inside dialogue, which already
  has a cursor. Dropping modes to close it would end the conversation it was
  opened from.

`locate.lua` was written for this phase and deleted at the end of it. It found
the stop nearest the player, which the dialogue-gated design no longer asks
about; `graph.stopOf` replaced it with an exact answer.

**This is the point the plan called worth using**, and it is: ask a caravaner
where you can get to, and the answer includes the boat you would change onto.
Booking is still vanilla dialogue, leg by leg.

**Phase 4 — booking. Done, 2026-08-19.** Clicking the fare under an expanded
stop buys the journey. `book.lua` decides it and is pure; `money.lua` and two
new calls in `adapter.lua` are the whole of what touches the engine.

- **The window can only ask "take me to this stop".** Where the journey starts,
  what it costs and where it ends are worked out again in the global script,
  from the operator being talked to, against the live graph — the same
  derivation `onRequestPlan` does. A fare is not a number to accept from
  elsewhere, and the list the player clicked may have been drawn before
  something changed.
- **Move first, charge second.** The teleport is the only step that can fail on
  something the script cannot see beforehand, so nobody pays for a journey that
  did not happen. No refund path exists because none is reachable.
- **One teleport, not one per leg**, which is where this departs from what the
  phase was written as. Intermediate stops are narrative: teleporting through
  them would put the player through a cell load per leg with nothing to see,
  and would rest on same-frame repeated-teleport behaviour nothing here has
  established. The clock still advances by the whole journey, legs and walks
  together, so the cost of changing is paid in the only currency that shows.
- **The conversation is ended before the request goes out.** The player is
  about to be a province away, and a dialogue window left open on the operator
  would follow them there. `I.UI.setMode()` with no argument drops it.
- **The player script checks the purse before closing the conversation.** A
  courtesy, not the decision: the global script quotes again and refuses again.
  It exists so an unaffordable journey does not end the conversation to say no.
- `BOOKING_RADIUS` is deleted. The operator is whoever is being talked to, so
  nothing searches for one and the constant had no claimant.

**Walk legs are teleported too** (decided 2026-08-18). The player books at
Balmora's silt strider and arrives in Caldera; the mod walks them through the
guild hall door rather than stopping the journey there and asking them to finish
it on foot. Two consequences, both held to:

- **A walk leg costs time but never money.** It advances the clock by
  `HOURS_PER_UNIT` like any other leg, because the mod is moving the player and
  a free teleport across town is not what "walk" should mean. It contributes
  nothing to the fare — nobody charges for a door, and a journey made only of
  walk legs is offered as *no charge* rather than as 0 gold.
- **A journey may begin with a walk.** Standing at the strider and asking for
  Caldera, the first leg is the walk to the guild hall. The operator you are
  standing next to sells the whole journey, including the legs their own
  vehicle does not cover.

**Regeneration: fatigue is restored, settled in game 2026-08-19.** The first
pass compensated for nothing, on the grounds that reproducing the engine's rest
arithmetic would be inventing a mechanic. Playing it answered the question the
other way: **vanilla travel leaves the player rested**, so restoring nothing
made a mod-booked journey strictly worse than the same legs bought one at a
time from the same people. Arrival now fills fatigue to `base + modifier`.
Health and magicka are left alone — nothing was observed restoring them, and
that side of the original reasoning still holds.

### Phase 4a — what playing it changed, 2026-08-19

The first in-game session of a complete mod, and every change came from using
it rather than from reading it.

- **The key says nothing outside a travel conversation.** It used to explain
  itself, on the reasoning that a silent keybind reads as a broken one. In play
  that reasoning is wrong: the key is bound to something a player also presses
  by accident, and a message every time it is brushed is worse than a key that
  is simply inert where it does not belong.
- **"…and 18 more" is now the control it looked like.** It said what it was
  hiding and did nothing about it. Clicking it shows the rest; a *Show fewer*
  row folds the list back.
- **Legs and vehicles are counted separately.** The summary called a two-leg
  silt strider journey "1 change" and a strider-then-boat journey "1 change",
  which are not the same thing to travel. `route.summarise` now counts
  `vehicleLegs` and `modeChanges` over vehicle legs only — a door between two
  rides is not a change — and the four readings a journey can have (*direct*,
  *on foot*, *all by one vehicle*, *changing vehicle*) are l10n keys chosen in
  `plan.summarise`. That moved the last English strings out of the pure modules
  and into the locale file, which they should have been in already.
- **Both routing penalties are settings now**, under Options → Scripts →
  Travel Network → Routing. They are what the planner will go out of its way to
  avoid, in units of detour — not a charge. (The surcharge that *is* a charge
  came next; see phase 4b.) **All settings live player-side** and travel to the
  global script on the event that asks for a plan or a journey, because whether
  a page registered by a player script can host a group registered by a global
  one is not established (repo notes §12). Read when a conversation opens, so a
  change applies at the next operator talked to.
- **Arriving a short drop above the ground** is left alone. It happens at some
  vanilla destinations and never far enough to hurt. `onGround = true` is
  available here — the cell is active by then, unlike the inactive-cell case in
  BalanceOfPower's notes — but it would let the engine second-guess an authored
  arrival point, including in interiors where the ground beneath one is not
  always the floor meant. Not worth the trade for a fall nobody takes damage
  from.

### Phase 4b — the price of convenience, 2026-08-19

Booking a whole journey at one counter is worth something, and it should cost
something. The fare is no longer the sum of the legs:

```
fare = base * (1 + 0.10 * (vehicleLegs - 1) + 0.20 * modeChanges)
```

**Additive, not compounded** — three legs with one change of vehicle is
10 + 10 + 20 per cent over the legs, not a product of three multipliers. Both
rates are settings, expressed to the player as whole per cents.

Four things the formula is arranged to get right:

- **A single leg is never surcharged.** Buying one ride through the planner
  costs exactly what buying it from the same operator costs, which keeps the
  mod from being a tax on using it.
- **Walk legs count for nothing.** They are not vehicles and nobody sells them,
  so a ride with a door at each end is one ride at one ride's price. Balmora to
  Caldera, which is walk-guide-walk, carries no surcharge at all.
- **Legs and changes are counted separately**, so two silt strider legs cost 10
  per cent while a strider-then-boat journey costs 30 — the leg *and* the
  change, because the change is the part two operators with separate books have
  to be talked into.
- **The window itemises it.** An expanded stop shows "100 gold in fares, plus
  60% (60 gold) for booking it in one go" above the button. A price the player
  cannot account for reads as invented.

### Phase 4c — the fare is the game's own, 2026-08-19

`FARE_PER_UNIT` began as 0.004, which priced Balmora to Seyda Neen at 214 gold
where the silt strider asks about thirteen. The engine does not expose its fare
*calculation* (§2) — but it does expose the number underneath it. Travel prices
are distance over the game setting `fTravelMult`, and `core.getGMST` reads game
settings from any context, so `adapter.travelRate()` returns `1 / fTravelMult`
and the mod charges on whatever scale the loaded content charges on. A total
conversion that reprices travel reprices this with it.

`config.FARE_PER_UNIT` stays as the fallback, now 0.00025 — the same thing
vanilla's 4000 works out to — for the case where the setting cannot be read.
`route.lua` takes the rate as an option rather than reaching for the constant,
which keeps it pure and makes the two scales testable.

The surcharges were raised with the rebase: **10 per cent a leg, 20 per cent a
change**. Against vanilla that puts a single ride at 10 to 44 gold, the
same-strider chains at 33 to 48, and the far Telvanni coast — four or five legs
with a change — at 117 to 176. A day's honest work for a crossing of the
province, and the direct legs unchanged from what the operator would charge.

**Phase 5 (optional) — fares that mean something.** What is left is variation
rather than scale: a fare modified by region and by mode, now that the base is
the game's own number. Vanilla also haggles travel prices against mercantile
and disposition, which the mod does not — a booked fare is the price before
anyone argues about it. Only ever applied to mod-booked journeys; single
legs bought through vanilla dialogue keep vanilla's price, and the planner
labels mod fares as such rather than pretending to quote the engine.

---

## 5. Config constants

`NODE_MERGE_RADIUS`, `MAX_DOOR_HOPS`, `TRANSFER_PENALTY`,
`MODE_CHANGE_PENALTY`, `FARE_PER_UNIT`, `HOURS_PER_UNIT`, `MAX_ROUTE_LEGS`.

`BOOKING_RADIUS` and `PLANNER_KEY` were both planned and neither is needed: the
key is a binding the player sets on the settings page, and the operator selling
a journey is whoever is being talked to. `FARE_MODE_MULTIPLIER` waits for
phase 5.

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

The runner is set up: `tests/run.py`, a near-copy of BalanceOfPower's, with its
own CI step. Nothing is stubbed, because nothing under test requires an
`openmw.*` package. `support/fixture.lua` converts the dump into operator tables
and is the deliberate twin of `adapter.lua` — same output shape, different
source, so the two drifting apart shows up as a different graph.

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
- ~~How do you get from a town to the guild hall standing in it?~~ **Doors**,
  and they answer it completely (§2c). Decided 2026-08-18: door-derived links
  only, no authored pairs and no proximity links, and a walk leg costs its
  distance with no fare and no time -- the player really does walk it.
- ~~How should a stop the game never named be labelled?~~ Region plus grid
  reference — "Azura's Coast (19, -5)" — with "Wilderness" when even the region
  is missing. Vanilla needs it exactly once, for the Holamayan landing.
- ~~Does `teleport` into a far interior behave, given the `onGround` finding in
  BalanceOfPower's phase 4b notes?~~ **Yes** *(played 2026-08-19)*. Authored
  travel positions land where they should; the only blemish is arriving a short
  drop above the ground at some of them, never far enough to take damage, and
  phase 4a says why that is left alone. Booking's other unverified calls came
  through the same session: `Inventory:countOf`/`findAll` on `gold_001`,
  `GameObject:remove`, and `I.UI.setMode()` ending a conversation from a click
  handler all behaved.
- ~~Does vanilla travel restore health, magicka or fatigue?~~ **Fatigue, yes**
  *(played 2026-08-19)*. Arrival restores it; health and magicka are left alone
  (phase 4a).
- **Do the routing penalties want different defaults now they are settings?**
  4000 and 6000 were guesses made before anyone had travelled on them. The
  settings page makes them answerable by playing rather than by editing a file,
  which is the whole reason they are there.
