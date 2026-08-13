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

| Faction | Territories |
|---|---|
| Redoran | 116 |
| Hlaalu | 102 |
| Telvanni | 64 |
| The Empire | 57 |
| Temple | 53 |
| Skaal | 15 |
| East Empire Company | 11 |
| Ashlanders | 3 |
| Sixth House | 1 |
| *unclaimed* | 176 |

The unclaimed cells are within reach of somebody but below the claim floor —
genuine expansion room rather than dead ground.

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
3. **The Sixth House's `basePower`**, which is where an invasion extension
   would start pushing from.

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
