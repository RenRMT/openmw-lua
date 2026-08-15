# Balance of Power — Next Steps

Near-term and actionable. The full phase breakdown is in
[implementation-plan.md](implementation-plan.md); repo-wide conventions are in
[CLAUDE.md](../CLAUDE.md).

## State of play

| Phase | Status |
|---|---|
| 1 — Framework skeleton | Done, **confirmed working in-game** |
| 2 — Resolution loop | Done, tested, **never run in-game** |
| 3 — Morrowind pack + frontier generator | Done, tested, **never run in-game** |
| 4a — Patrol decisions, hostility, growth | Done, tested, **never run in-game** |
| 4b — Spawning actual actors | **Blocked** on engine verification — see below |
| 5 — Player hooks | Not started — **recommended next**; commerce dropped |
| 6 — Invasion | **Dissolved.** It was two fields on a faction |
| 7 — Tuning and UX | Not started |

**165 unit tests pass** (`python BalanceOfPower/tests/run.py`), including a suite
that loads the real Morrowind pack through its own `main.lua` headlessly. What
tests cannot cover: whether the faction ids match real ESM records, whether the
derived map looks right against the actual game world, and first-tick timing
across ~600 territories.

Three mods, all on branch `feat/balance-of-power-framework`:

- `BalanceOfPower_Framework` — content-free engine
- `BalanceOfPower_Morrowind` — Vvardenfell and Solstheim
- `BalanceOfPower_Debug` — debug overlay; registers no content, so it
  composes with any content pack

### The one thing most likely to confuse a newcomer

While a territory's owner is also its strongest projector, **no rival roll
happens at all**. Rolls decide how long a takeover takes, not who wins it.
Territory only moves when the projection ordering changes, which happens when
faction power moves.

The map is no longer static: the Sixth House carries `growthPerDay = 1.5`, so
it strengthens every day and its border creeps outward on its own. It will not
reach Vvardenfell proper, though nothing forbids it any more — projection
halves with distance and never stops. What stops it is the exchange rate: from
Dagoth Ur, two cells out costs ~880 power and five cells ~258,000, so it creeps
for an in-game year and a half and then effectively stalls. Nothing pushes it
back yet either, which is phase 5's job.

---

## Step 0 — Load the Morrowind pack and look at the map

Enable `BalanceOfPower_Framework`, then `BalanceOfPower_Morrowind`, then
`BalanceOfPower_Debug` for the hotkeys. The overlay registers no content of
its own, so it composes with the pack rather than colliding with it.

At load you should see roughly:

```
[BalanceOfPower] registered landmass "vvardenfell": 22 factions, 57 settlements over 86 cells, 0 frontier cells
[BalanceOfPower] registered landmass "solstheim": 3 factions, 4 settlements over 7 cells, 0 frontier cells
[BalanceOfPower] generated ~370 frontier cells for "vvardenfell" from ... settlements
[BalanceOfPower] initial control assigned by projection: ~245 territories claimed
```

Then check, in the log or via `luag`:

1. ~~**Which way round do reactions read?**~~ **Settled: a row is the
   faction's own opinions.** Verified in-game on 2026-08-13 and re-verified
   against the raw ESM data on 2026-08-15 — the Nerevarine's record carries no
   reactions at all while Temple and Redoran carry −8 and −4 toward it, which
   only reads one way. The engine's documentation says the reverse and is wrong
   for ESM3; the framework shipped that reading through phases 1–3.

   ~~**Where do reaction values live?**~~ **Settled: the game's records, and
   nowhere else.** The pack's transcribed tables are gone and the registry now
   refuses a `reactions` field, so a faction rebalance mod the player loads
   actually takes effect. All 24 pack ids were confirmed against the FACT
   records, which also closes the old doubt about `temple` — the record is
   `FACT "Temple"` and lookup is case-insensitive.

2. **Run `luag require('openmw.interfaces').BalanceOfPower.dumpReactions()`.**
   **This is the one check that cannot be done headless**, because it is the
   only place the reaction-key casing gets a real answer: the ESM stores keys as
   `"Camonna Tong"` and `"Sixth House"` while the pack registers lowercase ids,
   and whether the engine lowercases them before Lua sees them is unverified.
   The framework normalizes both ends, so this should be a non-event — but a
   *wholesale* collapse of the report means the normalization missed a case.

   Every faction should have a non-zero `moves` *and* `movedBy`, except the ones
   vanilla leaves outside its politics: the Morag Tong, the Talos Cult, the
   Nerevarine, the Twin Lamps, Census and Excise, the Skaal, and the East Empire
   Company (which has a row but no column). The suite asserts exactly that list
   against the real dumped records, so an *additional* zero in-game means a
   record id doesn't match — fix the id in `data/factions.lua`, or set
   `recordId`.

   Then spot-check the direction and the pairs that changed with this rewrite:

   ```
   luag require('openmw.interfaces').BalanceOfPower.regardOf('twin lamps', 'telvanni')  --> -3
   luag require('openmw.interfaces').BalanceOfPower.regardOf('telvanni', 'twin lamps')  --> 0
   luag require('openmw.interfaces').BalanceOfPower.regardOf('redoran', 'sixth house')  --> 0
   luag require('openmw.interfaces').BalanceOfPower.regardOf('east empire company', 'redoran')  --> 1
   ```

   The first two are the direction check. If they come back swapped, stop.
   Record the casing answer in `openmw-lua-api-notes.md` §9a either way.
