# Tests

Headless unit tests for the Balance of Power framework. They load the mod's own
modules against stubbed `openmw.*` packages, so the simulation logic can be
exercised without launching Morrowind.

## Running

Paths are derived from the runner's own location, so it can be invoked from
anywhere:

```sh
pip install lupa
python BalanceOfPower/tests/run.py            # everything
python BalanceOfPower/tests/run.py resolve    # only cases matching a substring
python BalanceOfPower/tests/run.py resolve.cooldown
python BalanceOfPower/tests/run.py -v         # keep the mod's own print() output
```

## Why lupa

OpenMW runs **Lua 5.1**, and its sandbox removes `io`, `package`, `dofile` and
friends. [lupa](https://pypi.org/project/lupa/) embeds a genuine Lua 5.1
interpreter (`lupa.lua51`), which matters: 5.2+ drops `unpack` and `setfenv`,
so a newer interpreter would accept code the game rejects and vice versa.

A standalone `lua5.1` binary would work equally well for the language, but the
runner needs to set `package.path` and read files from disk — both unavailable
inside a `.lua` file here, since the repo's CI rejects `package.*`, `io.*` and
`dofile` in any Lua source. Keeping that on the Python side means the test
files obey exactly the same restrictions as the mod code they exercise.

## Layout

```
BalanceOfPower/
  BalanceOfPower_Framework/   the modules under test
  tests/
    run.py              the runner
    stubs/              fake openmw.* packages
      openmw/core.lua     records events, fakes game time and faction records
      openmw/world.lua    one fake player that records what it is sent
      openmw_aux/time.lua records timers instead of running them
    support/expect.lua  assertions
    cases/*.lua         the tests
```

The runner puts `BalanceOfPower_Framework/` on the Lua module path, so the test
files `require` the framework under its real
`scripts.BalanceOfPower.core.*` names — exactly as OpenMW's VFS presents them.

Each case file returns a table of named functions. A test fails by raising —
`support/expect.lua` does that with a readable message.

## Isolation

The framework's registry and state modules hold module-level tables, so a
reused interpreter would leak one test's factions into the next. The runner
therefore builds a **fresh Lua runtime per test function**. Nothing needs to be
torn down, and tests can't depend on each other's order.

## Writing a test

```lua
local expect = require('support.expect')
local registry = require('scripts.BalanceOfPower.core.registry')

local M = {}

function M.doesTheThing()
    registry.registerLandmass({ id = 'testland', factions = { { id = 'alpha' } } })
    expect.equal(registry.countFactions(), 1, 'faction count')
end

return M
```

Names starting with `_` are ignored, so helpers can live in the same table.

Anything random must be made deterministic rather than seeded — `math.randomseed`
ties results to one Lua build's generator. `resolve.setRandom(fn)` exists for
this; pass a function returning a fixed value to force a roll to succeed or
fail.
