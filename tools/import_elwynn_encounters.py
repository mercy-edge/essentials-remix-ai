#!/usr/bin/env python3
"""
Pull Elwynn Encounters from Google Sheets and write into PBS/encounters.txt.

Preserves non-Elwynn sections. Rebuilds Elwynn map blocks from the sheet.
Uses Rate % when present; otherwise maps rarity → default chances and normalizes.

Usage:
  python tools/import_elwynn_encounters.py           # dry-run diff
  python tools/import_elwynn_encounters.py --apply   # write PBS
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PBS_ENC = ROOT / "PBS" / "encounters.txt"
sys.path.insert(0, str(ROOT / "tools"))

from export_elwynn_encounters import ELWYNN_MAP_ORDER, parse_encounters  # noqa: E402
from sheets_bridge import get_sheets_service, spreadsheet_id  # noqa: E402

SHEET_URL_FILE = ROOT / "ContentTracker" / "spreadsheet_url.txt"

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
    "Rock Smash": "RockSmash",
    "Old Rod": "OldRod",
    # Good Rod / Super Rod / Surf not used in this project yet — ignored on import if present
}

RARITY_DEFAULT = {"Common": 30, "Uncommon": 15, "Rare": 4}

# Default density from existing PBS when rewriting a type block
DEFAULT_DENSITY = {
    "Land": "10",
    "Cave": "8",
    "OldRod": "",
    "GoodRod": "",
    "SuperRod": "",
    "Water": "2",
    "RockSmash": "50",
}


def species_id(name: str) -> str:
    """Display name → PBS SPECIES id (best effort)."""
    n = name.strip()
    # common display fixes
    specials = {
        "Nidoran♀": "NIDORANF",
        "Nidoran♂": "NIDORANM",
        "Farfetch'd": "FARFETCHD",
        "Sirfetch'd": "SIRFETCHD",
        "Mr. Mime": "MRMIME",
        "Mime Jr.": "MIMEJR",
        "Mr. Rime": "MRRIME",
        "Type: Null": "TYPE_NULL",
        "Ho-Oh": "HOOH",
        "Porygon-Z": "PORYGONZ",
        "Porygon2": "PORYGON2",
        "Flabébé": "FLABEBE",
        "Jangmo-o": "JANGMOO",
        "Hakamo-o": "HAKAMOO",
        "Kommo-o": "KOMMOO",
    }
    if n in specials:
        return specials[n]
    # "Shellos East" style not used; "Geodude 1" → GEODUDE_1
    m = re.match(r"^([A-Za-z]+)(?:\s+(\d+))?$", n)
    if m and m.group(2):
        return f"{m.group(1).upper()}_{m.group(2)}"
    return re.sub(r"[^A-Za-z0-9]", "", n).upper()


def parse_levels(text: str):
    t = str(text).strip().replace("–", "-").replace("—", "-").replace(" ", "")
    if not t:
        return 1, 1
    if "-" in t:
        a, b = t.split("-", 1)
        return int(a), int(b)
    v = int(t)
    return v, v


# Maps that use Cave encounter type in PBS (walking still shown as Land on the sheet)
CAVE_MAPS = {33, 82, 85}


def parse_cell_mons(cell: str, rarity: str):
    """Parse 'Poochyena 1–2' / multiline cells into entry fragments."""
    cell = (cell or "").strip()
    if not cell or cell in ("—", "-", "–"):
        return []
    out = []
    for line in re.split(r"[\n\r]+", cell):
        line = line.strip()
        if not line or line in ("—", "-", "–"):
            continue
        # "Name 1-2" or "Name 1–2" or "Name 5"
        m = re.match(r"^(.+?)\s+(\d+)(?:\s*[–\-]\s*(\d+))?$", line)
        if not m:
            # name only — default levels
            out.append(
                {
                    "display": line,
                    "species": species_id(line),
                    "min": 1,
                    "max": 1,
                    "chance": RARITY_DEFAULT[rarity],
                    "rarity": rarity,
                }
            )
            continue
        name = m.group(1).strip()
        mn = int(m.group(2))
        mx = int(m.group(3) or m.group(2))
        out.append(
            {
                "display": name,
                "species": species_id(name),
                "min": mn,
                "max": mx,
                "chance": RARITY_DEFAULT[rarity],
                "rarity": rarity,
            }
        )
    return out


def pull_sheet_zones(spreadsheet: str):
    """
    Horizontal layout:
      Method | Rarity | MapA | MapB | ...
    """
    svc, _, _ = get_sheets_service()
    sid = spreadsheet_id(spreadsheet)
    rows = (
        svc.spreadsheets()
        .values()
        .get(spreadsheetId=sid, range="'Elwynn Encounters'")
        .execute()
        .get("values", [])
    )

    # Find header row with Method | Rarity | maps...
    header_idx = None
    map_names = []
    for i, row in enumerate(rows):
        cells = [str(c).strip() for c in row]
        if len(cells) >= 3 and cells[0] == "Method" and cells[1] == "Rarity":
            header_idx = i
            map_names = cells[2:]
            break
    if header_idx is None:
        sys.exit("Could not find horizontal header row (Method | Rarity | ...)")

    zones = {}
    for name in map_names:
        if not name:
            continue
        zones[name] = {
            "map_id": NAME_TO_MAP.get(name),
            "name": name,
            "entries": [],
        }

    current_method = "Land"
    for row in rows[header_idx + 1 :]:
        cells = [str(c).strip() if c is not None else "" for c in row]
        while len(cells) < 2 + len(map_names):
            cells.append("")
        method, rarity = cells[0], cells[1]
        if method:
            current_method = method
        if rarity not in ("Common", "Uncommon", "Rare"):
            continue

        # Map sheet method → PBS detail
        if current_method in ("Land", "Cave"):
            base_detail = "Land"
        elif current_method in ("Old Rod", "Fishing"):
            base_detail = "Old Rod"
        else:
            continue

        for mi, name in enumerate(map_names):
            if not name or name not in zones:
                continue
            cell = cells[2 + mi] if 2 + mi < len(cells) else ""
            for frag in parse_cell_mons(cell, rarity):
                detail = base_detail
                mid = zones[name]["map_id"]
                if detail == "Land" and mid in CAVE_MAPS:
                    detail = "Cave"
                zones[name]["entries"].append(
                    {
                        "detail": detail,
                        "rarity": rarity,
                        "species": frag["species"],
                        "display": frag["display"],
                        "min": frag["min"],
                        "max": frag["max"],
                        "chance": frag["chance"],
                    }
                )

    # Drop maps with no map id
    for name, z in list(zones.items()):
        if z["map_id"] is None:
            print(f"WARN: unknown map column {name!r}")
    return zones


def existing_density(pbs_maps, map_id, enc_type):
    # sniff density from current PBS slots grouping — re-parse file text
    return DEFAULT_DENSITY.get(enc_type, "10")


def sniff_densities_from_file():
    """map_id -> {enc_type: density_str}"""
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
    """Build encounters.txt section for one map."""
    # group by enc type preserving sheet order
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
        if dens != "":
            lines.append(f"{et},{dens}")
        else:
            lines.append(et)
        for e in lst:
            if e["min"] == e["max"]:
                lines.append(f"    {e['chance']},{e['species']},{e['min']}")
            else:
                lines.append(f"    {e['chance']},{e['species']},{e['min']},{e['max']}")
    return "\n".join(lines) + "\n"


def replace_map_section(text: str, map_id: int, new_block: str) -> str:
    """Replace one [NNN] section in-place; append if missing."""
    pattern = re.compile(
        rf"(?ms)^#-------------------------------\r?\n\[{map_id:03d}\][^\n]*\n.*?(?=^#-------------------------------\r?\n\[|\Z)"
    )
    block = new_block if new_block.endswith("\n") else new_block + "\n"
    if pattern.search(text):
        return pattern.sub(block, text, count=1)
    # append before final newline
    return text.rstrip() + "\n" + block


def rebuild_encounters_txt(zones, apply: bool):
    densities = sniff_densities_from_file()
    original = PBS_ENC.read_text(encoding="utf-8")

    new_blocks = {}
    zone_by_id = {}
    for zname, z in zones.items():
        mid = z["map_id"]
        if mid is None:
            print(f"WARN: skip zone without map id: {zname}")
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
            # species-set change vs order-only
            old_set = {(t, s, c, mn, mx) for t, s, c, mn, mx in old_n}
            new_set = set(new_slots)
            kind = "reorder" if old_set == new_set else "content"
            content_diffs.append((mid, z["name"], kind, old_n, new_slots))
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
        for mid, name, kind, _, _ in content_diffs:
            if kind == "content":
                print(f"  content update: [{mid:03d}] {name}")
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
