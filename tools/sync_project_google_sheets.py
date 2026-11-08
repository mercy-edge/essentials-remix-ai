#!/usr/bin/env python3
"""
Create/update the live project Google Sheet (Pokémon catalog + battles).

Available Pokémon is uploaded first with IMAGE() sprites. Encounter / trainer
tabs then reference those sprites via INDEX/MATCH on Species ID.

Credentials (first match wins):
  1. GOOGLE_SERVICE_ACCOUNT_JSON
  2. GOOGLE_APPLICATION_CREDENTIALS
  3. ~/.config/gspread/service_account.json
  4. docs/sheets/google-service-account.json

Optional:
  GOOGLE_SHEETS_SHARE_EMAIL
  GOOGLE_SHEETS_FOLDER_ID

Usage:
  python3 tools/sync_project_google_sheets.py
  python3 tools/sync_project_google_sheets.py --export
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
import docs_lib as d  # noqa: E402
import generate_project_docs as gpd  # noqa: E402

CONFIG_PATH = d.OUT_DIR / "project_google_sheet.json"
# Keep old filename working as a pointer
LEGACY_CONFIG = d.OUT_DIR / "pokemon_google_sheet.json"

SCOPES = [
    "https://www.googleapis.com/auth/spreadsheets",
    "https://www.googleapis.com/auth/drive",
]

ALL_TABS = [
    "Index",
    d.POKEMON_TAB,
    "By Type",
    "BST Tiers",
    "Wild Encounters",
    "Encounter Summary",
    "Trainer Battles",
    "Trainer Party",
    "Static Battles",
]


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
        str(d.OUT_DIR / "google-service-account.json"),
    ]
    raw = os.environ.get("GOOGLE_SERVICE_ACCOUNT_JSON")
    if raw:
        return Credentials.from_service_account_info(json.loads(raw), scopes=SCOPES)
    for p in paths:
        if p and Path(p).is_file():
            return Credentials.from_service_account_file(p, scopes=SCOPES)
    raise SystemExit(
        "Google credentials not found.\n\n"
        "Meanwhile use local docs:\n"
        f"  {d.OUT_HTML}\n"
        f"  {d.OUT_XLSX}\n\n"
        "Setup: save service-account JSON to docs/sheets/google-service-account.json\n"
        "and set GOOGLE_SHEETS_SHARE_EMAIL, then re-run this script.\n"
    )


def load_config() -> dict:
    for path in (CONFIG_PATH, LEGACY_CONFIG):
        if path.is_file():
            cfg = json.loads(path.read_text(encoding="utf-8"))
            cfg.setdefault("title", d.PROJECT_TITLE)
            return cfg
    return {"spreadsheet_id": None, "spreadsheet_url": None, "title": d.PROJECT_TITLE}


def save_config(cfg: dict):
    d.OUT_DIR.mkdir(parents=True, exist_ok=True)
    text = json.dumps(cfg, indent=2) + "\n"
    CONFIG_PATH.write_text(text, encoding="utf-8")
    LEGACY_CONFIG.write_text(text, encoding="utf-8")


def open_or_create(gc: gspread.Client, cfg: dict) -> gspread.Spreadsheet:
    share_email = os.environ.get("GOOGLE_SHEETS_SHARE_EMAIL") or cfg.get("share_email")
    folder_id = os.environ.get("GOOGLE_SHEETS_FOLDER_ID")
    if cfg.get("spreadsheet_id"):
        try:
            return gc.open_by_key(cfg["spreadsheet_id"])
        except gspread.SpreadsheetNotFound:
            pass
    sh = gc.create(cfg.get("title") or d.PROJECT_TITLE, folder_id=folder_id)
    cfg["spreadsheet_id"] = sh.id
    cfg["spreadsheet_url"] = sh.url
    cfg["created"] = str(date.today())
    save_config(cfg)
    if share_email:
        sh.share(share_email, perm_type="user", role="writer", notify=True)
    try:
        sh.share(None, perm_type="anyone", role="reader", with_link=True)
    except Exception:
        pass
    return sh


def ensure_tabs(sh: gspread.Spreadsheet) -> dict[str, gspread.Worksheet]:
    existing = {ws.title: ws for ws in sh.worksheets()}
    tabs = {}
    for i, title in enumerate(ALL_TABS):
        if title in existing:
            tabs[title] = existing[title]
        else:
            tabs[title] = sh.add_worksheet(title=title, rows=2500, cols=22, index=i)
    for ws in sh.worksheets():
        if ws.title not in ALL_TABS and ws.title == "Sheet1":
            try:
                sh.del_worksheet(ws)
            except Exception:
                pass
    return tabs


def clear_and_write(ws: gspread.Worksheet, rows: list[list]):
    ws.clear()
    if rows:
        # Sheets API hard limit ~10M cells; chunk large tabs
        chunk = 1000
        for i in range(0, len(rows), chunk):
            part = rows[i : i + chunk]
            start = i + 1
            ws.update(part, range_name=f"A{start}", value_input_option="USER_ENTERED")


def workbook_to_sheet_rows(data: dict) -> dict[str, list[list]]:
    """Build value matrices with Sheets formulas (sprite catalog references)."""
    wb = gpd.build_workbook(
        poke_rows=data["poke_rows"],
        base_count=len(data["base"]),
        form_count=len(data["forms"]),
        catalog=data["catalog"],
        encounters=data["encounters"],
        trainers=data["trainers"],
        trainer_types=data["trainer_types"],
        placements=data["placements"],
        static=data["static"],
        maps=data["maps"],
        embed_images=False,
        sheets_formulas=True,
    )
    out: dict[str, list[list]] = {}
    for title in ALL_TABS:
        if title not in wb.sheetnames:
            continue
        ws = wb[title]
        rows = []
        for r in ws.iter_rows(values_only=True):
            # Drop fully empty trailing rows
            if all(c is None or c == "" for c in r):
                continue
            rows.append(["" if c is None else c for c in r])
        out[title] = rows
    return out


def format_catalog(sh: gspread.Spreadsheet, ws: gspread.Worksheet, n_rows: int):
    requests = [
        {
            "repeatCell": {
                "range": {"sheetId": ws.id, "startRowIndex": 0, "endRowIndex": 1},
                "cell": {
                    "userFormat": {
                        "backgroundColor": hex_rgb("374151"),
                        "textFormat": {
                            "foregroundColor": hex_rgb("FFFFFF"),
                            "bold": True,
                            "fontFamily": "Arial",
                            "fontSize": 10,
                        },
                    }
                },
                "fields": "userFormat(backgroundColor,textFormat)",
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
                    "endIndex": max(2, n_rows),
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
    for col_index in (4, 5):
        for type_id, color in d.TYPE_COLORS.items():
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
    data = gpd.load_all()
    # Refresh local offline artifacts with embedded sprites
    gpd.generate(embed_images=True, html=True, xlsx=True)

    cfg = load_config()
    gc = gspread.authorize(load_credentials())
    sh = open_or_create(gc, cfg)
    tabs = ensure_tabs(sh)
    matrices = workbook_to_sheet_rows(data)

    print(f"Syncing project docs → {sh.url}")
    # Catalog first so INDEX/MATCH targets exist
    order = [
        d.POKEMON_TAB,
        "Index",
        "By Type",
        "BST Tiers",
        "Wild Encounters",
        "Encounter Summary",
        "Trainer Battles",
        "Trainer Party",
        "Static Battles",
    ]
    for title in order:
        rows = matrices.get(title, [])
        print(f"  {title}: {len(rows)} rows")
        clear_and_write(tabs[title], rows)

    try:
        format_catalog(sh, tabs[d.POKEMON_TAB], len(matrices[d.POKEMON_TAB]))
    except Exception as e:
        print(f"Warning: catalog formatting skipped ({e})")

    cfg["spreadsheet_id"] = sh.id
    cfg["spreadsheet_url"] = sh.url
    cfg["title"] = d.PROJECT_TITLE
    cfg["last_synced"] = str(date.today())
    cfg["row_counts"] = {k: len(v) for k, v in matrices.items()}
    save_config(cfg)

    if export:
        d.OUT_XLSX.write_bytes(sh.export(format=ExportFormat.EXCEL))
        print(f"Exported {d.OUT_XLSX}")

    print(f"Live sheet: {sh.url}")
    return sh.url


def main():
    sync(export="--export" in sys.argv)


if __name__ == "__main__":
    main()
