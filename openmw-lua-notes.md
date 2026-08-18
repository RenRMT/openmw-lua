# OpenMW Lua — engine notes

Engine facts that hold for any mod in this repo. Target version: **OpenMW
0.51+**. The API surface moves between releases — re-check anything here
against the docs for the version you build against.

**Mod-specific findings live with their mod**, not here:

- [BalanceOfPower/engine-notes.md](BalanceOfPower/engine-notes.md) — what these
  facts mean for the faction framework, plus its ecosystem research.
- [TravelNetwork/implementation-plan.md](TravelNetwork/implementation-plan.md)
  §2a and §2b — what the ESM and the runtime say about travel data.

Every entry says how it was established and when. **Docs-checked** means read in
the documentation or the shipped LDoc stubs; **probed** means observed in a
running game; **ESM** means dumped from the content files with `esmtool`.
Anything not yet established is in §12, and belongs there until it is.

The most authoritative source is local, not online:
`D:\OpenMW 0.51.0\resources\lua_api\openmw\*.lua` — the stubs the readthedocs
pages are generated from — plus `CHANGELOG.txt` in the install root.
`esmtool.exe` ships beside them and settles any question about what the content
files actually contain.

---

## 1. Script types and lifecycle

- **Global scripts** — always active, can read and write the whole game world
  including unloaded areas, cannot be started or stopped mid-session, listed in
  `.omwscripts` content files.
- **Local scripts** — attached to an object, active only while that object is in
  an active cell; attachable and detachable at runtime by a global script.
- **Player scripts** — local scripts attached to the player.
- **Menu scripts** — run with no game loaded, for main-menu functionality.
- **Load scripts** (new/in progress) — run once immediately after content files
  load and expose loaded records as *mutable* data through a dedicated load
  context. Distinct from `world.createRecord`, which creates new records at
  runtime rather than editing loaded ones. Records injected this way are **not
  serialized into saves**.
- `reloadlua` in the console restarts all Lua scripts, calling their
  `onSave`/`onLoad` handlers, without restarting the game.

**Lua cannot intercept outcomes the C++ engine has already decided.** It acts
only through interfaces the engine deliberately exposes — AI packages, events,
interfaces — and cannot rewrite core decision logic. Player death once health
reaches zero is the standard example. *(Source: OpenMW dev forum on the Lua
design philosophy.)*

---

## 2. The console

**`luag` / `luap` / `luas` / `luam` are mode switches, not prefixes**
*(probed 2026-08-16)*. Typed on its own line, `luag` changes the prompt to
`Lua[Global]` and everything after is raw Lua; `exit()` leaves.

Getting this wrong fails in two different ways, one of them silent: `luag <code>`
at the plain console **switches mode and discards the rest of the line** — no
error, no output — while the same thing typed once already in Lua mode is a
syntax error near the first token.

The global environment (`resources/vfs/scripts/omw/console/global.lua`)
pre-binds **`I`** (`openmw.interfaces`), `world`, `types`, `util`, `core`,
`storage`, `vfs`, `markup`, `async`, `aux_util`, `calendar` and `time`, plus
`view()`, `help()` and `exit()`. `require` is never needed:
`I.SomeInterface.dump()` is the correct form.

---

## 3. World, cells and objects

- `world.cells` — list of all `Cell` objects. `world.activeActors` — currently
  active actors only.
- **Cell fields** *(docs-checked 2026-08-13)* — `name` (can be empty),
  `isExterior`, `gridX`/`gridY` (exteriors only), `region` (can be nil), `id`.
  Also `world.getCellByName`, `world.getCellById`,
  `world.getExteriorCell(gridX, gridY, cellOrName)`.
- **`Cell:getAll(type)` sees cells that have never been loaded** *(probed
  2026-08-18)*. Global scripts only. A named interior on the far side of the
  island, unvisited in that save, returned its full NPC list — 7 in `Balmora,
  Guild of Mages`, 10 in `Ald-ruhn, Guild of Mages`, matching the ESM exactly —
  and **`position` was readable on every one**. Objects whose properties only
  resolved while loaded would have been useless.
- **A full sweep of `world.cells` is affordable** *(probed 2026-08-18)*. 2887
  cells, `getAll` for both NPCs and creatures in each, no failures, **~600 ms**.
  Fine once at startup, too slow for a frame budget, and it needs the player
  nowhere in particular.
