#!/usr/bin/env python3
"""Generate tests/fixtures/vanilla_reactions.lua from the game's ESM files.

The framework reads faction reactions from `core.factions.records` and from
nowhere else. The test suite runs headless against a stub of that package, so
it needs the real numbers from somewhere -- this produces them, by dumping the
FACT records with OpenMW's own `esmtool`.

    python BalanceOfPower/BalanceOfPower_Morrowind/sources/build_reactions_fixture.py

The output is checked in, so CI never needs Morrowind installed. Re-run it only
when the fixture should track a different set of content files.

Two things this deliberately does NOT do:

  * It does not lowercase anything. The ESM stores record ids as they were
    authored -- "Camonna Tong", "Sixth House" -- and the framework normalizes
    case on the way in. A pre-lowercased fixture would hide exactly the bug
    that normalization exists to prevent.
  * It does not strip self-reactions or zeros. Every record carries a reaction
    toward itself, and explicit zeros occur; both are the framework's to
    handle, and a fixture that tidied them away would stop testing that it
    does.

This is test data, not mod data. Nothing under BalanceOfPower_Morrowind/scripts
reads it, and nothing should.
"""

from __future__ import annotations

import argparse
import pathlib
import re
import subprocess
import sys
from collections import OrderedDict

SOURCES = pathlib.Path(__file__).resolve().parent
PACK = SOURCES.parent
PROJECT = PACK.parent
OUT_PATH = PROJECT / "tests" / "fixtures" / "vanilla_reactions.lua"

# Defaults are this machine's; both are overridable, because neither path is
# something a checkout can assume.
DEFAULT_ESMTOOL = pathlib.Path(r"D:\OpenMW 0.51.0\esmtool.exe")
DEFAULT_DATA = pathlib.Path(r"D:\Steam\steamapps\common\Morrowind\Data Files")

# Load order matters: a later file's record replaces an earlier one wholesale,
# the same way the engine loads them.
CONTENT_FILES = ["Morrowind.esm", "Tribunal.esm", "Bloodmoon.esm"]

RECORD_RE = re.compile(r'^Record: FACT "(?P<id>.*)"\s*$')
REACTION_RE = re.compile(r'^\s*Reaction:\s*(?P<value>-?\d+)\s*=\s*"(?P<id>.*)"\s*$')
NAME_RE = re.compile(r"^\s+Name: (?P<name>.*)$")


def dump_factions(esmtool: pathlib.Path, esm: pathlib.Path) -> "OrderedDict[str, dict]":
    """Every FACT record in one content file, in file order."""
    result = subprocess.run(
        [str(esmtool), "dump", "--type", "FACT", str(esm)],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if result.returncode != 0:
        raise SystemExit(f"error: esmtool failed on {esm.name}:\n{result.stderr.strip()}")

    records: OrderedDict[str, dict] = OrderedDict()
    current: dict | None = None
    for line in result.stdout.splitlines():
        record = RECORD_RE.match(line)
        if record:
            current = {"name": "", "reactions": {}}
            records[record.group("id")] = current
            continue
        if current is None:
            continue
        name = NAME_RE.match(line)
        if name and not current["name"]:
            current["name"] = name.group("name").strip()
        reaction = REACTION_RE.match(line)
        if reaction:
            # Duplicate entries for the same pair do occur in vanilla. The
            # engine keeps the last, so this does too.
            current["reactions"][reaction.group("id")] = int(reaction.group("value"))
    return records


def lua_string(value: str) -> str:
    return "'" + value.replace("\\", "\\\\").replace("'", "\\'") + "'"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--esmtool", type=pathlib.Path, default=DEFAULT_ESMTOOL,
                        help="path to OpenMW's esmtool executable")
    parser.add_argument("--data", type=pathlib.Path, default=DEFAULT_DATA,
                        help="path to Morrowind's Data Files directory")
    args = parser.parse_args()

    if not args.esmtool.exists():
        print(f"error: no esmtool at {args.esmtool}", file=sys.stderr)
        return 1

    merged: OrderedDict[str, dict] = OrderedDict()
    counts = []
    for name in CONTENT_FILES:
        esm = args.data / name
        if not esm.exists():
            print(f"error: no content file at {esm}", file=sys.stderr)
            return 1
        records = dump_factions(args.esmtool, esm)
        counts.append((name, len(records)))
        merged.update(records)

    if not merged:
        print("error: no FACT records found -- check the esmtool output format",
              file=sys.stderr)
        return 1

    lines = [
        "-- GENERATED FILE -- do not edit.",
        "--",
        "-- Built from the game's own FACT records by",
        "-- BalanceOfPower_Morrowind/sources/build_reactions_fixture.py.",
        "--",
        "-- TEST DATA, not mod data. The framework reads reactions from",
        "-- core.factions.records at runtime; this stands in for that package when",
        "-- the suite runs headless. Nothing under a mod directory reads it.",
        "--",
        "-- Record ids, names and reaction keys are exactly as the ESM stores",
        "-- them, capitals and all, and self-reactions and explicit zeros are",
        "-- left in. Tidying any of that here would stop the suite testing that",
        "-- the framework handles it.",
        "--",
        "-- Sorted by id, then by reaction target, so a regeneration that changes",
        "-- nothing produces no diff.",
        "",
        "return {",
    ]

    for record_id in sorted(merged):
        record = merged[record_id]
        reactions = record["reactions"]
        lines.append(f"    [{lua_string(record_id)}] = {{")
        lines.append(f"        name = {lua_string(record['name'] or record_id)},")
        if not reactions:
            lines.append("        reactions = {},")
        else:
            lines.append("        reactions = {")
            for other_id in sorted(reactions):
                lines.append(f"            [{lua_string(other_id)}] = {reactions[other_id]},")
            lines.append("        },")
        lines.append("    },")

    lines.append("}")
    lines.append("")

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text("\n".join(lines), encoding="utf-8")

    print(f"wrote {OUT_PATH.relative_to(PROJECT.parent)}")
    for name, count in counts:
        print(f"  {name}: {count} faction records")
    total = sum(len(r["reactions"]) for r in merged.values())
    print(f"  {len(merged)} records, {total} reaction entries")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
