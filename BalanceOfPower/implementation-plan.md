# Balance of Power — Implementation Plan

Build order for [the design document](balance-of-power-design-doc.md). This is
the *development* sequence; section 6 of the design doc is a different axis —
which landmasses get content packs, and in what order, after the MVP works.

For the immediate, actionable version — what to do next and what to decide
first — see [next-steps.md](next-steps.md).

The ordering principle throughout: build the layers that produce numbers before
the layers that produce visible actors, and keep the invasion subsystem last so
it has to prove the doc's central claim — that an invader is a specialization of
the ordinary faction engine, needing no new machinery.

---

## Phase 1 — Framework skeleton ✅

**Ships:** `BalanceOfPower_Framework` — `config`, `log`, `events`, `state`,
`registry`, `power`, `driver`, `api`, `main`. Plus `BalanceOfPower_DevSandbox`,
a throwaway pack and on-screen debug console for testing it before the real
Morrowind data exists.

- Registration API (`registerLandmass`, `registerInvasion`) with validation and
  cross-pack faction merging via `extend = true`.
- Faction power: get/set/apply, reaction-driven propagation with the
  vanilla-record-or-authored-table indirection.
- Atomic per-pass batching, so no roll can be influenced by another roll that
  resolved earlier in the same pass.
- Persistent state with central default-fill, so a content update that adds a
  faction or territory works on an existing save.
- In-game day tick driver, polled against the game calendar so it survives
  sleeping and fast travel.
- Event bus.

**Why first:** everything else plugs into these. The save-compatibility
default-fill (doc 3.3) and the power-snapshot seam (doc 3.4) are both far
cheaper to build now than to retrofit — the doc flags both as the kind of thing
that becomes a bug once resolution is split across buckets.

**Observable result:** the framework loads and reports an empty world. With a
pack registered, `dump()` shows factions and their power, and `awardPower`
moves a faction and everyone with an opinion about it.

---

## Phase 2 — Resolution loop ✅

**Ships:** `core/resolve.lua`, plus a headless test suite under `BalanceOfPower/tests/`.

- `proximityFactor` / `effectivePower` — multi-power-center evaluation taking
  the **strongest** contribution, not the sum (doc 3.2).
- Initial control derived from power centers, so a generated frontier grid
  needs no hand-authored ownership. An authored `defaultOwner` overrides it.
- Pass 1: frontier cells, contestable regardless of adjacency, gated by
  cooldown. The attacker is whoever projects most; the roll decides how long
  the takeover takes, not who wins it.
- Pass 2: anchors accumulate a siege streak while surrounded, and only become
  contestable once the streak and cooldown both clear, with the defender's
  projection multiplied by `defenseMultiplier`.
- `BoP_TerritoryFlipped` and `BoP_AnchorSieged`.
- `resolve.run(day, batch)` takes an explicit batch from the start, so
  staggering resolution later is a scheduling change, not a rewrite.

**Why here:** pure math over the registry and state, with no engine surface at
all. It can be exercised against a hand-written toy landmass before any real
territory data exists — which is exactly what the test suite added alongside it
does.

**Design decisions settled here** (the open questions from the previous plan):

- The attacker at a territory is whichever faction projects the most power onto
  it — deterministic, no random selection among rivals.
- Ownership is derived from projection at initialization, subject to a
  configurable `MIN_CLAIM_POWER` floor for taking ground nobody holds.
- Frontier cells are always contestable; there is no adjacency gate, because
  proximity decay already prevents a faction from taking ground it can't reach.
- Freshly flipped territory gets a hard cooldown, not a temporary defence bonus.

**Also corrected here:** the design doc's illustrative `influenceRange = 6000`
is smaller than one exterior cell (8192 units), so a capital would have
projected onto nothing but its own cell and no frontier cell would ever have
been contested. Tier defaults are now sized in cells.

---

## Phase 3 — Morrowind data pack ✅

**Ships:** `BalanceOfPower_Morrowind`, plus `core/frontier.lua` in the
framework.

- 63 settlements across Vvardenfell and Solstheim, 36 of them contestable
  anchors, built from a CSV by a script rather than hand-written.
- Eight land-holding factions and six power-only ones.
- Frontier grid derived at load from the registered power centers: ~560 cells,
  averaging 1.2 factions able to reach each.
- The Sixth House invasion, homeland at Red Mountain.

**Why here:** the first point where territory actually moves in a real game,
and the first real test of whether the framework needed a single line of
Morrowind-specific code. It didn't — the generator works off power centers and
never learns what a "Small City" is; that vocabulary stays in the pack's own
`data/build.lua`.

