# Travel Agents — expanded travel & journey planning (OpenMW)

Turns Morrowind's travel NPCs into full-fledged travel agents, offering
multi-leg journeys and transfers between transport modes.

## Using it

Bind a key first, then talk to a silt strider driver, shipmaster, gondolier or
guild guide. The conversation prompts you by name of key (*Press T to plan a
journey from here*).

Press it and a window opens in two halves. On the left, everywhere you can get
to, cheapest first, split into the journeys that keep you on one kind of
vehicle and the ones that make you change.

## Settings

Options → Scripts → Travel Agents.

| Setting | What it does |
|---|---|
| *Open planner* | The key. Nothing is bound until you bind one |
| *Extra per leg (%)* | Convenience surcharge for every leg past the first |
| *Extra per change of vehicle (%)* | Convenience surcharge when the journey changes transport |
| *Detour worth avoiding stop* | How far out of your way is worth going to save one extra leg |
| *Detour worth avoiding change* | The same, for changing between kinds of transport |

## Setup

Point `openmw.cfg` at the mod directory and enable its script list:

```
data="<path to>/openmw-lua/TravelAgents"
content=TravelAgents.omwscripts
```

## What a journey does to you

The mod follows vanilla rather than inventing its own rules:

- **A guild guide teleports.** No time passes, whatever the distance — you
  still pay the fare, but the clock does not move.
- **Riding is a rest.** Step off a silt strider, boat or gondola and health,
  magicka and fatigue have all come back.
- **A teleport is a wait.** Step out of a guild hall and only fatigue has.

A journey that rides anything at all counts as a rest, even if a guild guide
carries the last leg.

## Compatibility

Should work out of the box with mods that add travel providers.

The travel graph is built once, on the first frame after a save loads, because
finding operators means walking every cell in the load order — a travel
destination lives on a record, but the near end of every route is wherever the
operator happens to be standing. On a large load order such as Tamriel Rebuilt
that is a few seconds of work; doing it here keeps it out of your first
conversation with a travel NPC. The log line `graph ready: N stops, M legs,
built in T` says how long it took.
