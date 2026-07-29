#!/usr/bin/env python3
"""
Create and sync battle documentation to Google Sheets.

Requires a Google Cloud service account with Sheets + Drive APIs enabled.
Credentials (first match wins):
  1. GOOGLE_SERVICE_ACCOUNT_JSON env var (full JSON string)
  2. GOOGLE_APPLICATION_CREDENTIALS env var (path to JSON file)
  3. ~/.config/gspread/service_account.json
  4. docs/sheets/google-service-account.json (gitignored)

Optional:
  GOOGLE_SHEETS_SHARE_EMAIL — your Google account email (Editor access)
  GOOGLE_SHEETS_FOLDER_ID    — Drive folder to create the spreadsheet in

Usage:
  python3 tools/sync_google_sheets.py          # create or update live sheet
  python3 tools/sync_google_sheets.py --export # also download .xlsx backup
"""

from __future__ import annotations

import json
import os
import sys
from datetime import date
from pathlib import Path

import gspread
from google.oauth2.service_account import Credentials
from gspread.utils import ExportFormat

# Reuse PBS parsers from the local generator
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import generate_battle_docs as gbd  # noqa: E402

CONFIG_PATH = ROOT / "docs" / "sheets" / "google_sheet.json"
XLSX_BACKUP = ROOT / "docs" / "sheets" / "Essentials_Remix_AI_Battles.xlsx"
SHEET_TITLE = "Essentials Remix AI — Battles"

SCOPES = [
    "https://www.googleapis.com/auth/spreadsheets",
    "https://www.googleapis.com/auth/drive",
]

TAB_INDEX = "Index"
TAB_ENCOUNTERS = "Wild Encounters"
TAB_SUMMARY = "Encounter Summary"
TAB_TRAINERS = "Trainer Battles"
TAB_STATIC = "Static Battles"

ALL_TABS = [TAB_INDEX, TAB_ENCOUNTERS, TAB_SUMMARY, TAB_TRAINERS, TAB_STATIC]


def hex_rgb(hex6: str) -> dict:
    h = hex6.lstrip("#")
    return {
        "red": int(h[0:2], 16) / 255,
        "green": int(h[2:4], 16) / 255,
        "blue": int(h[4:6], 16) / 255,
    }


def load_credentials() -> Credentials:
    paths = [
        os.environ.get("GOOGLE_APPLICATION_CREDENTIALS"),
        str(Path.home() / ".config/gspread/service_account.json"),
        str(ROOT / "docs/sheets/google-service-account.json"),
    ]
    raw = os.environ.get("GOOGLE_SERVICE_ACCOUNT_JSON")
    if raw:
        info = json.loads(raw)
        return Credentials.from_service_account_info(info, scopes=SCOPES)
    for p in paths:
        if p and Path(p).is_file():
            return Credentials.from_service_account_file(p, scopes=SCOPES)
    raise SystemExit(
        "Google credentials not found.\n\n"
        "One-time setup:\n"
        "  1. Google Cloud Console → create project → enable Sheets API + Drive API\n"
        "  2. IAM → Service Accounts → Create → Keys → JSON download\n"
        "  3. Save as docs/sheets/google-service-account.json  (gitignored)\n"
        "     OR set GOOGLE_SERVICE_ACCOUNT_JSON in Cursor Cloud Agent secrets\n"
        "  4. Set GOOGLE_SHEETS_SHARE_EMAIL to your Gmail (so you can open the sheet)\n"
        "  5. Re-run: python3 tools/sync_google_sheets.py\n"
    )


def load_config() -> dict:
    if CONFIG_PATH.is_file():
        return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    return {"spreadsheet_id": None, "spreadsheet_url": None, "title": SHEET_TITLE}


def save_config(cfg: dict):
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    CONFIG_PATH.write_text(json.dumps(cfg, indent=2) + "\n", encoding="utf-8")


def get_client() -> gspread.Client:
    creds = load_credentials()
    return gspread.authorize(creds)


