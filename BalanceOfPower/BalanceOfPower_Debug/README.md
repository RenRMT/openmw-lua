# Balance of Power — Debug Overlay

Hotkeys and on-screen readouts for whatever Balance of Power content you have
loaded. It **registers nothing** — no factions, no territory, no simulation — so
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
| `Ctrl+1` | Map: a window around you, then the full map (`Ctrl+Shift+1` cycles owner → projection → contest) |
| `Ctrl+2` | Standings: power and territory count per faction |
| `Ctrl+3` | Resolve one in-game day now (`Ctrl+Shift+3` for seven) |
| `Ctrl+4` | Push whoever **holds** the ground you're standing on, +50 (`Shift` for −50) |
| `Ctrl+5` | Push whoever is about to **take** it, +50 (`Shift` for −50) |
| `Ctrl+6` | Toggle the live event feed |
| `Ctrl+7` | Attempt a deliberately invalid registration |
| `Ctrl+8` | Full report on the cell you're in |

The number row rather than the function keys: Morrowind already uses F1–F12 for
quick slots, quicksave, quickload, screenshots and the log viewer, and the
engine acts on those whether or not a modifier is held.

Walking into a new cell prints one line — territory, holder, how contested, and
who's closing in. `Ctrl+8` gives the full picture for where you're standing.

## Reading the output

**Everything goes to `openmw.log`. Nothing is drawn over the HUD.** Press
**F11** for OpenMW's built-in log viewer, which scrolls back — a fifty-row map
was never going to fit in a message box, and output worth reading twice is worth
being able to scroll.

Every line is tagged `[BoP]`, so it can be pulled out of a log shared with the
framework's own output (`[BalanceOfPower]`) and everything else:

```
[BoP] ----------------------------------------------------------------
[BoP] STANDINGS -- day 42
[BoP] ----------------------------------------------------------------
[BoP]   36 settlements, 562 frontier cells, 47 contested
[BoP]
[BoP]   faction                       power    held
[BoP]   Tribunal Temple                65.0      53
[BoP]   The Empire                     65.0      57
[BoP]   House Hlaalu                   55.0     102
[BoP]   -- holds no land --
[BoP]   Camonna Tong                   35.0       -
```

Standings are ordered by power, so whether a push landed is visible at a glance.

`Ctrl+1` prints a window around you first, then the whole map:

```
[BoP]       8765432101234
[BoP]     3 Hhhrriiir.m.
[BoP]     2 hhh.iiIii
[BoP]     1 hhhhhhiii
[BoP] legend: H/h House Hlaalu   I/i The Empire   R/r House Redoran
```

Uppercase is a settlement, lowercase its wilderness. The column header is each
cell's last x digit, so you can count back to a real grid reference.

To follow along outside the game instead, tail the file — usually
`Documents\My Games\OpenMW\openmw.log`:

```powershell
Get-Content -Wait -Tail 60 "$env:USERPROFILE\Documents\My Games\OpenMW\openmw.log"
```

## The loop that shows the simulation working

Territory only moves when the *projection ordering* changes. So:

1. Walk to a border — the cell line says `<- … closing in` when you're on one.
   `Ctrl+Shift+1` twice gets the `contest` map, which shows where they all are.
2. `Ctrl+5` once or twice to push the challenger.
3. `Ctrl+3` a few times to run days.
4. `Ctrl+1` between each to watch the front move.

`Ctrl+4` pushes the other way, so you can shove a border back and forth and
watch the cooldown hold ground that has just changed hands.

## What each control actually tests

**`Ctrl+4` / `Ctrl+5` — reaction propagation.** Pushing one faction moves every
other faction too, scaled by how each feels about it. With the event feed on
(`Ctrl+6`) each one is logged individually; it's off by default because a single
award produces a dozen lines. Factions with a real faction record
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

**Cell walking and `Ctrl+8` — the cell index and projection cache.** Confirms
cells map to territories, and shows the numbers that actually decide ownership.

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
