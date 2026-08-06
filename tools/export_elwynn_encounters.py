#!/usr/bin/env python3
"""
Build a romhack-doc style Elwynn Forest encounters sheet (horizontal):
  Method | Rarity | Map… across columns
  Land + Old Rod only; Common / Uncommon / Rare rows

Usage:
  python tools/export_elwynn_encounters.py
  python tools/export_elwynn_encounters.py --upload
"""

from __future__ import annotations

import argparse
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PBS = ROOT / "PBS"
OUT = ROOT / "ContentTracker"
SHEET_URL_FILE = OUT / "spreadsheet_url.txt"
# Elwynn / Northshire outdoor + dungeon maps with (or expected) wild tables
ELWYNN_MAP_ORDER = [
    76,   # Northshire Abbey
    42,   # Northshire Vineyards
    33,   # Echo Ridge Mine
    83,   # Forest's Edge
    77,   # Goldshire
    79,   # Brackwell Pumpkin Patch
    92,   # The Stonefield Farm
    87,   # The Maclure Vineyards
    81,   # Eastvale Logging Camp
    86,   # Jerod's Landing
    80,   # Crystal Lake
    88,   # Mirror Lake
    89,   # Mirror Lake Orchard
    91,   # Stone Cairn Lake
    94,   # Thunder Falls
    82,   # Fargodeep Mine
    85,   # Jasperlode Mine
    84,   # Heroes' Vigil
    90,   # Ridgepoint Tower
    95,   # Tower of Azora
    96,   # Westbrook Garrison
]

# Project currently only uses land/cave walking + Old Rod (no Surf / Good / Super Rod yet).
LAND_TYPES = {
    "Land", "LandMorning", "LandDay", "LandAfternoon", "LandEvening", "LandNight",
    "Cave", "RockSmash", "BugContest", "HeadbuttLow", "HeadbuttHigh", "PokeRadar",
}
FISH_TYPES = {"OldRod"}
SURF_TYPES = set()  # Water/Surf intentionally omitted until enabled in-game

RARITY_COLORS = {
    "Common": {"red": 0.72, "green": 0.88, "blue": 0.72},      # soft green
    "Uncommon": {"red": 1.0, "green": 0.95, "blue": 0.70},    # soft yellow
    "Rare": {"red": 1.0, "green": 0.82, "blue": 0.70},        # soft orange
}
HEADER_BG = {"red": 0.12, "green": 0.22, "blue": 0.18}
ZONE_BG = {"red": 0.20, "green": 0.35, "blue": 0.28}
METHOD_BG = {"red": 0.85, "green": 0.90, "blue": 0.88}
TITLE_BG = {"red": 0.10, "green": 0.18, "blue": 0.14}
WHITE = {"red": 1.0, "green": 1.0, "blue": 1.0}
BLACK = {"red": 0.1, "green": 0.1, "blue": 0.1}


def rarity_for(chance: int) -> str:
    if chance > 20:
        return "Common"
    if chance >= 5:
        return "Uncommon"
    return "Rare"


def method_bucket(enc_type: str):
    if enc_type in LAND_TYPES:
        label = "Cave" if enc_type == "Cave" else "Land"
        if enc_type == "RockSmash":
            label = "Rock Smash"
        return "Land", label
    if enc_type in FISH_TYPES:
        return "Fishing", "Old Rod"
    return None, None


def species_slug(species: str) -> str:
    base = species.split("_")[0].lower()
    overrides = {
        "nidoranf": "nidoranf", "nidoranm": "nidoranm",
        "farfetchd": "farfetchd", "mrmime": "mrmime", "mimejr": "mimejr",
        "porygon2": "porygon2", "porygonz": "porygonz", "hooh": "hooh",
        "flabebe": "flabebe", "type": "typenull",
    }
    # Alolan form suffix in Essentials SPECIES_1 for regionals often
    form = ""
    if "_" in species:
        # Only apply -alola style if we know; else base sprite
        pass
    slug = re.sub(r"[^a-z0-9]", "", base)
    return overrides.get(slug, slug)