def open_or_create_spreadsheet(gc: gspread.Client, cfg: dict) -> gspread.Spreadsheet:
    share_email = os.environ.get("GOOGLE_SHEETS_SHARE_EMAIL") or cfg.get("share_email")
    folder_id = os.environ.get("GOOGLE_SHEETS_FOLDER_ID")

    if cfg.get("spreadsheet_id"):
        try:
            sh = gc.open_by_key(cfg["spreadsheet_id"])
            return sh
        except gspread.SpreadsheetNotFound:
            pass

    sh = gc.create(cfg.get("title") or SHEET_TITLE, folder_id=folder_id)
    cfg["spreadsheet_id"] = sh.id
    cfg["spreadsheet_url"] = sh.url
    cfg["created"] = str(date.today())
    save_config(cfg)

    if share_email:
        sh.share(share_email, perm_type="user", role="writer", notify=True)
    return sh


def ensure_tabs(sh: gspread.Spreadsheet) -> dict[str, gspread.Worksheet]:
    existing = {ws.title: ws for ws in sh.worksheets()}
    tabs: dict[str, gspread.Worksheet] = {}
    for i, title in enumerate(ALL_TABS):
        if title in existing:
            tabs[title] = existing[title]
        else:
            tabs[title] = sh.add_worksheet(title=title, rows=500, cols=20, index=i)
    # Remove default Sheet1 if still present and empty
    for ws in sh.worksheets():
        if ws.title not in ALL_TABS and ws.title == "Sheet1":
            try:
                sh.del_worksheet(ws)
            except Exception:
                pass
    return tabs


def build_index_rows(encounter_count: int, trainer_count: int) -> list[list]:
    return [
        ["Essentials Remix AI — Battle Documentation", "", "", "", "", ""],
        ["", "", "", "", "", ""],
        ["Game version", "1.0.0 (Pokémon Essentials 21.1, Gen 8 mechanics)", "", "", "", ""],
        ["Generated", str(date.today()), "", "", "", ""],
        ["Live sheet", "Auto-synced from PBS via tools/sync_google_sheets.py", "", "", "", ""],
        ["", "", "", "", "", ""],
        ["Sheet", "Description", "", "", "", ""],
        [TAB_ENCOUNTERS, f"{encounter_count} wild encounter slots", "", "", "", ""],
        [TAB_SUMMARY, "One row per area — species checklist", "", "", "", ""],
        [TAB_TRAINERS, f"{trainer_count} trainer definitions", "", "", "", ""],
        [TAB_STATIC, "Scripted wild battles", "", "", "", ""],
        ["", "", "", "", "", ""],
        ["Regenerate", "python3 tools/sync_google_sheets.py", "", "", "", ""],
    ]


def build_encounter_rows(slots, species_db, maps) -> list[list]:
    headers = ["Location", "Map", "Method", "Pokémon", "Type", "Level", "Rate %", "Notes"]
    rows = [headers]
    groups: dict[tuple, list] = gbd.defaultdict(list)
    for s in slots:
        groups[(s.map_id, s.version or 0, s.location)].append(s)

    for key in sorted(groups.keys(), key=lambda k: (gbd.map_sort_key(k[0], maps), k[1], k[2])):
        map_id, _ver, location = key
        rows.append([f"▸  {location}  (Map {map_id})", "", "", "", "", "", "", ""])
        by_method: dict[str, list] = gbd.defaultdict(list)
        for s in groups[key]:
            by_method[s.method].append(s)
        for method in sorted(
            by_method.keys(),
            key=lambda m: (gbd.METHOD_ORDER.index(m) if m in gbd.METHOD_ORDER else 99, m),
        ):
            method_label = gbd.METHOD_LABELS.get(method, method)
            for s in sorted(by_method[method], key=lambda x: (-x.rate, x.species)):
                sp = species_db.get(s.species, {})
                types = sp.get("types", [])
                rows.append([
                    location,
                    map_id,
                    method_label,
                    sp.get("name") or gbd.fmt_name(s.species),
                    gbd.fmt_types(types) if types else "?",
                    gbd.level_str(s.level_min, s.level_max),
                    s.rate,
                    "",
                ])
    return rows


