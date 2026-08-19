# TravelNetwork

Morrowind's silt striders, boats, gondolas and guild guides are four unrelated
dialogue menus. They are also, in the data, one directed graph that nothing has
ever assembled. This mod assembles it.

**Phases 1–4 — the graph, routing, a planner window, and booking.** Ask an
operator where you can get to, pick a stop, and be taken the whole way: fare
deducted once, clock advanced once, changes and walks included. See
[../implementation-plan.md](../implementation-plan.md) for the build order and
the decisions behind it.

## Using it

**Bind a key first** — Options → Scripts → Travel Network → *Open the planner*.
Nothing is bound by default, since any key this mod picked would be one some
other mod had already taken.

Then **talk to a silt strider driver, shipmaster, gondolier or guild guide**.
The conversation prompts you by name of key — *Press T to plan a journey from
here* — or, if you have not bound one yet, says where to. Press it and the
window lists every stop reachable from where they stand, cheapest first, with
what each journey asks of you, how long it runs and what it costs. Click a stop
to see its legs and the price of the whole journey; click again to fold it away.
The list shows the fourteen cheapest; the line at the bottom opens the rest.
Closing the window leaves you in the conversation, and leaving the conversation
closes the window.

A journey reads as one of four things, and the distinction is between legs and
vehicles rather than between stops:

| It says | It means |
|---|---|
| *direct* | One vehicle the whole way, however many doors it passes through |
| *on foot* | No vehicle at all — a walk through a door, free |
| *3 legs, all by Silt strider* | Several legs, nothing to change onto |
| *1 change of vehicle* | You leave one kind of transport for another |

**Click the price to travel.** The fare comes out of your purse once, the
conversation ends, and you arrive at the far stop with the clock moved on by the
length of the journey — every leg of it, including the changes and the walk
through a guild hall door. You buy the journey from whoever you happen to be
talking to, even the legs their own vehicle does not cover.

The key does nothing outside a travel conversation, on purpose — reading a route
out of the air in the middle of a street is a menu, not a journey. Press it
anywhere else and it is silent: it once explained itself, which turned out to
mean a message every time the key was brushed in a fight.

## Settings

Options → Scripts → Travel Network.

| Setting | What it does |
|---|---|
| *Open the planner* | The key. Nothing is bound until you bind one |
| *Detour worth avoiding a stop* | How far out of your way is worth going to save one extra leg |
| *Detour worth avoiding a change of vehicle* | The same, for changing between kinds of transport |
| *Extra per additional leg (%)* | What the ticket adds for every leg past the first |
| *Extra per change of vehicle (%)* | What it adds again when the journey changes transport |

The two **detours** are distances in game units, not gold. They decide which
route you are offered: raise them and the planner keeps you on one vehicle at
the price of going the long way round, drop them to zero and it will send you
through every interchange that saves a few paces.

The two **extras** are what the convenience costs, as percentages of the fare —
see *Booking* below. All four are read when a conversation opens, so a change
applies at the next operator you talk to.

## Setup

```
data="D:\projects\openmw-lua\TravelNetwork\TravelNetwork"
content=TravelNetwork.omwscripts
```

## Looking at the graph

From the console, `luag` on its own line, then:

```
I.TravelNetwork.dump()                 -- every stop, its modes, its out-degree
I.TravelNetwork.dump({ legs = true })  -- and every leg under its stop
I.TravelNetwork.dumpInterchanges()     -- only the stops where modes meet
I.TravelNetwork.rebuild()              -- throw the cache away and walk again

I.TravelNetwork.dumpRoute('place:balmora', 'place:caldera')
I.TravelNetwork.dumpDestinations('place:balmora')
```

A route reads like this:

```
[TravelNetwork] Balmora -> Caldera: 3 leg(s), 2 transfer(s), 44767 units, 5.4 h, 155 gold
[TravelNetwork]     walk     Balmora                  -> Balmora, Guild of Mages    5137  on foot
[TravelNetwork]     guide    Balmora, Guild of Mages  -> Caldera, Guild of Mages   38760  Masalinie Merian
[TravelNetwork]     walk     Caldera, Guild of Mages  -> Caldera                     870  on foot
```

Output goes to `openmw.log`, tagged `[TravelNetwork]`.

On unmodded Morrowind + Tribunal + Bloodmoon the dump reports **33 stops and
125 legs** (ten of them on foot) from **36 operators**, and — the number worth
the whole exercise — **five interchanges**:

| Place | Modes | |
|---|---|---|
| Khuul | boat + strider | vehicles meet on the spot |
| Molag Mar | boat + strider | vehicles meet on the spot |
| Vivec, Foreign Quarter | boat + gondola + guide | boat and gondola on the spot, the guild hall a walk away |
| Ald-ruhn | guide + strider | the change costs a walk |
| Balmora | guide + strider | the change costs a walk |

Five places in a province, for four modes of transport.

## API

`require('openmw.interfaces').TravelNetwork`, global context:

| Function | Returns |
|---|---|
| `graph()` | The whole graph, built and cached on first call |
| `rebuild()` | Discards the cache and rebuilds |
| `interchanges()` | `{ { key, name, modes }, ... }` for stops serving more than one mode |
| `modesAt(g, key)` / `modesWithinWalk(g, key)` | Vehicles meeting at a stop; and those one walk leg away |
| `edgesFrom(g, key)` / `isTransfer(g, key)` | Legs leaving a stop; whether vehicles meet there |
| `route(from, to, opts)` | The cheapest journey, or nil when there is none |
| `destinations(from, opts)` | Everywhere reachable, cheapest first |
| `transfersAt(key)` | What you can change to at a stop |
| `dump(opts)` / `dumpInterchanges()` / `dumpRoute(from, to)` / `dumpDestinations(from)` | Log output; `opts.legs` lists legs |

The graph:

```lua
Node  = { key, name, cellId, isExterior, position, anchor, modes = { [mode] = true } }
Edge  = { from, to, mode, operator, operatorName, distance }
Graph = { nodes = { [key] = Node }, order = { key, ... }, edges = { [from] = { Edge, ... } }, stats }
Route = { legs = { Edge, ... }, transfers, vehicleLegs, modeChanges, distance, walked,
          hours, baseFare, fare, surcharge, surchargePercent, modes, cost }
```

`anchor` is where a stop stands in the world when its own coordinates cannot say
— an interior's are cell-local, so it anchors to the street its walk link opens
onto. Vehicle legs are measured between anchors, which is what stops a guild
guide leg from reading as the few paces between two halls in their own cells.

Routing cost is distance plus `TRANSFER_PENALTY` per change and
`MODE_CHANGE_PENALTY` when the kind of vehicle changes — all in game units, so a
penalty reads as "worth this much of a detour". Both are settings; the values in
`config.lua` are only the defaults. `fare` counts vehicle legs only and is
provisional until fares get a formula worth quoting.

`transfers` counts legs; `vehicleLegs` and `modeChanges` count vehicles, walk
legs excluded. Two silt strider legs in a row are one transfer and no mode
change, which is the difference the planner puts in front of the player — and
what the surcharge is calculated from. `baseFare` is the legs, `fare` is what
the ticket costs, and `surcharge` / `surchargePercent` are the difference.

`order` is sorted by name, so a dump reads alphabetically. `stats` carries
`operators`, `nodes`, `edges`, `unplaced`, `excluded` and `selfEdges`.

## How a stop gets its identity

Positions alone cannot say what is one stop and what is two — same-town stops
run up to 10896 units apart while different towns come within 4192, and
interior coordinates are cell-local. So:

1. **Interior** — keyed on the cell. Two guild halls a few hundred raw units
   apart are in different worldspaces, not near each other.
2. **Named exterior cell** — keyed on the name, which is what makes Khuul's
   dock and its strider platform, in two different grid cells, one stop.
3. **Unnamed exterior cell** — merged into the nearest stop within
   `NODE_MERGE_RADIUS`, in a second pass so the result does not depend on the
   order operators were found in. Vanilla has exactly one stop that survives
   this: the Holamayan landing, which the game never named.

## Booking

One purchase, one arrival. The fare is the sum of the vehicle legs; the clock
moves by the whole journey, walks included; you are put down at the far stop's
own arrival point — the position the content file gives the operator who serves
it, so you land where a traveller is meant to.

The window never decides any of that. It can only say "take me to this stop":
where the journey starts, what it costs and where it ends are worked out again
in the global script, from the operator you are talking to, against the live
graph. A booking is quoted before it is charged, and the traveller is moved
before the gold is taken, so a journey that cannot be made is never paid for.

**You arrive rested**, because vanilla travel leaves you rested and a booked
journey should not be worse than the same legs bought one at a time.
`world.advanceTime` moves the clock, the weather and the world's AI but runs no
regeneration, so fatigue is refilled on arrival. Health and magicka are not
touched — nothing in vanilla was seen restoring them, and adding that would be
inventing a mechanic rather than matching one.

