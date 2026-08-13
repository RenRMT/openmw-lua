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
| 4 — Spawns | Parked by request |
| 5 — Player hooks | Not started; commerce dropped |
| 6 — Invasion | Not started — **recommended next**, as a separate mod |
| 7 — Tuning and UX | Not started |

**120 unit tests pass** (`python BalanceOfPower/tests/run.py`), including a suite
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
faction power moves. A static map is the correct behaviour right now, because
nothing yet moves power on its own — that arrives with phase 6.

---

## Step 0 — Load the Morrowind pack and look at the map

Enable `BalanceOfPower_Framework`, then `BalanceOfPower_Morrowind`, then
`BalanceOfPower_Debug` for the hotkeys. The overlay registers no content of
its own, so it composes with the pack rather than colliding with it.

At load you should see roughly:

```
[BalanceOfPower] registered landmass "vvardenfell": 15 factions, 33 settlements over 64 cells, 0 frontier cells
[BalanceOfPower] registered landmass "solstheim": 3 factions, 3 settlements over 4 cells, 0 frontier cells
[BalanceOfPower] generated ~540 frontier cells for "vvardenfell" from ... power centers
[BalanceOfPower] initial control assigned by projection: ~456 territories claimed
```

Then check, in the log or via `luag`:

1. ~~**Which way round do record reactions read?**~~ **Settled 2026-08-13:
   outbound.** Verified against the asymmetric Telvanni / Twin Lamps pair.
   `RECORD_REACTIONS_ARE_INBOUND` is now `false`; it shipped `true` — the
   reading OpenMW's own documentation gives — and propagated every asymmetric
   vanilla pair backwards for three phases.

   Worth an audit while playing: the pack's authored rows are inbound by
   convention, and hostility now reads the same table. An author writing
   Hlaalu's row and typing `['sixth house'] = -3` may have meant "Hlaalu hates
   them" where the convention says the reverse. The values are near-symmetric
   so it mostly won't show, which is exactly why it needs checking rather than
   assuming.

2. **Run `luag require('openmw.interfaces').BalanceOfPower.dumpReactions()`.**
   Every faction should have a non-zero `moves` *and* `movedBy`. A zero in
   either column means a faction is outside the politics in that direction.
   The suite asserts this against an empty record stub, so a zero appearing
   in-game means a record id doesn't match — most likely `temple`, whose exact
   id wasn't verifiable outside the game. Fix by correcting the id in
   `sources/build_settlements.py` / `data/factions.lua`, or by authoring the
   missing side of the relationship.
3. **Any cell-collision warnings?** The build script rejects collisions between
   settlements, but a generated cell overlapping something unexpected would
   show up here.
4. **Does the derived map look like Morrowind?** Ald-Ruhn Redoran, Balmora
   Hlaalu, Sadrith Mora Telvanni, Vivec Temple, Raven Rock EEC. The headless
   test asserts these, but only against the stubbed cell grid.
5. **How long does the first tick take?** ~600 territories resolving in one
   pass. If there's a visible hitch, `FRONTIER_CELLS_PER_UNIT = 2` cuts the
   count roughly fourfold.

Then let a week of game time pass and see whether anything moves. With no
player influence and nothing growing the Sixth House, the answer *should* be "almost
nothing" — power is static, so the projection ordering never changes. Territory
moving on its own at this stage would be a bug.

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
`config.lua`, because ownership is derived from projection. Current values are
~5 / ~3 / ~1.5 / ~1.2 cells for capital / regional / outpost / minor.

Things to look for:

- **Regions that read wrong.** If the Ascadian Isles come out Temple rather
  than Hlaalu, Vivec's `capital` range is drowning the plantation belt.
- **Too much unclaimed ground.** 174 cells start unowned. That's expansion
  room, but if it's mostly interior rather than coastal, ranges are too short.
- **Whether `SEAT_FLOOR = 250` is right.** It makes a settlement takeable only
  by roughly ten times a faction's starting standing, and gives minor holdings
  their own cell 16 times out of 17. Raise it for more stubborn one-cell
  islands; lower it to let a strong invader take a city.
- **Ashlanders holding almost nothing** (6 cells). Their camps are
  `outpost` tier, which may be too weak for a faction that nominally roams the
  whole Ashlands.

Per-faction overrides go on the power center, so a pack can give Telvanni long
weak reach and Hlaalu short strong reach without touching the framework.

---

## Step 2 — Pick the next system

Phase 4 is parked, so there are two candidates. They're independent.

### Phase 6 — the invasion subsystem *(recommended)*

**A separate mod**, not `core/invasion.lua`. The framework no longer knows what
an invasion is, and shouldn't: escalation, corruption and taking settlements
are mechanics, and the framework's remit is influence and ownership.

The Sixth House is already an ordinary faction in the Morrowind pack, holding
Red Mountain and reaching barely past it. What the invasion mod adds is
everything that acts on that.

It reads through the interface — `getOwner`, `getEffectivePower`, `getReach`,
`classify`, `isSurrounded`, `surroundedSince` — writes through `awardPower`,
and runs off `BoP_DayResolved`. It keeps its own state in its own global
script's `onSave`/`onLoad`.

The data that used to live in `data/invasions/sixth_house.lua`, kept here
because it's the only place it now exists:

```lua
growthPerDay = 1.5,                     -- ~3 weeks to raiding, ~4 months to overrunning
homeTerritories = { 'dagoth_ur' },
escalationThresholds = {
    { stage = 'stirring',    power = 30 },
    { stage = 'raiding',     power = 60 },
    { stage = 'encroaching', power = 100 },
    { stage = 'overrunning', power = 150 },
},
```

The patrol roster moved onto the faction in `data/factions.lua` and is still
carried by the framework.

**Why this one:** it's the first thing that makes the map move on its own, so
it's the first time the simulation is worth watching without a debug key. It's
also the sharpest test of the boundary — if an invasion can be built entirely
on top of the interface, the split is real.

**The first thing to check when building it:** whether `BoP_DayResolved` is
delivered soon enough to be useful, and whether the one-day lag from queued
event delivery matters. If it does, poll `getCurrentDay()` instead.

### Phase 5 — player influence hooks

Quest completion and faction rank feeding `awardPower`. Commerce is dropped.

**Why not first:** it needs an authored quest → faction map, which is a lot of
data entry for a mechanism that's already proven (`awardPower` works).

---

## Deferred, but don't forget

- **`FRONTIER_GENERATION_MARGIN` is 0 for a reason.** Influence decays to
  exactly zero at `influenceRange`, so ground beyond it can never be held by
  anyone. Only raise it for a pack where power centers can appear at runtime.
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