def build_summary_rows(slots, species_db, maps) -> list[list]:
    headers = ["Location", "Map", "Methods", "Species (unique)", "Level Range", "Slot Count"]
    rows = [headers]
    by_loc: dict[tuple, list] = gbd.defaultdict(list)
    for s in slots:
        by_loc[(s.map_id, s.location)].append(s)
    for (map_id, location) in sorted(by_loc.keys(), key=lambda k: gbd.map_sort_key(k[0], maps)):
        group = by_loc[(map_id, location)]
        methods = sorted({gbd.METHOD_LABELS.get(s.method, s.method) for s in group})
        species = sorted(
            {species_db.get(s.species, {}).get("name") or gbd.fmt_name(s.species) for s in group}
        )
        levels = []
        for s in group:
            levels.append(s.level_min)
            if s.level_max:
                levels.append(s.level_max)
        rows.append([
            location,
            map_id,
            ", ".join(methods),
            ", ".join(species),
            f"{min(levels)}–{max(levels)}" if levels else "—",
            len(group),
        ])
    return rows


def build_trainer_rows(trainers, trainer_types, species_db, placements, maps) -> list[list]:
    headers = ["Location", "Map", "Trainer", "Party", "Trainer Items", "Lose Text", "Notes"]
    rows = [headers]

    placed: dict[tuple, list] = gbd.defaultdict(list)
    for t in trainers:
        key = gbd.trainer_key(t)
        locs = placements.get(key, [])
        if locs:
            placed[key].extend(locs)

    entries: list[tuple] = []
    seen: set[tuple] = set()
    for t in trainers:
        key = gbd.trainer_key(t)
        if key in seen:
            continue
        seen.add(key)
        locs = placed.get(key, [])
        if locs:
            for loc in locs:
                entries.append((loc["map_id"], t, loc))
        else:
            entries.append((9999, t, None))

    entries.sort(
        key=lambda e: (
            gbd.map_sort_key(e[0], maps) if e[0] != 9999 else (9, 99, 99, 9999, ""),
            e[1].trainer_type,
            e[1].name,
            e[1].version,
        )
    )

    current_map = None
    for map_id, trainer, loc in entries:
        if map_id != current_map:
            current_map = map_id
            if map_id != 9999:
                meta = maps.get(map_id, {})
                loc_name = meta.get("Name", meta.get("editor_name", f"Map {map_id}"))
            else:
                loc_name = "Unplaced / Script-Only Battles"
            rows.append([f"▸  {loc_name}", "", "", "", "", "", ""])

        is_boss = trainer.trainer_type.startswith("LEADER_") or trainer.trainer_type == "CHAMPION"
        meta = maps.get(map_id, {}) if map_id != 9999 else {}
        loc_name = meta.get("Name", "") if map_id != 9999 else "—"
        party = "\n".join(gbd.mon_detail_line(m, species_db) for m in trainer.pokemon)
        t_items = ", ".join(gbd.fmt_name(i) for i in trainer.items) if trainer.items else "—"
        notes = "Boss" if is_boss else ""
        if loc and loc.get("event_id"):
            notes = (notes + f" Event {loc['event_id']}").strip()
        rows.append([
            loc_name,
            map_id if map_id != 9999 else "—",
            gbd.trainer_display_name(trainer, trainer_types),
            party,
            t_items,
            trainer.lose_text or "—",
            notes,
        ])

    rows.append(["▸  Script-Generated Battles (not in trainers.txt)", "", "", "", "", "", ""])
    for loc, trainer, note in [
        ("Northshire Abbey", "Kobold Worker / Laborer / Vermin Scout", "Quest Journal — dynamic parties"),
        ("Northshire Abbey", "Defias Thugs", "Quest chain battles"),
    ]:
        rows.append([loc, "—", trainer, note, "—", "—", "Plugin"])
    return rows


def build_static_rows(static, species_db, maps) -> list[list]:
    headers = ["Location", "Map", "Pokémon", "Type", "Level", "Notes"]
    rows = [headers]
    for b in sorted(static, key=lambda x: x["map_id"]):
        map_id = b["map_id"]
        meta = maps.get(map_id, {})
        loc = meta.get("Name", meta.get("editor_name", f"Map {map_id}"))
        sp = species_db.get(b["species"], {})
        types = sp.get("types", [])
        rows.append([
            loc,
            map_id,
            sp.get("name") or gbd.fmt_name(b["species"]),
            gbd.fmt_types(types) if types else "?",
            b["level"],
            f"Event {b['event_id']} — WildBattle.start",
        ])
    return rows


def write_tab(ws: gspread.Worksheet, rows: list[list]):
    ws.clear()
    if not rows:
        return
    ws.update(rows, value_input_option="USER_ENTERED")
    # Resize to fit content
    ws.resize(rows=max(len(rows) + 5, 100), cols=max(len(rows[0]) + 2, 10))


