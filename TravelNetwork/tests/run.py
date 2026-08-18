#!/usr/bin/env python3
"""Headless test runner for TravelNetwork's Lua.

Same shape as BalanceOfPower/tests/run.py -- a genuine Lua 5.1 runtime via
lupa, the mod's own directories on the module path, a fresh runtime per test --
and deliberately a separate copy rather than a shared runner, because the two
projects have no reason to agree about their search roots.

The engine is not stubbed here at all. The graph builder and the router take
plain tables and require no `openmw.*` package, which is exactly what makes
them testable; anything that does touch the engine lives in `adapter.lua` and
is not exercised from this suite.

All file loading happens on the Python side: `package.*`, `io.*` and `dofile`
are unavailable inside OpenMW and CI rejects them in any .lua file, so the test
files obey the same restrictions as the mod code they exercise.

Usage:  python TravelNetwork/tests/run.py [substring-filter ...] [-v]
"""

from __future__ import annotations

import sys
import pathlib

try:
    from lupa import lua51
except ImportError:
    print("error: lupa is not installed. Run:  pip install lupa", file=sys.stderr)
    raise SystemExit(2)

TESTS = pathlib.Path(__file__).resolve().parent
PROJECT = TESTS.parent
CASES = TESTS / "cases"

# Every directory that can satisfy a require(). The mod's own scripts must be
# reachable under their real `scripts.TravelNetwork.*` names, exactly as
# OpenMW's VFS presents them.
SEARCH_ROOTS = [
    PROJECT / "TravelNetwork",
    TESTS,
]

VERBOSE = False


def new_runtime():
    """A fresh Lua 5.1 runtime with the module path configured."""
    runtime = lua51.LuaRuntime(unpack_returned_tuples=True)
    template = ";".join(f"{root.as_posix()}/?.lua" for root in SEARCH_ROOTS)
    runtime.globals().package.path = template
    if not VERBOSE:
        runtime.execute("print = function() end")
    return runtime


def load_case(runtime, module_name: str):
    return runtime.eval(f"require('cases.{module_name}')")


def test_names(module) -> list[str]:
    names = [key for key in module.keys() if not str(key).startswith("_")]
    return sorted(str(name) for name in names)


def run() -> int:
    global VERBOSE
    args = sys.argv[1:]
    if "-v" in args or "--verbose" in args:
        VERBOSE = True
        args = [a for a in args if a not in ("-v", "--verbose")]
    filters = [arg.lower() for arg in args]
    case_files = sorted(path.stem for path in CASES.glob("*.lua"))
    if not case_files:
        print("no test cases found under tests/cases/", file=sys.stderr)
        return 2

    passed, failures = 0, []

    for case in case_files:
        names = test_names(load_case(new_runtime(), case))
        selected = [
            name for name in names
            if not filters or any(f in f"{case}.{name}".lower() for f in filters)
        ]
        if not selected:
            continue

        print(f"\n{case}")
        for name in selected:
            label = f"  {name}"
            try:
                # Fresh runtime per test, so a module-level table in one case
                # can never show up in the next.
                module = load_case(new_runtime(), case)
                module[name]()
            except Exception as exc:  # lupa.LuaError, mostly
                message = str(exc).strip()
                print(f"{label}  FAIL")
                for line in message.splitlines():
                    print(f"      {line.strip()}")
                failures.append((case, name, message.splitlines()[0].strip()))
            else:
                print(f"{label}  ok")
                passed += 1

    print()
    if failures:
        print(f"{passed} passed, {len(failures)} FAILED")
        for case, name, message in failures:
            print(f"  {case}.{name}: {message}")
        return 1

    print(f"{passed} passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(run())
