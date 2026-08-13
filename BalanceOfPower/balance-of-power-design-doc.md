# Balance of Power & Foreign Invasion — Design Document

**Status:** Original planning draft — **historical**. Kept because the reasoning
behind the design is worth having, but it is no longer a description of what
exists. For what was actually built and why, read
[implementation-plan.md](implementation-plan.md); for the current state,
[next-steps.md](next-steps.md).

**Target engine:** OpenMW Lua (0.51+)
**Scope of this document:** two coupled systems — (1) a faction Balance of Power framework, (2) a generalized foreign-invasion subsystem built on top of it. MVP target: base Morrowind factions + a single invading faction (Sixth House, origin Red Mountain).

---

## 0. What has been superseded

Decisions taken during phases 1–3 that contradict the text below. Everything
else still holds.

| This document says | What was actually built | Where |
|---|---|---|
| `influenceRange = 6000` | 40000 / 24000 / 12000 / 10000 by tier. 6000 is smaller than one exterior cell (8192), so a capital would have projected onto nothing but its own cell | §3.1, §3.2 |
| `territorial = false` excludes a faction from the territory *and* power loop | It means **power-only**: the faction has standing and propagates through the reaction table, but holds no ground and projects nothing. That's the guild / Great House split. A faction that should not participate at all is simply not registered | §5.1 |
| Frontier `defaultOwner` bulk-assigned from the nearest anchor | Ownership is **derived from projection**, for anchors and frontier alike. An authored `defaultOwner` is an override, used only for the invasion homeland | §3.2 |
| Roughly 18–22 anchors | 36 contestable anchors out of 63 settlements, across Vvardenfell **and Solstheim** | §5.2 |
| Anchor tiers `town` / `city` | Five: `outpost`, `village`, `town`, `city`, `metropolis`. Power-center tiers gained `minor` | §3.1 |
| Morag Tong excluded | Registered as a power-only faction, along with the Fighters, Mages and Thieves Guilds, the Imperial Cult and the Camonna Tong | §5.1 |
| "Anchor" for a territory containing a settlement | Renamed **settlement** throughout. The word never read as the opposite of "frontier", and its justification was internal — see [glossary.md](glossary.md), which is now the authority on every term in this document | everywhere |
| Frontier cells contestable via adjacency to rival-held ground | Contestable unconditionally. Proximity decay already *is* the adjacency rule — a faction with no foothold nearby projects nothing and cannot win | §3.4 |
| Commerce as a stretch goal | Dropped. No engine hook exists, and it was judged out of scope for the framework | §3.6, §7 |
| Homeland "Red Mountain interior + Ghostgate approach" | Dagoth Ur alone, from the settlement list | §5.3 |

Two further decisions the document leaves open, since resolved:

- **Who attacks a territory** — whichever faction projects the most power onto
  it. Deterministic; no random selection among rivals.
- **Cooldown vs. temporary defence bonus** after a flip (§3.4 floats both) — a
  hard cooldown.

One clarification worth stating, because it is the least obvious consequence of
the design and is easy to mistake for a bug: **while a territory's owner is also
its strongest projector, no rival roll happens at all.** The roll decides how
long a takeover takes, not who wins it.

---

## 1. Goals & Scope

- Track faction **power** (a number) and **territory control** (cell/settlement ownership) for Morrowind's political factions.
- Let ally/enemy relationships (sourced from the vanilla faction reaction table) propagate power changes between factions.
- Reflect territory control in the world via dynamic, disposition-appropriate patrols — friendly to the player, cosmetic/flavor rather than a hard gate.
- Layer a **foreign invasion** subsystem on top: a faction type that expands by force from a homeland, corrupts territory it takes, and can be pushed back.
- MVP: Vvardenfell only, vanilla factions only, Sixth House as the sole invader.
- Long-term: the same framework should onboard Tamriel Rebuilt, Province Cyrodiil, and Skyrim: Home of the Nords **without modifying the core framework code** — only by adding new data packs.
- Everything implementable in Lua; no Construction Set / new ESM records required for the MVP (reuse vanilla NPC and faction IDs throughout).

