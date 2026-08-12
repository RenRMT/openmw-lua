# Balance of Power — Dev Sandbox

A throwaway content pack plus an on-screen debug console, so the framework can
be exercised in-game before the real Morrowind data pack exists (phase 3).

> **Don't enable this in a playthrough you care about.** It registers fictional
> territory and writes simulation state into your save.

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
| `Ctrl+F10` | Dump the simulation — standings on screen, full detail to the log |
| `Ctrl+F11` | Award +10 power to Hlaalu (`Ctrl+Shift+F11` for −10) |
| `Ctrl+F12` | Resolve one in-game day now (`Ctrl+Shift+F12` for seven) |
| `Ctrl+F9` | Toggle the live event feed |
| `Ctrl+F8` | Attempt a deliberately invalid registration |

Walking between cells also prints the territory you're standing in and who
holds it — the sandbox covers Balmora (`-3,-2`), Seyda Neen (`-2,-9`), Red
Mountain (`2,4`) and four frontier cells around the first two.

## What each control actually tests

**`Ctrl+F11` — reaction propagation.** Hlaalu gains 10, and every other faction
moves too, scaled by how it feels about Hlaalu. The Imperial Legion and Hlaalu
values come from the game's own faction records; Sandbox Raiders has no ESM
record at all and uses an authored reactions table instead. Both paths run
through the same math, which is the claim in design doc 3.5. Turn on the event
feed (`Ctrl+F9`) first to watch each faction move individually.

**`Ctrl+F12` — the day tick.** The scheduled tick only fires when the game
calendar rolls over, so without this you'd have to sleep. Note it runs the
simulation *ahead* of game time, so the scheduled tick then idles until real
time catches up; a forced day is a real day, not a bonus one. Phase 1 has
nothing to resolve yet, so this currently just prints standings — it's here so
phases 2 and 6 are testable the moment they land.

**`Ctrl+F8` — validation and blast radius.** Tries to register Hlaalu a second
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
