# Balance of Power — engine notes

What the engine's behaviour means *for this project specifically*. The general
facts live in [openmw-lua-notes.md](../openmw-lua-notes.md) at the repo root and
are not repeated here — this file is only the part that would be noise in a
document another mod reads.

---

## Reactions: what the framework does about the outbound layout

The engine fact — `FactionRecord.reactions` reads outbound, and the
documentation says the opposite — is in the repo notes §7, with the evidence.

The framework read those records as **inbound** through phases 1–3 and
propagated every asymmetric vanilla pair in the wrong direction. It now reads
reactions from the records and from nowhere else: nothing configurable, nothing
transposed. Should an ESM4 game turn out to store the reverse, that is a
conversion at the point the records are read, not a second convention
downstream.

`BalanceOfPower_Morrowind/sources/build_reactions_fixture.py` automates the
`esmtool dump --type FACT` over the three content files for the test suite, so
CI never needs Morrowind installed.

---

## Spawning: what the `onGround` finding costs phase 4b

Teleporting into an inactive cell stores the position verbatim and never snaps
it to the ground (repo notes §3). For this project that rules out the obvious
implementation of remote spawning, and leaves two options:

- **Defer spawning until the cell is active** — simplest, but a patrol only
  exists when the player is nearby, which undercuts the point of simulating a
  world that moves without them.
- **Ship a per-territory ground height as pack data** — costs a generation step
  and a data file, and works regardless of where the player is.

Related, and pulling the same way: **there is no API to delete a runtime
record**, so phase 4b must create a fixed roster of records once rather than one
per spawn, or the save grows forever.

Whether spawned objects can be tracked in `onSave` data at all is still open
(repo notes §12). If they cannot, despawn tracking has to be rebuilt by sweeping
`world.activeActors`, which sees only active cells — which would push the design
toward deferred spawning regardless.

**Leveled lists** cannot be validated at runtime and are not exposed to Lua, so
any leveled id a pack uses is an unverifiable string, the same silent-failure
shape as a bad faction id. Ids come from `esmtool dump --type LEVC`.

---

## Storage: why the framework persists through `onSave`

The design document leaned on a mod-scoped persistent storage API for
`state.power`, `state.ownership` and the rest. Phase 1 sidestepped it: the
framework persists through the global script's own `onSave` / `onLoad`, because
the state is **per-save by nature** — a world's power balance is a fact about
that world, not a preference that should follow the player across games.

Settings went the other way. Both settings groups use `permanentStorage = true`,
since those *are* preferences about how the simulation behaves. The framework's
simulation settings are global-context and only the notification preferences are
per-player, because `storage.playerSection` is unavailable to global scripts
(repo notes §11) — a player-side group governing global code would be
unreadable by the code it governs.

---

## Commerce: the hook that does not exist

The design document's "player buys goods in a faction's territory" power hook
has no engine support: nothing reports a completed barter, and even adjusting
prices is an open feature request (repo notes §9). The workaround would be
diffing player gold and inventory around a trade-mode UI session, which depends
on a UI-mode-changed signal this project has never confirmed exists.

Treat that hook as unbuilt, not merely unbuilt-yet.

---

## Ecosystem precedent

Found while researching the design, and still the closest existing work:

- **Perks Framework** (Blurpandra) and its **FactionsPerks** extension — the
  nearest precedent for faction-rank-driven Lua mechanics; FactionsPerks reads
  faction standing and rank to scale passive bonuses per Great House.
- **Crafting Framework** (OwnlyMods) — worth studying as an architecture
  reference for "content as data tables, behaviour as exposed hooks",
  independent of its unrelated crafting domain.
- **Night Patrol** and **Lua NPC Schedule** — the nearest precedent for the
  patrol and spawn half of this project: both drive NPC AI packages from world
  conditions (time of day, weather) rather than fixed placement.
- **No mod was found doing cell-ownership or territorial control**, which
  appears to be genuinely open ground in the OpenMW Lua mod space.