---

## 2. Mod Architecture Decision

**Recommendation: framework mod + content data-pack mod(s), shipped initially as two physical files, but coded as three logically separate layers from day one.**

### Why not one mod?
A single monolithic mod means every future landmass (TR, Cyrodiil, Skyrim) requires editing the same file that vanilla depends on. That's fragile, makes compatibility patches harder for other people, and forces every user to load all landmass data even if they only own Vvardenfell.

### Why not fully split into many mods immediately?
For an MVP, standing up four separate mod packages (framework, Morrowind data, Sixth House data, plus scaffolding for three unwritten landmasses) is overhead you don't need yet. The important thing isn't the number of `.omwscripts` files today — it's that the *code* doesn't blur the boundary between "engine" and "content," so splitting later is a file move, not a rewrite.

### The three logical layers

| Layer | Contains | Depends on |
|---|---|---|
| **Framework (core)** | Territory/power data structures, resolution loop, propagation math, spawn engine, registration API, events | Nothing else in this project |
| **Landmass data pack** (e.g. Morrowind, later TR/Cyrodiil/Skyrim) | Territory definitions, faction list, adjacency graph, default ownership, spawn rosters | Framework |
| **Invasion data pack** (e.g. Sixth House) | One or more `InvadingFaction` definitions, homeland territory, escalation config | Framework, and loosely the landmass pack it invades into |

### MVP packaging

- **Mod A — `BalanceOfPower_Framework`**: zero faction/territory data. Pure engine + public API. This is the piece that stays untouched as you expand to other landmasses.
- **Mod B — `BalanceOfPower_Morrowind`**: vanilla faction list, Vvardenfell territory map, adjacency graph, patrol rosters, *and* the Sixth House invasion config, kept in its own subfolder/namespace inside this mod (`data/invasions/sixth_house.lua`) so it can be lifted into its own mod later without touching anything else.

This gets you to a working MVP with two files instead of four, while keeping the seam in the right place for when Sixth House (or a future invader) needs to become independently toggleable, or when TR/Cyrodiil/Skyrim packs get written by you or someone else against the same framework API.

---

## 3. System 1: Balance of Power Framework

### 3.1 Data schemas

```lua
-- Power center: one seat of a faction's influence (static, authored per landmass pack)
PowerCenter = {
  id = "balmora",
  coords = { x = ..., y = ... },
  landmass = "vvardenfell",
  tier = "capital",       -- "capital" | "regional" | "outpost" — see 3.2
  weight = 1.0,             -- fraction of faction power this center projects; outposts default lower
  influenceRange = 6000,     -- world units at which effective power from this center decays to ~0
}

-- Faction definition (static, authored per landmass pack)
Faction = {
  id = "hlaalu",              -- matches vanilla faction record id where applicable
  displayName = "House Hlaalu",
  territorial = true,          -- false = flavor-only faction, excluded from territory/power loop
  basePower = 50,
  powerCenters = {                -- a faction can have any number, across any number of landmasses
    { id = "balmora", coords = {...}, landmass = "vvardenfell", tier = "capital", weight = 1.0, influenceRange = 6000 },
    { id = "caldera_holdings", coords = {...}, landmass = "vvardenfell", tier = "outpost", weight = 0.25, influenceRange = 1500 },
  },
  patrolRoster = { "hlaalu guard", ... },   -- vanilla NPC record ids, reused as-is
  landmass = "vvardenfell",      -- the faction's "home" landmass; individual power centers carry their own
}

-- Anchor territory: a named settlement, hand-authored (static, per landmass pack)
Territory = {
  id = "balmora",
  displayName = "Balmora",
  tier = "city",                        -- "town" | "city" — see 3.2
  cells = { "Balmora", "#-3,-2", "#-2,-2" },  -- interior name(s) + exterior grid cells
  adjacentFrontier = { "west_gash_grid_a4", "west_gash_grid_a5", ... },  -- surrounding frontier cells, not other anchors
  defaultOwner = "hlaalu",
  landmass = "vvardenfell",
  siegeThreshold = 5,                   -- consecutive surrounded daily checks required before an attempt can occur
  cooldownDays = 30,                    -- minimum days between successful flips
}

-- Frontier cell: fine-grained wilderness unit (derived, not hand-placed one-by-one — see 3.2)
FrontierCell = {
  id = "west_gash_grid_a4",
  centroid = { x = ..., y = ... },
  adjacentFrontier = { "west_gash_grid_a3", "west_gash_grid_a5", "west_gash_grid_b4" },
  adjacentAnchors = { "balmora" },       -- which anchors treat this cell as part of their "surrounded" check
  defaultOwner = "hlaalu",
  landmass = "vvardenfell",
  cooldownDays = 3,
}
```

