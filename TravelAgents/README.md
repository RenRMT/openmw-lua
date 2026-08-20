# Travel Agents — expanded travel & journey planning (OpenMW)

Turns Morrowind's travel NPCs into full-fledged travel agents, offering
multi-leg journeys and transfers between transport modes.

## Using it

Bind a key first, then talk to a silt strider driver, shipmaster, gondolier or
guild guide. The conversation prompts you by name of key (*Press T to plan a
journey from here*).

Press it and a window opens. **Both halves are the destination list** —
everywhere you can get to, cheapest first, filling the left column and then the
right. Each row is a place and its fare.

Under the list is a strip with everything about whichever destination you have
picked: what the journey asks of you, the places it goes **via**, the fare split
into the base and the booking fee for the convenience, and the button to buy it.
When the cheapest way into a town ends in a building rather than the street, the
strip says where you actually get off.

Above the list is a tab per **number of changes of vehicle** — *Direct*, then
*1 change*, *2 changes*, and *3+ changes* for anything beyond. *All* drops the
filter. Only tabs with something in them appear, and the window opens on the
fewest changes that gets you anywhere: standing in front of a driver, where you
can get to without changing is usually the question being asked.

Stops no vehicle calls at — Caldera, Wolverine Hall — are reached by the walk
from the guild hall beside them, so they appear in the list like anywhere else,
with the walk as one of the legs.

MWUI has no scrollbar, so a list longer than a page is **paged** rather than
clipped: `< back` and `more >` appear under the columns when they are needed,
and never in a vanilla-sized world. A page holds 36 places, which is more than
vanilla has anywhere; on a mainland-sized load order *Direct* is what keeps the
first thing you see short, and *All* is where the paging shows up.

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

**A vehicle the mod has never heard of is still named after itself.** What
carries you on a leg is taken from its operator's class, and a class nothing
declares becomes a mode named after itself rather than joining a shared
"unknown" heap — so a modded vehicle reads as what it is in the journey
strip, not as *Unknown*.

In practice the large landmass mods lean on vanilla's classes: checked against a
real load order, only **river striders** carry a class of their own
(`Therionaut`), which `data/modes.lua` names. Guar caravans and carriages are
authored as ordinary caravaners, so nothing in the game's data distinguishes
them from a silt strider and they read as one.

To see what your own load order actually contains:

```
luag require('openmw.interfaces').TravelAgents.dumpClasses()
```

It lists every operator class found, how many operators carry it, and which
ones no entry claims. Output goes to `openmw.log`.

The travel graph is built once, on the first frame after a save loads, because
finding operators means walking every cell in the load order — a travel
destination lives on a record, but the near end of every route is wherever the
operator happens to be standing. On a large load order such as Tamriel Rebuilt
that is a few seconds of work; doing it here keeps it out of your first
conversation with a travel NPC. The log line `graph ready: N stops, M legs,
built in T` says how long it took.