- **Exterior cells have synthetic ids of the form
  `Esm3ExteriorCell:<gridX>:<gridY>`** *(probed 2026-08-18)*.
  `world.getCellById` resolves one to the real cell, whose `name` is the town
  ("Balmora", "Khuul"). An exterior position never has to be reverse-engineered
  into a grid coordinate — the id carries it, and the name comes free.
- **An empty cell name means the default exterior worldspace, and the
  destination cell is derived from the position** *(probed 2026-08-16)*.
  `obj:teleport('', util.vector3(x, y, z))` landed in `#3,-4` without naming a
  cell. This is the form a spawner should use; there is no way to name a cell
  the loaded content does not have.
- **`onGround = true` is inert when teleporting into an inactive cell**
  *(probed 2026-08-16)*. `GameObject:teleport(cell, position, {onGround = true})`
  into a cell outside the active grid **stores the position verbatim and never
  revisits it when the cell later loads** — there is no terrain in memory to snap
  against at the time of the call. A `rat` placed 40000 units away using the
  player's own z was found buried by the ~1800-unit difference in real ground
  height. Not a placement failure: the engine did exactly what it was told.
  Spawning into an inactive cell needs a ground height from somewhere else, and
  the navmesh functions cannot supply it — they are local context and see only
  the active grid.
- **The navmesh → creation round trip works** *(probed 2026-08-16)*.
  `nearby.findRandomPointAroundCircle` in a player script, position sent to a
  global script, `world.createObject` + `teleport` there. *Unverified:* the
  probe requested pathfinding bounds from the **player**, not from the actor
  being spawned, so it says nothing about non-humanoid agents.
- **GitLab #7453 does not reproduce for a plain creature record** *(probed
  2026-08-16, 0.51.0)*. `world.createObject('rat', 1)` teleported into an
  inactive exterior reported exactly the requested position in the correctly
  derived cell, not the world origin. **The leveled-list case — what the bug is
  actually about — remains untested.**
- `core.getFormId(contentFile, index)` builds a FormId string, needed for
  ESM4-style content. ESM3 (Morrowind-style) content uses plain lowercase string
  ids instead.

---

## 4. Naming and case

**Record ids, cell ids and class names are lowercased at runtime; names are
not** *(probed 2026-08-18)*. The ESM stores `Caravaner`, `Nevosi Hlan` and
`Ald-ruhn, Guild of Mages`; the engine hands back `caravaner`, `nevosi hlan` and
`ald-ruhn, guild of mages`. **`Cell.name` keeps its authored capitalisation.**

So **an id is a key and a name is a label**, and the two are never
interchangeable. Anything read straight from an ESM dump — a generated data
table, a test fixture — is in the other convention and has to be normalised on
the way in.

The exception worth knowing: **a reaction map's keys are case-preserved as
authored** *(ESM 2026-08-15)* — `"Camonna Tong"`, `"Sixth House"` — because the
map is a plain Lua table rather than a `RefId` lookup. Whether the binding
lowercases them before Lua sees them is **unverified**; normalising both ends
makes it a non-question.

---

## 5. Records

- Most types expose `Type.createRecordDraft(table)` — optionally based on a
  `template` of an existing record — plus `world.createRecord(draft)` to
  register it: `types.Armor`, `types.NPC`, `types.Clothing`, `types.Container`,
  `types.Light`, `types.Weapon`, `types.Potion`.
- **Version-gated.** As of 0.49: Activator, Armor, Book, Clothing, Light,
  Miscellaneous, Potion and Weapon are creatable and spawnable. As of **0.51**:
  Container, Creature, Door, Probe and Static as well. The load context
  additionally allows injecting custom magic effect and ingredient records —
  load-time only, not runtime, not save-serialized.
- `world.createObject(recordId, count)` — **global scripts only**. Creates an
  instance, which starts **disabled**; it must be placed with
  `:teleport(cellName, position)` or `:moveInto(container)`.
- **Runtime-created NPC records survive a save/load** *(probed 2026-08-16)*.
  A record made with `world.createRecord(types.NPC.createRecordDraft{...})` was
  still in `types.NPC.records` after saving and reloading, with its authored
  `name` intact, and its spawned instance still standing where it had been
  placed. A mod can generate actors in Lua and does not need to ship them in an
  `.omwaddon`. Two consequences:
  - **The id is engine-assigned and sequential** — `Generated:0x15` in that run.
    The `id` field on the draft is ignored, as documented. The id **must be
    persisted in the save and can never be hardcoded**; there is no reason to
    expect the same number under a different mod list.
  - **There is no API to delete a runtime record.** Anything created leaks into
    the save permanently, so create a fixed roster once rather than one record
    per spawn.