### 3.2 Anchors vs. frontier: the two-tier territory model

A flat territory list (as originally scoped) can't smoothly show a faction's influence creeping outward — a single coarse "West Gash wilderness" blob can only jump all at once, which is either noisy (if fine-grained) or static (if coarse). Splitting territory into two tiers gets both properties at once:

- **Anchors** — settlements, exactly as originally designed: hand-authored, named, tiered (`town`/`city`), patrol-bearing, and what any future UI would actually surface to the player. These are hard to take.
- **Frontier cells** — the wilderness between anchors, at a finer grain (raw exterior grid cells, or a light 2–3 cell block grouping as a performance compromise). Each has a centroid for distance math. These roll daily and are the layer that actually creeps — this is where "faction influence slowly encroaching" becomes visible.

An anchor's own flip eligibility is gated by its frontier: it only becomes contestable once a threshold share of its `adjacentFrontier` cells have already gone to a rival (see 3.4). The frontier is the leading edge; the settlement is what that edge has to fully reach before anything dramatic happens.

Frontier cells don't need individual hand-placement — derive them procedurally from `world.cells` exterior grid coordinates within each landmass's bounding region, then bulk-assign `defaultOwner` from whichever anchor's territory they fall nearest to. This keeps authoring cost close to the original coarse-territory design while getting a finer simulation grid for free.

**A faction can hold multiple power centers**, including across different landmass packs — e.g. Hlaalu anchored at Balmora on Vvardenfell and at Bal Foyen once a Tamriel Rebuilt pack is loaded, plus any number of minor `outpost`-tier holdings authored with a shared low default weight/range so they don't need individual tuning. When computing effective power at a given cell, evaluate every power center's proximity-decayed contribution and take the **strongest**, not the sum:

```lua
local function effectivePower(faction, cell)
  local best = 0
  for _, pc in ipairs(faction.powerCenters) do
    local d = distanceBetween(cell.centroid, pc.coords)
    best = math.max(best, faction.power * pc.weight * proximityFactor(d, pc.influenceRange))
  end
  return best
end
```

Summing would let a faction out-project a rival purely by accumulating minor outposts, which isn't the intended story — max-combination says a cell is under the influence of whichever foothold is nearest, which is both more defensible and cheaper to reason about when tuning. Deliberate cumulative reinforcement between nearby footholds, if ever wanted, should be an explicit opt-in on top of this, not the default.

### 3.3 Runtime state & persistence

```lua
state.power        -- factionId -> number
state.ownership     -- territoryId (anchor or frontier) -> factionId
state.siegeStreak    -- anchorId -> consecutive surrounded-day count
state.lastFlipped     -- territoryId -> game-day timestamp (for cooldowns)
```

All persisted through the mod storage API, and all default-filled on load: if a save predates a new faction/territory added by a mod update, missing keys are initialized from the static config rather than erroring. This is the main save-compatibility hazard for a framework meant to be extended after release — handle it once, centrally, rather than per data pack.

