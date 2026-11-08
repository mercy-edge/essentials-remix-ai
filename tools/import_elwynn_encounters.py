#!/usr/bin/env python3
"""
Pull Elwynn Encounters (romhack vertical layout) from Google Sheets → PBS/encounters.txt.

Layout: row of map names (2 cols each: name | level), Land/Old Rod sections,
Common x5, Uncommon x4, Rare x2 per section.

Usage:
  python tools/import_elwynn_encounters.py
  python tools/import_elwynn_encounters.py --apply
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PBS_ENC = ROOT / "PBS" / "encounters.txt"
SHEET_URL_FILE = ROOT / "ContentTracker" / "spreadsheet_url.txt"

sys.path.insert(0, str(ROOT / "tools"))
from export_elwynn_encounters import parse_encounters  # noqa: E402
from romhack_sheet_common import EMPTY_LEVEL, EMPTY_NAME, RARITY_SLOTS  # noqa: E402
from sheets_bridge import get_sheets_service, spreadsheet_id  # noqa: E402

NAME_TO_MAP = {
    "Northshire Abbey": 76,
    "Northshire Vineyards": 42,
    "Echo Ridge Mine": 33,
    "Forest's Edge": 83,
    "Goldshire": 77,
    "Brackwell Pumpkin Patch": 79,
    "The Stonefield Farm": 92,
    "The Maclure Vineyards": 87,
    "Eastvale Logging Camp": 81,
    "Jerod's Landing": 86,
    "Crystal Lake": 80,
    "Mirror Lake": 88,
    "Mirror Lake Orchard": 89,
    "Stone Cairn Lake": 91,
    "Thunder Falls": 94,
    "Fargodeep Mine": 82,
    "Jasperlode Mine": 85,
    "Heroes' Vigil": 84,
    "Ridgepoint Tower": 90,
    "Tower of Azora": 95,
    "Westbrook Garrison": 96,
}

DETAIL_TO_TYPE = {
    "Land": "Land",
    "Cave": "Cave",
    "Old Rod": "OldRod",
}

RARITY_DEFAULT = {"Common": 30, "Uncommon": 15, "Rare": 4}
DEFAULT_DENSITY = {
    "Land": "10",
    "Cave": "8",
    "OldRod": "",
}

CAVE_MAPS = {33, 82, 85}


def species_id(name: str) -> str:
    n = name.strip()
    specials = {
        "Nidoran♀": "NIDORANF",
        "Nidoran♂": "NIDORANM",
        "Farfetch'd": "FARFETCHD",
        "Mr. Mime": "MRMIME",
        "Mime Jr.": "MIMEJR",
        "Mr. Rime": "MRRIME",
        "Type: Null": "TYPE_NULL",
        "Ho-Oh": "HOOH",
        "Porygon-Z": "PORYGONZ",
        "Porygon2": "PORYGON2",
    }
    if n in specials:
        return specials[n]
    m = re.match(r"^(.+?)\s+\((.+)\)$", n)
    if m:
        base = re.sub(r"[^A-Za-z0-9]", "", m.group(1)).upper()
        form = re.sub(r"[^A-Za-z0-9]", "", m.group(2)).upper()
        return f"{base}_{form}"
    return re.sub(r"[^A-Za-z0-9]", "", n).upper()


def parse_levels(text: str):
    t = str(text).strip().lstrip("'").replace("–", "-").replace("—", "-").replace(" ", "")
    if not t or t == EMPTY_LEVEL:
        return 1, 1
    # Reject Excel date serials if Sheets still coerced a value
    if t.isdigit() and int(t) > 1000:
        return 1, 1
    if "-" in t:
        a, b = t.split("-", 1)
        return int(a), int(b)
    return int(t), int(t)


def is_empty_name(name: str) -> bool:
    return name.strip() in ("", EMPTY_NAME, "—", "-", "–", "------", "\\-----")


def pull_sheet_zones(spreadsheet: str):
    svc, _, _ = get_sheets_service()
    sid = spreadsheet_id(spreadsheet)
    rows = (
        svc.spreadsheets()
        .values()
        .get(spreadsheetId=sid, range="'Elwynn Encounters'")
        .execute()
        .get("values", [])
    )

    if len(rows) < 4:
        sys.exit("Sheet too short — expected title, map header, subheader, and data rows")

    header = rows[1]
    map_columns = []
    for ci in range(1, len(header), 2):
        name = str(header[ci]).strip() if ci < len(header) else ""
        if not name or name.lower() == "map":
            continue
        map_columns.append((ci, name))

    zones = {}
    for ci, name in map_columns:
        zones[name] = {
            "map_id": NAME_TO_MAP.get(name),
            "name": name,
            "entries": [],
        }

    current_method = "Land"
    current_rarity = None
    data_rows_left = 0

    for row in rows[3:]:
        cells = [str(c).strip() if c is not None else "" for c in row]
        label = cells[0] if cells else ""

        if label == "Land":
            current_method = "Land"
            current_rarity = None
            data_rows_left = 0
            continue
        if label == "Old Rod":
            current_method = "Old Rod"
            current_rarity = None
            data_rows_left = 0
            continue
        if label in RARITY_SLOTS:
            current_rarity = label
            data_rows_left = RARITY_SLOTS[label]
            continue

        if current_rarity and data_rows_left > 0:
            for ci, name in map_columns:
                if name not in zones:
                    continue
                pname = cells[ci] if ci < len(cells) else ""
                plvl = cells[ci + 1] if ci + 1 < len(cells) else ""
                if is_empty_name(pname):
                    continue
                mn, mx = parse_levels(plvl)
                detail = current_method if current_method != "Land" else "Land"
                mid = zones[name]["map_id"]
                if detail == "Land" and mid in CAVE_MAPS:
                    detail = "Cave"
                zones[name]["entries"].append({
                    "detail": detail,
                    "rarity": current_rarity,
                    "species": species_id(pname),
                    "display": pname,
                    "min": mn,
                    "max": mx,
                    "chance": RARITY_DEFAULT[current_rarity],
                })
            data_rows_left -= 1

    return zones


def sniff_densities_from_file():
    text = PBS_ENC.read_text(encoding="utf-8")
    dens = {}
    map_id = None
    for line in text.splitlines():
        m = re.match(r"^\[(\d+)", line.strip())
        if m:
            map_id = int(m.group(1))
            dens.setdefault(map_id, {})
            continue
        tm = re.match(r"^([A-Za-z]+)(?:,(\d+))?$", line.strip())
        if tm and map_id is not None and not re.match(r"^\d+,", line.strip()):
            dens[map_id][tm.group(1)] = tm.group(2) or ""
    return dens


def format_map_block(map_id, name, entries, densities):
    groups = []
    order = []
    for e in entries:
        et = DETAIL_TO_TYPE.get(e["detail"], e["detail"].replace(" ", ""))
        if et not in order:
            order.append(et)
            groups.append((et, []))
        for et2, lst in groups:
            if et2 == et:
                lst.append(e)
                break

    lines = [f"#-------------------------------", f"[{map_id:03d}] # {name}"]
    for et, lst in groups:
        dens = densities.get(map_id, {}).get(et)
        if dens is None:
            dens = DEFAULT_DENSITY.get(et, "10")
        lines.append(f"{et},{dens}" if dens != "" else et)
        for e in lst:
            if e["min"] == e["max"]:
                lines.append(f"    {e['chance']},{e['species']},{e['min']}")
            else:
                lines.append(f"    {e['chance']},{e['species']},{e['min']},{e['max']}")
    return "\n".join(lines) + "\n"


def replace_map_section(text: str, map_id: int, new_block: str) -> str:
    pattern = re.compile(
        rf"(?ms)^#-------------------------------\r?\n\[{map_id:03d}\][^\n]*\n.*?(?=^#-------------------------------\r?\n\[|\Z)"
    )
    block = new_block if new_block.endswith("\n") else new_block + "\n"
    if pattern.search(text):
        return pattern.sub(block, text, count=1)
    return text.rstrip() + "\n" + block


def rebuild_encounters_txt(zones, apply: bool):
    densities = sniff_densities_from_file()
    original = PBS_ENC.read_text(encoding="utf-8")
    new_blocks = {}
    zone_by_id = {}

    for zname, z in zones.items():
        mid = z["map_id"]
        if mid is None:
            print(f"WARN: unknown map column {zname!r}")
            continue
        if not z["entries"]:
            continue
        new_blocks[mid] = format_map_block(mid, z["name"], z["entries"], densities)
        zone_by_id[mid] = z

    old_maps = parse_encounters()
    print("Changes:")
    any_diff = False
    content_diffs = []

    for mid in sorted(new_blocks.keys()):
        z = zone_by_id[mid]
        old_slots = old_maps.get(mid, {}).get("slots", [])
        new_slots = [
            (
                DETAIL_TO_TYPE.get(e["detail"], e["detail"]),
                e["species"],
                e["chance"],
                e["min"],
                e["max"],
            )
            for e in z["entries"]
        ]
        old_n = [(t, s, c, mn, mx) for t, s, c, mn, mx in old_slots]
        if old_n != new_slots:
            any_diff = True
            kind = "reorder" if set(old_n) == set(new_slots) else "content"
            content_diffs.append((mid, z["name"], kind))
            print(f"\n[{mid:03d}] {z['name']} ({kind})")
            print("  OLD:", old_n)
            print("  NEW:", new_slots)

    if not any_diff:
        print("  (no slot differences detected)")

    if apply and any_diff:
        text = original
        for mid in sorted(new_blocks.keys()):
            text = replace_map_section(text, mid, new_blocks[mid])
        PBS_ENC.write_text(text, encoding="utf-8")
        print(f"\nWrote {PBS_ENC}")
    elif apply and not any_diff:
        print("\nNothing to apply.")
    else:
        print("\nDry-run only. Pass --apply to write PBS/encounters.txt")

    return any_diff


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--spreadsheet", default="")
    args = ap.parse_args()
    url = args.spreadsheet.strip()
    if not url and SHEET_URL_FILE.is_file():
        url = SHEET_URL_FILE.read_text(encoding="utf-8").strip()
    if not url:
        sys.exit("No spreadsheet URL")

    zones = pull_sheet_zones(url)
    print(f"Pulled {len(zones)} zones, {sum(len(z['entries']) for z in zones.values())} entries")
    rebuild_encounters_txt(zones, apply=args.apply)


if __name__ == "__main__":
    main()
