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

## Phase 2 — Resolution loop

**Ships:** `core/resolve.lua`.

- `proximityFactor` / `effectivePower` — multi-power-center evaluation taking
  the **strongest** contribution, not the sum (doc 3.2).
- Pass 1: frontier cells roll against rival-held neighbours, gated by cooldown.
- Pass 2: anchors accumulate a siege streak while surrounded, and only become
  contestable once the streak and cooldown both clear.
- `BoP_TerritoryFlipped` and `BoP_AnchorSieged`.
- `resolve.run(day, batch)` takes an explicit batch from the start, so
  staggering resolution later is a scheduling change, not a rewrite.

**Why here:** pure math over the registry and state, with no engine surface at
all. It can be exercised against a hand-written toy landmass before any real
territory data exists.

---

## Phase 3 — Morrowind data pack

**Ships:** `BalanceOfPower_Morrowind` — the second mod.

- The ten territorial factions from doc 5.1, with the merged Empire umbrella.
- ~18–22 anchors with default ownership following vanilla lore placement.
- Frontier grid derived procedurally from exterior cell coordinates and
  bulk-assigned to the nearest anchor, rather than hand-placed.

**Why here:** the first point where territory actually moves in a real game,
and the first real test of whether the framework needed a single line of
Morrowind-specific code. If it did, that's a gap to close before phase 4.

---

## Phase 4 — Spawn subsystem

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
- Commerce: prototype the trade-mode UI diff. Explicitly a stretch goal — there
  is no engine hook for a completed sale (doc 7), so it must not block the MVP.

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

- Player-facing notifications for flips, sieges and liberations.
- Settings page for the tuning constants worth exposing to players.
- Debug console commands.
- l10n for everything player-visible.

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
