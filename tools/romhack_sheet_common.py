"""Shared helpers for Essentials Remix tracker sheets (romhack-inspired, original layout)."""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Elwynn-themed palette (not copied from other romhack docs)
WHITE = {"red": 1.0, "green": 1.0, "blue": 1.0}
BLACK = {"red": 0.0, "green": 0.0, "blue": 0.0}
CREAM = {"red": 0.96, "green": 0.93, "blue": 0.86}
TITLE_BG = {"red": 0.12, "green": 0.28, "blue": 0.22}
TITLE_FG = CREAM
MAP_HEADER_BG = {"red": 0.76, "green": 0.68, "blue": 0.48}
GUIDE_BG = {"red": 0.28, "green": 0.32, "blue": 0.36}
GUIDE_FG = CREAM
SECTION_COMMON = {"red": 0.55, "green": 0.72, "blue": 0.58}
SECTION_UNCOMMON = {"red": 0.85, "green": 0.72, "blue": 0.38}
SECTION_RARE = {"red": 0.52, "green": 0.28, "blue": 0.42}
SECTION_LAND = {"red": 0.22, "green": 0.42, "blue": 0.40}
SECTION_FISH = {"red": 0.35, "green": 0.52, "blue": 0.62}
DATA_BG = {"red": 0.14, "green": 0.16, "blue": 0.18}
DATA_FG = {"red": 0.92, "green": 0.92, "blue": 0.90}
TRAINER_LOCATION_BG = {"red": 0.35, "green": 0.18, "blue": 0.22}
TRAINER_LOCATION_FG = {"red": 0.98, "green": 0.90, "blue": 0.82}
TRAINER_LABEL_BG = {"red": 0.25, "green": 0.30, "blue": 0.38}
TRAINER_LABEL_FG = {"red": 0.98, "green": 0.90, "blue": 0.82}
WHITE_CELL = {"red": 0.98, "green": 0.98, "blue": 0.97}

RARITY_SLOTS = {"Common": 5, "Uncommon": 4, "Rare": 2}
EMPTY_NAME = "-----"
EMPTY_LEVEL = "0"

SPRITE_LIST_TAB = "Sprite List"
SPRITE_LIST_CATCH_COL = "E"   # Available to catch? (1 = yes, 0 = no)
SPRITE_LIST_NAME_COL = "F"
SPRITE_LIST_URL_COL = "R"
WARN_PINK = {"red": 1.0, "green": 0.75, "blue": 0.82}
# Copy-paste helper shown on trainer sheet (replace B with column, n with name row)
SPRITE_FORMULA_TEMPLATE = (
    f'=IF(Bn="","",IF(Bn="{EMPTY_NAME}","",IMAGE(XLOOKUP(Bn,\'{SPRITE_LIST_TAB}\'!$'
    f"{SPRITE_LIST_NAME_COL}:$" f"{SPRITE_LIST_NAME_COL},'{SPRITE_LIST_TAB}'!$"
    f"{SPRITE_LIST_URL_COL}:$" f"{SPRITE_LIST_URL_COL}))))"
)

SPECIES_DISPLAY = {
    "NIDORANF": "Nidoran♀",
    "NIDORANM": "Nidoran♂",
    "FARFETCHD": "Farfetch'd",
    "MRIME": "Mr. Rime",
    "MRMIME": "Mr. Mime",
    "MIMEJR": "Mime Jr.",
    "TYPE_NULL": "Type: Null",
    "HOOH": "Ho-Oh",
    "PORYGON2": "Porygon2",
    "PORYGONZ": "Porygon-Z",
}


def col_a1(col_index: int, row_1based: int) -> str:
    """0-based column index + 1-based row → e.g. B7."""
    n = col_index + 1
    letters = ""
    while n:
        n, rem = divmod(n - 1, 26)
        letters = chr(65 + rem) + letters
    return f"{letters}{row_1based}"


