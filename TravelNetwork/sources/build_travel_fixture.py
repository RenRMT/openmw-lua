#!/usr/bin/env python3
"""Generate tests/fixtures/vanilla_travel.lua from the game's own records.

The mod builds its graph at runtime from two engine sources: travel
destinations, which live on NPC/CREA records, and the operators' own positions,
which live in the cells they are placed in. Neither is reachable from a headless
test, so this reproduces both with OpenMW's esmtool:

    python TravelNetwork/sources/build_travel_fixture.py

Two esmtool passes per content file. The first reads NPC_ and CREA records and
keeps the ones carrying travel destinations. The second walks cells with -C and
keeps the references that place those records -- the *near* end of every edge,
which no record carries.

The report it prints is half the point. It names every operator class actually
present in the shipped data, which is what data/modes.lua has to cover, and
flags the operators whose class says nothing useful.

TEST DATA, not mod data. Nothing under a mod directory reads this file. If the
runtime turns out not to see operators in unloaded cells, the placement half of
this parse is also what would be shipped as a data file -- but that is a
different generator, written only if the probe says so.

Deliberate choices worth knowing about:

  * Record ids keep the ESM's own capitalisation ('Nevosi Hlan' next to
    'navam veran'), because the engine's are inconsistent in exactly that way
    and a pre-normalised fixture would hide case bugs.
  * Rotations are converted to radians. esmtool prints degrees; the Lua API
    returns radians, and a fixture in the wrong units is a trap.
  * Exterior destinations and placements carry no cell name, because the ESM
    gives none -- only a position. Absence of `cell` is how the fixture says
    "exterior"; `exteriorNames` maps grid coordinates to the name of the
    exterior cells the game bothered to name.
  * Deleted references are skipped. Everything else is left exactly as found,
    including operators placed more than once.
"""

from __future__ import annotations

import argparse
import math
import pathlib
import re
import subprocess
import sys
from collections import Counter, OrderedDict

SOURCES = pathlib.Path(__file__).resolve().parent
PROJECT = SOURCES.parent
OUT_PATH = PROJECT / "tests" / "fixtures" / "vanilla_travel.lua"

# Defaults are this machine's; both are overridable, because neither path is
# something a checkout can assume.
DEFAULT_ESMTOOL = pathlib.Path(r"D:\OpenMW 0.51.0\esmtool.exe")
DEFAULT_DATA = pathlib.Path(r"D:\Steam\steamapps\common\Morrowind\Data Files")

# Load order matters: a later file's record replaces an earlier one wholesale,
# the same way the engine loads them.
CONTENT_FILES = ["Morrowind.esm", "Tribunal.esm", "Bloodmoon.esm"]

# Classes whose mode the mod can name. Anything outside this set still forms
# edges; it just gets reported here so data/modes.lua can be extended or an
# id-level override written.
KNOWN_CLASSES = {"Caravaner", "Shipmaster", "Guild Guide", "Gondolier"}

RECORD_RE = re.compile(r'^Record: (?P<type>NPC_|CREA) "(?P<id>.*)"\s*$')
NAME_RE = re.compile(r"^  Name: (?P<name>.*)$")
CLASS_RE = re.compile(r'^  Class: "(?P<class>.*)"$')
SERVICES_RE = re.compile(r"^\s+AI Services:0x(?P<mask>[0-9A-Fa-f]+)\s*$")
DEST_POS_RE = re.compile(r"^  Destination Position: \((?P<vec>[^)]*)\)\s*$")
DEST_ROT_RE = re.compile(r"^  Destination Rotation: \((?P<vec>[^)]*)\)\s*$")
DEST_CELL_RE = re.compile(r"^  Destination Cell: (?P<cell>.*)$")

CELL_HEADER_RE = re.compile(r"^Record: CELL\s*$")
CELL_FLAGS_RE = re.compile(r"^  Flags: .*\(0x(?P<mask>[0-9A-Fa-f]+)\)\s*$")
CELL_COORDS_RE = re.compile(r"^  Coordinates:\s+\((?P<x>-?\d+),(?P<y>-?\d+)\)\s*$")
REF_START_RE = re.compile(r"^  - Refnum: (?P<refnum>\d+)\s*$")
REF_ID_RE = re.compile(r'^    ID: "(?P<id>.*)"\s*$')
REF_POS_RE = re.compile(r"^    Position: \((?P<vec>[^)]*)\)\s*$")
REF_ROT_RE = re.compile(r"^    Rotation: \((?P<vec>[^)]*)\)\s*$")
REF_DELETED_RE = re.compile(r"^    Deleted: (?P<value>\d+)\s*$")