### 3.4 Resolution loop

Run once per in-game day. `resolve.run(territoryBatch)` takes an explicit batch of territories rather than implicitly meaning "resolve the whole world" — for the MVP the daily-tick driver calls it once with every registered territory, but keeping the batch explicit is what makes staggering (see below) a scheduling change later rather than a rewrite of the resolution logic itself.

Each pass uses the multi-center `effectivePower` from 3.2, in two passes:

**Pass 1 — frontier cells.** For each frontier cell adjacent to rival-held ground, skip it if still within `cooldownDays` of its last flip; otherwise roll using **distance-decayed** power rather than raw faction power:

```lua
local function proximityFactor(distance, influenceRange)
  return math.max(0, 1 - distance / influenceRange)
end

local function powerRoll(atkEffective, defEffective)
  return math.random() < atkEffective / (atkEffective + defEffective)
end
```

(`effectivePower` itself is defined once in 3.2 and reused everywhere power needs to be evaluated at a location — frontier rolls, anchor sieges, and anywhere else a "how strong is faction X here" question comes up.)

A successful roll flips the cell, stamps `lastFlipped`, and fires `BoP_TerritoryFlipped`. Because effective power decays with distance from each faction's nearest power center, contested ground naturally sits at the rough midpoint between two footholds rather than being deterministically owned by whichever faction currently has the higher raw power score — this is what produces the "slow encroachment" feel rather than a coin-flip that could jump anywhere.

**Pass 2 — anchors.** For each anchor, check whether it's currently "surrounded" (a threshold share — configurable, majority or all — of its `adjacentFrontier` cells are rival-held):

```lua
territory.siegeStreak = isSurrounded(territory) and (territory.siegeStreak + 1) or 0
if territory.siegeStreak >= territory.siegeThreshold
   and (currentDay - territory.lastFlipped) >= territory.cooldownDays then
  -- only now attempt a roll, with the owner's effective power multiplied
  -- by a defense bonus (garrison/walls), heavily favoring the defender
  local defEffective = effectivePower(ownerFaction, territory) * territory.defenseMultiplier
  local atkEffective = effectivePower(attackerFaction, territory)
  if powerRoll(atkEffective, defEffective) then
    -- flip anchor, stamp lastFlipped, fire BoP_TerritoryFlipped
  end
end
```

`city`-tier anchors should have a `defenseMultiplier` high enough that ordinary faction-vs-faction politics essentially can't take them — reserve real city flips for the invasion subsystem's `overrunning` stage (Section 4), matching how vanilla lore treats the Great Houses: Balmora doesn't change hands over a trade dispute, but "the Sixth House is currently sacking it" is a legitimate exception. `town`-tier anchors can use a lower threshold and multiplier so they're rare but not effectively impossible.

An optional refinement: rather than a hard cooldown-based immunity, give a freshly-flipped territory a temporary *defense bonus* for its new owner instead of an outright roll-skip. Mechanically similar, but reads better narratively — "the new owner is consolidating" rather than "the rules forbid this."

This loop is landmass-agnostic in both passes — it just iterates whatever territories and frontier cells are currently registered, regardless of which pack they came from. This is the mechanism that lets adjacency bridge across landmass packs later (e.g., a Tamriel Rebuilt mainland frontier cell adjacent to a Vvardenfell one) with no special-casing.

**Timing: single tick for MVP, staggered later.** Resolve everything in one pass at day rollover for the MVP — it's simpler to reason about and debug, and at MVP scale (~20 anchors, a few hundred frontier cells for one landmass) the cost is trivial table math. At multi-landmass scale, a single synchronous pass across a much larger graph is more likely to produce a hitch, and it also reads worse — a wall of a dozen simultaneous "territory changed hands" notifications is worse UX than the same changes trickling in through the day. Because `resolve.run` already takes an explicit batch, staggering later just means a different driver that partitions territories into buckets and runs each bucket on its own smaller timer, skipping buckets with no contested boundary — the resolution function itself doesn't change. Whichever timing strategy is active, **snapshot faction power at the start of a pass and apply all deltas atomically at the end**, rather than letting one roll's outcome affect another roll evaluated later in the same pass — otherwise results become order-dependent on which territory happens to resolve first, which is an easy bug to introduce once resolution is split across buckets that may not have an obvious canonical order.