def species_display(species_id: str) -> str:
    sid = species_id.strip().upper()
    if sid in SPECIES_DISPLAY:
        return SPECIES_DISPLAY[sid]
    if "_" in sid:
        base, form = sid.split("_", 1)
        return f"{species_display(base)} ({form})"
    parts = sid.split("_")
    return " ".join(p.capitalize() for p in parts)


def move_display(move_id: str) -> str:
    return move_id.replace("_", " ").title()


def trainer_type_display(tt: str) -> str:
    return tt.replace("_", " ").title()


def trainer_title(tt: str, name: str, version: str = "0") -> str:
    base = f"{trainer_type_display(tt)} {name}"
    if version and version != "0":
        return f"{base} (v{version})"
    return base


def sprite_lookup_formula(name_cell: str) -> str:
    """Lookup sprite URL from Sprite List by species name in the cell below."""
    return (
        f'=IF({name_cell}="","",IF({name_cell}="{EMPTY_NAME}","",'
        f"IMAGE(XLOOKUP({name_cell},'{SPRITE_LIST_TAB}'!${SPRITE_LIST_NAME_COL}:${SPRITE_LIST_NAME_COL},"
        f"'{SPRITE_LIST_TAB}'!${SPRITE_LIST_URL_COL}:${SPRITE_LIST_URL_COL}))))"
    )


def encounter_catch_validation_formula(name_cell: str, lookup_name_col: str, lookup_catch_col: str) -> str:
    """Pink when name is filled but not catchable (0) or not in Sprite List lookup columns."""
    return (
        f"=AND(LEN({name_cell})>0,NOT({name_cell}=\"{EMPTY_NAME}\"),"
        f"IFERROR(XLOOKUP({name_cell},${lookup_name_col}$2:${lookup_name_col},"
        f"${lookup_catch_col}$2:${lookup_catch_col}),0)=0)"
    )


def clear_conditional_format_rules(svc, sid: str, sheet_id: int):
    meta = svc.spreadsheets().get(
        spreadsheetId=sid,
        fields="sheets(properties.sheetId,conditionalFormats)",
    ).execute()
    for sh in meta.get("sheets", []):
        if sh["properties"]["sheetId"] != sheet_id:
            continue
        rules = sh.get("conditionalFormats") or []
        if not rules:
            return
        requests = [
            {"deleteConditionalFormatRule": {"sheetId": sheet_id, "index": i}}
            for i in range(len(rules) - 1, -1, -1)
        ]
        batch_format(svc, sid, requests)


def add_encounter_catch_validation_rules(
    sheet_id: int,
    name_col_indexes: list[int],
    start_row: int,
    end_row: int,
    lookup_name_col_index: int,
    lookup_catch_col_index: int,
) -> list[dict]:
    """One boolean rule per Pokémon name column (data rows only)."""
    lookup_name_col = col_a1(lookup_name_col_index, 1).rstrip("0123456789")
    lookup_catch_col = col_a1(lookup_catch_col_index, 1).rstrip("0123456789")
    requests = []
    for col in name_col_indexes:
        anchor = col_a1(col, start_row + 1)
        formula = encounter_catch_validation_formula(anchor, lookup_name_col, lookup_catch_col)
        requests.append({
            "addConditionalFormatRule": {
                "rule": {
                    "ranges": [{
                        "sheetId": sheet_id,
                        "startRowIndex": start_row,
                        "endRowIndex": end_row,
                        "startColumnIndex": col,
                        "endColumnIndex": col + 1,
                    }],
                    "booleanRule": {
                        "condition": {
                            "type": "CUSTOM_FORMULA",
                            "values": [{"userEnteredValue": formula}],
                        },
                        "format": {"backgroundColor": WARN_PINK},
                    },
                },
                "index": 0,
            }
        })
    return requests


def level_text(min_lv: int, max_lv: int) -> str:
    if min_lv == max_lv:
        return str(min_lv)
    return f"{min_lv}-{max_lv}"