def format_sheet(sh: gspread.Spreadsheet, tab_title: str, rows: list[list], *, kind: str):
    """Apply Run-and-Bun-style formatting via batch_update."""
    ws = sh.worksheet(tab_title)
    sheet_id = ws.id
    requests = []

    # Freeze header row on data tabs
    if kind != "index" and rows:
        requests.append({
            "updateSheetProperties": {
                "properties": {"sheetId": sheet_id, "gridProperties": {"frozenRowCount": 1}},
                "fields": "gridProperties.frozenRowCount",
            }
        })
        requests.append({
            "setBasicFilter": {
                "filter": {
                    "range": {
                        "sheetId": sheet_id,
                        "startRowIndex": 0,
                        "endRowIndex": len(rows),
                        "startColumnIndex": 0,
                        "endColumnIndex": len(rows[0]),
                    }
                }
            }
        })

    header_fmt = {
        "backgroundColor": hex_rgb("374151"),
        "textFormat": {"bold": True, "foregroundColor": {"red": 1, "green": 1, "blue": 1}},
        "horizontalAlignment": "CENTER",
        "wrapStrategy": "WRAP",
    }
    section_fmt = {
        "backgroundColor": hex_rgb("2563EB"),
        "textFormat": {"bold": True, "foregroundColor": {"red": 1, "green": 1, "blue": 1}, "fontSize": 11},
    }
    title_fmt = {
        "backgroundColor": hex_rgb("1E3A5F"),
        "textFormat": {"bold": True, "foregroundColor": {"red": 1, "green": 1, "blue": 1}, "fontSize": 14},
    }
    alt_fmt = {"backgroundColor": hex_rgb("F3F4F6")}

    if kind == "index" and rows:
        requests.append({
            "mergeCells": {
                "range": {"sheetId": sheet_id, "startRowIndex": 0, "endRowIndex": 1, "startColumnIndex": 0, "endColumnIndex": 6},
                "mergeType": "MERGE_ALL",
            }
        })
        requests.append({
            "repeatCell": {
                "range": {"sheetId": sheet_id, "startRowIndex": 0, "endRowIndex": 1},
                "cell": {"userEnteredFormat": title_fmt},
                "fields": "userEnteredFormat(backgroundColor,textFormat)",
            }
        })

    data_start = 0 if kind == "index" else 0
    header_row = 0 if kind != "index" else None

    if header_row is not None and rows:
        requests.append({
            "repeatCell": {
                "range": {
                    "sheetId": sheet_id,
                    "startRowIndex": 0,
                    "endRowIndex": 1,
                    "startColumnIndex": 0,
                    "endColumnIndex": len(rows[0]),
                },
                "cell": {"userEnteredFormat": header_fmt},
                "fields": "userEnteredFormat(backgroundColor,textFormat,horizontalAlignment,wrapStrategy)",
            }
        })
        data_start = 1

    # Column widths
    col_widths = {
        TAB_ENCOUNTERS: [180, 60, 110, 120, 100, 70, 70, 120],
        TAB_SUMMARY: [180, 60, 160, 280, 90, 80],
        TAB_TRAINERS: [160, 60, 180, 380, 140, 180, 100],
        TAB_STATIC: [180, 60, 120, 100, 70, 200],
    }
    if tab_title in col_widths and rows:
        for i, px in enumerate(col_widths[tab_title]):
            requests.append({
                "updateDimensionProperties": {
                    "range": {"sheetId": sheet_id, "dimension": "COLUMNS", "startIndex": i, "endIndex": i + 1},
                    "properties": {"pixelSize": px},
                    "fields": "pixelSize",
                }
            })

    # Row styling
    alt = False
    for r_idx in range(data_start, len(rows)):
        row = rows[r_idx]
        first = str(row[0]) if row else ""
        if first.startswith("▸"):
            requests.append({
                "mergeCells": {
                    "range": {
                        "sheetId": sheet_id,
                        "startRowIndex": r_idx,
                        "endRowIndex": r_idx + 1,
                        "startColumnIndex": 0,
                        "endColumnIndex": len(row),
                    },
                    "mergeType": "MERGE_ALL",
                }
            })
            requests.append({
                "repeatCell": {
                    "range": {"sheetId": sheet_id, "startRowIndex": r_idx, "endRowIndex": r_idx + 1},
                    "cell": {"userEnteredFormat": section_fmt},
                    "fields": "userEnteredFormat(backgroundColor,textFormat)",
                }
            })
            continue

        fmt = dict(alt_fmt) if alt else {"backgroundColor": {"red": 1, "green": 1, "blue": 1}}
        if kind == "trainers" and len(row) > 6 and row[6] == "Boss":
            fmt = {"backgroundColor": hex_rgb("FEF3C7")}

        requests.append({
            "repeatCell": {
                "range": {
                    "sheetId": sheet_id,
                    "startRowIndex": r_idx,
                    "endRowIndex": r_idx + 1,
                    "startColumnIndex": 0,
                    "endColumnIndex": len(row),
                },
                "cell": {
                    "userEnteredFormat": {
                        **fmt,
                        "wrapStrategy": "WRAP",
                        "verticalAlignment": "TOP",
                    }
                },
                "fields": "userEnteredFormat(backgroundColor,wrapStrategy,verticalAlignment)",
            }
        })

        # Type column color (encounters + static)
        type_col = 4 if kind in ("encounters", "static") else None
        if type_col is not None and len(row) > type_col:
            type_name = str(row[type_col]).split(" / ")[0].upper()
            if type_name in gbd.TYPE_COLORS:
                requests.append({
                    "repeatCell": {
                        "range": {
                            "sheetId": sheet_id,
                            "startRowIndex": r_idx,
                            "endRowIndex": r_idx + 1,
                            "startColumnIndex": type_col,
                            "endColumnIndex": type_col + 1,
                        },
                        "cell": {
                            "userEnteredFormat": {
                                "backgroundColor": hex_rgb(gbd.TYPE_COLORS[type_name]),
                                "textFormat": {"bold": True, "foregroundColor": {"red": 1, "green": 1, "blue": 1}},
                                "horizontalAlignment": "CENTER",
                            }
                        },
                        "fields": "userEnteredFormat(backgroundColor,textFormat,horizontalAlignment)",
                    }
                })
        alt = not alt

    if requests:
        sh.batch_update({"requests": requests})