**Design decisions settled here:**

- `territorial = false` now means **power-only**: the faction has standing and
  propagates through the reaction table, but holds no ground and projects
  nothing. That's the guild/Great House split. A faction that shouldn't
  participate at all is simply not registered.
- Frontier granularity is one territory per exterior cell, behind
  `FRONTIER_CELLS_PER_UNIT`.
- Generation runs at load, not offline, so it can never go stale.
- Only ground within reach of a power center becomes territory.
- Minor holdings (farms, shacks, mines) are power centers but not anchors.
- Solstheim is a separate landmass registered by the same pack, at its
  **Anthology / Tamriel Rebuilt** position rather than vanilla Bloodmoon's.

**Also corrected here:** the projection cache. Distance geometry is static, so
it's computed once at load as a factor per (territory, faction) pair; the daily
pass is then a multiplication with no square roots, and each territory carries
the short list of factions that can actually reach it.

**A bug the numbers caught:** the generation margin created territory beyond
every power center's influence range — where projection is exactly zero no
matter how strong a faction becomes, so the cells were permanently unownable.
482 of 904 on the Morrowind pack. The margin now defaults to zero.

---

## Phase 4 — Spawn subsystem *(deferred by request)*

Explicitly parked. Everything below it can proceed without it; the cost is that
territory stays invisible in-world until it lands.

**Ships:** `core/spawn.lua`.

- Player cell entry looks up the territory, its owner, and spawns 1–3 roster
  actors with a `Wander` package, friendly to the player.
- Lighter spawn density on frontier cells than on anchors.
- A `Combat` package instead of ambient wandering where a rival is already
  present in contested ground.

**Why here:** the first visible half of the mod, and it's only meaningful once
ownership actually varies. Triggering on cell entry rather than on ownership
change also keeps spawns tightly gated to player proximity, which is the main
lever against the performance risk in doc 7.

---

## Phase 5 — Player influence hooks

- Quest completion watcher against an authored quest → faction map.
- Faction rank as the `awardPower` multiplier, via `NPC.getFactionRank`.

**Commerce is dropped**, not deferred. There is no engine hook for a completed
sale, the UI-mode-diff workaround is fragile, and it was judged out of scope for
the framework. `awardPower` remains available to any mod that wants to build it
externally.

**Note:** the mechanism this phase feeds already works and is tested — this
phase is the *sources* that call it, which is mostly data entry (the quest →
faction map). That makes it lower value per hour than phase 6.

---

## Phase 6 — Invasion subsystem

**Ships:** `core/invasion.lua` plus the Sixth House config in the Morrowind pack.

- Ambient power growth on a curve, independent of player action.
- Escalation stages gating spawn radius, roll frequency and roster tier.
- Corruption on a won territory — a flag distinct from plain ownership — with
  `BoP_TerritoryCorrupted` / `BoP_TerritoryLiberated`.
- Amplified counter-play: player kills and quest completions against the
  invader push its power back at a higher rate than ordinary awards.

**Why last:** it's a specialization of phases 1–5, and building it last is what
proves the claim. If it needs new engine code rather than new configuration,
the abstraction has a gap.

---

## Phase 7 — Tuning and UX

- Player-facing notifications for flips, sieges and liberations. **How much the
  player sees should be configurable**, and the underlying detail exposed
  through the log and the API rather than only as notifications.
- A snapshot call so a player script can ask for current state. Events fire on
  change only, and the API is global-context, so any UI mod currently needs a
  request/response bridge of its own. Needed before any UI work.
- Settings page for the tuning constants worth exposing to players.
- l10n for everything player-visible.

Debug tooling is already done: `dump`, `dumpMap` (owner / projection / contest
views), `forceDay`, and the dev sandbox's hotkeys.

A graphical map overlay was investigated and deferred — there is no map API in
Lua, so a true overlay on the vanilla map is impossible without an engine
change. Findings are recorded in [next-steps.md](next-steps.md).

**Why last:** there's nothing to tune until the numbers exist, and every string
written before phase 6 is a string rewritten after it.

---

## Cross-cutting checks

- **The framework never names content.** The day `core/` needs
  `if landmass == 'cyrodiil'`, the abstraction has failed (doc 3.8).
- **Adding a landmass means writing a pack, not editing the framework.** If a
  phase requires framework edits, close that gap before moving on (doc 6).
- **Every tunable is a named constant in `config.lua`,** never inlined (doc 7).
- **New state sections and new registered entities must load on an old save**
  via `state.deserialize` / `state.fillDefaults` (doc 3.3).
