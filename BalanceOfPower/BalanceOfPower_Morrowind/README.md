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
| Settlements | 57 | 4 |
| Settlement cells | 86 | 7 |
| Generated frontier cells | ~370 | ~30 |

61 settlements in total. Every holding is one: farms, shacks, mines and minor
manors are `minor location` settlements, projecting a little and holding their
own cell. The CSV lists 63 holdings; two are dropped for sharing a cell with a
larger neighbour.

### Factions

**Land-holding** — House Hlaalu, House Redoran, House Telvanni, the Tribunal
Temple, the Empire, the Ashlanders, and on Solstheim the East Empire Company
and the Skaal.

**Power-only** — the Fighters, Mages and Thieves Guilds, the Imperial Cult,
Knights, Blades and Census and Excise, the Camonna Tong and the Morag Tong, the
Talos Cult, the Twin Lamps, the Nerevarine and the three vampire clans. They
have standing that rises and falls with their allies through the reaction
table, and other systems can read it, but they hold no ground. The Fighters
Guild is a real political force in Vvardenfell; it just doesn't own Balmora.

Every faction in the vanilla reaction matrix is registered, whether or not it
has any political weight — the Nerevarine and the Talos Cult are here because
the game has them, not because the simulation does anything with them.

Three notes on the data:

- **The Empire is registered as `imperial legion`.** Design doc 5.1 merges the
  Legion, Cult and Knights into one umbrella for the MVP. Mapping that onto the
  Legion's own record id means its reaction row is the game's data rather than
  something invented here — and every Imperial holding in the settlement list
  is a fort or a Legion-garrisoned town, so it isn't much of a stretch. The
  Imperial Cult and the Knights are kept separate, as power-only factions.
- **The reaction rows are vanilla's, transcribed**, with zeros omitted (an
  absent entry already reads as zero) and three classes of exception marked in
  the file: Bloodmoon's East Empire Company and Skaal, which the base game's
  matrix does not contain and whose pairs are therefore guesswork; one
  deliberate override on Redoran's regard for the Sixth House, which vanilla
  puts at 0 alone among the Houses; and `basePower`, which is guesswork
  throughout and the first number to reach for when the starting map looks
  wrong.

  Transcribing costs nothing — the same value merged over the same value — and
  means the pack does not depend on every record id resolving in game, while
  the test suite (which runs against an empty record stub) exercises real
  numbers rather than an empty world.
- **Four factions sit outside the politics, and vanilla says so.** The Morag
  Tong and the Talos Cult have no reactions in either direction; the Nerevarine
  reacts to nobody, though Redoran and the Temple react to it; the Twin Lamps
  hate House Telvanni and are beneath everyone else's notice. `BoP.dumpReactions()`
  reports each as a zero column, which is normally the sign of a mistake — here
  it is the data, and the suite asserts exactly this list so that a *fifth*
  faction arriving in that state fails.

## The starting map is derived, not authored

There is no authored ownership anywhere in this pack. The whole map falls out
of where the settlements are. Registering Balmora as a Hlaalu seat is what
makes the West Gash Hlaalu ground; nobody writes down that the West Gash is
Hlaalu, and nobody writes down that Red Mountain is the Sixth House's — it
holds its own seat because its settlement stands there and nobody else reaches
it.

That's what makes the ~560 generated frontier cells viable — there is no second
list of ownership to keep in step with the first.

Ownership at load, derived:

| Faction | Cells |
|---|---|
| Temple | 96 |
| Redoran | 52 |
| Hlaalu | 42 |
| The Empire | 24 |
| Telvanni | 15 |
| East Empire Company | 6 |
| Ashlanders | 6 |
| Skaal | 3 |
| Sixth House | 1 |
| *unclaimed* | 248 |

493 cells in total — 93 belonging to settlements, 400 frontier. The unclaimed
ones are genuine expansion room: nobody projects above the claim threshold
there *yet*, and since projection has no cut-off, whoever grows enough takes
them. Half the map being unowned at the start is the headroom the frontier
generator plans for, not dead ground.

By cell state at load: 223 consolidated, 22 uncontested, 248 unclaimed and
**nothing contested**. That last figure is correct rather than suspicious —
initial control hands every cell to its strongest projector, so no owner starts
out being out-projected. The map only develops fronts once power moves.

**These numbers want tuning and are the least settled thing in the pack.** The
Temple holding nearly twice what Redoran does is Vivec's metropolis reach
against a scattering of Redoran towns, and mid-tier settlements lost about a
quarter of their claim radius when projection went exponential. Raising the
`village`, `town` and `small city` halving distances is the first lever.

Every minor holding with a faction behind it — 15 of 15 — holds its own cell.
That is the garrison floor working as intended: a farm is a one-cell island of
its owner inside whoever's country surrounds it.

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

| CSV tier | Framework tier |
|---|---|
| Metropolis | `metropolis` |
| Small City | `small city` |
| Town | `town` |
| Village | `village` |
| Outpost/Fortress/Camp | `outpost` |
| Minor location | `minor location` |

Every row becomes a settlement. There is no second category — a farm is a
settlement of the smallest tier, projecting a little and holding its own cell,
which is exactly what a farm should do.

The CSV's vocabulary is Morrowind's and stays in this pack; the right-hand
column is the framework's own ladder. That mapping is the only reason this
table exists, and it is why the framework never learns what a "Small City" is.

`Velothi/Unaffiliated` is not a faction — it marks a holding with no political
owner, which projects nothing and starts unclaimed.

### Corrections applied to the source data

Kept in the build script rather than edited into the CSV, so the original
survives:

- **Thirsk** is promoted from `Minor location` to `Village`. It's a mead hall
  with its own warrior population and a faction behind it, not a farmstead.

Two holdings are dropped outright, because they stand in a cell another holding
already occupies and the simulation has room for one owner per cell. There is
no tier that resolves this: a holding used to be able to duck the collision by
being a power center and not a settlement, projecting into a cell without
claiming it, and now that every holding is a settlement something has to give.

- **Arvs-Drelen** shares cell `-11,11` with Gnisis. A Redoran town outranks a
  Telvanni tower standing in it, so Gnisis takes the cell and the Telvanni lose
  their foothold in the West Gash — the one real casualty of the merge, and the
  place to look if Telvanni influence there ever reads thin.
- **Nilera's Farm** shares cell `4,-8` with Piernette's Farm. Both are Hlaalu
  holdings of the same tier, so which survives changes nothing: projection takes
  the strongest single seat, never the sum.

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

**It will not take Vvardenfell**, and not because a rule forbids it. Nothing
forbids it: projection halves with distance and never stops, so there is no
ground that is unreachable in principle. What stops it is the exchange rate.

Dagoth Ur is an `outpost`, so its halving distance is 3000 units. Reaching two
cells out needs about 880 power; five cells needs 258,000; Balmora, twelve
cells away, needs power in the hundreds of billions. At `growthPerDay = 1.5`
from a base of 30, that is roughly an in-game year and a half for the first
two cells and several centuries for the next three.

So the Sixth House creeps outward from Red Mountain at a decelerating rate and
never realistically leaves the Ashlands — a consequence of arithmetic rather
than a wall, and one that a content pack can change by giving it a bigger seat
rather than by editing the framework.

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

**Every vanilla faction but the Sixth House has no roster yet**, so they field
no patrols —
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
  data/build.lua           holdings -> settlements
```
