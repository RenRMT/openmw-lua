# Balance of Power — Next Steps

Near-term, actionable. The full phase breakdown is in
[implementation-plan.md](implementation-plan.md); this is what to do next and
what to decide before doing it.

**Where things stand:** phase 1 (framework skeleton) is written but has never
been executed — there's no Lua interpreter in the dev environment, so it has
only been checked structurally. Nothing is committed.

---

## Step 0 — Run it (do this first)

Everything below assumes phase 1 actually works. It has not been proven to.

1. Enable `BalanceOfPower_Framework` and `BalanceOfPower_DevSandbox` (in that
   order) per the [sandbox README](BalanceOfPower_DevSandbox/README.md).
2. Work through the checklist there: registration, propagation, forced day,
   validation rejection, cell walking, save/reload.
3. Fix whatever breaks. Realistic candidates, in rough order of likelihood:
   - a syntax or nil-indexing error in a path that was never run;
   - `I.BalanceOfPower` being nil in the sandbox, if interface availability at
     script-body time doesn't work the way the load order implies;
   - faction ids not matching the real ESM records (`hlaalu`, `imperial legion`
     and `sixth house` are assumed lowercase, per the ESM3 convention noted in
     the API notes) — if reaction propagation moves nobody, this is why;
   - `onKeyPress` not firing, or `input.KEY.F10` differing in name.
4. Get CI green (luacheck has never run against this code either).

Only then start phase 2.

---

## Step 1 — Phase 2: the resolution loop

New file: `core/resolve.lua`. Called from `driver.runDay()`, which already has
the call site marked.

### Tasks

- [ ] `proximityFactor(distance, influenceRange)` — linear decay to zero, per
      design doc 3.4.
- [ ] `effectivePower(faction, territory)` — evaluate every power center and
      take the **strongest**, not the sum (doc 3.2). Needs a distance helper;
      `util.vector2` is available, and centroids are stored as `{x, y, z}` with
      z ignored.
- [ ] `powerRoll(atkEffective, defEffective)` — `math.random()` against the
      attacker's share.
- [ ] Pass 1, frontier: for each frontier cell adjacent to rival-held ground,
      skip if within `cooldownDays` of `lastFlipped`, else roll. On success,
      flip, stamp `lastFlipped`, fire `BoP_TerritoryFlipped`.
- [ ] Pass 2, anchors: maintain `siegeStreak` against `isSurrounded()`, fire
      `BoP_AnchorSieged` each day it advances, and only roll once both the
      streak and the cooldown clear — with the defender's effective power
      multiplied by `defenseMultiplier`.
- [ ] `resolve.run(day, batch)` taking an explicit territory batch.
- [ ] Add `SURROUND_SHARE` to `config.lua` (what fraction of an anchor's
      adjacent frontier must be rival-held to count as surrounded).

### Decisions to make first

- **Who is "the attacker" for a given territory?** The doc never says. Options:
  the strongest rival by `effectivePower` at that location (deterministic,
  cheap, tends to produce steady fronts), or a weighted random pick among
  rivals with a foothold (noisier, more surprising). Recommend the former for
  the MVP — it's easier to debug, and the frontier already supplies the
  variety.
- **What makes a frontier cell contestable at all?** Adjacency to a
  rival-held cell is the obvious rule, but unclaimed cells (`defaultOwner`
  omitted) need a rule too: are they free to take by anyone adjacent, or inert?
  Recommend free to take, with no defender, so the map can fill in.
- **Freshly-flipped territory: hard cooldown, or a temporary defense bonus?**
  Doc 3.4 floats the bonus as reading better narratively ("the new owner is
  consolidating") but the schema currently has `cooldownDays`. Pick one before
  writing pass 1 — supporting both is not worth it.

### How to test it without the Morrowind pack

The sandbox's four frontier cells and three anchors are enough: two factions
with adjacent holdings and a rival between them. Push Hlaalu with `Ctrl+F11`
until it outweighs the Legion, then `Ctrl+Shift+F12` to run a week and watch
whether the frontier creeps in the right direction and stops at the anchors.
Add more frontier cells to the sandbox if the graph is too small to show a
front forming.

---

## Step 2 — Phase 3 prep: the frontier grid generator

Phase 3's real cost is data, not code, and the frontier grid is the part that
must not be hand-authored (doc 3.2 explicitly derives it).

- [ ] Decide grid granularity: raw exterior cells (finest, most cells) or 2×2 /
      3×3 blocks (cheaper per tick, coarser creep). This determines how many
      units the daily loop evaluates and is the main lever on the performance
      risk in doc 7.
- [ ] Write the generator: walk `world.cells`, filter to exteriors in the
      landmass's bounding region, compute centroids from grid coordinates,
      derive adjacency from grid neighbours, and bulk-assign `defaultOwner` from
      the nearest anchor.
- [ ] Decide **when** it runs: at load in the pack's global script (simple,
      costs startup time, always matches the installed game), or offline into a
      generated `data/frontier.lua` (fast at runtime, must be regenerated when
      the landmass changes). Recommend at load for the MVP — it's the option
      that can't go stale.
- [ ] Decide where the generator lives. It's landmass-agnostic, so it's
      arguably framework code — but it reads `world.cells`, which makes it
      feel like content tooling. If it goes in the framework, it must not
      assume Vvardenfell's bounds.

---

## Deferred, but don't forget

- **A headless test harness.** The core modules are pure Lua apart from their
  `openmw.*` requires. Stubbing those and running the registry/power/resolve
  logic under plain Lua would catch the class of error that currently can only
  be found by launching Morrowind. Worth doing before phase 2's math lands —
  roll-heavy code is exactly what benefits.
- **Turn off `DEBUG` and `DEBUG_DAILY_SUMMARY`** in `config.lua` before any
  release.
- **Load-order documentation** for users, once there's more than one content
  mod (doc 7).
- **Commerce hook** (phase 5) — still has no engine support; prototype the
  trade-mode UI diff early enough to know whether it's viable, but never let it
  block the MVP.
- **Faction reputation setter** — unconfirmed whether one exists. Keep power
  fully separate from vanilla reputation until verified.

---

## Open questions for later phases

- Vivec as one anchor or per-district (doc 5.2 says one for the MVP; districts
  would be the first real test of dense adjacency).
- Whether the merged Empire faction feels flat enough to split in phase 2 of the
  expansion path.
- What the player actually *sees* when a territory flips out of view. Phase 7
  question, but worth deciding before phase 4's spawn work, since patrols are
  the main channel for communicating a change without a UI.
