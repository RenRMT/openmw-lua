# OpenMW Lua API — Session Reference Notes

Compiled from documentation lookups during this design session (August 2026). Target version context: OpenMW 0.51+. API surface has been moving fast release-to-release — re-check anything here against the docs for whatever version you actually build against, especially anything marked "new in 0.51" below.

Primary doc root used throughout: `https://openmw.readthedocs.io/en/latest/reference/lua-scripting/`

---

## 1. Script types & lifecycle

- **Global scripts** — always active, can read/write the whole game world including unloaded areas, cannot be started/stopped mid-session, listed via `.omwscripts` content files.
- **Local scripts** — attached to a specific object, only active while that object is in an active cell; can be attached/detached at runtime by a global script.
- **Player scripts** — local scripts specifically attached to the player.
- **Menu scripts** — run even with no game loaded, for main-menu-level functionality.
- **Load scripts** (new/in-progress) — run once immediately after all content files load, expose loaded records as *mutable* data via a dedicated "load context." Distinct from `world.createRecord` (which creates new records at runtime instead of editing loaded ones). Records injected this way are **not serialized into saves**.
- In-game console command `reloadlua` restarts all Lua scripts (calling their `onSave`/`onLoad` handlers) without a full game restart — useful for iteration.

**Confirmed limitation:** Lua cannot intercept or cancel outcomes the C++ engine has already decided on — it can only act through interfaces the engine deliberately exposes (AI packages, events, etc.), not rewrite core decision logic (e.g., can't prevent player death once health hits 0; source: OpenMW dev forum discussion on the Lua design philosophy).

---

## 2. World & object manipulation

- `world.createObject(recordId, count)` — **global scripts only**. Creates a new instance of a record, starts **disabled**. Must call `:teleport(cellName, position)` or `:moveInto(container/inventory)` to actually place it.
- `world.cells` — list of all `Cell` objects.
- `world.activeActors` — list of currently active actors.
- `world.createRecord(recordDraft)` — registers a custom record (built from a type's `createRecordDraft`) into the world database.
- **Known engine bug:** creating a leveled list via `world.createObject` and teleporting it can place the resulting creature at world origin (0,0,0) instead of the intended position (GitLab #7453) — worth testing before relying on leveled-list spawns.
- `core.getFormId(contentFile, index)` — builds a FormId string; needed for ESM4-style content (e.g. a future Skyrim landmass pack). ESM3 (Morrowind-style) content uses plain lowercase string IDs instead.

---

## 3. AI packages & actor control

Exposed via `require('openmw.interfaces').AI`, from a local script on the actor itself, or from any script via an event:

```lua
-- from a local script, on self
local AI = require('openmw.interfaces').AI
AI.startPackage({type = 'Combat', target = anotherActor})

-- from any script, targeting any non-player actor
actor:sendEvent('StartAIPackage', {type = 'Combat', target = anotherActor})
actor:sendEvent('RemoveAIPackages', 'Pursue')   -- optional type filter; omit to clear all
```

Built-in package types: **Combat** (attack a target), **Pursue**, **Follow**, **Escort** (to a destination), **Wander** (near current position). Common optional arguments across packages: `target`, `destPosition`, `distance`, `duration`, `idle`, `isRepeat`, `help` (whether to assist the target in combat).

---

## 4. Factions

All under `require('openmw.types').NPC` unless noted:

| Function | Notes |
|---|---|
| `NPC.getFactionRank(actor, factionId)` | Rank index from 1; **0** means not in the faction |
| `NPC.getFactionReputation(actor, factionId)` | Reputation level; 0 if not a member |
| `NPC.getFactions(actor)` | List of faction IDs the actor is a member of (does *not* account for expelled status) |
| `NPC.expel(actor, factionId)` | Expels; NPC keeps rank/reputation, just gets an expelled flag |
| `NPC.clearExpelled(actor, factionId)` | Clears the expelled flag |

- `core.factions.records` — indexable **both** by record id string and by integer, per the `@usage` lines in the shipped stub. A **FactionRecord** has exactly: `id`, `name`, `ranks` (list of `FactionRank`), `reactions`, `attributes`, `skills`, `hidden`. Nothing else. Not available in load scripts; available in global, menu, local and player.
- **`.reactions` reads outbound.** Settled — see §9a. A row is *this faction's* reaction toward the named ones, matching the ESM3 `FACT` record, whose ANAM/INTV pairs live on the faction's own record. **The OpenMW documentation states the opposite** (inbound) and is wrong for ESM3.
- **`FactionRank.factionReaction` is DEPRECATED** as of 0.51.0 in favour of `factionReputation` (GitLab #8789). Same value; it is a rank *requirement*, unrelated to `FactionRecord.reactions`.
- **Fixed, was #7553.** Earlier notes here described OpenMW collapsing duplicate reaction entries to the last value in the file rather than vanilla's minimum. `Bug #7553: Faction reaction loading is incorrect` is listed in the **0.49.0** changelog — the fix shipped two releases before 0.51.0.
- **Faction reputation getters *and setters* exist as of 0.51.0** (`Feature #9013: Expose reputation to Lua`): `NPC.getFactionReputation` / `setFactionReputation` / `modifyFactionReputation`, plus `joinFaction`, `leaveFaction`, `isExpelled`. This closes the old #7468 question. There is still **no setter for faction-to-faction `reactions`** — `FactionRecord` is documented read-only throughout.
- `NpcRecord` exposes **no** faction field. `primaryFaction` / `primaryFactionRank` are on `CreatureRecord` only; for an NPC, go through `NPC.getFactions` / `getFactionRank` on a live GameObject.

---

## 5. Custom records

Most types expose `Type.createRecordDraft(table)` (build a draft, optionally based on a `template` of an existing record) plus `world.createRecord(draft)` (register it) — e.g. `types.Armor.createRecordDraft`, `types.NPC.createRecordDraft`, `types.Clothing.createRecordDraft`, `types.Container.createRecordDraft`, `types.Light.createRecordDraft`, `types.Weapon.createRecordDraft`, `types.Potion.createRecordDraft`.

**Version history matters here:**
- As of 0.49: Activator, Armor, Book, Clothing, Light, Miscellaneous, Potion, Weapon records creatable/spawnable.
- As of **0.51** (current at time of writing): **Container, Creature, Door, Probe, and Static** records can also be created **at runtime**, in addition to the above. A new "load context" additionally allows injecting Custom magic effect and ingredient records (load-time only, not runtime, not save-serialized).

For the MVP scoped in the design document, none of this is actually required — reusing existing vanilla NPC/creature record IDs for patrol and invader rosters avoids needing any custom record creation at all.

---

## 6. Events

Selected built-ins relevant to this project (via `eventHandlers = { ... }` in a script, or `core.sendGlobalEvent(name, data)` / `object:sendEvent(name, data)`):

- `Died` — sent to an actor's local script on death.
- `DialogueResponse` — sent to the player's local script on greeting/topic/persuasion/service-refusal/voice line; includes `actor`, `type`, `recordId`, `infoId`.
- `StartAIPackage` / `RemoveAIPackages` — see Section 3.
- `UseItem` — makes an actor use/equip/consume an inventory item.
- `Pause` / `Unpause` / `SetGameTimeScale` / `SetSimulationTimeScale` — thin wrappers around the matching `world.*` functions.

**Notable gap found this session:** no confirmed built-in event for "a barter/trade transaction completed." The only related item found is an **open feature request** (GitLab #8015, "Lua API for altering barter offer") — meaning even *adjusting* barter prices isn't a settled API yet, let alone observing a completed sale. Any commerce-driven mechanic (like the "player buys goods in a faction's territory" power hook discussed in the design doc) needs a workaround — e.g. diffing player gold/inventory around a trade-mode UI session — rather than a direct hook, as of this session's research.

---

## 7. Quests / player journal

`Player` (from `openmw.types`) exposes a quest interface — confirmed present as of the 0.50 release notes ("access player journals... create custom NPCs"):

- Quest object fields: `id` (read-only), `stage` (settable from global/player scripts — setting it also starts the quest if not already started), `finished` (boolean, settable).
- A journal-entry-adding function takes an optional `actor` argument (source of the entry, used for dialogue variable substitution like `%name`/`%race`).

This is what the design document's "quest completion feeds faction power" hook relies on — watch for a tracked quest's `finished` flag flipping (or reaching a specific `stage`), mapped through an authored quest→faction table (the engine has no innate concept of which faction a given quest "belongs" to).

---

## 8. Ecosystem notes (not API, but relevant precedent found this session)

- **Perks Framework** (Blurpandra) + **FactionsPerks** extension — closest existing precedent for faction-rank-driven Lua mechanics; FactionsPerks reads faction standing/rank to scale passive bonuses per Great House.
- **Crafting Framework** (OwnlyMods) — worth studying as an architecture reference for "content as data tables, behavior as exposed hooks," independent of its (unrelated) crafting domain.
- **Night Patrol** and **Lua NPC Schedule** — closest existing precedent for the patrol/spawn half of this project: both drive NPC AI packages dynamically based on world conditions (time of day, weather) rather than fixed placement.
- No existing mod found that does cell-ownership/territorial control specifically — that appears to be genuinely open ground in the current OpenMW Lua mod space.

---

## 9. Used in the design but not explicitly re-confirmed this session

Flagging these separately because the design document leans on them, but this session's searches didn't specifically pull current documentation for them — confirm exact function names/signatures against your target version's docs before implementing:

- **Persistent mod storage API** (`window`/mod-scoped key-value storage referenced for `state.power`, `state.ownership`, etc. across saves) — referenced from general knowledge of the OpenMW Lua design, not pulled from a doc page this session. *Sidestepped in phase 1:* the framework persists via the global script's own `onSave`/`onLoad` instead, since the state is per-save by nature.
- **A trade/barter UI-mode-changed signal**, proposed as a workaround for the missing commerce event (Section 6 above) — plausible based on general knowledge of a UI-mode-changed event existing, but not directly confirmed this session.

### 9a. Confirmed during phase 1 implementation (August 2026)

Checked directly against the docs while building the framework, so these no longer need re-verification:

- **Faction record reactions read OUTBOUND** *(verified in-game 2026-08-13; re-verified against the raw ESM data 2026-08-15)*. `core.factions.records[id].reactions` is a map of *how this faction feels about the named ones*, not how they feel about it.

  **The documentation says inbound, and is wrong** for ESM3 content. The exact wording, in the shipped stub at `resources/lua_api/openmw/core.lua` (line 1355 in 0.51.0):

  > `@field #map<#string, #number> reactions A read-only map containing reactions of other factions to this faction.`

  Anyone building on that alone will get it backwards, as this project did: the framework read records as inbound through phases 1–3 and propagated every asymmetric vanilla pair in the wrong direction.

  Three independent lines of evidence, in descending order of how hard they are to argue with:

  1. **The Nerevarine.** `FACT "Nerevarine"` carries **zero** reaction entries — not even the self-reaction every other joinable faction has. Yet `FACT "Temple"` carries `-8 = "Nerevarine"` and `FACT "Redoran"` carries `-4 = "Nerevarine"`. In game, becoming Nerevarine is what makes Temple and Redoran members hate *you*. That effect is stored on their records, naming the Nerevarine. Outbound.
  2. **Asymmetric pairs.** `FACT "Twin Lamps"` → `-3 = "Telvanni"` while `FACT "Telvanni"` has no Twin Lamps entry. Same shape for `Imperial Knights` → `Imperial Legion` = 2, unreciprocated.
  3. **OpenMW's own dialogue-condition docs**, in the same stub file, describing the same underlying data unambiguously: *"Lowest faction reaction **from the speaker's primary faction to** the player's factions."*

  Dumped with `esmtool dump --type FACT` over Morrowind.esm, Tribunal.esm and Bloodmoon.esm. `BalanceOfPower_Morrowind/sources/build_reactions_fixture.py` automates that dump for the test suite.

  The framework now reads reactions from the records and from nowhere else, with nothing configurable and nothing transposed. Should an ESM4 game turn out to store the reverse, that is a conversion at the point the records are read, not a second convention downstream.

- **Three more properties of the reaction map**, all of which the framework has to handle and none of which are documented *(verified against the ESM 2026-08-15)*:

  - **Keys are stored case-preserved as authored** — `"Camonna Tong"`, `"Sixth House"`, `"Clan Aundae"`. These are record ids, not display names (id `Redoran`, name `Great House Redoran`). Record *lookup* goes through a `RefId` and is case-insensitive; a reaction map is a plain Lua table, so its keys arrive however the content file wrote them. **Whether the binding lowercases them before handing them to Lua is still unverified** — the framework normalizes both ends defensively, which makes it a non-question either way.
  - **Rows are sparse, but explicit zeros occur** — `Imperial Cult → Morag Tong = 0`, `Census and Excise → Fighters Guild = 0`. Absence means zero by engine convention, so `reactions[x] ~= nil` is not a test for "has a relationship".
  - **Every record carries a reaction toward itself**, usually 3 (`Census and Excise` is an oddity at -1). It has to be stripped, and stripped *after* case normalization.

- **Expansion factions carry their reactions on their own new records; base-game records are never patched to point back.** `Bloodmoon.esm` adds `East Empire Company` (14 entries) and `Skaal` (0); `Tribunal.esm` adds `Royal Guard` (12), `Dark Brotherhood` (0), `Hands of Almalexia` (0). This is a direct consequence of the outbound layout, and it means an expansion faction commonly has a row and no column — it reacts to the world and the world does not react to it.

- **`openmw_aux.time`** — constants `time.second` / `time.minute` / `time.hour` / `time.day`, type constants `time.SimulationTime` / `time.GameTime`, and `time.runRepeatedly(fn, period, options)` where `options` accepts `initialDelay` and `type`, returning a stop function. This covers the once-per-day resolution tick.
- **`core.getGameTime()`** — returns game time in **seconds**, so an in-game day index is `math.floor(core.getGameTime() / time.day)`.
- **`world.players`** — exists; an ObjectList, currently always one element. Used to broadcast framework events to player scripts.
- **Cell fields** — `name` (can be empty), `isExterior`, `gridX` / `gridY` (exteriors only), `region` (can be nil), `id`. Also `world.getCellByName`, `world.getCellById`, `world.getExteriorCell(gridX, gridY, cellOrName)`.
- **Player cell-change detection** — no dedicated built-in event was found; polling the player's `cell` field from a player script is the working approach (the debug overlay does this on a 1-second timer). Relevant to the phase 4 spawn subsystem.
- **In-game console Lua commands** — `lua player` / `luap`, `lua global` / `luag`, `lua selected` / `luas`, `lua menu` / `luam`. `luag` is what reaches a global-script interface: `luag require('openmw.interfaces').BalanceOfPower.dump()`.
- **`onKeyPress` / `KeyboardEvent`** — fields `code` (a `KeyCode`), `symbol`, `withCtrl`, `withAlt`, `withShift`, `withSuper`; `input.KEY` includes `F1`–`F12`, letters `A`–`Z`, digits `_0`–`_9`, arrows and modifiers. Also `input.registerActionHandler` and `input.registerTriggerHandler`.

---

## 10. Source pages referenced this session

- `openmw.readthedocs.io/en/latest/reference/lua-scripting/aipackages.html` and `.../ai/combat.html` — AI package system
- `openmw.readthedocs.io/en/latest/reference/lua-scripting/interface_ai.html` — AI interface
- `openmw.readthedocs.io/en/latest/reference/lua-scripting/openmw_types.html` — `types.*`, faction functions, record drafts
- `openmw.readthedocs.io/en/latest/reference/lua-scripting/openmw_world.html` — `world.*`
- `openmw.readthedocs.io/en/latest/reference/lua-scripting/openmw_core.html` — `core.*`, factions, FormId
- `openmw.readthedocs.io/en/latest/reference/lua-scripting/events.html` — built-in events
- `openmw.readthedocs.io/en/latest/reference/lua-scripting/overview.html` — script types, `reloadlua`
- `openmw.org/2026/openmw-0-51-0-released` and `openmw.org` 0.50 release notes — version-gated feature confirmation
- `wiki.openmw.org` Research:Disposition and Persuasion — vanilla disposition/reaction formula
- GitLab issues referenced: #7468 (factions API request), #7553 (reaction dedup bug — **fixed in 0.49.0**), #7453 (leveled list spawn position bug), #8015 (barter API request), #8789 (FactionRank field naming), #9013 (expose reputation to Lua — **new in 0.51.0**)
- **Local, and more authoritative than the readthedocs pages**: `D:\OpenMW 0.51.0\resources\lua_api\openmw\*.lua` — the LDoc stubs the documentation is generated from — and `CHANGELOG.txt` in the install root. `esmtool.exe` ships alongside them and is the way to settle a question about what the content files actually contain.
- Nexus Mods pages for Night Patrol, Lua NPC Schedule, FactionsPerks, Crafting Framework
