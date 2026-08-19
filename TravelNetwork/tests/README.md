# TravelNetwork tests

```sh
pip install lupa
python TravelNetwork/tests/run.py            # all
python TravelNetwork/tests/run.py vanilla    # filter by substring
python TravelNetwork/tests/run.py -v         # keep print() output
```

A real Lua 5.1 runtime via lupa, fresh per test. **No `openmw.*` package is
stubbed here**, because nothing under test requires one: `graph.lua` takes plain
tables, and everything that touches the engine lives in `adapter.lua`, which
this suite does not exercise.

- `cases/graph.lua` — the merge and mode rules, on hand-built input.
- `cases/vanilla.lua` — the same builder over `fixtures/vanilla_travel.lua`,
  the real shipped data, guarding the counts the ESM dump and the in-game probe
  both produced.
- `support/fixture.lua` — turns the dump into operator tables. It is the
  test-side twin of `adapter.lua`: same output shape, different source, so the
  two disagreeing shows up as a different graph.

The runner is a near-copy of `BalanceOfPower/tests/run.py`. The projects share
no search roots, and a runner that tried to serve both would need to know about
each of them.
