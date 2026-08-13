# Balance of Power — Dev Sandbox

A throwaway content pack plus an on-screen debug console: a world small enough
to hold in your head, where every mechanic can be triggered on a keypress and
the consequences fit in one message box.

The [Morrowind pack](../BalanceOfPower_Morrowind/README.md) is what you want for
real content. This is what you want when something is behaving oddly and you
need to isolate it.

> **Don't enable this in a playthrough you care about.** It registers fictional
> territory and writes simulation state into your save.
>
> **Do not enable it alongside `BalanceOfPower_Morrowind`.** Both define
> `hlaalu` and the Sixth House, and redefining a faction is an error rather
> than a silent overwrite — whichever loads second will fail to register. Pick
> one: the sandbox for a small world with a debug console, the Morrowind pack
> for real content.

## Setup

Add both mods to `openmw.cfg`, **framework first**:

```ini
data="D:\projects\openmw-lua\BalanceOfPower\BalanceOfPower_Framework"
data="D:\projects\openmw-lua\BalanceOfPower\BalanceOfPower_DevSandbox"

content=BalanceOfPower_Framework.omwscripts
content=BalanceOfPower_DevSandbox.omwscripts
```

Order matters: the sandbox reads the framework's interface at load, and fails
with an explicit message if the framework hasn't loaded yet.

Load a save. You should see a message listing the hotkeys, and this in
`openmw.log`:

```
[BalanceOfPower] framework initialized (interface v1)
[BalanceOfPower] registered landmass "dev_sandbox": 3 factions, 3 anchors, 4 frontier cells
[BalanceOfPower] registered invasion "dev_sixth_house" (faction "sixth house"): 1 home territories, 4 stages
```

`reloadlua` in the console restarts all Lua scripts without restarting the
game, which makes the edit/test loop fast.

## Hotkeys

| Key | Does |
|---|---|
| `Ctrl+1` | Show the whole map: who holds what, and what's contested |
| `Ctrl+2` | Dump the simulation — standings on screen, full detail to the log |
| `Ctrl+3` | Resolve one in-game day now (`Ctrl+Shift+3` for seven) |
| `Ctrl+4` | Push the raiders +50 (`Ctrl+Shift+4` for −50) — moves the front |
| `Ctrl+5` | Award +25 power to Hlaalu (`Ctrl+Shift+5` for −25) |
| `Ctrl+6` | Toggle the live event feed |
| `Ctrl+7` | Attempt a deliberately invalid registration |

The number row rather than the function keys: Morrowind already uses F1–F12 for
quick slots, quicksave, quickload and screenshots, and the engine acts on those
whether or not a modifier is held.

Walking between cells also prints the territory you're standing in, who holds
it, and every faction's projection onto it — the sandbox covers Balmora
(`-3,-2`), Seyda Neen (`-2,-9`), Red Mountain (`2,4`) and four frontier cells
around the first two.

## The map

Nothing here has an authored owner except Red Mountain. The starting map is
derived from where the power centers are, on the first tick. Projections at
base power (Hlaalu 55, Legion 50, raiders 25):

| Territory | Cell | Hlaalu | Legion | Raiders | Starts as |
|---|---|---|---|---|---|
| Balmora (city) | `-3,-2` | 55.0 | 1.7 | 0 | Hlaalu |
| West Gash approach | `-4,-2` | 47.5 | 0.3 | 0 | Hlaalu |
| Odai headwaters | `-3,-3` | 47.5 | 8.5 | 2.3 | Hlaalu |
| Bitter Coast north | `-2,-8` | 9.3 | 43.2 | 13.6 | Legion |
| Bitter Coast east | `-1,-9` | 0.3 | 43.2 | 4.9 | Legion |
| Seyda Neen (town) | `-2,-9` | 1.9 | 50.0 | 8.0 | Legion |
| Red Mountain (city) | `2,4` | 0 | 0 | 0 | Sixth House *(authored)* |

The raiders are camped at `-3,-6`, between the two settlements, with a shorter
reach. At rest they contest nothing. Push them and their projection walks
outward:

- **~80 power** — they out-project the Legion at Bitter Coast north and take it
  within a day or two.
- **~165 power** — Bitter Coast east falls too. Seyda Neen is now surrounded on
  both its frontier cells, so its siege streak starts climbing (`Ctrl+6` to
  watch the `BoP_AnchorSieged` events).
- **three more days** — the streak clears the town's threshold and Seyda Neen
  can be rolled for, with the Legion's projection doubled by the town's defence
  multiplier. It takes a while. That's the point.

`Ctrl+4` four times then `Ctrl+Shift+3` a few times walks the whole
sequence. `Ctrl+1` between each shows where the front is.

Balmora is a `city`, with a much steeper defence multiplier and a higher siege
threshold — it should be effectively untakeable this way, which is the intended
behaviour (design doc 3.4 reserves real city flips for the invasion subsystem).

## What each control actually tests

**`Ctrl+5` — reaction propagation.** Hlaalu gains 10, and every other faction
moves too, scaled by how it feels about Hlaalu. The Imperial Legion and Hlaalu
values come from the game's own faction records; Sandbox Raiders has no ESM
record at all and uses an authored reactions table instead. Both paths run
through the same math, which is the claim in design doc 3.5. Turn on the event
feed (`Ctrl+6`) first to watch each faction move individually.

**`Ctrl+3` — the day tick.** The scheduled tick only fires when the game
calendar rolls over, so without this you'd have to sleep. Note it runs the
simulation *ahead* of game time, so the scheduled tick then idles until real
time catches up; a forced day is a real day, not a bonus one.

**`Ctrl+4` then `Ctrl+1` — territory resolution.** The core of phase 2. See
the map section above for the thresholds. Two behaviours worth confirming
specifically: a cell whose owner is *also* the strongest projector is never
rolled for at all, and a cell that has just changed hands is protected by its
cooldown even if the balance immediately swings back.

**`Ctrl+7` — validation and blast radius.** Tries to register Hlaalu a second
time without `extend = true`. It should be rejected with a message naming the
faction, and the standings printed afterwards should be unchanged — proving a
bad pack can't half-register or take the framework down with it.

**Cell walking — the cell index.** Confirms cells map to territories and that
ownership defaults were seeded from the static definitions.

**Save, quit, reload** — standings should survive, which is the `onSave`/
`onLoad` path plus `fillDefaults` seeding anything new.

Red Mountain is deliberately declared with `defaultOwner = 'sixth house'`
*before* `registerInvasion` creates that faction. The reference check runs on
the first tick, once every pack has loaded, so this should produce **no**
warning. A warning there would be a bug.

## Console

The framework's interface is reachable from the in-game console in global
context:

```
luag require('openmw.interfaces').BalanceOfPower.dump()
luag require('openmw.interfaces').BalanceOfPower.awardPower('hlaalu', 25)
luag require('openmw.interfaces').BalanceOfPower.forceDay(3)
luag print(require('openmw.interfaces').BalanceOfPower.powerSummary())
```

(`luag` is short for `lua global`; there's also `luap` for player context.)
Output goes to `openmw.log`, so keep it open in a tail.
