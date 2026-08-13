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
`registry`, `power`, `driver`, `api`, `main`. Plus `BalanceOfPower_Debug`, an
on-screen debug console. (It shipped as a self-contained toy world, and was
rewritten during phase 3 into a content-agnostic overlay that registers nothing
and composes with any content pack.)

- Registration API (`registerLandmass`, later `generateFrontier`) with
  validation and cross-pack faction merging via `extend = true`.
  `registerInvasion` also shipped here, and was removed in the phase-3
  follow-up that moved invasion out of the framework entirely.
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
- Pass 2: settlements. Shipped as a siege system — streak while surrounded,
  then a roll against `defenseMultiplier` — and **later removed**. Settlements
  are now claimed once and held; being surrounded is observed and published,
  and nothing in the framework acts on it. See the decision below.
- `BoP_TerritoryFlipped`, `BoP_SettlementSurrounded`, `BoP_SettlementRelieved`.
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
  settlements, built from a CSV by a script rather than hand-written.
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
- Minor holdings (farms, shacks, mines) are power centers but not settlements.
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

## Phase 3a — Narrowing the framework's remit

Not originally a phase. It came out of a code review that asked whether the
framework/pack split still held, and the answer was that the framework had
quietly acquired mechanics.

**The decision:** the framework models **influence and ownership, and nothing
else.** The competition it simulates is non-violent — borders move, seats do
not. Everything that acts on the result is an extension.

Removed outright: `registerInvasion`, invasion stages, corruption, and the
whole settlement siege system (`siegeThreshold`, `defenseMultiplier`,
`siegeStreak`, and the roll that could take a city).

**Why settlements stopped changing hands.** Morrowind was not built for cities
changing owner, and a mechanic for taking them would be bolted onto a game with
nowhere to put the consequences. A settlement is now claimed once and then
held.

**What replaced the mechanics:**

- `isSurrounded(territoryId)` and `surroundedSince(territoryId)` — the fact,
  published, with nothing acting on it. It stays in the framework because
  answering it needs the frontier ownership map, and every extension that cares
  would otherwise derive the same thing from the same data.
- `BoP_DayResolved` — the scheduling hook. Removing the mechanics from
  `runDay()` left extensions with no way to run in step with the daily pass,
  and a private timer would drift. This is the one thing the split *required*
  the framework to gain.

**Also settled here:** the vocabulary. `anchor` became `settlement`, and
[glossary.md](glossary.md) became the authority — with *cell* and *territory*
pinned as different things, which they had been used as if they were not.

**And then the model followed the vocabulary.** Once *cell* and *territory*
were pinned apart, the fact that a settlement was one territory over fifteen
cells stopped looking like a convenience and started looking like the source of
the confusion. So **every territory became exactly one cell**, and a settlement
became a group tagged across them.

That let the last special case go. Settlements no longer take a separate
resolution path: every cell in the world runs the same rule, and what holds a
city is `SEAT_FLOOR` — a garrison floor on a faction's projection at a cell its
own power centre occupies. A rule with no exceptions beat a rule that read
slightly more directly, because weight 0 gives a floor of 0 and an unaffiliated
ruin falls out correctly with nothing written about it.

Ownership also became continuously governed by the claim threshold rather than
only at first claim: a cell nobody can hold is released rather than staying on
the books, and a roll now requires the challenger to be above the threshold.
`classify()` became a four-way partition where `unclaimed` means exactly "no
owner".

---

## Phase 4 — Patrols

Un-parked, and the framework's remit widened to take it. Phase 3a's rule was
that anything acting on ownership is an extension, which put spawning outside;
the rule now is that **the framework owns the mechanisms that make ownership
observable, and decides nothing about who or what.** A territory system nobody
can see is a spreadsheet. The cross-cutting test is unchanged: no faction id,
no record id, no `if landmass ==` in `core/`.

### 4a — the decision layer ✅

