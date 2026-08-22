#!/usr/bin/env python3
"""Generate TravelAgents/scripts/TravelAgents/data/operators.lua.

Where every travel operator in a given load order is standing.

The mod can find out *which* records offer travel without touching the world:
that lives on the record, and reading every NPC and creature record is cheap.
What it cannot get cheaply is where each of them is *standing* -- the near end
of a leg is a placement, and finding a placement means asking cells what is in
them. On a load order with two mainlands that is ten thousand cells at about a
millisecond each.

This turns that into a hint. Given the answer for the load orders most people
run, the mod opens one cell per operator instead of all of them -- about 130
against 10,319 -- and only falls back to walking everything when it finds an
operator the table does not account for.

The table is a hint and never an authority. The mod reads the live position
off the object it finds, and any operator not where the table says triggers
the full walk, so a stale entry costs speed and never correctness.

    python TravelAgents/sources/build_operators.py

Add content files with --content, in load order: later files win, so a patch
that moves an operator must come after the file that placed them.

The defaults are meant to be the load order most people actually run rather
than the smallest one that works. Province: Cyrodiil is played with Tamriel
Rebuilt by most of the people who play it at all, and the patch between them
moves at least one travel operator -- so the patch belongs in this list, and
leaving it out costs every one of those players a full cell walk per load.

Cells are recorded as grid coordinates for exteriors and as a name for
interiors, because `world.getExteriorCell` and `world.getCellByName` take
exactly those. Nothing here has to know how the engine spells a cell id.
"""

from __future__ import annotations

import argparse
import pathlib
import re
import subprocess
import sys
from collections import OrderedDict

SOURCES = pathlib.Path(__file__).resolve().parent
MOD = SOURCES.parent
OUT_PATH = MOD / "scripts" / "TravelAgents" / "data" / "operators.lua"

DEFAULT_ESMTOOL = pathlib.Path(r"D:\OpenMW 0.51.0\esmtool.exe")
MODS = pathlib.Path(r"D:/Morrowind mods/04 landmass")
DEFAULT_CONTENT = [
    r"D:\Steam\steamapps\common\Morrowind\Data Files\Morrowind.esm",
    r"D:\Steam\steamapps\common\Morrowind\Data Files\Tribunal.esm",
    r"D:\Steam\steamapps\common\Morrowind\Data Files\Bloodmoon.esm",
    r"D:/Morrowind mods/02 resources/Tamriel_Data_25.05/00 Data Files/Tamriel_Data.esm",
    # In load order. Later files win, so this list is not a set of content --
    # it is a sequence, and getting it wrong silently changes the answer.
    str(MODS / "Tamriel Rebuilt 25.08.12-42145-25-08-12-1755040619/00 Core/TR_Mainland.esm"),
    str(MODS / "Cyr_Main-44922-25-05a-1747259314/00 Core/Cyr_Main.esm"),
    str(MODS / "Sky_Main-44921-25-05-1746468832/00 Core/Sky_Main.esm"),
]

CELL_RE = re.compile(r"^Record: CELL")
NAME_RE = re.compile(r"^  Name: (.*)$")
FLAGS_RE = re.compile(r"^  Flags: (.*)$")
COORD_RE = re.compile(r"^  Coordinates:\s+\((-?\d+),\s*(-?\d+)\)")
REF_ID_RE = re.compile(r'^    ID: "(.*)"$')
DELETED_RE = re.compile(r"^    Deleted: (\d+)$")


def travel_record_ids(esmtool: pathlib.Path, files: list[pathlib.Path]) -> set[str]:
    """Every record id that offers travel, lowercased."""
    wanted: set[str] = set()
    for esm in files:
        for kind in ("NPC_", "CREA"):
            out = subprocess.run(
                [str(esmtool), "dump", "--type", kind, "--plain", str(esm)],
                capture_output=True, text=True, errors="replace").stdout
            current = None
            for line in out.splitlines():
                match = re.match(r'^Record: (?:NPC_|CREA) "(.*)"\s*$', line)
                if match:
                    current = match.group(1)
                elif current and line.startswith("  Destination Position:"):
                    wanted.add(current.lower())
                    current = None
    return wanted