3. **Any cell-collision warnings?** The build script rejects collisions between
   settlements, but a generated cell overlapping something unexpected would
   show up here.
4. **Does the derived map look like Morrowind?** Ald-Ruhn Redoran, Balmora
   Hlaalu, Sadrith Mora Telvanni, Vivec Temple, Raven Rock EEC. The headless
   test asserts these, but only against the stubbed cell grid.
5. **How long does the first tick take?** ~600 territories resolving in one
   pass. If there's a visible hitch, `FRONTIER_CELLS_PER_UNIT = 2` cuts the
   count roughly fourfold.

6. **Does `dump()` show the Sixth House as hostile, and with the right
   enemies?** The line now carries `[+1.50/day]` and `[hostile: ...]`. A
   hostile faction with an empty enemy list is the failure worth catching — it
   looks identical to a working one until you watch its patrols ignore a rival.
   The suite pins the list against the pack data, but only the game can confirm
   the reaction rows behind it come out as expected once real ESM records are
   merged in.

Then let a week or two of game time pass. Unlike previous phases, **something
should move**: the Sixth House gains 1.5 power a day, so its projection grows
and the cells around Red Mountain change hands. Everything else should stay put
— nothing else grows, and no other faction's ordering changes.

If the whole map starts emptying instead, `GROWTH_PROPAGATES` has been turned
on; see the constant.

---

## Step 1 — Tune the map

Read the map from the console rather than guessing from ownership counts:

```
luag require('openmw.interfaces').BalanceOfPower.dumpMap()
luag require('openmw.interfaces').BalanceOfPower.dumpMap({ mode = 'projection' })
luag require('openmw.interfaces').BalanceOfPower.dumpMap({ mode = 'contest' })
```

`projection` is the one to tune against: it shows the consequence of a range
change immediately, where `owner` only catches up after days of rolls. Combine
with `reloadlua` to edit `config.lua` and see the result without restarting.

The single most important dial is `influenceRange` per tier in the framework's
`config.lua`, because ownership is derived from projection. It is now a
**halving distance**, not a limit: every doubling of a faction's power pushes
its border out by exactly one of them. The ladder runs from 2500 units
(`minor location`) to 14000 (`megalopolis`).

**The mid tiers are the known weak point.** Projection went from linear to
exponential, and weight enters logarithmically now, so low- and mid-weight
settlements lost more reach than large ones did. A `town` claims out to ~1.7
cells at base power where the linear model gave it ~2.3, which is most of why
Redoran dropped from 88 cells to 52 and Hlaalu from 68 to 42. Raising `village`,
`town` and `small city` is the first thing to try.

Scaling the whole ladder was measured rather than guessed: x1.25 gives 609
territories and 40% unclaimed, x1.5 gives 757 and 36%, x2.0 gives 1032 and 32%.
The map fills, but the territory count is the performance risk in doc 7, so
prefer raising the middle of the ladder over all of it.

Things to look for:

- **Regions that read wrong.** If the Ascadian Isles come out Temple rather
  than Hlaalu, Vivec's `metropolis` range is drowning the plantation belt. The
  Temple now holds 96 cells to Hlaalu's 42, which is the most suspicious number
  on the map.
- **Too much unclaimed ground.** 248 cells of 493 start unowned — half the
  map. Some of that is deliberate: `FRONTIER_GENERATION_POWER` plans for twice
  the base power, so the generated map has a doubling of headroom to grow into.
  Lower it for a tighter map, raise it for more room, and note the fraction
  follows from that ratio alone — the tier ranges cancel out of it.
- **Whether `SEAT_FLOOR = 250` is right.** It makes a settlement takeable only
  by roughly ten times a faction's starting standing, and every minor holding
  with a faction behind it — 15 of 15 — keeps its own cell. Raise it for more
  stubborn one-cell islands; lower it to let a strong invader take a city.
- **Telvanni at 15 cells.** Sadrith Mora is a `small city` where it used to
  project at what is now `large city` reach, and the exponential decay took
  another bite out of the mid tiers. Whether that is a correction or an
  over-correction is a question for the map, not the table.