CELL_INTERIOR_FLAG = 0x1


def run_esmtool(esmtool: pathlib.Path, esm: pathlib.Path, args: list[str]):
    """Yield esmtool's stdout line by line.

    Streamed rather than collected: a cell dump of Morrowind.esm runs to
    millions of lines and only a few dozen of them are wanted.
    """
    process = subprocess.Popen(
        [str(esmtool), "dump", *args, str(esm)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    assert process.stdout is not None
    for line in process.stdout:
        yield line.rstrip("\n")
    process.stdout.close()
    if process.wait() != 0:
        stderr = process.stderr.read().strip() if process.stderr else ""
        raise SystemExit(f"error: esmtool failed on {esm.name}:\n{stderr}")


def parse_vec(text: str) -> list[float]:
    return [float(part) for part in text.split(",")]


def to_radians(vec: list[float]) -> list[float]:
    return [math.radians(component) for component in vec]


def dump_operators(esmtool: pathlib.Path, esm: pathlib.Path) -> "OrderedDict[str, dict]":
    """Every NPC/CREA record in one content file that carries a destination."""
    records: OrderedDict[str, dict] = OrderedDict()
    current: dict | None = None

    for line in run_esmtool(esmtool, esm, ["--type", "NPC_", "--type", "CREA"]):
        header = RECORD_RE.match(line)
        if header:
            current = {
                "id": header.group("id"),
                "type": "NPC" if header.group("type") == "NPC_" else "Creature",
                "name": "",
                "class": "",
                "services": 0,
                "destinations": [],
            }
            records[header.group("id")] = current
            continue
        if current is None:
            continue

        name = NAME_RE.match(line)
        if name and not current["name"]:
            current["name"] = name.group("name").strip()
            continue
        klass = CLASS_RE.match(line)
        if klass:
            current["class"] = klass.group("class")
            continue
        services = SERVICES_RE.match(line)
        if services:
            current["services"] = int(services.group("mask"), 16)
            continue

        position = DEST_POS_RE.match(line)
        if position:
            current["destinations"].append({"position": parse_vec(position.group("vec"))})
            continue
        if not current["destinations"]:
            continue
        # Rotation and cell always follow the position they belong to.
        rotation = DEST_ROT_RE.match(line)
        if rotation:
            current["destinations"][-1]["rotation"] = to_radians(parse_vec(rotation.group("vec")))
            continue
        cell = DEST_CELL_RE.match(line)
        if cell:
            current["destinations"][-1]["cell"] = cell.group("cell").strip()

    return OrderedDict(
        (record_id, record)
        for record_id, record in records.items()
        if record["destinations"]
    )


def dump_placements(esmtool: pathlib.Path, esm: pathlib.Path, wanted: set[str]):
    """Where each wanted record is placed, plus the named exterior cells.

    Both come out of the same pass because both live in CELL records and the
    pass is the expensive part.
    """
    placements: dict[str, list[dict]] = {}
    exterior_names: dict[tuple[int, int], str] = {}

    cell: dict = {}
    ref: dict | None = None

    def flush(reference: dict | None) -> None:
        if reference is None or reference.get("deleted"):
            return
        if reference["id"] not in wanted or "position" not in reference:
            return
        entry = {
            "position": reference["position"],
            "rotation": reference.get("rotation", [0.0, 0.0, 0.0]),
            "isInterior": bool(cell.get("interior")),
        }
        if cell.get("interior"):
            entry["cell"] = cell.get("name", "")
        else:
            if cell.get("grid"):
                entry["grid"] = list(cell["grid"])
            if cell.get("name"):
                entry["cell"] = cell["name"]
        placements.setdefault(reference["id"], []).append(entry)

    for line in run_esmtool(esmtool, esm, ["-C", "--type", "CELL"]):
        if CELL_HEADER_RE.match(line):
            flush(ref)
            ref = None
            cell = {}
            continue

        start = REF_START_RE.match(line)
        if start:
            flush(ref)
            ref = {}
            continue

        if not ref:
            # Still reading the cell header.
            name = NAME_RE.match(line)
            if name:
                cell["name"] = name.group("name").strip()
                continue
            flags = CELL_FLAGS_RE.match(line)
            if flags:
                cell["interior"] = bool(int(flags.group("mask"), 16) & CELL_INTERIOR_FLAG)
                continue
            coords = CELL_COORDS_RE.match(line)
            # Interior cells print a coordinate pair too, and it is garbage.
            if coords and not cell.get("interior"):
                cell["grid"] = (int(coords.group("x")), int(coords.group("y")))
                if cell.get("name"):
                    exterior_names[cell["grid"]] = cell["name"]
                continue

        identifier = REF_ID_RE.match(line)
        if identifier and ref is not None:
            ref["id"] = identifier.group("id")
            continue
        if not ref or "id" not in ref:
            continue

        position = REF_POS_RE.match(line)
        if position:
            ref["position"] = parse_vec(position.group("vec"))
            continue
        rotation = REF_ROT_RE.match(line)
        if rotation:
            ref["rotation"] = to_radians(parse_vec(rotation.group("vec")))
            continue
        deleted = REF_DELETED_RE.match(line)
        if deleted:
            ref["deleted"] = deleted.group("value") != "0"

    flush(ref)
    return placements, exterior_names


def lua_string(value: str) -> str:
    return "'" + value.replace("\\", "\\\\").replace("'", "\\'") + "'"


def lua_vec(vec: list[float]) -> str:
    return "{ " + ", ".join(f"{component:.4f}" for component in vec) + " }"


def lua_entry(fields: list[tuple[str, str]], indent: int) -> list[str]:
    """One table constructor, a field per line.

    Wrapped rather than inlined because luacheck runs over this file like any
    other and fails on a line past 120 characters, which a cell name and two
    vectors comfortably exceed.
    """
    pad = " " * indent
    lines = [pad + "{"]
    for key, value in fields:
        lines.append(f"{pad}    {key} = {value},")
    lines.append(pad + "},")
    return lines


def emit(operators: "OrderedDict[str, dict]", exterior_names: dict) -> str:
    lines = [
        "-- GENERATED FILE -- do not edit.",
        "--",
        "-- Built from the game's own records by",
        "-- TravelNetwork/sources/build_travel_fixture.py.",
        "--",
        "-- TEST DATA, not mod data. The mod reads destinations from NPC records",
        "-- and operator positions from cells at runtime; this stands in for both",
        "-- when the suite runs headless. Nothing under a mod directory reads it.",
        "--",
        "-- Positions are game units, rotations radians (esmtool prints degrees;",
        "-- the Lua API returns radians, so the conversion happens here). A",
        "-- destination or placement with no `cell` is in the exterior worldspace,",
        "-- which is what the ESM says and all it says -- `exteriorNames` maps the",
        "-- grid coordinates of the named exterior cells to their names.",
        "--",
        "-- Sorted by record id, so a regeneration that changes nothing produces",
        "-- no diff. Placements keep the order the cells gave them.",
        "",
        "return {",
        "    operators = {",
    ]

    for record_id in sorted(operators, key=str.lower):
        record = operators[record_id]
        lines.append("        {")
        lines.append(f"            id = {lua_string(record_id)},")
        lines.append(f"            name = {lua_string(record['name'] or record_id)},")
        lines.append(f"            class = {lua_string(record['class'])},")
        lines.append(f"            recordType = {lua_string(record['type'])},")
        # The raw AI services bitmask. Vanilla leaves it empty on nearly every
        # travel operator, which is why the mod keys off destinations instead.
        lines.append(f"            services = 0x{record['services']:08X},")

        lines.append("            placements = {")
        for placement in record.get("placements", []):
            fields = []
            if placement.get("cell"):
                fields.append(("cell", lua_string(placement["cell"])))
            fields.append(("position", lua_vec(placement["position"])))
            fields.append(("rotation", lua_vec(placement["rotation"])))
            fields.append(("isInterior", "true" if placement["isInterior"] else "false"))
            if placement.get("grid"):
                fields.append(("grid", f"{{ {placement['grid'][0]}, {placement['grid'][1]} }}"))
            lines.extend(lua_entry(fields, 16))
        lines.append("            },")

        lines.append("            destinations = {")
        for destination in record["destinations"]:
            fields = []
            if destination.get("cell"):
                fields.append(("cell", lua_string(destination["cell"])))
            fields.append(("position", lua_vec(destination["position"])))
            fields.append(("rotation", lua_vec(destination.get("rotation", [0.0, 0.0, 0.0]))))
            lines.extend(lua_entry(fields, 16))
        lines.append("            },")
        lines.append("        },")

    lines.append("    },")
    lines.append("    exteriorNames = {")
    for grid in sorted(exterior_names):
        key = "%d,%d" % grid
        lines.append(f"        [{lua_string(key)}] = {lua_string(exterior_names[grid])},")
    lines.append("    },")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def report(operators: "OrderedDict[str, dict]", per_file: list, exterior_names: dict) -> None:
    """What the dump is actually for: the answers, printed."""
    print()
    for name, count, creatures in per_file:
        note = f", {creatures} of them creatures" if creatures else ", none of them creatures"
        print(f"  {name}: {count} records with travel destinations{note}")

    destinations = sum(len(r["destinations"]) for r in operators.values())
    interior = sum(1 for r in operators.values() for d in r["destinations"] if d.get("cell"))
    print(f"  {len(operators)} operators, {destinations} destinations "
          f"({interior} interior, {destinations - interior} exterior)")
    print(f"  {len(exterior_names)} named exterior cells")

    print()
    print("  operator classes:")
    for klass, count in Counter(r["class"] for r in operators.values()).most_common():
        mark = " " if klass in KNOWN_CLASSES else "?"
        print(f"    {mark} {klass or '(none)':<14} {count}")

    unknown = [r for r in operators.values() if r["class"] not in KNOWN_CLASSES]
    if unknown:
        print()
        print("  operators whose class names no mode -- each needs a decision:")
        for record in sorted(unknown, key=lambda r: r["id"].lower()):
            where = ", ".join(p.get("cell") or "exterior" for p in record.get("placements", []))
            print(f"    {record['id']!r} ({record['name']}, {record['class']}) "
                  f"in {where or 'NOWHERE'}: {len(record['destinations'])} destination(s)")

    unplaced = [r for r in operators.values() if not r.get("placements")]
    if unplaced:
        print()
        print("  operators no cell places -- unreachable, or placed by a script:")
        for record in sorted(unplaced, key=lambda r: r["id"].lower()):
            print(f"    {record['id']!r} ({record['name']}, {record['class']})")

    with_flag = [r for r in operators.values() if r["services"]]
    print()
    print(f"  {len(with_flag)} of {len(operators)} operators set any AI services bit at all; "
          "travel has no bit of its own,")
    print("  so a non-empty destination list is the only reliable signal that "
          "someone offers travel.")


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
    per_file = []
    for name in CONTENT_FILES:
        esm = args.data / name
        if not esm.exists():
            print(f"error: no content file at {esm}", file=sys.stderr)
            return 1
        print(f"reading records from {name} ...")
        records = dump_operators(args.esmtool, esm)
        creatures = sum(1 for r in records.values() if r["type"] == "Creature")
        per_file.append((name, len(records), creatures))
        merged.update(records)

    if not merged:
        print("error: no travel destinations found -- check the esmtool output format",
              file=sys.stderr)
        return 1

    # Placement comes second because it needs to know which ids to keep, and a
    # later content file can place -- or move -- an operator the first defined.
    exterior_names: dict[tuple[int, int], str] = {}
    for name in CONTENT_FILES:
        print(f"walking cells in {name} ...")
        placements, names = dump_placements(args.esmtool, args.data / name, set(merged))
        exterior_names.update(names)
        for record_id, entries in placements.items():
            merged[record_id].setdefault("placements", []).extend(entries)

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text(emit(merged, exterior_names), encoding="utf-8")

    print()
    print(f"wrote {OUT_PATH.relative_to(PROJECT.parent)}")
    report(merged, per_file, exterior_names)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
