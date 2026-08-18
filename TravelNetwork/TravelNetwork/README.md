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

On unmodded Morrowind + Tribunal + Bloodmoon the dump reports **31 stops, 115
legs, 36 operators**, and — the number worth the whole exercise — **three
interchanges**: Khuul and Molag Mar, where boat meets silt strider, and Vivec's
Foreign Quarter, where boat meets gondola. Nowhere else in the game can you
change vehicle without walking.

## API

`require('openmw.interfaces').TravelNetwork`, global context:

| Function | Returns |
|---|---|
| `graph()` | The whole graph, built and cached on first call |
| `rebuild()` | Discards the cache and rebuilds |
| `interchanges()` | `{ { key, name, modes }, ... }` for stops serving more than one mode |
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
| `scripts/TravelNetwork/adapter.lua` | The engine half: walks cells and records, hands `graph` plain tables |
| `scripts/TravelNetwork/main.lua` | Global script, cache, interface, dumps |
| `scripts/TravelNetwork/config.lua` | Every tunable |
| `scripts/TravelNetwork/data/modes.lua` | Which class drives what, plus the four vanilla operators whose class does not say |

## Known gap

**The guild guide network is a separate island.** Guides run between guild
halls, which are interiors, and no leg connects a hall to the town it stands
in — in the world you walk out of a door, and the graph has no concept of that.
Until walk links exist, no route can mix a guide with a strider. See the plan's
open questions.
