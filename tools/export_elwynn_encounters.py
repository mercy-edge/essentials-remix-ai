#!/usr/bin/env python3
"""
Build Elwynn encounters sheet — original layout inspired by romhack docs:
  Col A: method / rarity guide
  Col B+: Pokémon name | Lv pairs per map
  Land + Old Rod, 5 / 4 / 2 rows per rarity band

Usage:
  python tools/export_elwynn_encounters.py
  python tools/export_elwynn_encounters.py --upload
"""

from __future__ import annotations

import argparse
import csv
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PBS = ROOT / "PBS"
OUT = ROOT / "ContentTracker"
SHEET_URL_FILE = OUT / "spreadsheet_url.txt"

sys.path.insert(0, str(ROOT / "tools"))
from romhack_sheet_common import (  # noqa: E402
    BLACK,
    CREAM,
    DATA_BG,
    DATA_FG,
    EMPTY_LEVEL,
    EMPTY_NAME,
    GUIDE_BG,
    GUIDE_FG,
    MAP_HEADER_BG,
    RARITY_SLOTS,
    SECTION_COMMON,
    SECTION_FISH,
    SECTION_LAND,
    SECTION_RARE,
    SECTION_UNCOMMON,
    SPRITE_LIST_TAB,
    SPRITE_LIST_CATCH_COL,
    SPRITE_LIST_NAME_COL,
    TITLE_BG,
    TITLE_FG,
    WHITE,
    add_encounter_catch_validation_rules,
    batch_format,
    clear_conditional_format_rules,
    col_a1,
    ensure_sheet,
    level_text,
    merge_req,
    repeat_cell,
    rgb_cell,
    species_display,
    upload_values,
)

ELWYNN_MAP_ORDER = [
    76, 42, 33, 83, 77, 79, 92, 87, 81, 86, 80, 88, 89, 91, 94, 82, 85, 84, 90, 95, 96,
]

LAND_TYPES = {
    "Land", "LandMorning", "LandDay", "LandAfternoon", "LandEvening", "LandNight",
    "Cave", "RockSmash", "BugContest", "HeadbuttLow", "HeadbuttHigh", "PokeRadar",
}
FISH_TYPES = {"OldRod"}

RARITY_COLORS = {
    "Common": SECTION_COMMON,
    "Uncommon": SECTION_UNCOMMON,
    "Rare": SECTION_RARE,
}


def level_cell(levels: str) -> str:
    if not levels or levels == EMPTY_LEVEL:
        return EMPTY_LEVEL
    return f"'{levels}"


def rarity_for(chance: int) -> str:
    if chance > 20:
        return "Common"
    if chance >= 5:
        return "Uncommon"
    return "Rare"


def method_bucket(enc_type: str):
    if enc_type in LAND_TYPES:
        return "Land"
    if enc_type in FISH_TYPES:
        return "Old Rod"
    return None


def parse_encounters():
    path = PBS / "encounters.txt"
    maps = {}
    map_id = None
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
        sm = re.match(r"^(\d+),([A-Z0-9_]+),(\d+)(?:,(\d+))?$", stripped)
        if sm and enc_type:
            maps[map_id]["slots"].append(
                (enc_type, sm.group(2), int(sm.group(1)), int(sm.group(3)), int(sm.group(4) or sm.group(3)))
            )
            continue
        tm = re.match(r"^([A-Za-z]+)(?:,(\d+))?$", stripped)
        if tm:
            enc_type = tm.group(1)
    return maps


def aggregate_zone(slots):
    agg = {}
    for enc_type, species, chance, mn, mx in slots:
        bucket = method_bucket(enc_type)
        if not bucket:
            continue
        key = (bucket, species)
        if key not in agg:
            agg[key] = {"chance": 0, "min": mn, "max": mx, "species": species, "bucket": bucket}
        agg[key]["chance"] += chance
        agg[key]["min"] = min(agg[key]["min"], mn)
        agg[key]["max"] = max(agg[key]["max"], mx)

    by_method_rarity = defaultdict(list)
    for info in agg.values():
        rarity = rarity_for(info["chance"])
        by_method_rarity[(info["bucket"], rarity)].append({
            "display": species_display(info["species"]),
            "species": info["species"],
            "rarity": rarity,
            "chance": info["chance"],
            "levels": level_text(info["min"], info["max"]),
        })

    for key in by_method_rarity:
        by_method_rarity[key].sort(key=lambda e: (-e["chance"], e["species"]))
    return by_method_rarity


