# Travel Agents — expanded travel & journey planning (OpenMW)

Turns Morrowind's travel NPCs into full-fledged travel agents, offering
multi-leg journeys and transfers between transport modes.

## Using it

Bind a key first, then talk to a silt strider driver, shipmaster, gondolier or
guild guide. The conversation prompts you by name of key (*Press T to plan a
journey from here*).

Press it and a window opens with everywhere you can get to, cheapest first. Trips requiring 1 or more transfers are listed on separate tabs.

Trips made through a travel agent are more expensive. You pay for the convenience. Surcharges are added based on the number of legs in your journey, ans well as the number of transfers required.

## Settings

Options → Scripts → Travel Agents.

| Setting | What it does |
|---|---|
| *Open planner* | The key. Nothing is bound until you bind one |
| *Extra per leg (%)* | Convenience surcharge for every leg past the first |
| *Extra per change (%)* | Convenience surcharge when the journey changes transport |

## Setup

Point `openmw.cfg` at the mod directory and enable its script list:

```
data="<path to>/openmw-lua/TravelAgents"
content=TravelAgents.omwscripts
```

## Telling other mods about a journey

Arriving is silent — the window has already said where, how long and what it
costs. So that a mod with something more interesting to say can hear about it,
a completed journey sends the player an event:

```lua
TravelAgentsArrived = {
    class = 'caravaner',    -- the operator's class id, as the content files spell it
    place = 'Ald-ruhn',     -- the stop, which is a better name than the cell's
    hours = 3.2,            -- 0 for a guild guide, who arrives at the hour they left
}
```

The class rather than this mod's own vehicle id, so a listener needs to know
nothing about how vehicles are filed here. Nothing in this mod listens for it.

## Compatibility

Should work out of the box with mods that add travel providers.

**A vehicle the mod has never heard of is still named after itself.** What
carries you on a leg is taken from its operator's class, and a class nothing
declares becomes a mode named after itself rather than joining a shared
"unknown" heap — so a modded vehicle reads as what it is in the journey
strip, not as *Unknown*.

To see what your own load order actually contains:

```
luag require('openmw.interfaces').TravelAgents.dumpClasses()
```

It lists every operator class found, how many operators carry it, and which
ones no entry claims. Output goes to `openmw.log`.

The travel graph is built once, on the first frame after a save loads. A travel
destination lives on a record, but the near end of every route is wherever the
operator happens to be standing, and nothing in the engine indexes that — so a
shipped table says where the operators of the common load orders stand, and the
build opens one cell each rather than all of them. That is about 155 cells and
a tenth of a second. The log line `graph ready: N stops, M legs` says what came
out.

A load order that adds a travel service the table has never heard of still
needs the long way round: opening cells until the missing operators turn up.
That search is deferred — the graph is built and answering from the table
first, and the search runs behind it a slice at a time, outdoors before indoors
and stopping the moment everybody has been found. Talking to an operator the
graph does not know finishes it on the spot rather than making you wait for it
on every load.

Talking to any operator is also how the table corrects itself: at that moment
they are standing in front of you, so where they are costs nothing to read. An
operator a patch has moved, or one no table places, is remembered from the
conversation and looked up directly on every load after.
