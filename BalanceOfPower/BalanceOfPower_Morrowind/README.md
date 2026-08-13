# Balance of Power — Morrowind

The Vvardenfell and Solstheim content pack: factions, settlements, and the
Sixth House. Pure data plus the four API calls that hand it to the
framework — all behaviour lives in
[BalanceOfPower_Framework](../BalanceOfPower_Framework/README.md), which must
load **before** this mod.

> ## ⚠ Solstheim uses the Anthology position
>
> Solstheim's settlements are placed at the coordinates used by the
> **Morrowind Anthology / Tamriel Rebuilt** layout, which is also what
> **Tomb of the Snow Prince** uses — *not* vanilla Bloodmoon's placement.
>
> If you play vanilla Bloodmoon with Solstheim in its original position, the
> Solstheim half of this pack will register territory in the wrong cells.
> Vvardenfell is unaffected. Either install a mod that moves Solstheim to the
> Anthology position, or delete the four Solstheim rows from
> `sources/settlements.csv` and rebuild.

## What it registers

| | Vvardenfell | Solstheim |
|---|---|---|
| Holdings | 59 | 4 |
| Of those, settlements | 33 | 3 |
| Settlement cells | 64 | 4 |
| Generated frontier cells | ~540 | ~20 |

63 holdings in total, 36 of them settlements. Everything else — farms, shacks,
mines, minor manors — is a power center only: it shapes who a region belongs to
without being a place on the map.

### Factions

**Land-holding** — House Hlaalu, House Redoran, House Telvanni, the Tribunal
Temple, the Empire, the Ashlanders, and on Solstheim the East Empire Company
and the Skaal.

**Power-only** — the Fighters, Mages and Thieves Guilds, the Imperial Cult, the
Camonna Tong and the Morag Tong. They have standing that rises and falls with
their allies through the reaction table, and other systems can read it, but
they hold no ground. The Fighters Guild is a real political force in
Vvardenfell; it just doesn't own Balmora.

Two notes on ids:

- **The Empire is registered as `imperial legion`.** Design doc 5.1 merges the
  Legion, Cult and Knights into one umbrella for the MVP. Mapping that onto the
  Legion's own record id means its reaction row is the game's data rather than
  something invented here — and every Imperial holding in the settlement list
  is a fort or a Legion-garrisoned town, so it isn't much of a stretch. The
  Imperial Cult is kept separate, as a power-only faction.
- **Four factions have no ESM record: the East Empire Company, the Skaal, the
  Ashlanders and the Sixth House.** Their own reaction tables are authored in
  full. Everyone else reads theirs from `core.factions.records`.

  Because nothing in Morrowind.esm can name those four, the *other* half of
  each relationship is authored too — every vanilla faction here carries a
  short `reactions` table naming them. Authored values merge over the record
  rather than replacing it, so those additions cost the vanilla rows nothing.

  Without them, all four would move other factions perfectly well and never
  move themselves: their standing could only change through a direct award.
  Nothing about that reads as an error, which is why
  `BoP.dumpReactions()` reports a `movedBy` column, and why the test suite
  asserts no faction sits at zero in either direction.

  The numbers in those added rows are guesswork, like `basePower`. They are
  the second thing to reach for when the politics feel wrong.

## The starting map is derived, not authored

There is no authored ownership anywhere in this pack. The whole map falls out
of where the settlements are. Registering Balmora as a Hlaalu seat is what
makes the West Gash Hlaalu ground; nobody writes down that the West Gash is
Hlaalu, and nobody writes down that Red Mountain is the Sixth House's — it
holds its own seat because it has a power centre there and nobody else reaches
it.

That's what makes the ~560 generated frontier cells viable — there is no second
list of ownership to keep in step with the first.

Ownership at load, derived:

| Faction | Cells |
|---|---|
| Redoran | 120 |
| Hlaalu | 111 |
| Telvanni | 66 |
| The Empire | 63 |
| Temple | 61 |
| Skaal | 16 |
| East Empire Company | 12 |
| Ashlanders | 6 |
| Sixth House | 1 |
| *unclaimed* | 174 |

630 cells in total — 68 belonging to settlements, 562 frontier. The unclaimed
ones are within reach of somebody but below the claim threshold: genuine
expansion room rather than dead ground.

By cell state at load: 404 consolidated, 52 uncontested, 174 unclaimed and
**nothing contested**. That last figure is correct rather than suspicious —
initial control hands every cell to its strongest projector, so no owner starts
out being out-projected. The map only develops fronts once power moves.

Minor holdings hold their own cell 16 times out of 17, the exception being one
that sits next to a far larger neighbour. That is the garrison floor working as
intended: a farm is a one-cell island of its owner inside whoever's country
surrounds it.

## Editing the data

`sources/settlements.csv` is the source of truth.
`scripts/BalanceOfPowerMorrowind/data/settlements.lua` is **generated** from it
and must not be hand-edited. After changing the CSV:

```sh
python BalanceOfPower/BalanceOfPower_Morrowind/sources/build_settlements.py
```