def build_sheet_values(all_maps):
    map_cols = []
    for mid in ELWYNN_MAP_ORDER:
        info = all_maps.get(mid)
        if not info or not info["slots"]:
            continue
        name = info["name"] or f"Map {mid:03d}"
        by_key = aggregate_zone(info["slots"])
        map_cols.append({"id": mid, "name": name, "by_key": by_key})

    width = max(1 + len(map_cols) * 2, 3)
    values = []
    row_kinds = []

    values.append(["Elwynn Forest — Wild Encounters"] + [""] * (width - 1))
    row_kinds.append("title")

    header = ["Map"]
    for m in map_cols:
        header.extend([m["name"], ""])
    while len(header) < width:
        header.append("")
    values.append(header)
    row_kinds.append("mapheader")

    sub = [""]
    for _ in map_cols:
        sub.extend(["Pokémon", "Lv"])
    while len(sub) < width:
        sub.append("")
    values.append(sub)
    row_kinds.append("subheader")

    for method_label, method_color in (("Land", SECTION_LAND), ("Old Rod", SECTION_FISH)):
        method_row = [method_label] + [""] * (width - 1)
        values.append(method_row)
        row_kinds.append(("method", method_color))

        for rarity in ("Common", "Uncommon", "Rare"):
            slots = RARITY_SLOTS[rarity]
            for slot_i in range(slots):
                row = [rarity]
                for m in map_cols:
                    entries = m["by_key"].get((method_label, rarity), [])
                    if slot_i < len(entries):
                        e = entries[slot_i]
                        row.extend([e["display"], level_cell(e["levels"])])
                    else:
                        row.extend([EMPTY_NAME, level_cell(EMPTY_LEVEL)])
                while len(row) < width:
                    row.append("")
                values.append(row)
                row_kinds.append(("data", rarity))

    return values, row_kinds, width, len(map_cols)


def write_csv(values):
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / "Elwynn_Encounters.csv"
    with path.open("w", encoding="utf-8", newline="") as f:
        csv.writer(f).writerows(values)
    print(f"wrote {path} ({len(values)} rows)")
    return path


def build_row_kinds(map_count: int):
    """Row metadata for formatting (fixed Land + Old Rod layout)."""
    width = 1 + map_count * 2
    row_kinds = ["title", "mapheader", "subheader"]
    for method_label, method_color in (("Land", SECTION_LAND), ("Old Rod", SECTION_FISH)):
        row_kinds.append(("method", method_color))
        for rarity in ("Common", "Uncommon", "Rare"):
            for _ in range(RARITY_SLOTS[rarity]):
                row_kinds.append(("data", rarity))
    return row_kinds, width


def read_sheet_layout(svc, sid: str, tab: str):
    rows = (
        svc.spreadsheets()
        .values()
        .get(spreadsheetId=sid, range=f"'{tab}'")
        .execute()
        .get("values", [])
    )
    if len(rows) < 2:
        return None, 0, 0
    header = rows[1]
    map_count = sum(
        1 for ci in range(1, len(header), 2)
        if ci < len(header) and str(header[ci]).strip() and str(header[ci]).strip().lower() != "map"
    )
    width = max(1 + map_count * 2, 3)
    return rows, width, map_count