def parse_map_metadata(pbs_root: Path | None = None):
    pbs_root = pbs_root or ROOT / "PBS"
    maps = {}
    map_id = None
    for raw in (pbs_root / "map_metadata.txt").read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("# See"):
            continue
        m = re.match(r"^\[(\d+)\]", line)
        if m:
            map_id = int(m.group(1))
            maps[map_id] = f"Map {map_id:03d}"
            continue
        if map_id is None:
            continue
        m = re.match(r"^Name\s*=\s*(.*)$", line)
        if m:
            name = m.group(1).strip().replace("\\PN", "Player")
            if name:
                maps[map_id] = name
    return maps


def ensure_sheet(svc, sid: str, tab: str, row_count: int, col_count: int, index: int = 2, *, clear_values: bool = False):
    meta = svc.spreadsheets().get(spreadsheetId=sid).execute()
    existing = {sh["properties"]["title"]: sh["properties"]["sheetId"] for sh in meta.get("sheets", [])}
    if tab not in existing:
        resp = svc.spreadsheets().batchUpdate(
            spreadsheetId=sid,
            body={
                "requests": [{
                    "addSheet": {
                        "properties": {
                            "title": tab,
                            "index": index,
                            "gridProperties": {
                                "rowCount": row_count,
                                "columnCount": col_count,
                            },
                        }
                    }
                }]
            },
        ).execute()
        sheet_id = resp["replies"][0]["addSheet"]["properties"]["sheetId"]
    else:
        sheet_id = existing[tab]
        if clear_values:
            svc.spreadsheets().values().clear(spreadsheetId=sid, range=f"'{tab}'").execute()
        svc.spreadsheets().batchUpdate(
            spreadsheetId=sid,
            body={
                "requests": [{
                    "updateSheetProperties": {
                        "properties": {
                            "sheetId": sheet_id,
                            "gridProperties": {
                                "rowCount": row_count,
                                "columnCount": col_count,
                            },
                        },
                        "fields": "gridProperties.rowCount,gridProperties.columnCount",
                    }
                }]
            },
        ).execute()
    return sheet_id


def upload_values(svc, sid: str, tab: str, values: list[list]):
    svc.spreadsheets().values().update(
        spreadsheetId=sid,
        range=f"'{tab}'!A1",
        valueInputOption="USER_ENTERED",
        body={"values": values},
    ).execute()


def batch_format(svc, sid: str, requests: list, chunk: int = 80):
    for i in range(0, len(requests), chunk):
        svc.spreadsheets().batchUpdate(
            spreadsheetId=sid, body={"requests": requests[i : i + chunk]}
        ).execute()


def rgb_cell(bg, fg=BLACK, bold=False, halign="CENTER", valign="MIDDLE", wrap=False):
    fmt = {
        "backgroundColor": bg,
        "textFormat": {"foregroundColor": fg, "bold": bold},
        "horizontalAlignment": halign,
        "verticalAlignment": valign,
    }
    if wrap:
        fmt["wrapStrategy"] = "WRAP"
    return {"userEnteredFormat": fmt}


def merge_req(sheet_id, r0, r1, c0, c1):
    return {
        "mergeCells": {
            "range": {
                "sheetId": sheet_id,
                "startRowIndex": r0,
                "endRowIndex": r1,
                "startColumnIndex": c0,
                "endColumnIndex": c1,
            },
            "mergeType": "MERGE_ALL",
        }
    }


def repeat_cell(sheet_id, r0, r1, c0, c1, cell_fmt, fields="userEnteredFormat"):
    return {
        "repeatCell": {
            "range": {
                "sheetId": sheet_id,
                "startRowIndex": r0,
                "endRowIndex": r1,
                "startColumnIndex": c0,
                "endColumnIndex": c1,
            },
            "cell": cell_fmt,
            "fields": fields,
        }
    }
