# Balance of Power — a factions framework

Tracks faction power and territory control, and exposes an interface that
content packs register data against. It ships **no factions and no
territories**. On its own it does nothing.

## Status

In development. The framework core is in place; the Morrowind content pack and
the debug overlay are not yet published here.

What exists:

- registration API with cross-pack faction merging
- faction power, reaction-driven propagation, atomic per-pass batching
- persistent state with central default-fill for save compatibility
- the in-game day tick driver
- territory resolution: projection maths, derived initial control, frontier
  rolls
- frontier grid generation from registered settlements
- the event bus, including the `BoP_DayResolved` scheduling hook

## Setup

Point `openmw.cfg` at the mod directory and enable its script list. The
framework must load before any content pack.

```
data="<path to>/openmw-lua/BalanceOfPower"
content=BalanceOfPower.omwscripts
```