def apply_sheet_formatting(
    svc, sid: str, tab: str, sheet_id: int, row_kinds, width: int, map_count: int, row_count: int
):
    format_rows = len(row_kinds)

    lookup_name_col = width
    lookup_catch_col = width + 1
    lookup_formulas = [
        f"=ARRAYFORMULA(FILTER('{SPRITE_LIST_TAB}'!${SPRITE_LIST_NAME_COL}$2:${SPRITE_LIST_NAME_COL},"
        f"'{SPRITE_LIST_TAB}'!${SPRITE_LIST_NAME_COL}$2:${SPRITE_LIST_NAME_COL}<>\"\"))",
        f"=ARRAYFORMULA(FILTER('{SPRITE_LIST_TAB}'!${SPRITE_LIST_CATCH_COL}$2:${SPRITE_LIST_CATCH_COL},"
        f"'{SPRITE_LIST_TAB}'!${SPRITE_LIST_NAME_COL}$2:${SPRITE_LIST_NAME_COL}<>\"\"))",
    ]
    svc.spreadsheets().values().update(
        spreadsheetId=sid,
        range=f"'{tab}'!{col_a1(lookup_name_col, 3)}:{col_a1(lookup_catch_col, 3)}",
        valueInputOption="USER_ENTERED",
        body={"values": [lookup_formulas]},
    ).execute()

    requests = [
        {
            "unmergeCells": {
                "range": {
                    "sheetId": sheet_id,
                    "startRowIndex": 0,
                    "endRowIndex": max(format_rows, row_count) + 5,
                    "startColumnIndex": 0,
                    "endColumnIndex": width,
                }
            }
        },
        {
            "updateCells": {
                "range": {
                    "sheetId": sheet_id,
                    "startRowIndex": 0,
                    "endRowIndex": max(format_rows, row_count),
                    "startColumnIndex": 0,
                    "endColumnIndex": width,
                },
                "fields": "userEnteredFormat",
            }
        },
        {
            "updateSheetProperties": {
                "properties": {
                    "sheetId": sheet_id,
                    "gridProperties": {"frozenRowCount": 0, "frozenColumnCount": 0},
                },
                "fields": "gridProperties.frozenRowCount,gridProperties.frozenColumnCount",
            }
        },
        repeat_cell(
            sheet_id, 0, max(format_rows, row_count), 0, width,
            rgb_cell(DATA_BG, DATA_FG, wrap=True),
            "userEnteredFormat(backgroundColor,textFormat,wrapStrategy,verticalAlignment,horizontalAlignment)",
        ),
    ]

    for i, kind in enumerate(row_kinds):
        if kind == "title":
            requests.append(merge_req(sheet_id, i, i + 1, 0, width))
            requests.append(repeat_cell(
                sheet_id, i, i + 1, 0, width,
                rgb_cell(TITLE_BG, TITLE_FG, bold=True, halign="LEFT"),
            ))
        elif kind == "mapheader":
            requests.append(repeat_cell(
                sheet_id, i, i + 1, 0, 1,
                rgb_cell(GUIDE_BG, GUIDE_FG, bold=True),
            ))
            for mi in range(map_count):
                c0 = 1 + mi * 2
                requests.append(merge_req(sheet_id, i, i + 1, c0, c0 + 2))
                requests.append(repeat_cell(
                    sheet_id, i, i + 1, c0, c0 + 2,
                    rgb_cell(MAP_HEADER_BG, BLACK, bold=True),
                ))
        elif kind == "subheader":
            requests.append(repeat_cell(
                sheet_id, i, i + 1, 0, 1,
                rgb_cell(GUIDE_BG, GUIDE_FG, bold=True),
            ))
            for mi in range(map_count):
                c0 = 1 + mi * 2
                requests.append(repeat_cell(
                    sheet_id, i, i + 1, c0, c0 + 1,
                    rgb_cell(GUIDE_BG, GUIDE_FG, bold=True, halign="LEFT"),
                ))
                requests.append(repeat_cell(
                    sheet_id, i, i + 1, c0 + 1, c0 + 2,
                    rgb_cell(GUIDE_BG, GUIDE_FG, bold=True),
                ))
        elif isinstance(kind, tuple) and kind[0] == "method":
            requests.append(repeat_cell(
                sheet_id, i, i + 1, 0, 1,
                rgb_cell(kind[1], CREAM, bold=True, halign="LEFT"),
            ))
            requests.append(repeat_cell(
                sheet_id, i, i + 1, 1, width,
                rgb_cell(DATA_BG, DATA_FG, halign="LEFT"),
            ))
        elif isinstance(kind, tuple) and kind[0] == "data":
            rarity = kind[1]
            requests.append(repeat_cell(
                sheet_id, i, i + 1, 0, 1,
                rgb_cell(RARITY_COLORS[rarity], BLACK, bold=False, halign="LEFT"),
            ))
            for mi in range(map_count):
                c0 = 1 + mi * 2
                requests.append(repeat_cell(
                    sheet_id, i, i + 1, c0, c0 + 1,
                    rgb_cell(DATA_BG, DATA_FG, halign="LEFT"),
                ))
                requests.append(repeat_cell(
                    sheet_id, i, i + 1, c0 + 1, c0 + 2,
                    rgb_cell(DATA_BG, DATA_FG, halign="CENTER"),
                ))

    requests.append({
        "updateDimensionProperties": {
            "range": {"sheetId": sheet_id, "dimension": "COLUMNS", "startIndex": 0, "endIndex": 1},
            "properties": {"pixelSize": 88},
            "fields": "pixelSize",
        }
    })
    for mi in range(map_count):
        c0 = 1 + mi * 2
        requests.append({
            "updateDimensionProperties": {
                "range": {"sheetId": sheet_id, "dimension": "COLUMNS", "startIndex": c0, "endIndex": c0 + 1},
                "properties": {"pixelSize": 108},
                "fields": "pixelSize",
            }
        })
        requests.append({
            "updateDimensionProperties": {
                "range": {"sheetId": sheet_id, "dimension": "COLUMNS", "startIndex": c0 + 1, "endIndex": c0 + 2},
                "properties": {"pixelSize": 42},
                "fields": "pixelSize",
            }
        })

    batch_format(svc, sid, requests)

    clear_conditional_format_rules(svc, sid, sheet_id)
    first_data_row = next(
        (i for i, k in enumerate(row_kinds) if isinstance(k, tuple) and k[0] == "data"),
        3,
    )
    name_cols = [1 + mi * 2 for mi in range(map_count)]
    cf_requests = add_encounter_catch_validation_rules(
        sheet_id, name_cols, first_data_row, row_count, lookup_name_col, lookup_catch_col
    )
    if cf_requests:
        batch_format(svc, sid, cf_requests)
        print(f"  conditional formatting on {len(name_cols)} Pokémon columns (rows {first_data_row + 1}+)")

    batch_format(svc, sid, [{
        "updateDimensionProperties": {
            "range": {
                "sheetId": sheet_id,
                "dimension": "COLUMNS",
                "startIndex": lookup_name_col,
                "endIndex": lookup_catch_col + 1,
            },
            "properties": {"hiddenByUser": True, "pixelSize": 32},
            "fields": "hiddenByUser,pixelSize",
        }
    }])

    svc.spreadsheets().batchUpdate(
        spreadsheetId=sid,
        body={
            "requests": [{
                "updateSheetProperties": {
                    "properties": {
                        "sheetId": sheet_id,
                        "gridProperties": {"frozenRowCount": 3, "frozenColumnCount": 0},
                    },
                    "fields": "gridProperties.frozenRowCount,gridProperties.frozenColumnCount",
                }
            }]
        },
    ).execute()
    print(f"formatted '{tab}'")


