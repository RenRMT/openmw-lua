# Balance of Power — Debug Overlay

Hotkeys and on-screen readouts for whatever Balance of Power content you have
loaded. It **registers nothing** — no factions, no territory, no invasion — so
it sits on top of the [Morrowind pack](../BalanceOfPower_Morrowind/README.md),
or any other content pack, rather than competing with it for faction ids.

Nothing in it names a faction. The power keys work out what to push from the
ground the player is standing on, which is both content-agnostic and the fastest
way to make the simulation do something visible.

> Safe to leave enabled while testing, but it writes power changes and forced
> days into your save, so don't use it in a playthrough you care about.

## Setup

Add to `openmw.cfg`, **framework first, this one last**:

```ini
data="D:\projects\openmw-lua\BalanceOfPower\BalanceOfPower_Framework"
data="D:\projects\openmw-lua\BalanceOfPower\BalanceOfPower_Morrowind"
data="D:\projects\openmw-lua\BalanceOfPower\BalanceOfPower_Debug"

content=BalanceOfPower_Framework.omwscripts
content=BalanceOfPower_Morrowind.omwscripts
content=BalanceOfPower_Debug.omwscripts
```

It only needs the framework to have loaded, but putting it last keeps the
ordering obvious. `reloadlua` in the console restarts all Lua without restarting
the game, which makes the edit/test loop fast.

## Hotkeys

| Key | Does |
|---|---|
| `Ctrl+1` | Map of the cells around you, on screen — and the full map to `openmw.log` (`Ctrl+Shift+1` cycles owner → projection → contest) |
| `Ctrl+2` | Standings: power and territory count per faction |
| `Ctrl+3` | Resolve one in-game day now (`Ctrl+Shift+3` for seven) |
| `Ctrl+4` | Push whoever **holds** the ground you're standing on, +50 (`Shift` for −50) |
| `Ctrl+5` | Push whoever is about to **take** it, +50 (`Shift` for −50) |
| `Ctrl+6` | Toggle the live event feed |
| `Ctrl+7` | Attempt a deliberately invalid registration |

The number row rather than the function keys: Morrowind already uses F1–F12 for
quick slots, quicksave, quickload and screenshots, and the engine acts on those
whether or not a modifier is held.

Walking between cells also reports the territory you've entered, who holds it,
how contested it is, and every faction's projection onto it.

### Reading the map

`Ctrl+1` gives you both halves at once. On screen, a 13×13 window centred on
where you're standing — uppercase is a settlement, lowercase its wilderness:

```
      8765432101234
    5 hhrrrrRrrrm.
    4 hhhrrrrrrrMm
    3 Hhhrriiir.m.
    2 hhh.iiIii
    1 hhhhhhiii
legend: H/h House Hlaalu   I/i The Empire   M/m Tribunal Temple   R/r House Redoran
```

The full map of every landmass goes to `openmw.log` on the same keypress, for
when the window isn't enough. **There is no way to read the log from inside the
game** — it's a file next to your saves, usually
`Documents\My Games\OpenMW\openmw.log` on Windows. Tail it in a second window:

```powershell
Get-Content -Wait -Tail 60 "$env:USERPROFILE\Documents\My Games\OpenMW\openmw.log"
```

The column header is the last digit of each cell's x coordinate, so you can
count back to a real grid reference.

## The loop that shows the simulation working

Territory only moves when the *projection ordering* changes. So:

1. Walk to a border — the cell readout says `contested by: …` when you're on one.
   `Ctrl+Shift+1` twice gets you the `contest` map, which shows where they are.
2. `Ctrl+5` once or twice to push the challenger.
3. `Ctrl+3` a few times to run days.
4. `Ctrl+1` between each to watch the front move.

`Ctrl+4` pushes the other way, so you can shove a border back and forth and
watch the cooldown hold ground that has just changed hands.

## What each control actually tests

**`Ctrl+4` / `Ctrl+5` — reaction propagation.** Pushing one faction moves every
other faction too, scaled by how each feels about it. With the event feed on
(`Ctrl+6`) you see them move individually. Factions with a real faction record
read their reactions from the game's data; ones without use an authored table —
both go through identical math, which is the claim in design doc 3.5.

**`Ctrl+3` — the day tick.** The scheduled tick only fires when the game calendar
rolls over, so without this you'd have to sleep. It runs the simulation *ahead*
of game time, and the scheduled tick then idles until real time catches up: a
forced day is a real day, not a bonus one.

**`Ctrl+1` — resolution.** Two behaviours worth confirming specifically: a cell
whose owner is *also* its strongest projector is never rolled for at all, and a
cell that has just changed hands is protected by its cooldown even if the
balance immediately swings back. Both look like bugs and are not.

**`Ctrl+7` — validation and blast radius.** Tries to re-register an
already-registered faction without `extend = true`. It should be rejected with a
message naming the faction, and the standings printed afterwards should be
unchanged — proving a bad pack can't half-register or take the framework down
with it.

**Cell walking — the cell index and projection cache.** Confirms cells map to
territories, and shows the numbers that actually decide ownership.

**Save, quit, reload** — standings and ownership should survive, which is the
`onSave`/`onLoad` path plus `fillDefaults` seeding anything new.

## Console

Everything here is also reachable from the console in global context, without
the overlay loaded at all:

```
luag require('openmw.interfaces').BalanceOfPower.dumpMap({ mode = 'projection' })
luag require('openmw.interfaces').BalanceOfPower.dump()
luag require('openmw.interfaces').BalanceOfPower.forceDay(7)
luag require('openmw.interfaces').BalanceOfPower.awardPower('hlaalu', 50)
```

(`luag` is short for `lua global`; there's also `luap` for player context.)
Output goes to `openmw.log`, so keep it open in a tail.
