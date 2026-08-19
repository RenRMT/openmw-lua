# Travel Agents — expanded travel & journey planning (OpenMW)

Turns Morrowind's travel NPCs into full-fledged travel agents, offering
multi-leg journeys and transfers between transport modes.

## Using it

Bind a key first, then talk to a silt strider driver, shipmaster, gondolier or
guild guide. The conversation prompts you by name of key (*Press T to plan a
journey from here*).

Press it and a window opens. **Both halves are the destination list** —
everywhere you can get to, cheapest first, filling the left column and then the
right. A `+` beside a fare means that journey changes vehicle on the way.

Under the list is a strip with everything about whichever destination you have
picked: how many legs and changes, the places it goes **via**, the fare split
into the base and the surcharge for the convenience, and the button to buy it.

Above the list is a tab per **network** — silt striders, boats, guild guides,
gondolas, and whatever a landmass mod adds. The window opens on the network of
whoever you are talking to, so a silt strider driver shows you where their
striders go before it shows you the rest of the continent. *All* drops the
filter.

A tab lists the places that network **serves**, not journeys made only by that
vehicle: picking a Mages Guild off the guild guide tab while standing in Khuul
still routes you by strider first. The right-hand pane always shows the actual
legs, the fare and the time before you commit to anything.

Stops no vehicle calls at — Caldera, Wolverine Hall — appear under the network
you walk to them from, so nothing falls between the tabs.

MWUI has no scrollbar, so a list longer than a page is **paged** rather than
clipped: `< back` and `more >` appear under the columns when they are needed,
and never in a vanilla-sized world. A page holds 36 places, which is more than
vanilla has anywhere; the tabs are what keep a mainland-sized load order down
to one or two pages.

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

**A vehicle the mod has never heard of still gets its own tab.** The network a
route belongs to is taken from its operator's class, and a class nothing
declares becomes a network named after itself rather than joining a shared
"unknown" heap.

In practice the large landmass mods lean on vanilla's classes: checked against a
real load order, only **river striders** carry a class of their own
(`Therionaut`), which `data/modes.lua` names. Guar caravans and carriages are
authored as ordinary caravaners, so nothing in the game's data distinguishes
them from a silt strider and they share the overland tab — the right grouping
for choosing how to travel, even if the label is vanilla's word for it.

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
