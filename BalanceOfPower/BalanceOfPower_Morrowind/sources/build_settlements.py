#!/usr/bin/env python3
"""Generate data/settlements.lua from sources/settlements.csv.

The CSV is the source of truth and the place to make edits; the Lua file is
generated and should not be hand-edited. Run after changing the CSV:

    python BalanceOfPower/BalanceOfPower_Morrowind/sources/build_settlements.py

One row per cell, so a settlement occupying several cells appears several
times. Rows are grouped by (settlement, landmass) into a single entry with a
cell list, which is what lets Vivec be one fourteen-cell anchor rather than
fourteen separate ones.
"""

from __future__ import annotations

import csv
import pathlib
import sys
from collections import OrderedDict

SOURCES = pathlib.Path(__file__).resolve().parent
PACK = SOURCES.parent
CSV_PATH = SOURCES / "settlements.csv"
OUT_PATH = PACK / "scripts" / "BalanceOfPowerMorrowind" / "data" / "settlements.lua"

# Faction names as written in the CSV, mapped to the ids the framework and
# the game use. Morrowind's ESM3 records use lowercase string ids.
FACTION_IDS = {
    "Hlaalu": "hlaalu",
    "Redoran": "redoran",
    "Telvanni": "telvanni",
    "Tribunal Temple": "temple",
    # The design doc merges Legion / Cult / Knights into one "Empire" for
    # the MVP. Mapping it onto the Legion's own id rather than inventing
    # an `empire` id means the reaction row comes from the game's data
    # instead of being hand-authored -- and the Legion genuinely is the
    # Empire's territorial arm, since every Imperial holding in the list
    # is a fort or a Legion-garrisoned town. The Imperial Cult is kept
    # separate, as a power-only faction.
    "Empire": "imperial legion",
    "Ashlanders": "ashlanders",
    "Sixth House": "sixth house",
    "East Empire Company": "east empire company",
    "Skaal Nords": "skaal",
    # Not a faction: the CSV uses this for holdings with no political
    # owner, which become unclaimed ground rather than anyone's territory.
    "Velothi/Unaffiliated": None,
}

# CSV tier -> (anchor tier, power center tier). A nil anchor tier means the
# location projects influence but is not itself contestable territory --
# farms, shacks and mines shape who a region belongs to without any single
# one of them being worth a war.
TIERS = {
    "Metropolis": ("metropolis", "capital"),
    "Small City": ("city", "capital"),
    "Town": ("town", "regional"),
    "Village": ("village", "regional"),
    "Outpost/Fortress/Camp": ("outpost", "outpost"),
    "Minor location": (None, "minor"),
}

# Individual corrections to the source data, applied on load. Keeping them
# here rather than editing the CSV preserves the original as received.
TIER_OVERRIDES = {
    # A mead hall with its own warrior population and a faction behind it,
    # not a farmstead.
    ("Thirsk", "Solstheim"): "Village",
    # Shares cell -11,11 with Gnisis, which holds it. Left as a power
    # center so the Telvanni presence in the West Gash still registers
    # without two settlements claiming one cell.
    ("Arvs-Drelen", "Vvardenfell"): "Minor location",
}

LANDMASS_IDS = {"Vvardenfell": "vvardenfell", "Solstheim": "solstheim"}


def lua_string(value: str) -> str:
    return "'" + value.replace("\\", "\\\\").replace("'", "\\'") + "'"


def main() -> int:
    with CSV_PATH.open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))

    grouped: OrderedDict[tuple[str, str], dict] = OrderedDict()
    problems = []

    for line, row in enumerate(rows, start=2):
        name = row["settlement"].strip()
        landmass = row["landmass"].strip()
        tier = TIER_OVERRIDES.get((name, landmass), row["tier"].strip())
        faction_name = row["faction"].strip()

        if tier not in TIERS:
            problems.append(f"line {line}: unknown tier {tier!r}")
            continue
        if faction_name not in FACTION_IDS:
            problems.append(f"line {line}: unknown faction {faction_name!r}")
            continue
        if landmass not in LANDMASS_IDS:
            problems.append(f"line {line}: unknown landmass {landmass!r}")
            continue

        entry = grouped.setdefault(
            (name, landmass),
            {
                "name": name,
                "landmass": LANDMASS_IDS[landmass],
                "region": row["region"].strip(),
                "tier": tier,
                "faction": FACTION_IDS[faction_name],
                "cells": [],
            },
        )
        cell = (int(row["cell_x"]), int(row["cell_y"]))
        if cell not in entry["cells"]:
            entry["cells"].append(cell)

    if problems:
        for problem in problems:
            print(f"error: {problem}", file=sys.stderr)
        return 1

    # A cell can only belong to one settlement. Report collisions loudly:
    # the framework would warn at load and silently keep the first claim,
    # which is a poor way to find out.
    seen_cells: dict[tuple[str, int, int], str] = {}
    for entry in grouped.values():
        if entry["tier"] == "Minor location":
            continue  # power centers only; they claim no cells
        for cell in entry["cells"]:
            token = (entry["landmass"], *cell)
            if token in seen_cells:
                print(
                    f"error: cell {cell} claimed by both "
                    f"{seen_cells[token]!r} and {entry['name']!r}",
                    file=sys.stderr,
                )
                return 1
            seen_cells[token] = entry["name"]

    lines = [
        "-- GENERATED FILE -- do not edit.",
        "--",
        "-- Built from sources/settlements.csv by sources/build_settlements.py.",
        "-- Edit the CSV and re-run that script instead.",
        "--",
        "-- One entry per settlement. `cells` lists the exterior grid cells it",
        "-- occupies, so a multi-cell city is a single anchor covering all of",
        "-- them rather than several adjacent ones.",
        "",
        "return {",
    ]

    for entry in grouped.values():
        anchor_tier, centre_tier = TIERS[entry["tier"]]
        lines.append("    {")
        lines.append(f"        name = {lua_string(entry['name'])},")
        lines.append(f"        landmass = {lua_string(entry['landmass'])},")
        lines.append(f"        region = {lua_string(entry['region'])},")
        lines.append(
            f"        anchorTier = {lua_string(anchor_tier) if anchor_tier else 'nil'},"
        )
        lines.append(f"        centerTier = {lua_string(centre_tier)},")
        lines.append(
            f"        faction = {lua_string(entry['faction']) if entry['faction'] else 'nil'},"
        )
        # Wrapped, because the repo lints Lua at a 120-column limit and
        # Vivec's fifteen cells comfortably exceed it on one line.
        cells = [f"{{ {x}, {y} }}" for x, y in entry["cells"]]
        if len(cells) <= 5:
            lines.append(f"        cells = {{ {', '.join(cells)} }},")
        else:
            lines.append("        cells = {")
            for start in range(0, len(cells), 5):
                lines.append("            " + ", ".join(cells[start:start + 5]) + ",")
            lines.append("        },")
        lines.append("    },")

    lines.append("}")
    lines.append("")

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text("\n".join(lines), encoding="utf-8")

    anchors = sum(1 for e in grouped.values() if TIERS[e["tier"]][0])
    centres = len(grouped)
    print(f"wrote {OUT_PATH.relative_to(PACK.parent)}")
    print(f"  {centres} settlements, {anchors} of them contestable anchors")
    for landmass in LANDMASS_IDS.values():
        count = sum(1 for e in grouped.values() if e["landmass"] == landmass)
        print(f"  {landmass}: {count}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
