# LockMemory — implementation plan

*Name is a placeholder.* Buildings react to being robbed. Rob the same manor
three nights running and you find the door harder to pick, the strongbox
trapped, and the whole district a little less welcoming. Leave it alone for a
season and it relaxes again.

**Finish line.** A burgled interior escalates its own security over the
following days, visibly and reversibly, and decays back to its authored state
when left alone. One state table, one daily tick, one escalation ladder.

---

## 1. Why this is possible at all

Lock state is authored once in the ESM and never changes again in vanilla. It is
also, as of 0.51, fully writable at runtime from global scripts
(`types.lua:1710-1764`):

| Function | Notes |
|---|---|
| `types.Lockable.isLocked(obj)` / `getLockLevel(obj)` | Read; level is retained while unlocked |
| `types.Lockable.lock(obj, level)` | Global only. Locks and sets level; omitting level reuses the previous one |
| `types.Lockable.unlock(obj)` | Global only. Keeps the level for future use |
| `types.Lockable.getTrapSpell(obj)` / `setTrapSpell(obj, spellOrId)` | Global only; empty string removes the trap |
| `types.Lockable.getKeyRecord(obj)` / `setKey(obj, id)` | Global only; empty string removes the key |

Ownership is readable — and writable — on any object:
`obj.owner.recordId`, `obj.owner.factionId`, `obj.owner.factionRank`
(`core.lua:182-186`). That is what separates "a house" from "a cave with a
chest in it" without any authored data.

---

## 2. Detecting a burglary

**There is no crime-committed hook.** `I.Crimes` exposes exactly one function,
`commitCrime`, for *causing* crimes from Lua, plus a `CommitCrime` event that
calls it (`scripts/omw/crimes.lua`, interface version 2). Nothing reports a
crime the player commits. This is the central constraint and it shapes phase 1.

What is available is `I.Activation`, and it is better than it looks
(`scripts/omw/activationhandlers.lua`):

```lua
I.Activation.addHandlerForType(types.Container, function(obj, actor) ... end)
```

The handler runs in global context on every activation, receives both the object
and the actor, and — critically — vanilla behaviour only runs afterwards, via
`world._runStandardActivationAction`, if no handler returned `false`. So the mod
can **observe without blocking**, and could block later if it ever needs to.

The working definition of an incident, built only from what can actually be
seen:

1. Player activates a `Door` or `Container`, and
2. `obj.owner.recordId` or `obj.owner.factionId` is set (it belongs to someone), and
3. `types.Lockable.isLocked(obj)` was true at the moment of activation, or the
   object's lock level is above zero and it is found unlocked on the next tick.

Condition 3 catches both "picked it" and "opened it with a stolen key". A
next-frame timer comparing `isLocked` before and after is what distinguishes a
break-in from a bounced-off attempt.

`types.Player.getCrimeLevel` (`types.lua:1217`) supplies a second, coarser
signal: a bounty jump in the same tick means the act was *seen*, which is worth
weighting differently from a clean job. It cannot tell you what was taken.

**Not detectable, and deliberately out of scope:** items removed from an
unlocked owned container, trespass, and sleeping in an owned bed. The mod
responds to locks being defeated, not to theft in general. Saying so plainly in
the README is better than approximating it badly.

---

## 3. The building is the interior cell

Grouping incidents needs a notion of "premises", and the interior cell is one
that already exists, needs no authoring, and matches how Morrowind is built:
one house, one interior. Heat accumulates per `cell.id`. Exterior owned objects
are rare enough to ignore in v1 — they are logged and otherwise skipped.

Applying a response means revisiting every lockable in that cell later, which
is the same `cell:getAll` question TravelNetwork phase 0 answers:

```lua
for _, door in ipairs(world.getCellById(cellId):getAll(types.Door)) do ... end
```

Storing `obj.id` strings in save data rather than GameObjects sidesteps
BalanceOfPower's still-open "can a GameObject live in `onSave` data" question
entirely — objects are re-found by matching ids against a cell sweep, so
nothing but strings and numbers is ever persisted.

---

## 4. State

```lua
state.buildings[cellId] = {
    heat = 0,              -- decays daily
    lastIncident = 0,      -- game day index
    incidents = 0,         -- lifetime count, for the escalation ladder
    touched = {            -- every object this mod has modified, for restoration
        [objId] = { baseLevel = 40, baseTrap = '', level = 60, trap = '' },
    },
}
```