**A journey with no vehicle in it is free.** Walk legs carry no fare, so the
short hop from Balmora's street to its guild hall costs time and nothing else,
and the window says *no charge* rather than *0 gold*.

### What the ticket adds

Somebody has to arrange a connection two operators have no arrangement about, so
a journey costs more than the legs it is made of:

```
fare = legs * (1 + 10% per leg past the first + 20% per change of vehicle)
```

Added together, never compounded. Three legs with one change is 10 + 10 + 20 per
cent over the fares themselves, and the expanded stop itemises it — *100 gold in
fares, plus 60% (60 gold) for booking it in one go* — so the price is always
accountable.

The legs themselves are priced at **the game's own rate**: travel prices in
Morrowind are distance over the game setting `fTravelMult`, which the mod reads
rather than guesses, so a single leg costs what the operator would charge for it
and a total conversion that reprices travel reprices this too. Vanilla then
haggles that number against mercantile and disposition; the mod does not, so a
booked fare is the price before anyone argues about it.

**A single leg is never surcharged**: bought through the planner it costs what
it costs bought from the operator directly — 18 gold from Balmora to Ald-ruhn,
44 to Sadrith Mora. **Walks count for nothing**, being
neither a vehicle nor anybody's to sell — Balmora to Caldera is walk, guide,
walk, and pays no extra at all. Both rates are settings, and setting them to
zero turns the whole thing off.

## Files

| File | What it is |
|---|---|
| `scripts/TravelNetwork/graph.lua` | Building, merging and querying. Pure — no `openmw.*` at all, which is what makes it testable |
| `scripts/TravelNetwork/walk.lua` | Follows doors out of a building, so a stop indoors knows which street it belongs to. Pure as well |
| `scripts/TravelNetwork/route.lua` | Dijkstra over (stop, mode) pairs. Pure |
| `scripts/TravelNetwork/plan.lua` | The plan the window draws, as data. Pure |
| `scripts/TravelNetwork/book.lua` | What a journey costs and whether it can be bought. Pure |
| `scripts/TravelNetwork/adapter.lua` | The engine half: walks cells, records and doors, hands the rest plain tables; moves the traveller and the clock |
| `scripts/TravelNetwork/money.lua` | Gold. Read in both contexts, spent in the global one |
| `scripts/TravelNetwork/main.lua` | Global script, cache, interface, dumps, and the booking counter |
| `scripts/TravelNetwork/player.lua` | The keybind, the settings page and the window |
| `scripts/TravelNetwork/config.lua` | Every tunable; the two routing penalties are defaults the settings page overrides |
| `scripts/TravelNetwork/data/modes.lua` | Which class drives what, plus the four vanilla operators whose class does not say |

## Walking between stops

Guild guides run between interiors, so without help the guide network would be
an island: no leg would connect a hall to the town around it. Doors supply the
missing legs. Each stop indoors is followed out through teleport doors — up to
`MAX_DOOR_HOPS` of them, because Vivec's hall opens onto a canton plaza and
Sadrith Mora's onto the inside of Wolverine Hall — and joined to whatever stop
is at the far end by a `walk` leg in both directions.

A walk leg carries a distance and no fare — nobody charges for a door. It
measures both halves: across the room to the door, then from the doorstep to
the stop out on the street.

It is not a stretch the player is left to cover themselves. A booked journey
takes walk legs along with vehicle legs, so you buy passage at Balmora's silt
strider and arrive in Caldera. The clock advances for a walk as it does for a
ride; only the fare stays at zero.

Two consequences worth knowing:

- **Walking counts as changing.** `isTransfer` asks what you can reach on foot,
  because a player at Balmora's silt strider who wants Caldera walks to the
  guild hall without thinking about it. `modesAt` stays the narrower fact —
  what meets on this exact spot — so anything needing to tell Khuul from
  Balmora still can, and `interchanges()` reports it as `onFoot`.
- **A junction is a place, not a stop.** A guild hall and the street outside it
  are one interchange between them, named after whichever stop the most
  vehicles reach. Otherwise Balmora would be counted twice and Vivec's hall
  would look like a separate junction from the canton it opens onto.
- **Sadrith Mora's guide is not joined to its boats.** The guide lets out at
  Wolverine Hall, 11593 units away in a differently named cell, and no door
  connects two exteriors. The graph says they are separate stops, because they
  are. This is the one place in the game where doors-only is visibly lossy.
