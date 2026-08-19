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

## Compatibility

Should work out of the box with mods that add travel providers.