- **Ashlanders holding almost nothing** (6 cells). Their camps are
  `outpost` tier, which may be too weak for a faction that nominally roams the
  whole Ashlands.

Per-settlement overrides sit on the settlement, so a pack can give Telvanni
long weak reach and Hlaalu short strong reach without touching the framework.

---

## Step 2 — Pick the next system

### Phase 4b — spawning actual actors *(blocked)*

The decision layer is done and tested; what's left touches the engine and can't
be settled from here. Four facts to check in-game, in order of how much depends
on them:

1. **Do runtime-created NPC records survive a save/load?** Decides whether a
   pack can make generic actors in Lua at all, or must ship them in its own
   `.omwaddon`. A save containing actors whose records vanish on reload is a
   broken save, not a cosmetic bug.
2. **Is an actor's AI `fight` value settable?** If so, hostility should set it
   and let the engine handle approach and re-aggro. If not, it's a `Combat`
   package, and hostile actors charge across the cell like missiles.
3. **Can GameObjects live in `onSave` data?** Decides whether despawn tracking
   survives a reload or has to be rebuilt by sweeping `world.activeActors`.
4. **Does teleporting a created object into a cell place it correctly?**
   GitLab #7453 is a leveled-list bug, but it's close enough to this path to be
   worth five minutes.

Then it needs the framework's first `PLAYER` script: navmesh queries are in
`openmw.nearby` (local context) and `world.createObject` is global, so
placement is decided player-side and creation happens global-side.

**Also still content work:** only the Sixth House has a patrol roster. The
eight vanilla factions need real record ids, and those have to be verified
against the game rather than guessed — a wrong id fails silently, since the
framework never inspects one. Until then those factions field nothing, which
is the empty-roster rule working as intended.

### Phase 5 — player influence hooks *(recommended)*

Quest completion and faction rank feeding `awardPower`. Commerce is dropped.

**Why this one now:** the Sixth House grows every day and nothing pushes back,
so the only arc currently available is a slow slide. Counter-play is what makes
ambient growth a story rather than a countdown. It needs an authored quest →
faction map, which is data entry, but the mechanism underneath it already works
and is tested.

---

## Deferred, but don't forget

- **`FRONTIER_GENERATION_MARGIN` is 0 for a reason.** Influence decays to
  exactly zero at `influenceRange`, so ground beyond it can never be held by
  anyone. Only raise it for a pack where settlements can appear at runtime.
- **`adjacentFrontier` on frontier cells is tracked but unread.** Only settlements
  use theirs. Kept deliberately, exposed through the API, available when a
  later phase wants real adjacency.
- **Turn off `DEBUG` and `DEBUG_DAILY_SUMMARY`** in `config.lua` before any
  release.
- **Solstheim is at its Anthology position.** Anyone playing vanilla Bloodmoon
  gets Solstheim territory in the wrong cells. Documented in the pack README;
  worth a compatibility note if this is ever released.
- **Faction reputation setter** — still unconfirmed whether one exists. Power
  stays fully separate from vanilla reputation.
- **Commerce hook** — dropped by decision. Out of scope for the framework.
- **Graphical map overlay** — investigated and deferred (August 2026); the
  text map (`dumpMap`) covers the debugging need instead. Findings worth
  keeping so this doesn't get re-researched:
  - There is **no map API in Lua**. Nothing exposes the map window's pan
    offset, zoom or screen rect, so a true overlay aligned to the vanilla map
    is impossible without an engine change. `I.UI.registerWindow` can only
    *replace* the map window, and the map art isn't reachable from Lua.
  - A **standalone schematic political map** on its own UI layer is about a
    day's work, and cheap because the frontier is already a 1:1 exterior-cell
    grid: cell to pixel is `(x - minX) * size`, and `getOwner` / `classify` /
    `getReach` already return everything a renderer needs.
  - Unverified risk: ~600 `Image` widgets in one element. Prototype with a
    stub grid before committing.
  - It belongs in its own optional mod, not the framework or a content pack.
- **The framework has no "give me the current state" call for player scripts.**
  Events fire on change only, and the API is global-context, so any UI mod
  needs a request/response bridge like the debug overlay improvises. Worth adding
  a snapshot event before phase 7, independent of whether the map ever gets
  built.

---

## Open questions

- **What the player sees when territory changes hands out of view.** Your
  answer was cut off mid-sentence — "expose the relevant information either
  through the log or an API, and …". The events already fire and carry the
  detail; what's undecided is whether anything surfaces it by default.
- **How minor factions eventually influence the map.** They're power-only for
  now and deliberately so, but the note was that this "needs later refinement".
  A guild presence probably ought to mean *something* territorially.
- **Whether the Great Houses need mainland capitals before Tamriel Rebuilt.**
  Every settlement in the list is `is_capital = No`, so no Vvardenfell holding
  is currently a faction's true seat.
