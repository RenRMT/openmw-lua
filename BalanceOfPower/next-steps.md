# Balance of Power — Next Steps

Near-term, actionable. The full phase breakdown is in
[implementation-plan.md](implementation-plan.md).

**Where things stand:** phases 1–3 are written. Phase 1 has been confirmed
working in-game. Phases 2 and 3 have 78 passing unit tests, including one suite
that loads the real Morrowind pack headlessly, but have **not** been seen
running in Morrowind. Phase 4 (spawns) is parked by request.

---

## Step 0 — Load the Morrowind pack and look at the map

Enable `BalanceOfPower_Framework` then `BalanceOfPower_Morrowind` — **not** the
dev sandbox, which defines the same factions and will collide.

At load you should see roughly:

```
[BalanceOfPower] registered landmass "vvardenfell": 14 factions, 33 anchors, 0 frontier cells
[BalanceOfPower] registered landmass "solstheim": 3 factions, 3 anchors, 0 frontier cells
[BalanceOfPower] registered invasion "sixth_house" (faction "sixth house"): 1 home territories, 4 stages
[BalanceOfPower] generated ~540 frontier cells for "vvardenfell" from ... power centers
[BalanceOfPower] initial control assigned by projection: ~500 territories claimed
```

Then check, in the log or via `luag`:

1. **Any "has no reactions" warnings?** Each one names a faction whose id
   doesn't match a real faction record and has no authored table. Most likely
   candidates are `sixth house`, `ashlanders` and `temple`, whose exact record
   ids weren't verifiable outside the game. Fix by correcting the id in
   `sources/build_settlements.py` / `data/factions.lua`, or by authoring a
   `reactions` table.
2. **Any cell-collision warnings?** The build script rejects collisions between
   settlements, but a generated cell overlapping something unexpected would
   show up here.
3. **Does the derived map look like Morrowind?** Ald-Ruhn Redoran, Balmora
   Hlaalu, Sadrith Mora Telvanni, Vivec Temple, Raven Rock EEC. The headless
   test asserts these, but only against the stubbed cell grid.
4. **How long does the first tick take?** ~600 territories resolving in one
   pass. If there's a visible hitch, `FRONTIER_CELLS_PER_UNIT = 2` cuts the
   count roughly fourfold.

Then let a week of game time pass and see whether anything moves. With no
player influence and no invasion growth yet, the answer *should* be "almost
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
- **Too much unclaimed ground.** ~176 cells start unowned. That's expansion
  room, but if it's mostly interior rather than coastal, ranges are too short.
- **Ashlanders holding almost nothing** (3 territories). Their camps are
  `outpost` tier, which may be too weak for a faction that nominally roams the
  whole Ashlands.

Per-faction overrides go on the power center, so a pack can give Telvanni long
weak reach and Hlaalu short strong reach without touching the framework.

---

## Step 2 — Pick the next system

Phase 4 is parked, so there are two candidates. They're independent.

### Phase 6 — the invasion subsystem *(recommended)*

`core/invasion.lua`. The Sixth House is already registered, holds Red Mountain,
and has thresholds defined; nothing yet grows it or acts on the stages.

- Ambient growth per day, and stage transitions firing `BoP_InvasionEscalated`.
- Corruption: a flag distinct from ownership, with `BoP_TerritoryCorrupted` /
  `BoP_TerritoryLiberated`.
- Stage gating on how far the invader will roll from its homeland.

**Why this one:** it's the first thing that makes the map move on its own, so
it's the first time the simulation is worth watching without a debug key. It's
also the design's central claim — that an invader needs no new engine — and
that claim is now cheap to test.

### Phase 5 — player influence hooks

Quest completion and faction rank feeding `awardPower`. Commerce is dropped.

**Why not first:** it needs an authored quest → faction map, which is a lot of
data entry for a mechanism that's already proven (`awardPower` works).

---

## Deferred, but don't forget

- **`FRONTIER_GENERATION_MARGIN` is 0 for a reason.** Influence decays to
  exactly zero at `influenceRange`, so ground beyond it can never be held by
  anyone. Only raise it for a pack where power centers can appear at runtime.
- **`adjacentFrontier` on frontier cells is tracked but unread.** Only anchors
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
  needs a request/response bridge like the dev sandbox improvises. Worth adding
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