The script validates as it goes: unknown tier, unknown faction, unknown
landmass, or two settlements claiming the same cell all fail the build rather
than producing data that misbehaves at load.

### Columns

`settlement, cell_x, cell_y, region, landmass, tier, faction, is_capital`

One row per cell, so a multi-cell settlement appears several times and is
grouped into a single settlement. Vivec is one fifteen-cell metropolis, not fifteen
adjacent districts fighting each other.

`is_capital` is currently `No` throughout — the Great Houses' capitals are on
the mainland, which arrives with a Tamriel Rebuilt pack.

### Tier mapping

| CSV tier | Settlement | Power center |
|---|---|---|
| Metropolis | `metropolis` | `capital` |
| Small City | `city` | `capital` |
| Town | `town` | `regional` |
| Village | `village` | `regional` |
| Outpost/Fortress/Camp | `outpost` | `outpost` |
| Minor location | — *(power center only)* | `minor` |

A power center's cells are handed to the framework along with its coordinates,
because that is what gives its faction the garrison floor there. It is why a
minor holding keeps its own cell without being a settlement.

`Velothi/Unaffiliated` is not a faction — it marks a holding with no political
owner, which projects nothing and starts unclaimed.

### Corrections applied to the source data

Kept in the build script rather than edited into the CSV, so the original
survives:

- **Thirsk** is promoted from `Minor location` to `Village`. It's a mead hall
  with its own warrior population and a faction behind it, not a farmstead.
- **Arvs-Drelen** is demoted to `Minor location`. It shares cell `-11,11` with
  Gnisis, and one cell can only belong to one settlement; as a power center the
  Telvanni presence in the West Gash still registers.

## Tuning

Look at the map rather than guessing. From the in-game console:

```
luag require('openmw.interfaces').BalanceOfPower.dumpMap()
luag require('openmw.interfaces').BalanceOfPower.dumpMap({ mode = 'projection' })
luag require('openmw.interfaces').BalanceOfPower.dumpMap({ mode = 'contest' })
```

Output goes to `openmw.log`, one character per exterior cell, north at the top.
`projection` shows the effect of a range change straight away; `owner` only
catches up after days of rolls. `reloadlua` re-reads `config.lua` without
restarting the game.

The numbers most worth touching, in order of effect:

1. **`influenceRange` per tier**, in the framework's `config.lua`. This decides
   the entire starting map, since ownership is derived from projection. A
   Morrowind exterior cell is 8192 units, so the tier defaults are ~5, ~3 and
   ~1.5 cells of reach.
2. **`basePower` per faction**, in `data/factions.lua`. Pure guesswork until
   played.
3. **The Sixth House's `growthPerDay`** (1.5), which sets the pace of the only
   thing on the map that moves on its own. At this rate it doubles its standing
   in about three weeks and holds every cell it can reach within a few months.
   Nothing pushes back yet, so this is a countdown rather than a contest until
   the player-influence hooks land.

## The Sixth House

Not a subsystem, and there is no invasion mod. It is an ordinary faction with
two fields set:

```lua
growthPerDay = 1.5,     -- gains power whether or not anyone is watching
hostile = true,         -- attacks the player, and everyone it regards at -3
```

Everything that was scoped as an invasion falls out of those. **Escalation is
emergent:** projection is power scaled by distance decay, so at low standing it
reaches barely past Red Mountain and its patrols appear near Ghostgate, and the
radius grows with its power. There is no stage table because there is nothing
for one to gate.

**It cannot take Vvardenfell**, and not because a rule forbids it. Influence
decays to exactly zero at `influenceRange` no matter how strong a faction
becomes, so Balmora is not far away — it is unreachable. The Sixth House
saturates its own country and stops.

Its enemies come from the reaction table rather than a list: everyone it
regards at -3, which is every faction except the Ashlanders and the Camonna
Tong, both authored at -2. No other faction in this pack is flagged hostile, so
the Great Houses go on tolerating each other exactly as they do in vanilla.

### Patrol rosters

Only the Sixth House has one, tiered so that what appears gets worse as it
grows:

| Tier | Records |
|---|---|
| 1 | `ash slave`, `corprus stalker` |
| 2 | `ash zombie` |
| 3 | `ash ghoul` |

Lower tiers stay in the pool at every tier above, so a strong Sixth House
fields an ash ghoul leading a knot of slaves rather than four ghouls together.

**The eight vanilla factions have no rosters yet**, so they field no patrols —
that is the empty-roster rule, not an oversight, but it is the pack's main
remaining content job. It needs real NPC record ids verified against the game:
the framework never inspects a record id, so a wrong one fails silently.

## Layout

```
sources/
  settlements.csv          source of truth, hand-edited
  build_settlements.py     generates the Lua below
scripts/BalanceOfPowerMorrowind/
  main.lua                 GLOBAL: registration + frontier generation
  data/settlements.lua     GENERATED -- do not edit
  data/factions.lua        faction list and authored reactions
  data/build.lua           holdings -> settlements and power centers
```