- **Leveled lists are not exposed to Lua at all** *(probed 2026-08-16)*.
  `openmw.types` has no records table for them, unlike `Creature` and `NPC`. A
  leveled id can only be obtained externally (`esmtool dump --type LEVC`), and
  **a mod can never validate one at runtime** — the same silent-failure shape as
  an unverified faction record id.

---

## 6. Actors and AI

Exposed via `require('openmw.interfaces').AI`, from a local script on the actor,
or from any script via an event:

```lua
-- from a local script, on self
local AI = require('openmw.interfaces').AI
AI.startPackage({type = 'Combat', target = anotherActor})

-- from any script, targeting any non-player actor
actor:sendEvent('StartAIPackage', {type = 'Combat', target = anotherActor})
actor:sendEvent('RemoveAIPackages', 'Pursue')   -- omit the filter to clear all
```

Built-in package types: **Combat**, **Pursue**, **Follow**, **Escort**,
**Wander**. Common optional arguments: `target`, `destPosition`, `distance`,
`duration`, `idle`, `isRepeat`, `help`.

- **`StartAIPackage` works from global context** *(probed 2026-08-16)*.
  `actor:sendEvent('StartAIPackage', {type = 'Combat', target = player})` made an
  ordinary NPC attack immediately, with no script attachment needed.
- **AI stat writes are refused from global context** *(probed 2026-08-16)*.
  `types.Actor.stats.ai.fight(actor).base = 100` from a global script throws
  `Allowed only in local scripts for 'openmw.self'.` The `AIStat.base` field
  documented as writable is writable **only by the actor on itself**. The
  remaining path is a runtime-attached local script via
  `GameObject:addScript(path, initData)`, which requires the **`CUSTOM`** flag in
  the content file — `NPC` or `CREATURE` would attach it to every actor in the
  game. **Still unverified: whether the write succeeds from there, and whether
  the engine acts on it if it does.** Watch for three outcomes, not two: a write
  that lands but changes no behaviour is the one most easily misread as success.
- **Player cell-change detection** — no dedicated built-in event was found;
  polling the player's `cell` field from a player script is the working
  approach.

---

## 7. Factions

All under `require('openmw.types').NPC` unless noted:

| Function | Notes |
|---|---|
| `NPC.getFactionRank(actor, factionId)` | Rank index from 1; **0** means not a member |
| `NPC.getFactionReputation(actor, factionId)` | Reputation level; 0 if not a member |
| `NPC.getFactions(actor)` | Faction ids the actor belongs to (ignores expelled status) |
| `NPC.expel(actor, factionId)` | Expels; rank and reputation are kept, an expelled flag is set |
| `NPC.clearExpelled(actor, factionId)` | Clears that flag |

- `core.factions.records` — indexable **both** by record id string and by
  integer. A **FactionRecord** has exactly `id`, `name`, `ranks`, `reactions`,
  `attributes`, `skills`, `hidden`, and nothing else. Unavailable in load
  scripts; available in global, menu, local and player.
- **Reputation getters *and setters* exist as of 0.51.0** (`Feature #9013`):
  `getFactionReputation` / `setFactionReputation` / `modifyFactionReputation`,
  plus `joinFaction`, `leaveFaction`, `isExpelled`. There is still **no setter
  for faction-to-faction `reactions`** — `FactionRecord` is read-only throughout.