def parse_encounters():
    """map_id -> {name, methods: {(bucket, subtype): {species: {chance, min, max}}}}"""
    path = PBS / "encounters.txt"
    maps = {}
    map_id = None
    map_name = ""
    enc_type = None

    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.rstrip()
        if not line.strip() or line.startswith("#---") or line.startswith("# See"):
            continue
        m = re.match(r"^\[(\d+)(?:,(\d+))?\]\s*(?:#\s*(.*))?$", line.strip())
        if m:
            map_id = int(m.group(1))
            map_name = (m.group(3) or "").strip()
            maps.setdefault(map_id, {"name": map_name, "slots": []})
            if map_name:
                maps[map_id]["name"] = map_name
            enc_type = None
            continue
        if map_id is None:
            continue
        stripped = line.strip()
        # Slot line first (starts with digits)
        sm = re.match(r"^(\d+),([A-Z0-9_]+),(\d+)(?:,(\d+))?$", stripped)
        if sm and enc_type:
            chance = int(sm.group(1))
            species = sm.group(2)
            mn = int(sm.group(3))
            mx = int(sm.group(4) or sm.group(3))
            maps[map_id]["slots"].append((enc_type, species, chance, mn, mx))
            continue
        # Type line: Land,21 or OldRod
        tm = re.match(r"^([A-Za-z]+)(?:,(\d+))?$", stripped)
        if tm:
            enc_type = tm.group(1)
    return maps


def aggregate_zone(slots):
    """
    Returns list of row dicts sorted by method then rarity.
    Aggregates duplicate species within same method subtype.
    """
    # key: (bucket, subtype, species) -> chance sum, minlv, maxlv
    agg = {}
    for enc_type, species, chance, mn, mx in slots:
        bucket, subtype = method_bucket(enc_type)
        if not bucket:
            continue
        key = (bucket, subtype, species)
        if key not in agg:
            agg[key] = {"chance": 0, "min": mn, "max": mx}
        agg[key]["chance"] += chance
        agg[key]["min"] = min(agg[key]["min"], mn)
        agg[key]["max"] = max(agg[key]["max"], mx)

    rows = []
    for (bucket, subtype, species), info in agg.items():
        rows.append({
            "bucket": bucket,
            "subtype": subtype,
            "species": species,
            "display": species.replace("_", " ").title() if "_" in species else species.title(),
            "rarity": rarity_for(info["chance"]),
            "chance": info["chance"],
            "levels": f"{info['min']}–{info['max']}" if info["min"] != info["max"] else str(info["min"]),
            "slug": species_slug(species),
        })

    rarity_order = {"Common": 0, "Uncommon": 1, "Rare": 2}
    method_order = {"Land": 0, "Cave": 0, "Rock Smash": 1, "Fishing": 2, "Old Rod": 2, "Good Rod": 3, "Super Rod": 4, "Surf": 5}
    rows.sort(key=lambda r: (
        0 if r["bucket"] == "Land" else 1,
        method_order.get(r["subtype"], 9),
        rarity_order.get(r["rarity"], 9),
        -r["chance"],
        r["species"],
    ))
    return rows


RARITY_ROWS = ("Common", "Uncommon", "Rare")
# Method label shown in col A (covers Land+Cave walking, and Old Rod fishing)
METHOD_ROWS = (
    ("Land", "Land"),       # display method, aggregate bucket
    ("Old Rod", "Fishing"),
)


def cell_text_for(entries):
    """Format encounter entries for one map/method/rarity cell."""
    if not entries:
        return "—"
    lines = [f"{e['display']} {e['levels']}" for e in entries]
    return "\n".join(lines)


def build_sheet_values(all_maps):
    """
    Horizontal layout:
      Method | Rarity | Map A | Map B | Map C | ...
    """
    # Active maps (with encounters) in display order
    map_cols = []
    for mid in ELWYNN_MAP_ORDER:
        info = all_maps.get(mid)
        if not info or not info["slots"]:
            continue
        name = info["name"] or f"Map {mid:03d}"
        by_key = defaultdict(list)  # (bucket, rarity) -> [entry dicts]
        for r in aggregate_zone(info["slots"]):
            by_key[(r["bucket"], r["rarity"])].append(r)
        map_cols.append({"id": mid, "name": name, "by_key": by_key})

    values = []
    row_meta = []

    values.append(["Elwynn Forest — Wild Encounters"])
    row_meta.append("title")

    header = ["Method", "Rarity"] + [m["name"] for m in map_cols]
    values.append(header)
    row_meta.append("colheader")

    for method_label, bucket in METHOD_ROWS:
        for ri, rarity in enumerate(RARITY_ROWS):
            row = [
                method_label if ri == 0 else "",
                rarity,
            ]
            for m in map_cols:
                row.append(cell_text_for(m["by_key"].get((bucket, rarity), [])))
            values.append(row)
            row_meta.append(("data", rarity, method_label if ri == 0 else None))

    # Pad width
    width = 2 + len(map_cols)
    for i, row in enumerate(values):
        while len(row) < width:
            row.append("")
        # Title row: only first cell used (merged later)
        if row_meta[i] == "title":
            values[i] = [row[0]] + [""] * (width - 1)
        else:
            values[i] = row[:width]

    return values, row_meta, width