def placements(esmtool: pathlib.Path, esm: pathlib.Path, wanted: set[str]):
    """Stream one file's cells, yielding (operator id, cell) for wanted refs."""
    process = subprocess.Popen(
        [str(esmtool), "dump", "-C", "--plain", str(esm)],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        text=True, errors="replace", bufsize=1024 * 1024)

    cell: dict = {}
    ref_id: str | None = None
    assert process.stdout is not None
    for line in process.stdout:
        line = line.rstrip("\n")
        if CELL_RE.match(line):
            cell = {"name": "", "interior": False, "grid": None}
            ref_id = None
            continue
        match = NAME_RE.match(line)
        if match and not cell.get("seen_refs"):
            cell["name"] = match.group(1)
            continue
        match = FLAGS_RE.match(line)
        if match:
            cell["interior"] = "Interior" in match.group(1)
            continue
        match = COORD_RE.match(line)
        if match:
            cell["grid"] = (int(match.group(1)), int(match.group(2)))
            continue
        if line == "  References:":
            cell["seen_refs"] = True
            continue
        match = REF_ID_RE.match(line)
        if match:
            candidate = match.group(1).lower()
            ref_id = candidate if candidate in wanted else None
            continue
        match = DELETED_RE.match(line)
        if match and ref_id:
            if match.group(1) == "0":
                yield ref_id, dict(cell)
            ref_id = None
    process.wait()


def lua_cell(cell: dict) -> str:
    if not cell["interior"] and cell["grid"] is not None:
        return "{ x = %d, y = %d }" % cell["grid"]
    name = cell["name"].replace("\\", "\\\\").replace("'", "\\'")
    return "{ name = '%s' }" % name


def render(found: "OrderedDict[str, list]", files: list[pathlib.Path], cells: int) -> str:
    lines = [
        "-- GENERATED FILE -- do not edit.",
        "--",
        "-- Where each travel operator stands, so the mod does not have to ask",
        "-- every cell in the load order. Built by",
        "-- TravelAgents/sources/build_operators.py.",
        "--",
        "-- The mod reads the live position off the object it finds here;",
        "-- an operator that has moved, or one this table has never heard of,",
        "-- sends it back to walking every cell. Exteriors are grid coordinates",
        "-- and interiors are cell names.",
        "--",
        "-- Built from:",
    ]
    for esm in files:
        lines.append("--   %s" % esm.name)
    lines += [
        "-- %d record(s) that offer travel, %d placement(s) between them."
        % (len(found), cells),
        "",
        "return {",
    ]
    for operator in sorted(found):
        rendered = ", ".join(lua_cell(cell) for cell in found[operator])
        lines.append("    ['%s'] = { %s }," % (operator.replace("'", "\\'"), rendered))
    lines += ["}", ""]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--esmtool", type=pathlib.Path, default=DEFAULT_ESMTOOL)
    parser.add_argument("--content", nargs="*", default=DEFAULT_CONTENT)
    args = parser.parse_args()

    if not args.esmtool.exists():
        print("error: no esmtool at %s" % args.esmtool, file=sys.stderr)
        return 2
    files = [pathlib.Path(name) for name in args.content]
    for esm in files:
        if not esm.exists():
            print("error: no content file at %s" % esm, file=sys.stderr)
            return 2

    wanted = travel_record_ids(args.esmtool, files)
    print("%d record(s) offer travel" % len(wanted))

    # Later files win, because that is what a load order does. A patch that
    # moves an operator -- Province: Cyrodiil puts Titus Corilex on Vvardenfell
    # and the Tamriel Rebuilt patch moves him to Old Ebonheart's docks -- must
    # replace the earlier placement, not add to it. Accumulating both would
    # give him two hints, and the mod reads a hint list as "standing in all of
    # these", so he would fail the check and cost a full walk on every load.
    #
    # Within one file placements do accumulate: a record genuinely placed
    # twice by the same file is standing in two cells, and both are real.
    found: "OrderedDict[str, list]" = OrderedDict()
    moved: "OrderedDict[str, str]" = OrderedDict()
    for esm in files:
        here: "OrderedDict[str, list]" = OrderedDict()
        for operator, cell in placements(args.esmtool, esm, wanted):
            here.setdefault(operator, []).append(cell)

        relocated = 0
        for operator, cells in here.items():
            if operator in found and found[operator] != cells:
                moved[operator] = esm.name
                relocated += 1
            found[operator] = cells

        note = ", %d moved from an earlier file" % relocated if relocated else ""
        print("  %-22s %d placement(s)%s"
              % (esm.name, sum(len(c) for c in here.values()), note))

    total = sum(len(cells) for cells in found.values())

    # A record that offers travel and is placed nowhere is still *accounted
    # for*: an empty list says "looked, stands nowhere". Leaving it out would
    # read as "never looked" and send the mod back to walking every cell for
    # somebody who is not there -- and vanilla alone has four of them.
    missing = sorted(wanted - set(found))
    for operator in missing:
        found[operator] = []

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text(render(found, files, total), encoding="utf-8")

    print("\n%d of %d located, %d placement(s) -> %s"
          % (len(found), len(wanted), total, OUT_PATH))
    if missing:
        print("not placed anywhere (the mod will not find these either): %s"
              % ", ".join(missing))
    if moved:
        print("moved by a later file: %s"
              % ", ".join("%s (%s)" % (o, f) for o, f in sorted(moved.items())))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