def export_xlsx(gc: gspread.Client, spreadsheet_id: str):
    data = gc.http_client.export(spreadsheet_id, format=ExportFormat.EXCEL)
    XLSX_BACKUP.write_bytes(data)
    print(f"Exported backup → {XLSX_BACKUP}")


def sync(export: bool = False):
    cfg = load_config()
    gc = get_client()
    sh = open_or_create_spreadsheet(gc, cfg)
    tabs = ensure_tabs(sh)

    species_db = gbd.parse_pokemon_db(gbd.PBS / "pokemon.txt")
    trainer_types = gbd.parse_trainer_types(gbd.PBS / "trainer_types.txt")
    maps = gbd.parse_map_metadata(gbd.PBS / "map_metadata.txt")
    encounters = gbd.parse_encounters(gbd.PBS / "encounters.txt", maps)
    trainers = gbd.parse_trainers(gbd.PBS / "trainers.txt")
    placements, static = gbd.parse_battle_placements(gbd.PBS / "MapEvents")

    datasets = {
        TAB_INDEX: (build_index_rows(len(encounters), len(trainers)), "index"),
        TAB_ENCOUNTERS: (build_encounter_rows(encounters, species_db, maps), "encounters"),
        TAB_SUMMARY: (build_summary_rows(encounters, species_db, maps), "summary"),
        TAB_TRAINERS: (build_trainer_rows(trainers, trainer_types, species_db, placements, maps), "trainers"),
        TAB_STATIC: (build_static_rows(static, species_db, maps), "static"),
    }

    for title, (rows, kind) in datasets.items():
        print(f"  Updating {title} ({len(rows)} rows)...")
        write_tab(tabs[title], rows)
        format_sheet(sh, title, rows, kind=kind)

    cfg["spreadsheet_id"] = sh.id
    cfg["spreadsheet_url"] = sh.url
    cfg["last_synced"] = str(date.today())
    save_config(cfg)

    print(f"\nGoogle Sheet ready:\n  {sh.url}\n")
    if export:
        export_xlsx(gc, sh.id)
    return sh.url


if __name__ == "__main__":
    do_export = "--export" in sys.argv
    sync(export=do_export)