**Ships:** `core/patrol.lua`, `core/hostility.lua`, and ambient growth in
`core/power.lua`.

- `planPatrol(territoryId, day)` — who fields how many of what, and who fights
  whom. Pure: it creates nothing and touches no actor.
- Eligibility from two different questions. The owner patrols ground it holds;
  a hostile faction patrols anywhere it projects above a floor, which is what
  makes an invader visible on a border before it takes anything.
- Roster tiers, so strength scales without mutating an actor's stats.
- Hostility as one opt-in rule over the reaction table, replacing what was
  scoped as three features.
- `growthPerDay`, which is what makes the map move on its own.

**Design decisions settled here:**

- **A faction with an empty roster fields no patrols.** The whole opt-out, with
  no flag and no `territorial` check.
- **The spawn roll is seeded on `(territory, day)`, not random.** Without it,
  re-entering a cell rerolls, and every patrol becomes a renewable source of
  the gear and gold a vanilla record carries.
- **Hostility defaults to nobody.** Derived from reaction values alone it would
  have Redoran and Telvanni fighting in the street, which is wrong about
  vanilla.
- **Ambient growth does not propagate.** A daily drip through the reaction
  table compounds where a one-off award does not; at the pack's own numbers it
  empties the entire map inside an in-game year.
- **Roster tiers are numbers, not names.** A name would be content.

**Two bugs the tests caught**, both of which produce a plausible-looking world
rather than an error:

- The spawn seed was built as `"territory@day"`, which left the hash nearly
  linear in the day — consecutive days landed 0.000008 apart, so a cell stayed
  lucky or unlucky for hundreds of days and the map had almost no patrols on
  it. The day goes first now.
- `build.factionsFor` in the Morrowind pack copied a hand-listed set of fields
  and had been silently dropping `patrolRoster` for as long as the field
  existed.

### 4b — the actor layer *(blocked)*

**Ships:** the module that creates, places and clears up actors, plus the
framework's first `PLAYER` script.

Blocked on engine facts that can't be settled headlessly: whether runtime NPC
records survive a save, whether AI `fight` is settable, whether GameObjects can
live in `onSave` data, and whether teleport-into-cell places reliably.

It also forces a two-script design: navmesh queries are in `openmw.nearby`
(local context) and `world.createObject` is global, so placement is decided
player-side and creation happens global-side. That is what settles the ocean
question — spawning only in owned cells excludes almost all water already, and
a navmesh check covers the coastal remainder without an authored exclusion
list.

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

## Phase 6 — Invasion subsystem *(dissolved)*

**There is no invasion mod.** The subsystem turned out to be two fields on an
ordinary faction, which is the strongest possible version of the claim this
phase existed to test — an invader isn't a specialization of the faction
engine, it's a faction with different numbers.

The Sixth House in the Morrowind pack carries `growthPerDay = 1.5` and
`hostile = true`, and everything the phase was scoped to build falls out:

- **Ambient growth on a curve** — the field.
- **Escalation stages** — emergent. Projection is power scaled by distance
  decay, so at low standing the Sixth House reaches barely past Red Mountain
  and its patrols appear near Ghostgate; the radius grows with its power. No
  stage table.
- **Spawn radius and roster tier gated by strength** — both already scale with
  projection, for every faction equally.
- **Taking settlements** — it can't, and neither can anyone. Not a gap.

What's genuinely gone rather than absorbed: **corruption**, a flag distinct
from ownership, with the services and ambience changes that would follow. If it
ever gets built it belongs in an extension over `BoP_DayResolved` and the
ownership map, and needs nothing from the framework it doesn't already expose.

Also still missing: **counter-play**. Nothing pushes the Sixth House back, so
its power only ever climbs. That's phase 5's quest hooks, which makes phase 5
the thing standing between this and a playable arc.

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
views), `forceDay`, and the debug overlay's hotkeys.

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
