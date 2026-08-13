#!/usr/bin/env python3
"""Headless test runner for the Lua under this repo.

OpenMW's Lua is 5.1 and heavily sandboxed, so the modules under test can't
be loaded by an ordinary Lua install without something standing in for the
`openmw.*` packages. This runner supplies that:

  * a genuine Lua 5.1 runtime, via lupa (`pip install lupa`);
  * `tests/stubs/` on the module path, so `require('openmw.core')` resolves
    to a fake that records what the framework did instead of touching a
    game that isn't running;
  * a fresh runtime per test, so module-level state in the registry and the
    state module can't leak from one test into the next.

All file loading happens here rather than in Lua, deliberately: `package.*`,
`io.*` and `dofile` are unavailable inside OpenMW, and the repo's CI rejects
them in any .lua file. Keeping them on this side means the test files obey
the same restrictions as the mod code they exercise.

Usage:  python tests/run.py [substring-filter ...]
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
PROJECT = TESTS.parent          # the BalanceOfPower project directory
CASES = TESTS / "cases"

# Every directory that can satisfy a require(). Order matters only in that
# the framework's own scripts must be reachable under their real
# `scripts.BalanceOfPower.*` names, exactly as OpenMW's VFS presents them.
SEARCH_ROOTS = [
    PROJECT / "BalanceOfPower_Framework",
    # Content packs, so their real main.lua can be required and exercised
    # exactly as the engine would load it.
    PROJECT / "BalanceOfPower_Morrowind",
    PROJECT / "BalanceOfPower_DevSandbox",
    TESTS / "stubs",
    TESTS,
]


VERBOSE = False


def new_runtime():
    """A fresh Lua 5.1 runtime with the module path configured."""
    runtime = lua51.LuaRuntime(unpack_returned_tuples=True)
    template = ";".join(f"{root.as_posix()}/?.lua" for root in SEARCH_ROOTS)
    runtime.globals().package.path = template
    if not VERBOSE:
        # The framework logs registration and daily summaries through
        # print(). Tests assert on state rather than output, so silence it
        # unless asked -- otherwise every case buries its own result.
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
        # One throwaway runtime just to enumerate the tests in the file.
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
                # Fresh runtime per test: the registry and state modules
                # hold module-level tables, so reusing a runtime would let
                # one test's factions show up in the next one's world.
                module = load_case(new_runtime(), case)
                module[name]()
            except Exception as exc:  # lupa.LuaError, mostly
                # Keep the whole message. Assertion failures raise at
                # level 0 and are one clean line; anything else is a real
                # Lua error whose traceback is the point.
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