### 3.5 Power propagation

As designed previously: pull each faction's `reactions` map (either from `core.factions.records[id].reactions` for vanilla-sourced factions, or an authored table for new factions that don't exist as real ESM faction records), clamp to [-3, 3], scale by a tunable `INFLUENCE_STRENGTH`, and apply directionally — the *reacting* faction's own attitude determines how much it moves in sympathy or opposition.

```lua
function power.apply(factionId, delta, opts)
  power.set(factionId, power.get(factionId) + delta)
  for otherId, reactionValue in pairs(reactionsFor(factionId)) do
    if otherId ~= factionId and factions.get(otherId).territorial then
      power.set(otherId, power.get(otherId) + delta * allyCoefficient(reactionValue))
    end
  end
end
```

`reactionsFor` is an indirection point deliberately: for vanilla factions it reads `core.factions.records`, for authored/new factions (a future TR house, a Skyrim faction, an invading faction with no real ESM record) it falls back to a hand-written reactions table in that faction's definition. Same propagation math either way.

### 3.6 Player influence hooks

Exposed as one function other systems call into, so quest mods, dialogue mods, or your own future content can award power without knowing anything about the internals:

```lua
BalanceOfPower.awardPower(factionId, baseDelta, playerRankMultiplier)
```

MVP sources for this call:
- **Quest completion** — via `Player.quests` (quest id → territory/faction mapping authored per landmass pack).
- **Faction rank** — read via `types.NPC.getFactionRank(player, factionId)` as the multiplier.
- **Commerce** — flagged as the shakiest piece (see Section 7); implement as a stretch goal via a UI-trade-mode diff, not a blocking MVP requirement.

### 3.7 Spawn subsystem

Triggered on player cell entry, not on ownership change — see prior discussion. Looks up the entered cell's territory (anchor or frontier), current owner, spawns 1-3 actors from that faction's `patrolRoster` with a `Wander` package, friendly to the player by default. Anchors warrant a full patrol roster; frontier cells can use a lighter, more sparsely-spawned roster so the wilderness doesn't feel over-populated relative to before. If a rival or invader spawn is already present in a contested territory, issue a `Combat` package between them instead of pure ambient wandering.

### 3.8 Registration API

The seam that makes this generalizable:

```lua
BalanceOfPower.registerLandmass({
  id = "vvardenfell",
  factions = { ... },
  territories = { ... },
})

BalanceOfPower.registerInvasion({
  id = "sixth_house",
  faction = { ... },        -- an InvadingFaction, see Section 4
})
```

Data packs call these once at world init. The framework never imports a data pack directly — data packs depend on the framework, never the reverse. This is the rule to protect most carefully as the project grows: the day the framework needs an `if landmass == "cyrodiil"` branch is the day the abstraction has failed.

**Cross-pack faction identity.** A faction like Hlaalu logically spans multiple landmass packs (Balmora on Vvardenfell, Bal Foyen once Tamriel Rebuilt is loaded). `registerLandmass` needs an explicit merge policy for this: if a faction id already exists in the registry, an incoming pack marks its entry `extend = true` to signal "append to the existing faction" — its power centers, patrol roster entries, and any authored reaction overrides get merged in — rather than silently overwriting or creating a duplicate faction under the same id.

```lua
BalanceOfPower.registerLandmass({
  id = "tamriel_rebuilt",
  factions = {
    { id = "hlaalu", extend = true, powerCenters = { {...bal foyen...} }, patrolRoster = {...} },
  },
  territories = { ... },
})
```

