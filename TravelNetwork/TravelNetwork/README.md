# TravelNetwork

Morrowind's silt striders, boats, gondolas and guild guides are four unrelated
dialogue menus. They are also, in the data, one directed graph that nothing has
ever assembled. This mod assembles it.

**Phase 1 — the graph, and a way to look at it.** No UI, no routing, no
booking. See [../implementation-plan.md](../implementation-plan.md) for the
build order and the decisions behind it.

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
```

Output goes to `openmw.log`, tagged `[TravelNetwork]`.

On unmodded Morrowind + Tribunal + Bloodmoon the dump reports **33 stops and
125 legs** (ten of them on foot) from **36 operators**, and — the number worth
the whole exercise — **three interchanges**: Khuul and Molag Mar, where boat
meets silt strider, and Vivec's Foreign Quarter, where boat meets gondola.
Nowhere else in the game can you change vehicle without walking.

## API

`require('openmw.interfaces').TravelNetwork`, global context:

| Function | Returns |
|---|---|
| `graph()` | The whole graph, built and cached on first call |
| `rebuild()` | Discards the cache and rebuilds |
| `interchanges()` | `{ { key, name, modes }, ... }` for stops serving more than one mode |
| `modesAt(g, key)` / `modesWithinWalk(g, key)` | Vehicles meeting at a stop; and those one walk leg away |
| `edgesFrom(g, key)` / `isTransfer(g, key)` | Legs leaving a stop; whether vehicles meet there |
| `dump(opts)` / `dumpInterchanges()` | Log output; `opts.legs` lists legs |

The graph:

```lua
Node  = { key, name, cellId, isExterior, position, modes = { [mode] = true } }
Edge  = { from, to, mode, operator, operatorName, distance }
Graph = { nodes = { [key] = Node }, order = { key, ... }, edges = { [from] = { Edge, ... } }, stats }
```

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

## Files

| File | What it is |
|---|---|
| `scripts/TravelNetwork/graph.lua` | Building, merging and querying. Pure — no `openmw.*` at all, which is what makes it testable |
| `scripts/TravelNetwork/walk.lua` | Follows doors out of a building, so a stop indoors knows which street it belongs to. Pure as well |
| `scripts/TravelNetwork/adapter.lua` | The engine half: walks cells, records and doors, hands the rest plain tables |
| `scripts/TravelNetwork/main.lua` | Global script, cache, interface, dumps |
| `scripts/TravelNetwork/config.lua` | Every tunable |
| `scripts/TravelNetwork/data/modes.lua` | Which class drives what, plus the four vanilla operators whose class does not say |

## Walking between stops

Guild guides run between interiors, so without help the guide network would be
an island: no leg would connect a hall to the town around it. Doors supply the
missing legs. Each stop indoors is followed out through teleport doors — up to
`MAX_DOOR_HOPS` of them, because Vivec's hall opens onto a canton plaza and
Sadrith Mora's onto the inside of Wolverine Hall — and joined to whatever stop
is at the far end by a `walk` leg in both directions.

A walk leg carries a distance and nothing else: no fare, since nobody charges
for a door, and no time, since the player walks it themselves. It measures both
halves — across the room to the door, then from the doorstep to the stop out on
the street.

Two consequences worth knowing:

- **Walk legs never make a stop an interchange.** `modesAt` stays the vehicles
  that meet in one place, so the count of real interchanges cannot inflate;
  `modesWithinWalk` is the wider view. Balmora's strider and its guild guide are
  one door apart, which is a change you can make — and a different fact from
  Khuul, where two vehicles meet on the spot.
- **Sadrith Mora's guide is not joined to its boats.** The guide lets out at
  Wolverine Hall, 11593 units away in a differently named cell, and no door
  connects two exteriors. The graph says they are separate stops, because they
  are. This is the one place in the game where doors-only is visibly lossy.
