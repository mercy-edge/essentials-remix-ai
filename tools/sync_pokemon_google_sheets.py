#!/usr/bin/env python3
"""
Create/update a live Google Sheet of available Pokémon (name, sprite, types, BST).

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
  python3 tools/sync_pokemon_google_sheets.py
  python3 tools/sync_pokemon_google_sheets.py --export
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

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import generate_pokemon_docs as gpd  # noqa: E402

CONFIG_PATH = ROOT / "docs" / "sheets" / "pokemon_google_sheet.json"
XLSX_BACKUP = ROOT / "docs" / "sheets" / "Essentials_Remix_AI_Pokemon.xlsx"
SHEET_TITLE = "Essentials Remix AI — Available Pokémon"

SCOPES = [
    "https://www.googleapis.com/auth/spreadsheets",
    "https://www.googleapis.com/auth/drive",
]

TAB_INDEX = "Index"
TAB_POKEMON = "Available Pokémon"
TAB_TYPES = "By Type"
TAB_BST = "BST Tiers"
ALL_TABS = [TAB_INDEX, TAB_POKEMON, TAB_TYPES, TAB_BST]


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
        "     OR set GOOGLE_SERVICE_ACCOUNT_JSON as a secret\n"
        "  4. Set GOOGLE_SHEETS_SHARE_EMAIL to your Gmail\n"
        "  5. Re-run: python3 tools/sync_pokemon_google_sheets.py\n\n"
        "Meanwhile you can still use:\n"
        "  docs/sheets/Available_Pokemon.html\n"
        "  docs/sheets/Essentials_Remix_AI_Pokemon.xlsx → File → Import in Sheets\n"
    )


def load_config() -> dict:
    if CONFIG_PATH.is_file():
        return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    return {"spreadsheet_id": None, "spreadsheet_url": None, "title": SHEET_TITLE}


def save_config(cfg: dict):
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    CONFIG_PATH.write_text(json.dumps(cfg, indent=2) + "\n", encoding="utf-8")


def get_client() -> gspread.Client:
    return gspread.authorize(load_credentials())


def open_or_create_spreadsheet(gc: gspread.Client, cfg: dict) -> gspread.Spreadsheet:
    share_email = os.environ.get("GOOGLE_SHEETS_SHARE_EMAIL") or cfg.get("share_email")
    folder_id = os.environ.get("GOOGLE_SHEETS_FOLDER_ID")

    if cfg.get("spreadsheet_id"):
        try:
            return gc.open_by_key(cfg["spreadsheet_id"])
        except gspread.SpreadsheetNotFound:
            pass

    sh = gc.create(cfg.get("title") or SHEET_TITLE, folder_id=folder_id)
    cfg["spreadsheet_id"] = sh.id
    cfg["spreadsheet_url"] = sh.url
    cfg["created"] = str(date.today())
    save_config(cfg)

    if share_email:
        sh.share(share_email, perm_type="user", role="writer", notify=True)
    # Anyone-with-link can view (handy for a public Run & Bun-style doc)
    try:
        sh.share(None, perm_type="anyone", role="reader", with_link=True)
    except Exception:
        pass
    return sh


def ensure_tabs(sh: gspread.Spreadsheet) -> dict[str, gspread.Worksheet]:
    existing = {ws.title: ws for ws in sh.worksheets()}
    tabs: dict[str, gspread.Worksheet] = {}
    for i, title in enumerate(ALL_TABS):
        if title in existing:
            tabs[title] = existing[title]
        else:
            tabs[title] = sh.add_worksheet(title=title, rows=2000, cols=20, index=i)
    for ws in sh.worksheets():
        if ws.title not in ALL_TABS and ws.title == "Sheet1":
            try:
                sh.del_worksheet(ws)
            except Exception:
                pass
    return tabs


def clear_and_write(ws: gspread.Worksheet, rows: list[list]):
    ws.clear()
    if not rows:
        return
    ws.update(rows, value_input_option="USER_ENTERED")


def build_index_rows(base_count: int, form_count: int, total: int) -> list[list]:
    return [
        ["Essentials Remix AI — Available Pokémon", "", "", "", ""],
        ["", "", "", "", ""],
        ["Generated", str(date.today()), "", "", ""],
        ["Base species", base_count, "", "", ""],
        ["Alternate forms", form_count, "", "", ""],
        ["Total rows", total, "", "", ""],
        ["", "", "", "", ""],
        ["Tabs", "Contents", "", "", ""],
        ["Available Pokémon", "Sprite (IMAGE), Dex #, Name, Form, Types, base stats, BST", "", "", ""],
        ["By Type", "Counts and top BST examples per type", "", "", ""],
        ["BST Tiers", "Rough power bands by base stat total", "", "", ""],
        ["", "", "", "", ""],
        [
            "Note",
            "Sprites use PokéAPI national-dex images (form rows fall back to base sprite). "
            "For local Essentials sprites, open Available_Pokemon.html or the .xlsx backup.",
            "",
            "",
            "",
        ],
    ]


def build_pokemon_rows(rows: list[gpd.SpeciesRow]) -> list[list]:
    header = [
        "Sprite",
        "#",
        "Name",
        "Form",
        "Type 1",
        "Type 2",
        "HP",
        "Atk",
        "Def",
        "SpA",
        "SpD",
        "Spe",
        "BST",
        "Generation",
        "Abilities",
        "Hidden Ability",
        "Flags",
        "Species ID",
    ]
    out = [header]
    for row in rows:
        url = gpd.pokeapi_sprite_url(row.dex, row.form, row.form_name)
        sprite = f'=IMAGE("{url}")'
        out.append(
            [
                sprite,
                row.dex,
                row.name,
                row.form_name,
                row.types[0].title() if row.types else "",
                row.types[1].title() if len(row.types) > 1 else "",
                *row.stats,
                row.bst,
                row.generation,
                row.abilities,
                row.hidden_ability.replace(",", " / ") if row.hidden_ability else "",
                row.flags,
                row.species_id if row.form == 0 else f"{row.species_id},{row.form}",
            ]
        )
    return out


def build_type_rows(rows: list[gpd.SpeciesRow]) -> list[list]:
    header = ["Type", "Count", "Avg BST", "Examples (highest BST)"]
    out = [header]
    buckets: dict[str, list[gpd.SpeciesRow]] = {t: [] for t in gpd.TYPE_COLORS}
    for row in rows:
        for t in row.types:
            buckets.setdefault(t, []).append(row)
    for t in gpd.TYPE_COLORS:
        group = buckets.get(t, [])
        if not group:
            continue
        avg = round(sum(x.bst for x in group) / len(group), 1)
        top = sorted(group, key=lambda x: (-x.bst, x.name))[:8]
        examples = ", ".join(f"{gpd.display_name(x)} ({x.bst})" for x in top)
        out.append([t.title(), len(group), avg, examples])
    return out


def build_bst_rows(rows: list[gpd.SpeciesRow]) -> list[list]:
    tiers = [
        ("NU / weak", 0, 399),
        ("RU / mid", 400, 479),
        ("UU / strong", 480, 529),
        ("OU / very strong", 530, 569),
        ("Uber / legendary tier", 570, 9999),
    ]
    out = [["Tier", "BST range", "Count", "Examples"]]
    for label, lo, hi in tiers:
        group = [x for x in rows if lo <= x.bst <= hi]
        examples = ", ".join(
            gpd.display_name(x) for x in sorted(group, key=lambda x: (-x.bst, x.name))[:12]
        )
        out.append([label, f"{lo}–{hi if hi < 9999 else '∞'}", len(group), examples])
    return out


def format_pokemon_sheet(sh: gspread.Spreadsheet, ws: gspread.Worksheet, n_rows: int):
    """Apply column widths, freeze, basic header formatting via Sheets API."""
    requests = [
        {
            "repeatCell": {
                "range": {
                    "sheetId": ws.id,
                    "startRowIndex": 0,
                    "endRowIndex": 1,
                },
                "cell": {
                    "userFormat": {
                        "backgroundColor": hex_rgb("374151"),
                        "textFormat": {
                            "foregroundColor": hex_rgb("FFFFFF"),
                            "bold": True,
                            "fontFamily": "Arial",
                            "fontSize": 10,
                        },
                        "horizontalAlignment": "CENTER",
                    }
                },
                "fields": "userFormat(backgroundColor,textFormat,horizontalAlignment)",
            }
        },
        {
            "updateSheetProperties": {
                "properties": {
                    "sheetId": ws.id,
                    "gridProperties": {"frozenRowCount": 1, "frozenColumnCount": 3},
                },
                "fields": "gridProperties.frozenRowCount,gridProperties.frozenColumnCount",
            }
        },
        {
            "autoResizeDimensions": {
                "dimensions": {
                    "sheetId": ws.id,
                    "dimension": "COLUMNS",
                    "startIndex": 1,
                    "endIndex": 18,
                }
            }
        },
        {
            "updateDimensionProperties": {
                "range": {
                    "sheetId": ws.id,
                    "dimension": "COLUMNS",
                    "startIndex": 0,
                    "endIndex": 1,
                },
                "properties": {"pixelSize": 56},
                "fields": "pixelSize",
            }
        },
        {
            "updateDimensionProperties": {
                "range": {
                    "sheetId": ws.id,
                    "dimension": "ROWS",
                    "startIndex": 1,
                    "endIndex": n_rows,
                },
                "properties": {"pixelSize": 48},
                "fields": "pixelSize",
            }
        },
        {
            "setBasicFilter": {
                "filter": {
                    "range": {
                        "sheetId": ws.id,
                        "startRowIndex": 0,
                        "endRowIndex": n_rows,
                        "startColumnIndex": 0,
                        "endColumnIndex": 18,
                    }
                }
            }
        },
    ]

    # Color Type 1 / Type 2 columns from values (batch by type)
    # Type 1 = col E (4), Type 2 = col F (5)
    for col_index in (4, 5):
        for type_id, color in gpd.TYPE_COLORS.items():
            requests.append(
                {
                    "addConditionalFormatRule": {
                        "rule": {
                            "ranges": [
                                {
                                    "sheetId": ws.id,
                                    "startRowIndex": 1,
                                    "endRowIndex": n_rows,
                                    "startColumnIndex": col_index,
                                    "endColumnIndex": col_index + 1,
                                }
                            ],
                            "booleanRule": {
                                "condition": {
                                    "type": "TEXT_EQ",
                                    "values": [{"userEnteredValue": type_id.title()}],
                                },
                                "format": {
                                    "backgroundColor": hex_rgb(color),
                                    "textFormat": {
                                        "foregroundColor": hex_rgb("FFFFFF"),
                                        "bold": True,
                                    },
                                },
                            },
                        },
                        "index": 0,
                    }
                }
            )

    sh.batch_update({"requests": requests})


def sync(export: bool = False) -> str:
    base, forms, rows = gpd.collect_rows()
    cfg = load_config()
    gc = get_client()
    sh = open_or_create_spreadsheet(gc, cfg)
    tabs = ensure_tabs(sh)

    print(f"Syncing {len(rows)} rows → {sh.url}")
    clear_and_write(tabs[TAB_INDEX], build_index_rows(len(base), len(forms), len(rows)))
    poke_rows = build_pokemon_rows(rows)
    clear_and_write(tabs[TAB_POKEMON], poke_rows)
    clear_and_write(tabs[TAB_TYPES], build_type_rows(rows))
    clear_and_write(tabs[TAB_BST], build_bst_rows(rows))

    try:
        format_pokemon_sheet(sh, tabs[TAB_POKEMON], len(poke_rows))
    except Exception as e:
        print(f"Warning: formatting skipped ({e})")

    cfg["spreadsheet_id"] = sh.id
    cfg["spreadsheet_url"] = sh.url
    cfg["title"] = SHEET_TITLE
    cfg["last_synced"] = str(date.today())
    cfg["row_count"] = len(rows)
    save_config(cfg)

    # Always refresh local xlsx/html backups
    gpd.OUT_DIR.mkdir(parents=True, exist_ok=True)
    wb = gpd.build_workbook(rows, len(base), len(forms), embed_images=True)
    wb.save(XLSX_BACKUP)
    gpd.OUT_HTML.write_text(gpd.generate_html(rows), encoding="utf-8")

    if export:
        data = sh.export(format=ExportFormat.EXCEL)
        XLSX_BACKUP.write_bytes(data)
        print(f"Exported backup → {XLSX_BACKUP}")

    print(f"Live sheet: {sh.url}")
    return sh.url


def main():
    export = "--export" in sys.argv
    sync(export=export)


if __name__ == "__main__":
    main()