Load order matters here: whichever pack registers a faction first defines its `basePower`/`displayName`/base config, and every later pack must use `extend = true` against that same id rather than redefining it.

### 3.9 Events

Fire these globally so UI mods, quest mods, or your own later systems can react without editing framework code:

- `BoP_TerritoryFlipped { territory, from, to }`
- `BoP_AnchorSieged { territory, streak, threshold }` — fires each day an anchor's siege streak advances, useful for a "the town is under pressure" notification well before a flip is even possible
- `BoP_PowerChanged { faction, delta, newTotal }`
- `BoP_InvasionEscalated { invasion, oldStage, newStage }`
- `BoP_TerritoryCorrupted` / `BoP_TerritoryLiberated` (invasion-specific, see 4.4)

---

## 4. System 2: Invasion Subsystem

### 4.1 Concept

An invasion is a **specialized faction type** layered on the same territory/power engine, not a parallel system. It reuses adjacency rolls, patrol spawning, and the event bus — it just has a different power-growth source and a different consequence when it wins a territory.

Key differences from an ordinary territorial faction:

- **Grows from a homeland, not commerce.** An invading faction has one or more `homeTerritories` it always controls and effectively can't lose (or can only lose at very high narrative cost). Its power grows on a timer/curve rather than (only) through player commerce/quests in the way ordinary factions do.
- **Escalation stages**, not just a raw number. Power maps to a small number of discrete stages that gate behavior (spawn radius, roll frequency, roster strength).
- **Winning a territory corrupts it** rather than just changing a flag on a map. This should read as a crisis, distinct from routine faction politics.

### 4.2 Data schema: Invading Faction

```lua
InvadingFaction = {
  id = "sixth_house",
  displayName = "Sixth House",
  homeTerritories = { "red_mountain_interior", "ghostgate_approach" },
  basePower = 30,
  growthPerDay = 1.5,               -- ambient drift, independent of player action
  escalationThresholds = {
    { stage = "stirring",    power = 30  },
    { stage = "raiding",     power = 60  },
    { stage = "encroaching", power = 100 },
    { stage = "overrunning", power = 150 },
  },
  patrolRoster = { "ash ghoul", "ash zombie", "dagoth cultist", ... },  -- vanilla ids
  landmass = "vvardenfell",
}
```

Because Sixth House's vanilla reaction row is strongly negative toward nearly everyone, and everyone's reaction toward Sixth House is strongly negative back, the existing propagation math already produces the right story for free: as Sixth House grows, every ordinary territorial faction takes a small ambient power hit (a shared existential threat), and every point of ground clawed back from Sixth House gives everyone else a small lift (relief after a crisis). No special-casing needed — this is a direct payoff of reusing the disposition table rather than hand-authoring a separate ally/enemy list.

### 4.3 Escalation stages

| Stage | Trigger | Effect |
|---|---|---|
| Dormant | Below first threshold | No rolls against neighbors, no spawns beyond homeland |
| Stirring | Power ≥ threshold 1 | Occasional roving cultist spawns near the homeland border; homeland-adjacent territories begin rolling |
| Raiding | Power ≥ threshold 2 | Roll frequency increases; corrupted territories possible |
| Encroaching | Power ≥ threshold 3 | Wider spawn radius; stronger roster tier unlocked |
| Overrunning | Power ≥ threshold 4 | Full aggression; reserved for a late-game "things have gone very wrong" state — should be rare/hard to reach in normal play, and is a good hook for tying into main-quest pacing later |

Thresholds and growth rate are exposed constants — this is the primary tuning surface for playtesting pacing, and should not be buried in logic.

### 4.4 Corruption / overrun mechanic

When an invading faction wins a territory roll, don't just flip `ownership[territory] = "sixth_house"`. Instead:

1. Set a `corrupted = true` flag on the territory (separate from plain ownership, so UI/other systems can distinguish "politically annexed" from "overrun").
2. Fire `BoP_TerritoryCorrupted` — this is the hook for suppressing normal services/vendors in that cell, swapping ambient sound/lighting if you want to go further later, and spawning the invader's patrol roster instead of a normal one.
3. To flip it back, require the *previous owner or an ally* to win a roll against it, and fire `BoP_TerritoryLiberated` on success — this is a distinct, better-telegraphed event than a routine ownership change, worth a on-screen notification even in the MVP.

### 4.5 Player counter-play

For the MVP, keep this modest: player quest completions and combat kills against the invader's roster within a corrupted or contested territory feed into `power.apply("sixth_house", negativeDelta)` at an amplified rate compared to ordinary faction power awards (an `invasionPressureMultiplier`, separate constant). This gives the player a legible way to visibly push the invasion back without needing new quest content — it works on top of vanilla Sixth House-related kills and quests that already exist.

---

## 5. MVP Scope (Morrowind + Sixth House)

### 5.1 Territorial factions

From the reaction table, factions to include as territory-holding, power-tracked actors:

- Ashlanders
- Camonna Tong
- Fighters Guild
- Hlaalu
- Redoran
- Telvanni
- Temple
- Thieves Guild
- Mages Guild
- **Empire** (merged umbrella of Imperial Legion / Imperial Cult / Imperial Knights for MVP — they aren't independently territorial in vanilla; split them apart later if it earns its complexity)

Excluded from territory/power for MVP (flavor-only, `territorial = false`, or omitted entirely): Blades, Census and Excise, vampire clans (Aundae/Berne/Quarra), Morag Tong, Nerevarine, Talos Cult, Twin Lamps. Their reaction rows are mostly zero/quest-specific and don't represent real territorial politics — revisit if a later feature wants them (e.g., vampire clans as wilderness-only hostile spawns, à la the original warring-factions inspiration).

Sixth House is the sole `InvadingFaction`.

### 5.2 Territory map (starting list — adjust after playtesting)

Roughly 18–22 **anchors**: Seyda Neen, Pelagiad, Balmora, Suran, Vivec (treated as one anchor for MVP, not per-district), Molag Mar, Ald-ruhn, Maar Gan, Gnisis, Khuul/Dagon Fel, Caldera, Sadrith Mora, Tel Branora/Tel Vos/Tel Mora (Telvanni holdings, could be one or split), plus Red Mountain interior + Ghostgate approach (Sixth House homeland). `city`-tier: Balmora, Ald-ruhn, Vivec, Sadrith Mora; the rest `town`-tier for MVP.

Surrounding them, a **frontier grid** derived from exterior cell coordinates covers the Grazelands, Ashlands, West Gash, Bitter Coast, Azura's Coast, and Sheogorad regions — this replaces what would otherwise have been single coarse "wilderness" territories, and is what actually shows a faction's influence creeping toward or away from Red Mountain over time.

Default ownership follows vanilla lore placement (Redoran → Ald-ruhn/Ashlands, Hlaalu → Balmora/Suran/Pelagiad, Telvanni → their towers, Ashlanders → the wilderness camps' surrounding territories, Empire → Ebonheart-adjacent and garrison towns, Temple → Vivec/Molag Mar, etc.).

### 5.3 Sixth House invasion config

Homeland: Red Mountain interior + Ghostgate approach. Adjacent contestable territories at MVP launch: Ashlands wilds, Molag Mar, Maar Gan — the ring immediately around Red Mountain, matching vanilla geography and the base-game's own Sixth House cultist placements.

---

## 6. Roadmap / Expansion Path

1. **Phase 1 (MVP):** Framework + Morrowind data pack + Sixth House invasion, as scoped above. Pure console-observable power/ownership first, then patrols, then player hooks, then invasion — same phased build order discussed earlier in this design process.
2. **Phase 2:** Split remaining vanilla factions in (vampire clans as non-territorial hostile wilderness spawns), separate Empire into its three sub-factions if the merged version feels flat.
3. **Phase 3 — Tamriel Rebuilt pack:** new territories on the mainland, adjacency bridges connecting Vvardenfell territories to mainland ones across existing travel routes/geography. This is also where the multi-power-center mechanism (Section 3.2) earns its keep: Hlaalu's TR pack registers Bal Foyen as an `extend = true` power center on the same `hlaalu` faction id rather than a new faction, so the existing capital at Balmora and the new regional seat at Bal Foyen both project influence simultaneously. House Dres (present in TR, absent from the vanilla reaction table you started from) will need an authored reactions table rather than a `core.factions.records` lookup — this is exactly the fallback path built into `reactionsFor` in Section 3.5.
4. **Phase 4 — Province Cyrodiil pack:** Imperial-centric territories; the MVP's merged "Empire" faction is a natural anchor to split into its Cyrodiil-relevant sub-identities here. Candidate for a second, Cyrodiil-flavored `InvadingFaction`.
5. **Phase 5 — Skyrim: Home of the Nords pack:** Nordic factions; another candidate invader pack.

The health check for the framework at each phase: adding a landmass should only ever mean writing a new data pack and calling `registerLandmass`/`registerInvasion`. If a phase requires editing framework code, that's a signal the abstraction has a gap worth fixing before moving on, not a normal cost of expansion.

---

## 7. Open Risks & Design Questions

- **Commerce detection has no clean engine hook today.** No confirmed "sale completed" event as of current OpenMW Lua docs — only an open feature request for barter interaction. Plan to prototype the UI-trade-mode-diff workaround early, and treat it as optional/stretch for MVP rather than a blocker.
- **Faction reputation setter status is unconfirmed.** If you ever want power to also nudge vanilla NPC disposition, verify a setter exists in your target OpenMW version before depending on it — treat the power score as fully separate from vanilla reputation until then.
- **Balance tuning is unknown until playtested.** Expose every constant (`INFLUENCE_STRENGTH`, growth rates, roll frequency, invasion thresholds) as named, easily-edited values from the start rather than inlining them.
- **Save compatibility across content updates.** Central default-fill logic (Section 3.3) needs to exist before you ship the first update that adds a territory or faction to an existing save.
- **Performance at multi-landmass scale.** Vvardenfell alone at ~20 anchors is trivial; TR + Cyrodiil + Skyrim combined could mean 100+ anchors and a much larger adjacency graph. The daily resolution loop should stay cheap (it's just table math), but re-check patrol-spawn frequency and actor counts once the map grows — gate spawns tightly to player proximity as already planned, and consider capping how many territories resolve per tick if the graph gets large.
- **Frontier-grid resolution cost.** The anchor/frontier split (Section 3.2) multiplies the number of units the daily loop evaluates, since frontier cells are far more numerous than anchors. Mitigate by only actively resolving frontier cells within some radius of a currently-contested boundary, and leaving firmly-interior cells (deep inside one faction's territory, no rival within N hops) idle until something nearby changes.
- **Cross-mod load order.** Content packs must load after the framework; if you split Sixth House out of the Morrowind pack later, it must load after both the framework and the Morrowind pack (for territory adjacency to resolve). Worth documenting explicitly once there's more than one content mod.

---

## 8. Suggested File Layout (MVP)

```
BalanceOfPower_Framework/
  core/resolve.lua
  core/power.lua
  core/spawn.lua
  core/invasion.lua
  core/api.lua            -- registerLandmass, registerInvasion, awardPower, events
  main.lua                -- GLOBAL script, owns the timer, wires modules together

BalanceOfPower_Morrowind/
  data/factions.lua
  data/territories.lua       -- anchors
  data/frontier.lua          -- derived/generated frontier grid + centroids
  data/spawn_rosters.lua
  data/invasions/sixth_house.lua
  data/quest_hooks.lua
  main.lua                -- calls BalanceOfPower.registerLandmass(...) and registerInvasion(...)
```