def write_csv(values):
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / "Elwynn_Encounters.csv"
    import csv
    with path.open("w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerows(values)
    print(f"wrote {path} ({len(values)} rows)")
    return path


def upload(values, row_meta, spreadsheet: str, width: int):
    sys.path.insert(0, str(ROOT / "tools"))
    from sheets_bridge import get_sheets_service, spreadsheet_id

    svc, _, _ = get_sheets_service()
    sid = spreadsheet_id(spreadsheet)
    tab = "Elwynn Encounters"

    meta = svc.spreadsheets().get(spreadsheetId=sid).execute()
    existing = {sh["properties"]["title"]: sh["properties"]["sheetId"] for sh in meta.get("sheets", [])}
    row_count = max(len(values) + 10, 40)
    col_count = max(width + 2, 24)

    if tab not in existing:
        resp = svc.spreadsheets().batchUpdate(
            spreadsheetId=sid,
            body={
                "requests": [{
                    "addSheet": {
                        "properties": {
                            "title": tab,
                            "index": 2,
                            "gridProperties": {"rowCount": row_count, "columnCount": col_count},
                        }
                    }
                }]
            },
        ).execute()
        sheet_id = resp["replies"][0]["addSheet"]["properties"]["sheetId"]
    else:
        sheet_id = existing[tab]
        svc.spreadsheets().values().clear(spreadsheetId=sid, range=f"'{tab}'").execute()
        svc.spreadsheets().batchUpdate(
            spreadsheetId=sid,
            body={
                "requests": [{
                    "updateSheetProperties": {
                        "properties": {
                            "sheetId": sheet_id,
                            "gridProperties": {"rowCount": row_count, "columnCount": col_count},
                        },
                        "fields": "gridProperties.rowCount,gridProperties.columnCount",
                    }
                }]
            },
        ).execute()

    svc.spreadsheets().values().update(
        spreadsheetId=sid,
        range=f"'{tab}'!A1",
        valueInputOption="USER_ENTERED",
        body={"values": values},
    ).execute()
    print(f"  uploaded {len(values)} rows x {width} cols")

    requests = [
        {
            "updateCells": {
                "range": {
                    "sheetId": sheet_id,
                    "startRowIndex": 0,
                    "endRowIndex": max(len(values), 50),
                    "startColumnIndex": 0,
                    "endColumnIndex": max(width, 30),
                },
                "fields": "userEnteredFormat",
            }
        },
        {
            "unmergeCells": {
                "range": {
                    "sheetId": sheet_id,
                    "startRowIndex": 0,
                    "endRowIndex": max(len(values), 50),
                    "startColumnIndex": 0,
                    "endColumnIndex": max(width, 30),
                }
            }
        },
        # Method / Rarity columns
        {
            "updateDimensionProperties": {
                "range": {"sheetId": sheet_id, "dimension": "COLUMNS", "startIndex": 0, "endIndex": 1},
                "properties": {"pixelSize": 80},
                "fields": "pixelSize",
            }
        },
        {
            "updateDimensionProperties": {
                "range": {"sheetId": sheet_id, "dimension": "COLUMNS", "startIndex": 1, "endIndex": 2},
                "properties": {"pixelSize": 90},
                "fields": "pixelSize",
            }
        },
        # Map columns
        {
            "updateDimensionProperties": {
                "range": {
                    "sheetId": sheet_id,
                    "dimension": "COLUMNS",
                    "startIndex": 2,
                    "endIndex": width,
                },
                "properties": {"pixelSize": 130},
                "fields": "pixelSize",
            }
        },
        # Freeze header rows + Method/Rarity before any merges that span those regions
        {
            "updateSheetProperties": {
                "properties": {
                    "sheetId": sheet_id,
                    "gridProperties": {"frozenRowCount": 2, "frozenColumnCount": 2},
                },
                "fields": "gridProperties.frozenRowCount,gridProperties.frozenColumnCount",
            }
        },
        # Title row styling (no full-width merge — that fights frozen columns)
        {
            "repeatCell": {
                "range": {
                    "sheetId": sheet_id,
                    "startRowIndex": 0,
                    "endRowIndex": 1,
                    "startColumnIndex": 0,
                    "endColumnIndex": width,
                },
                "cell": {
                    "userEnteredFormat": {
                        "backgroundColor": TITLE_BG,
                        "textFormat": {"bold": True, "fontSize": 16, "foregroundColor": WHITE},
                    }
                },
                "fields": "userEnteredFormat(backgroundColor,textFormat)",
            }
        },
        # Wrap text in data area
        {
            "repeatCell": {
                "range": {
                    "sheetId": sheet_id,
                    "startRowIndex": 1,
                    "endRowIndex": len(values),
                    "startColumnIndex": 0,
                    "endColumnIndex": width,
                },
                "cell": {
                    "userEnteredFormat": {
                        "wrapStrategy": "WRAP",
                        "verticalAlignment": "TOP",
                        "textFormat": {"foregroundColor": BLACK},
                    }
                },
                "fields": "userEnteredFormat(wrapStrategy,verticalAlignment,textFormat.foregroundColor)",
            }
        },
    ]

    for i, meta in enumerate(row_meta):
        if meta == "colheader":
            requests.append({
                "repeatCell": {
                    "range": {
                        "sheetId": sheet_id,
                        "startRowIndex": i,
                        "endRowIndex": i + 1,
                        "startColumnIndex": 0,
                        "endColumnIndex": width,
                    },
                    "cell": {
                        "userEnteredFormat": {
                            "backgroundColor": HEADER_BG,
                            "textFormat": {"bold": True, "foregroundColor": WHITE},
                            "wrapStrategy": "WRAP",
                            "verticalAlignment": "MIDDLE",
                            "horizontalAlignment": "CENTER",
                        }
                    },
                    "fields": "userEnteredFormat(backgroundColor,textFormat,wrapStrategy,verticalAlignment,horizontalAlignment)",
                }
            })
            requests.append({
                "updateDimensionProperties": {
                    "range": {"sheetId": sheet_id, "dimension": "ROWS", "startIndex": i, "endIndex": i + 1},
                    "properties": {"pixelSize": 48},
                    "fields": "pixelSize",
                }
            })
        elif isinstance(meta, tuple) and meta[0] == "data":
            rarity = meta[1]
            color = RARITY_COLORS.get(rarity, WHITE)
            requests.append({
                "repeatCell": {
                    "range": {
                        "sheetId": sheet_id,
                        "startRowIndex": i,
                        "endRowIndex": i + 1,
                        "startColumnIndex": 0,
                        "endColumnIndex": width,
                    },
                    "cell": {
                        "userEnteredFormat": {
                            "backgroundColor": color,
                            "textFormat": {"foregroundColor": BLACK, "bold": False},
                            "wrapStrategy": "WRAP",
                            "verticalAlignment": "TOP",
                        }
                    },
                    "fields": "userEnteredFormat(backgroundColor,textFormat,wrapStrategy,verticalAlignment)",
                }
            })
            requests.append({
                "updateDimensionProperties": {
                    "range": {"sheetId": sheet_id, "dimension": "ROWS", "startIndex": i, "endIndex": i + 1},
                    "properties": {"pixelSize": 72},
                    "fields": "pixelSize",
                }
            })

    # Merge Method cells (Land x3, Old Rod x3)
    # rows: 0 title, 1 header, 2-4 Land, 5-7 Old Rod
    for start in (2, 5):
        if start + 2 < len(values):
            requests.append({
                "mergeCells": {
                    "range": {
                        "sheetId": sheet_id,
                        "startRowIndex": start,
                        "endRowIndex": start + 3,
                        "startColumnIndex": 0,
                        "endColumnIndex": 1,
                    },
                    "mergeType": "MERGE_ALL",
                }
            })
            requests.append({
                "repeatCell": {
                    "range": {
                        "sheetId": sheet_id,
                        "startRowIndex": start,
                        "endRowIndex": start + 3,
                        "startColumnIndex": 0,
                        "endColumnIndex": 1,
                    },
                    "cell": {
                        "userEnteredFormat": {
                            "backgroundColor": METHOD_BG,
                            "textFormat": {"bold": True, "foregroundColor": BLACK},
                            "verticalAlignment": "MIDDLE",
                            "horizontalAlignment": "CENTER",
                        }
                    },
                    "fields": "userEnteredFormat(backgroundColor,textFormat,verticalAlignment,horizontalAlignment)",
                }
            })

    for i in range(0, len(requests), 80):
        svc.spreadsheets().batchUpdate(
            spreadsheetId=sid, body={"requests": requests[i : i + 80]}
        ).execute()
    print(f"formatted '{tab}'")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--upload", action="store_true")
    ap.add_argument("--spreadsheet", default="")
    args = ap.parse_args()

    all_maps = parse_encounters()
    # Report coverage
    present = [m for m in ELWYNN_MAP_ORDER if all_maps.get(m, {}).get("slots")]
    print(f"Elwynn zones with encounters: {len(present)}")
    for m in present:
        print(f"  {m:03d} {all_maps[m]['name']} ({len(all_maps[m]['slots'])} slots)")

    values, row_meta, width = build_sheet_values(all_maps)
    write_csv(values)

    if args.upload:
        url = args.spreadsheet.strip()
        if not url and SHEET_URL_FILE.is_file():
            url = SHEET_URL_FILE.read_text(encoding="utf-8").strip()
        if not url:
            sys.exit("No spreadsheet URL")
        print(f"uploading to {url}")
        upload(values, row_meta, url, width)


if __name__ == "__main__":
    main()