def format_only(spreadsheet: str):
    from sheets_bridge import get_sheets_service, spreadsheet_id

    svc, _, _ = get_sheets_service()
    sid = spreadsheet_id(spreadsheet)
    tab = "Elwynn Encounters"
    existing, width, map_count = read_sheet_layout(svc, sid, tab)
    if not map_count:
        sys.exit("Sheet missing map header — use --push-from-pbs once to create layout")
    row_kinds, _ = build_row_kinds(map_count)
    row_count = max(len(existing or []) + 5, 40)
    col_count = max(width + 2, 24)
    sheet_id = ensure_sheet(svc, sid, tab, row_count, col_count, index=2, clear_values=False)
    print(f"  formatting only ({map_count} maps, data untouched)")
    apply_sheet_formatting(svc, sid, tab, sheet_id, row_kinds, width, map_count, row_count)


def push_from_pbs(values, row_kinds, spreadsheet: str, width: int, map_count: int):
    from sheets_bridge import get_sheets_service, spreadsheet_id

    svc, _, _ = get_sheets_service()
    sid = spreadsheet_id(spreadsheet)
    tab = "Elwynn Encounters"
    row_count = max(len(values) + 5, 40)
    col_count = max(width + 2, 24)
    sheet_id = ensure_sheet(svc, sid, tab, row_count, col_count, index=2, clear_values=True)

    upload_values(svc, sid, tab, values)
    print(f"  pushed {len(values)} rows x {width} cols from PBS")
    apply_sheet_formatting(svc, sid, tab, sheet_id, row_kinds, width, map_count, row_count)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--format-only",
        action="store_true",
        help="Apply colors/conditional formatting only (does not overwrite your data)",
    )
    ap.add_argument(
        "--push-from-pbs",
        action="store_true",
        help="Replace sheet data from PBS/encounters.txt (explicit overwrite)",
    )
    ap.add_argument(
        "--upload",
        action="store_true",
        help=argparse.SUPPRESS,
    )
    ap.add_argument("--spreadsheet", default="")
    args = ap.parse_args()

    all_maps = parse_encounters()
    present = [m for m in ELWYNN_MAP_ORDER if all_maps.get(m, {}).get("slots")]
    print(f"Elwynn zones with encounters: {len(present)}")

    values, row_kinds, width, map_count = build_sheet_values(all_maps)
    write_csv(values)

    url = args.spreadsheet.strip()
    if not url and SHEET_URL_FILE.is_file():
        url = SHEET_URL_FILE.read_text(encoding="utf-8").strip()

    if args.upload and not args.format_only and not args.push_from_pbs:
        print("NOTE: --upload now means --format-only (safe). Use --push-from-pbs to overwrite data.")
        args.format_only = True

    if args.format_only:
        if not url:
            sys.exit("No spreadsheet URL")
        print(f"formatting {url}")
        format_only(url)
    elif args.push_from_pbs:
        if not url:
            sys.exit("No spreadsheet URL")
        print(f"pushing from PBS to {url}")
        push_from_pbs(values, row_kinds, url, width, map_count)


if __name__ == "__main__":
    main()
