# openmw-lua

Lua mods for OpenMW. Each top-level directory is either a mod (a directory you
point `data=` at in `openmw.cfg`) or a project containing several.

- **CombatNotify** — accessibility mod: directional indicators when something
  attacks the player. Complete.
- **BalanceOfPower** — faction power and territory control framework, plus a
  foreign-invasion subsystem. In development; see
  [BalanceOfPower/next-steps.md](BalanceOfPower/next-steps.md) for the current
  state and what comes next.

## Where the truth lives

For BalanceOfPower specifically, five documents, in the order to read them:

| Document | What it is |
|---|---|
| [glossary.md](BalanceOfPower/glossary.md) | **Read this first.** Shared vocabulary. Several terms are near-synonyms in English and mean different things here — *cell* vs *territory* above all |
| [next-steps.md](BalanceOfPower/next-steps.md) | Current state, what to do next, open questions |
| [implementation-plan.md](BalanceOfPower/implementation-plan.md) | Phase-by-phase build order, with decisions recorded per phase |
| [balance-of-power-design-doc.md](BalanceOfPower/balance-of-power-design-doc.md) | Original intent. **Historical** — parts have been superseded; it says so at the top |
| [openmw-lua-api-notes.md](BalanceOfPower/openmw-lua-api-notes.md) | Engine API facts, split into verified and unverified |

Each mod also has its own README covering its API and data formats.

## Working on this repo

### Tests

```sh
pip install lupa
python BalanceOfPower/tests/run.py            # all
python BalanceOfPower/tests/run.py resolve    # filter by substring
python BalanceOfPower/tests/run.py -v         # keep the mod's print() output
```

A genuine Lua 5.1 runtime with stubbed `openmw.*` packages, fresh per test. See
[BalanceOfPower/tests/README.md](BalanceOfPower/tests/README.md). **There is no
Lua interpreter or luacheck installed for direct use** — lupa is the only way to
execute this code outside the game, and CI is the only thing that runs luacheck.

Anything touching simulation logic should have a test. The suite has repeatedly
caught things that reading the code did not, including two bugs that would have
shipped silently.

### Regenerating settlement data

`BalanceOfPower_Morrowind/scripts/.../data/settlements.lua` is **generated**.
Edit the CSV, never the Lua:

```sh
python BalanceOfPower/BalanceOfPower_Morrowind/sources/build_settlements.py
```

### Running in-game

Point `openmw.cfg` at the mod directories and list the `.omwscripts`, framework
first. The framework must load before any content pack. `reloadlua` in the
console restarts all Lua without restarting the game.

Reaching the framework from the console (global context):

```
luag require('openmw.interfaces').BalanceOfPower.dumpMap({ mode = 'projection' })
luag require('openmw.interfaces').BalanceOfPower.dump()
```

Output goes to `openmw.log`.

## Rules that must not be broken

**The framework never names content.** `BalanceOfPower_Framework/` knows nothing
about Morrowind, faction ids, or that Balmora is Hlaalu's. The day `core/` needs
`if landmass == 'cyrodiil'`, the abstraction has failed. Content packs depend on
the framework; never the reverse.

The settlement tier ladder is the edge case worth understanding: the framework
owns generic size words (`village`, `town`, `small city`, `metropolis`), and the
pack maps its own source vocabulary onto them in `build_settlements.py`. A tier
name that only makes sense in one game world belongs on the pack's side of that
mapping.

**Content packs reach the framework only through its interface.** The merged VFS
technically lets a pack `require` a core module directly. Doing so couples it to
internals that change between phases.

**Every tunable is a named constant in `core/config.lua`,** never inlined. The
whole thing is unplayable-until-tuned, and burying a number in logic makes it
unfindable.

**New state must load on an old save.** `state.deserialize` starts from a fully
shaped state and `state.fillDefaults` seeds anything the save predates. Adding a
section or a faction must not break an existing game.

## Conventions

**OpenMW's Lua is 5.1 and sandboxed.** No `io.*`, `package.*`, `dofile`,
`loadstring`, `collectgarbage`. CI rejects them in any `.lua` file — including
test files, which is why the test runner does its file loading from Python.

**Every `openmw.*` package is `require`d as a local.** There are no ambient
globals; luacheck runs with `globals = {}`, so an unexpected global is almost
always a typo.

**luacheck fails on warnings, not just errors.** Keep lines at or under 120
characters, no unused locals, no trailing whitespace.

**`.omwscripts` files are validated by CI** — every referenced script must exist,
and the flags must be recognised.

**Verify engine APIs before depending on them.** The API surface moves between
releases. `openmw-lua-api-notes.md` separates what has been checked against the
docs from what has only been assumed; add to it rather than trusting memory.
When a fact is confirmed, move it into the verified section and note the date.

**Comments explain why, not what** — and sparingly. A line or two where a
decision looks arbitrary until you know the reason (why projection uses max and
not sum, why the generation margin is zero, why initial assignment stamps no
cooldown). Don't restate the code, work arithmetic out in prose, or narrate
history the git log holds. Long-form reasoning belongs in
[implementation-plan.md](BalanceOfPower/implementation-plan.md) and the READMEs.

Some older files still carry paragraph-length blocks; trim them when you touch
them rather than matching the density.

## CI

`.github/workflows/lint.yml` runs on push and PR: luacheck, a grep for
sandbox-unavailable APIs, `.omwscripts` validation, l10n validation, and the
Lua unit tests.