`touched` is the honesty mechanism: the mod never raises a lock without
recording what the lock was, so decay restores the authored value exactly rather
than subtracting its way back and drifting.

New sections must load on an old save — same rule as BalanceOfPower, same
`fillDefaults` shape.

---

## 5. The escalation ladder

Applied on the daily tick, not at the moment of the crime — someone has to
notice in the morning and call a locksmith, and the delay is both more plausible
and much easier to reason about than reacting mid-burglary.

| Heat | Response |
|---|---|
| ≥ `HEAT_LOCK_STEP` | Every already-locked lockable in the cell gains `LOCK_STEP` levels, capped at `MAX_LOCK_LEVEL` |
| ≥ `HEAT_TRAP` | The highest-level container in the cell gains `DEFAULT_TRAP_SPELL`, if it had no trap |
| below both, and `DECAY_DAYS` since the last incident | Walk one step back toward the recorded base; at zero heat restore `baseLevel`/`baseTrap` exactly and drop the entry |

Three deliberate cuts, each of which prevents a way this mod could ruin a save:

- **Never lock something that was unlocked.** Only already-locked objects
  escalate. An open door stays open, so no unreachable quest interiors.
- **Never rotate keys.** `setKey` works, and using it would be the most
  interesting response available — and would also silently break any quest that
  hands the player a key. Not worth it.
- **Cap the level.** `MAX_LOCK_LEVEL` keeps a determined burglar's investment in
  Security meaningful instead of arms-racing them out of the game.

Traps are the one genuinely risky response left, so they sit behind a config
flag and a high heat threshold, and only ever land on containers that were
already locked.

---

## 6. Phases

**Phase 0 — done, without this mod having to do anything.** TravelNetwork's
probe answered `cell:getAll` on 2026-08-18: it **does** see cells the player has
never loaded, positions are readable, and a full sweep of every cell costs
~600 ms. See the repo's [engine notes](../openmw-lua-notes.md) §3. Nothing here
is blocked.

**Phase 1 — observation only.** Activation handlers on `Door` and `Container`,
the next-tick lock-state comparison, crime-level delta, an incident log, and a
`dump()` on the interface. The mod changes nothing in the world. Play normally,
rob a few places, and read the log to find out whether the detection rule
actually fires when it should — this is the phase that decides whether the mod
works, and it is cheap to abandon if the answer is no.

**Phase 2 — heat and decay.** Accumulation, the daily tick, decay. Entirely pure
functions over the state table, so the whole phase is unit tests plus a console
dump. Still no world mutation.

**Phase 3 — lock escalation.** The first thing that touches the world, and the
first thing that needs `touched` to be right. Verify restoration works before
moving on: escalate, wait out the decay, confirm the lock is byte-identical to
its authored level.

**Phase 4 — traps.** Behind `TRAPS_ENABLED`.

**Phase 5 (optional) — wealth-shaped baselines.** At first load, vary authored
lock levels by the owner's means: `NpcRecord.baseGold` for a personal owner,
a small table for faction owners. A different mod really, and honest to split it
out if phases 1-4 took longer than expected.

---

## 7. Config constants

`HEAT_PER_INCIDENT`, `HEAT_SEEN_MULTIPLIER`, `HEAT_LOCK_STEP`, `HEAT_TRAP`,
`LOCK_STEP`, `MAX_LOCK_LEVEL`, `DECAY_PER_DAY`, `DECAY_DAYS`, `TRAPS_ENABLED`,
`DEFAULT_TRAP_SPELL`, `TICK_HOUR`.

---

## 8. Tests

Heat accumulation, decay to exactly the authored base, the ladder's thresholds,
the cap, and the "never lock what was unlocked" invariant are all pure table
transformations and belong in the lupa harness. The invariant is the one to
write first and never delete: given a set of objects where some started
unlocked, no sequence of incidents may ever produce a locked one.

Detection cannot be unit tested — it depends on engine ordering — which is
exactly why phase 1 ships as an observation-only build you play with.

---

## 9. Open questions

- Does `cell:getAll` see inactive cells? (Phase 0, shared with TravelNetwork.)
- Is `obj.id` stable across a save/load for content-file objects? The design
  assumes yes for cell-resident objects; worth confirming in phase 1 by dumping
  ids before and after a reload.
- Does the activation handler fire before or after the engine's own lock check —
  i.e. is `isLocked` at handler time the pre- or post-activation state? Phase 1
  answers this by logging both and comparing.
- Do NPCs re-lock doors themselves in any circumstance, and would that collide
  with the restoration bookkeeping?
