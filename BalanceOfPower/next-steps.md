# Balance of Power — Next Steps

Near-term, actionable. The full phase breakdown is in
[implementation-plan.md](implementation-plan.md); this is what to do next and
what to decide before doing it.

**Where things stand:** phases 1 and 2 are written. Phase 1 has been confirmed
working in-game. Phase 2 (territory resolution) has 51 passing unit tests but
has **not** been seen running in Morrowind yet.

---

## Step 0 — Watch a front move

Phase 2's maths is tested; its behaviour in a real session isn't.

1. Load with the sandbox enabled and confirm the derived starting map matches
   the projection table in the
   [sandbox README](BalanceOfPower_DevSandbox/README.md) — nothing but Red
   Mountain has an authored owner any more, so if the map looks right, initial
   assignment works.
2. `Ctrl+F7` ×4, then `Ctrl+Shift+F12` a few times, checking `Ctrl+F6` between
   each. The raiders should take Bitter Coast north, then east, then put Seyda
   Neen under siege, then eventually take it.
3. Confirm Balmora does **not** fall to the same treatment — the city defence
   multiplier is what reserves real city flips for the invasion subsystem.
4. Save, reload, and confirm ownership and the siege streak survive.

Two behaviours are easy to misread as bugs and are not:

- A cell whose owner is also the strongest projector is never rolled for. Rolls
  decide how long a takeover takes, not who wins it.
- A cell that just changed hands is protected by its cooldown even if the
  balance immediately swings back.

---

## Step 1 — Phase 3: the Morrowind data pack

This is the big one, and its cost is data, not code.

### The frontier grid generator

Doc 3.2 explicitly derives the frontier rather than hand-authoring it, and
phase 2's derived initial control means the generator doesn't have to assign
ownership at all — only geometry.

- [ ] **Decide granularity.** Raw exterior cells (finest, most units to
      resolve) or 2×2 / 3×3 blocks (cheaper per tick, coarser creep). This is
      the main lever on the performance risk in doc 7. Vvardenfell is roughly
      50×60 cells, so raw cells means a few thousand frontier units — worth
      measuring a daily pass at that size before committing.
- [ ] **Decide when it runs.** At load in the pack's global script (simple,
      costs startup time, can never go stale) or offline into a generated
      `data/frontier.lua` (fast at runtime, must be regenerated when the
      landmass changes). Recommend at load.
- [ ] **Decide where it lives.** It's landmass-agnostic, so it's arguably
      framework code — but it reads `world.cells`, which makes it feel like
      content tooling. If it goes in the framework it must not assume
      Vvardenfell's bounds.
- [ ] Write it: walk `world.cells`, filter to exteriors in the landmass's
      bounding region, compute centroids from grid coordinates (cell size is
      8192; centre is `grid * 8192 + 4096`), and derive `adjacentAnchors` from
      proximity. `adjacentFrontier` is only used for the anchor surround check
      now, so frontier-to-frontier links can be skipped entirely unless a later
      phase wants them.

### The factions and anchors

- [ ] The ten territorial factions from doc 5.1, with the merged Empire.
- [ ] ~18–22 anchors with real coordinates.
- [ ] **Tune `influenceRange` per faction against the real map.** This is now
      the single most important tuning surface: it decides the entire starting
      map, since ownership is derived from projection. Expect to iterate.
      Telvanni towers are far apart and should probably have long, weak reach;
      Hlaalu's holdings are clustered and should have short, strong reach.
- [ ] Verify the derived starting map against vanilla lore placement, and only
      author `defaultOwner` where the derivation genuinely can't be made to
      produce the right answer.

---

## Step 2 — Phase 4: spawns

Unchanged from the original plan, but now unblocked: ownership actually varies,
so patrols have something to reflect. Cell-change detection is polling the
player's `cell` field (the sandbox already does this on a 1-second timer);
there's no dedicated engine event for it.

---

## Deferred, but don't forget

- **Should taking territory move faction power?** Currently it doesn't —
  territory is downstream of power, never upstream. Adding a feedback loop
  would make conquest self-reinforcing and could easily run away. Worth
  considering deliberately once there's a real map to watch, not before.
- **Frontier resolution cost at scale** (doc 7). Every territory is evaluated
  against every faction each day. Fine at sandbox size; measure at Vvardenfell
  size. The mitigation is already scoped: only resolve cells near a contested
  boundary, and leave firmly-interior ones idle.
- **`adjacentFrontier` on frontier cells is now unused.** Only anchors read it.
  Harmless, but the phase 3 generator shouldn't spend effort producing it.
- **Turn off `DEBUG` and `DEBUG_DAILY_SUMMARY`** in `config.lua` before any
  release.
- **Commerce hook** (phase 5) — still no engine support; prototype the
  trade-mode UI diff early enough to know whether it's viable, but never let it
  block the MVP.
- **Faction reputation setter** — unconfirmed whether one exists. Keep power
  fully separate from vanilla reputation until verified.

---

## Open questions for later phases

- Vivec as one anchor or per-district (doc 5.2 says one for the MVP; districts
  would be the first real test of dense adjacency).
- Whether the merged Empire faction feels flat enough to split.
- What the player actually *sees* when a territory flips out of view. Phase 7
  question, but worth deciding before phase 4's spawn work, since patrols are
  the main channel for communicating a change without a UI.