- **`FactionRank.factionReaction` is deprecated** as of 0.51.0 in favour of
  `factionReputation` (GitLab #8789). It is a rank *requirement*, unrelated to
  `FactionRecord.reactions`.
- **GitLab #7553 is fixed.** OpenMW once collapsed duplicate reaction entries to
  the last value in the file rather than vanilla's minimum; the fix shipped in
  **0.49.0**.
- `NpcRecord` exposes **no** faction field. `primaryFaction` and
  `primaryFactionRank` are on `CreatureRecord` only; for an NPC, go through
  `NPC.getFactions` / `getFactionRank` on a live GameObject.

### Faction reactions read OUTBOUND, and the documentation says otherwise

*(probed in-game 2026-08-13; re-verified against the raw ESM 2026-08-15)*

`core.factions.records[id].reactions` is a map of **how this faction feels about
the named ones**, not how they feel about it. The shipped stub at
`resources/lua_api/openmw/core.lua` (line 1355 in 0.51.0) says:

> `@field #map<#string, #number> reactions A read-only map containing reactions
> of other factions to this faction.`

That is wrong for ESM3 content, and anyone building on it alone will get the
direction backwards. Three lines of evidence, hardest to argue with first:

1. **The Nerevarine.** `FACT "Nerevarine"` carries **zero** reaction entries —
   not even the self-reaction every other joinable faction has. Yet
   `FACT "Temple"` carries `-8 = "Nerevarine"` and `FACT "Redoran"` carries
   `-4 = "Nerevarine"`. In game, becoming Nerevarine is what makes Temple and
   Redoran members hate *you*, and that effect is stored on their records.
2. **Asymmetric pairs.** `FACT "Twin Lamps"` → `-3 = "Telvanni"` while
   `FACT "Telvanni"` has no Twin Lamps entry. Same shape for
   `Imperial Knights` → `Imperial Legion` = 2, unreciprocated.
3. **OpenMW's own dialogue-condition docs**, in the same stub, describing the
   same data: *"Lowest faction reaction **from the speaker's primary faction
   to** the player's factions."*

Three further properties, none documented *(ESM 2026-08-15)*:

- **Keys are case-preserved as authored** (§4).
- **Rows are sparse, but explicit zeros occur** — `Imperial Cult → Morag Tong
  = 0`. Absence means zero by convention, so `reactions[x] ~= nil` is not a test
  for "has a relationship".
- **Every record carries a reaction toward itself**, usually 3 (`Census and
  Excise` is an oddity at -1). It has to be stripped, and stripped *after* case
  normalisation.
- **Expansion factions carry reactions on their own new records; base-game
  records are never patched to point back.** `Bloodmoon.esm` adds
  `East Empire Company` (14 entries) and `Skaal` (0); `Tribunal.esm` adds
  `Royal Guard` (12), `Dark Brotherhood` (0), `Hands of Almalexia` (0). A direct
  consequence of the outbound layout: an expansion faction commonly has a row
  and no column.

---

## 8. Travel and services

*(ESM and probe, 2026-08-18. Fuller detail, including the vanilla numbers, in
TravelNetwork's plan §2a/§2b.)*

- **`travelDestinations` is populated on NPC records**, each entry carrying
  `cellId`, `position` and `rotation`. **No vanilla creature record carries
  one** — zero across Morrowind, Tribunal and Bloodmoon.
- **`servicesOffered.Travel` is derived, not stored.** The ESM3 format has no
  travel bit at all and vanilla leaves the services mask empty on nearly every
  operator, yet the engine reports `Travel = true` for them. It can be trusted;
  it is simply not what the file says. *(Checked on two records.)*
- **`NpcRecord.class` is the only signal of what an operator drives** — the
  records say nothing about vehicles. Vanilla's classes are `caravaner`,
  `shipmaster`, `guild guide` and `gondolier`, lowercased at runtime per §4.

---

## 9. Events

Via `eventHandlers = { ... }` in a script, or `core.sendGlobalEvent(name, data)`
/ `object:sendEvent(name, data)`:

- `Died` — sent to an actor's local script on death.
- `DialogueResponse` — sent to the player's local script on
  greeting/topic/persuasion/service-refusal/voice line; includes `actor`,
  `type`, `recordId`, `infoId`.
- `StartAIPackage` / `RemoveAIPackages` — §6.
- `UseItem` — makes an actor use, equip or consume an inventory item.
- `Pause` / `Unpause` / `SetGameTimeScale` / `SetSimulationTimeScale` — thin
  wrappers around the matching `world.*` functions.

**No event reports a completed barter or trade.** The only related item is an
open feature request (GitLab #8015, "Lua API for altering barter offer") —
meaning even *adjusting* prices is not a settled API, let alone observing a
sale. Any commerce-driven mechanic needs a workaround, such as diffing player
gold and inventory around a trade-mode UI session.

---

## 10. Quests and journal

`types.Player` exposes a quest interface, present as of the 0.50 release notes:

- Quest fields: `id` (read-only), `stage` (settable from global or player
  scripts — setting it also starts the quest), `finished` (boolean, settable).
- The journal-entry function takes an optional `actor` argument, the source of
  the entry, used for dialogue variable substitution like `%name` / `%race`.

The engine has **no concept of which faction a quest belongs to**; that mapping
has to be authored.

---

## 11. Settings, storage, UI, l10n, time and input

*(docs-checked 2026-08-18; the settings and l10n entries were then exercised in
a shipped settings page.)*

- **`I.Settings.registerPage{ key, l10n, name, description }`** and
  **`I.Settings.registerGroup{ key, page, l10n, name, description, order,
  permanentStorage, settings }`**. `name` and `description` are *l10n keys*, not
  literals, in both calls and in every entry of `settings`.
- **A group's key prefix decides which context owns it.** `SettingsGlobal*` is
  registered by a global script and read with `storage.globalSection(key)`;
  `SettingsPlayer*` is registered by a player script and read with
  `storage.playerSection(key)`. Not decoration: **`storage.playerSection` is
  unavailable to global scripts**, so a player-side group governing global code
  is unreadable by it.
- **`permanentStorage`** — `true` stores across saves, `false` in the save file.
- **Six built-in renderers**: `textLine`, `checkbox`, `number`, `select`,
  `color`, `inputBinding`. `number` takes `{ integer, min, max }`; `select`
  takes `{ l10n, items }` and resolves each item **as an l10n key**.
- **`storage`**: `section:get(key)`, `section:set(key, value)`,
  `section:subscribe(async:callback(fn))`. A subscription is what makes a slider
  apply mid-game rather than at next load.
- **`ui.showMessage(msg, options)`** — `options.showInDialogue` only. Local
  context, so a global script cannot call it.
- **`core.l10n('Context', 'en')`** returns a lookup function; files live at
  `l10n/<Context>/<Locale>.yaml` and messages are ICU MessageFormat.
- **`openmw_aux.time`** — `time.second` / `minute` / `hour` / `day`,
  `time.SimulationTime` / `time.GameTime`, and
  `time.runRepeatedly(fn, period, options)` with `initialDelay` and `type`,
  returning a stop function.
- **`core.getGameTime()`** returns game time in **seconds**, so an in-game day
  index is `math.floor(core.getGameTime() / time.day)`.
- **`world.advanceTime(hours)`** advances time, weather and AI, but **not**
  regeneration — a long journey will not heal the way sleeping does.
- **`world.players`** — an ObjectList, currently always one element.
- **`onKeyPress` / `KeyboardEvent`** — `code`, `symbol`, `withCtrl`, `withAlt`,
  `withShift`, `withSuper`; `input.KEY` includes `F1`–`F12`, `A`–`Z`, `_0`–`_9`,
  arrows and modifiers. Also `input.registerActionHandler` and
  `input.registerTriggerHandler`.

**Two silent l10n traps**, both found the hard way:

- **An unknown message key renders as the key itself.** No error, no log line — a
  typo ships as the player seeing `flipTakenn`.
- **YAML reads `off`, `on`, `yes`, `no` as booleans.** A `select` renderer's
  items double as l10n keys, so an item called `off` needs an `off:` key — which
  parses as `false`, stops being a string, and never matches. Use prefixed key
  names. `.github/scripts/validate_l10n.py` now fails on both.

---

## 12. Not established

Do not build on these without checking first.

- **Can a GameObject live in `onSave` data?** A probe run was inconclusive — it
  was not armed when the save was written, so nothing was attempted and the
  report could not distinguish that from a silent drop. Decides whether tracking
  spawned objects is plain save data or has to be rebuilt by sweeping
  `world.activeActors`, which sees active cells only.
- **Does an AI stat write work from the actor's own local script?** §6.
- **Does GitLab #7453 still bite leveled lists?** §3.
- **Does the binding lowercase reaction-map keys before Lua sees them?** §4.
- **Does the navmesh round trip hold for non-humanoid agents?** §3.
- **A trade/barter UI-mode-changed signal**, proposed as the workaround for the
  missing commerce event (§9), is plausible from general knowledge of a
  UI-mode-changed event but was never confirmed.

---

## 13. Sources

- `openmw.readthedocs.io/en/latest/reference/lua-scripting/` — `overview`
  (script types, `reloadlua`), `openmw_world`, `openmw_core`, `openmw_types`,
  `events`, `aipackages` and `ai/combat`, `interface_ai`, `interface_settings`,
  `setting_renderers`, `openmw_storage`, `openmw_ui`.
- `.../reference/modding/localisation.html` — l10n layout and ICU
  MessageFormat.
- `openmw.org/2026/openmw-0-51-0-released` and the 0.50 release notes — version
  gating.
- `wiki.openmw.org` Research:Disposition and Persuasion — the vanilla
  disposition and reaction formula.
- GitLab issues: #7468 (factions API request), #7553 (reaction dedup —
  **fixed in 0.49.0**), #7453 (leveled list spawn position), #8015 (barter API
  request), #8789 (FactionRank field naming), #9013 (expose reputation —
  **new in 0.51.0**).
- Local and more authoritative than any of the above:
  `D:\OpenMW 0.51.0\resources\lua_api\openmw\*.lua`, `CHANGELOG.txt`, and
  `esmtool.exe`.
