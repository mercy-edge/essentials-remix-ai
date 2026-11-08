#!/usr/bin/env python3
"""
Build Trainers tab — romhack-doc inspired layout (original Elwynn styling):
  Label column A, party slots B–G.
  Sprite row uses XLOOKUP from Sprite List via species name in the row below.

Usage:
  python tools/export_trainers_doc.py
  python tools/export_trainers_doc.py --upload
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PBS = ROOT / "PBS"
OUT = ROOT / "ContentTracker"
SHEET_URL_FILE = OUT / "spreadsheet_url.txt"
TAB = "Trainers"
COLS = 8  # A–H

sys.path.insert(0, str(ROOT / "tools"))
from romhack_sheet_common import (  # noqa: E402
    BLACK,
    CREAM,
    DATA_BG,
    DATA_FG,
    SPRITE_FORMULA_TEMPLATE,
    TITLE_BG,
    TITLE_FG,
    TRAINER_LABEL_BG,
    TRAINER_LABEL_FG,
    TRAINER_LOCATION_BG,
    TRAINER_LOCATION_FG,
    WHITE_CELL,
    batch_format,
    col_a1,
    ensure_sheet,
    merge_req,
    move_display,
    repeat_cell,
    rgb_cell,
    species_display,
    sprite_lookup_formula,
    trainer_title,
    upload_values,
)

SCRIPTED_TRAINERS = [
    {
        "location": "Northshire Abbey",
        "type": "KOBOLD",
        "name": "Kobold Vermin",
        "version": "0",
        "party_size": "1",
        "notes": "Random Lv.1 from vermin pool. Counts toward Kobold Camp Cleanup (need 4).",
        "options": ["Rattata", "Poochyena", "Nidoran♂", "Nidoran♀", "Caterpie"],
        "options_levels": "1",
        "party": [],
    },
    {
        "location": "Echo Ridge / Forest's Edge",
        "type": "KOBOLD",
        "name": "Kobold Worker",
        "version": "0",
        "party_size": "1",
        "notes": "Counts toward Investigate Echo Ridge (need 5).",
        "options": [
            "Spinarak Lv.1–2",
            "Poochyena Lv.2",
            "Rattata Lv.2",
            "Pidgey Lv.1–2",
        ],
        "party": [],
    },
    {
        "location": "Echo Ridge Mine",
        "type": "KOBOLD",
        "name": "Kobold Laborer",
        "version": "0",
        "party_size": "1–2",
        "notes": "Rolls 1–2 Pokémon at Lv.3 from pool.",
        "options": ["Diglett Lv.3", "Zubat Lv.3", "Rattata Lv.3", "Spinarak Lv.3"],
        "party": [],
    },
]


@dataclass
class Mon:
    species: str
    level: str
    item: str = ""
    moves: list[str] = field(default_factory=list)
    ability: str = ""
    nickname: str = ""
    note: str = ""


@dataclass
class Trainer:
    location: str
    trainer_type: str
    name: str
    version: str = "0"
    party: list[Mon] = field(default_factory=list)
    party_size: str = ""
    options: list[str] = field(default_factory=list)
    notes: str = ""
    reinforcement: str = ""


def parse_trainers_txt():
    path = PBS / "trainers.txt"
    trainers = []
    current = None

    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.rstrip()
        if not line.strip() or line.startswith("# See") or line.startswith("#---"):
            continue
        m = re.match(r"^\[([A-Z0-9_]+),([^,\]]+)(?:,(\d+))?\]$", line.strip())
        if m:
            if current:
                if not current.party_size or current.party_size == "0":
                    current.party_size = str(len(current.party))
                trainers.append(current)
            current = Trainer(
                location="Various (PBS demo)",
                trainer_type=m.group(1),
                name=m.group(2).strip(),
                version=m.group(3) or "0",
                party_size="",
            )
            continue
        if not current:
            continue
        if re.match(r"^(LoseText|Items)\s*=", line):
            continue
        pm = re.match(r"^Pokemon\s*=\s*([A-Z0-9_]+),(\d+)", line)
        if pm:
            current.party.append(Mon(species=pm.group(1), level=pm.group(2)))
            continue
        if not current.party:
            continue
        mon = current.party[-1]
        sm = line.strip()
        if sm.startswith("Moves ="):
            moves = sm.split("=", 1)[1].strip()
            mon.moves = [move_display(x.strip()) for x in moves.split(",") if x.strip()][:4]
        elif sm.startswith("Item ="):
            mon.item = sm.split("=", 1)[1].strip().replace("_", " ").title()
        elif sm.startswith("AbilityIndex ="):
            mon.ability = f"Slot {sm.split('=', 1)[1].strip()}"
        elif sm.startswith("Name ="):
            mon.nickname = sm.split("=", 1)[1].strip()
        elif sm.startswith("Reinforcement ="):
            val = sm.split("=", 1)[1].strip()
            mon.note = f"Reinforcement ({val})"
            current.party_size = "varies (3 + reinforcements)"
            current.reinforcement = val

    if current:
        if not current.party_size:
            current.party_size = str(len(current.party))
        trainers.append(current)

    for t in trainers:
        if t.trainer_type == "YOUNGSTER" and t.name == "Ben" and t.version == "2":
            t.location = "Northshire Abbey (test)"
            if "varies" not in t.party_size:
                t.party_size = "varies (3 on field + reinforcements)"
            t.notes = "Ekans joins after 3 turns; Pidgey after 2 main Pokémon faint."

    return trainers


def build_scripted_trainers():
    out = []
    for raw in SCRIPTED_TRAINERS:
        t = Trainer(
            location=raw["location"],
            trainer_type=raw["type"],
            name=raw["name"],
            version=raw.get("version", "0"),
            party_size=raw["party_size"],
            notes=raw.get("notes", ""),
            options=raw.get("options", []),
        )
        out.append(t)
    return out


def pad_party(party: list[Mon], size: int = 6) -> list[Mon]:
    out = list(party[:size])
    while len(out) < size:
        out.append(Mon(species="", level="", note=""))
    return out


def build_trainer_block(trainer: Trainer, start_row: int) -> tuple[list[list], list]:
    """start_row = 0-based sheet row index for this block's location row."""
    rows = []
    meta = []
    party = pad_party(trainer.party, 6)
    names_row_1based = start_row + 4  # location + name + sprite + names

    def add_row(cells, kind="data"):
        row = list(cells) + [""] * (COLS - len(cells))
        rows.append(row[:COLS])
        meta.append(kind)

    add_row([trainer.location] + [""] * (COLS - 1), "location")

    title = trainer.name
    if trainer.trainer_type != "KOBOLD":
        title = trainer_title(trainer.trainer_type, trainer.name, trainer.version)
    add_row(["Trainer", title] + [""] * 5, "name")

    sprites = ["Sprite"]
    for slot_i, mon in enumerate(party):
        if mon.species:
            name_cell = col_a1(1 + slot_i, names_row_1based)
            sprites.append(sprite_lookup_formula(name_cell))
        else:
            sprites.append("")
    add_row(sprites, "sprites")

    names = ["Species"]
    for mon in party:
        if mon.species:
            label = species_display(mon.species)
            if mon.note:
                label = f"{label} *"
            names.append(label)
        else:
            names.append("")
    add_row(names, "names")

    nicknames = ["Nickname"]
    for mon in party:
        nicknames.append(mon.nickname if mon.nickname else "")
    add_row(nicknames, "labels")

    add_row(["Level"] + [mon.level for mon in party], "labels")
    add_row(["Held Item"] + [mon.item for mon in party], "labels")
    add_row(["Ability"] + [mon.ability for mon in party], "labels")
    add_row(["Nature"] + [""] * 6, "labels")

    for mi in range(4):
        label = "Moves" if mi == 0 else ""
        move_row = [label]
        for mon in party:
            move_row.append(mon.moves[mi] if mi < len(mon.moves) else "")
        add_row(move_row, "moves")

    if trainer.options:
        opts = ", ".join(trainer.options)
        add_row(["Pool", opts] + [""] * 5, "options")
    if trainer.party_size:
        add_row(["Party size", trainer.party_size] + [""] * 5, "options")
    if trainer.notes or trainer.reinforcement:
        note = trainer.notes
        if trainer.reinforcement and trainer.reinforcement not in (note or ""):
            note = (note + " " if note else "") + f"Reinforcement rule: {trainer.reinforcement}"
        add_row(["Notes", note] + [""] * 5, "options")

    add_row([""] * COLS, "spacer")
    return rows, meta


def build_sheet(trainers: list[Trainer]):
    values = [
        ["Essentials Remix — Trainers"] + [""] * (COLS - 1),
        ["Sprite lookup", SPRITE_FORMULA_TEMPLATE] + [""] * (COLS - 2),
    ]
    row_meta = ["title", "helper"]

    row_cursor = len(values)
    for trainer in trainers:
        block, block_meta = build_trainer_block(trainer, row_cursor)
        values.extend(block)
        row_meta.extend(block_meta)
        row_cursor += len(block)

    return values, row_meta


def write_csv(values):
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / "Trainers_Doc.csv"
    import csv
    with path.open("w", encoding="utf-8", newline="") as f:
        csv.writer(f).writerows(values)
    print(f"wrote {path} ({len(values)} rows)")


def upload(values, row_meta, spreadsheet: str, *, push_data: bool):
    from sheets_bridge import get_sheets_service, spreadsheet_id

    svc, _, _ = get_sheets_service()
    sid = spreadsheet_id(spreadsheet)
    row_count = max(len(values) + 10, 200)
    col_count = COLS + 2
    sheet_id = ensure_sheet(svc, sid, TAB, row_count, col_count, index=3, clear_values=push_data)

    if push_data:
        upload_values(svc, sid, TAB, values)
        print(f"  pushed {len(values)} rows to '{TAB}' from PBS")
    else:
        print(f"  formatting '{TAB}' only (data untouched)")

    requests = [
        {
            "unmergeCells": {
                "range": {
                    "sheetId": sheet_id,
                    "startRowIndex": 0,
                    "endRowIndex": len(values) + 5,
                    "startColumnIndex": 0,
                    "endColumnIndex": COLS,
                }
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
            sheet_id, 0, len(values), 0, COLS,
            rgb_cell(WHITE_CELL, BLACK, wrap=True),
        ),
    ]

    requests.append(merge_req(sheet_id, 0, 1, 0, COLS))
    requests.append(repeat_cell(
        sheet_id, 0, 1, 0, COLS,
        rgb_cell(TITLE_BG, TITLE_FG, bold=True, halign="LEFT"),
    ))
    requests.append(repeat_cell(
        sheet_id, 1, 2, 0, 1,
        rgb_cell(TRAINER_LABEL_BG, TRAINER_LABEL_FG, bold=True, halign="LEFT"),
    ))
    requests.append(merge_req(sheet_id, 1, 2, 1, COLS))
    requests.append(repeat_cell(
        sheet_id, 1, 2, 1, COLS,
        rgb_cell(DATA_BG, DATA_FG, halign="LEFT", wrap=True),
    ))

    i = 2
    while i < len(row_meta):
        kind = row_meta[i]
        if kind != "location":
            i += 1
            continue
        block_end = i + 1
        while block_end < len(row_meta) and row_meta[block_end] not in ("location", "title", "helper"):
            if row_meta[block_end] == "spacer":
                block_end += 1
                break
            block_end += 1

        moves_start = None
        for ri in range(i, block_end):
            k = row_meta[ri]
            if k == "location":
                requests.append(repeat_cell(
                    sheet_id, ri, ri + 1, 0, 1,
                    rgb_cell(TRAINER_LOCATION_BG, TRAINER_LOCATION_FG, bold=True, halign="LEFT"),
                ))
                requests.append(repeat_cell(
                    sheet_id, ri, ri + 1, 1, COLS,
                    rgb_cell(DATA_BG, DATA_FG, halign="LEFT"),
                ))
                requests.append({
                    "updateDimensionProperties": {
                        "range": {"sheetId": sheet_id, "dimension": "ROWS", "startIndex": ri, "endIndex": ri + 1},
                        "properties": {"pixelSize": 26},
                        "fields": "pixelSize",
                    }
                })
            elif k == "name":
                requests.append(repeat_cell(
                    sheet_id, ri, ri + 1, 0, 1,
                    rgb_cell(TRAINER_LABEL_BG, TRAINER_LABEL_FG, bold=True, halign="LEFT"),
                ))
                requests.append(merge_req(sheet_id, ri, ri + 1, 1, COLS))
                requests.append(repeat_cell(
                    sheet_id, ri, ri + 1, 1, COLS,
                    rgb_cell(TRAINER_LABEL_BG, CREAM, bold=True, halign="LEFT"),
                ))
            elif k == "sprites":
                requests.append(repeat_cell(
                    sheet_id, ri, ri + 1, 0, 1,
                    rgb_cell(TRAINER_LABEL_BG, TRAINER_LABEL_FG, bold=True, halign="LEFT"),
                ))
                requests.append({
                    "updateDimensionProperties": {
                        "range": {"sheetId": sheet_id, "dimension": "ROWS", "startIndex": ri, "endIndex": ri + 1},
                        "properties": {"pixelSize": 68},
                        "fields": "pixelSize",
                    }
                })
            elif k == "names":
                requests.append(repeat_cell(
                    sheet_id, ri, ri + 1, 0, 1,
                    rgb_cell(TRAINER_LABEL_BG, TRAINER_LABEL_FG, bold=True, halign="LEFT"),
                ))
                requests.append(repeat_cell(
                    sheet_id, ri, ri + 1, 1, COLS,
                    rgb_cell(WHITE_CELL, BLACK, halign="CENTER", bold=True),
                ))
            elif k in ("labels", "moves", "options"):
                requests.append(repeat_cell(
                    sheet_id, ri, ri + 1, 0, 1,
                    rgb_cell(TRAINER_LABEL_BG, TRAINER_LABEL_FG, bold=True, halign="LEFT"),
                ))
                requests.append(repeat_cell(
                    sheet_id, ri, ri + 1, 1, COLS,
                    rgb_cell(WHITE_CELL, BLACK, halign="CENTER"),
                ))
                if k == "moves" and moves_start is None:
                    moves_start = ri
            elif k == "spacer":
                pass

        if moves_start is not None:
            moves_end = min(moves_start + 4, block_end)
            if moves_end > moves_start + 1:
                requests.append(merge_req(sheet_id, moves_start, moves_end, 0, 1))

        for ri in range(i, block_end):
            if row_meta[ri] == "options":
                requests.append(merge_req(sheet_id, ri, ri + 1, 1, COLS))

        i = block_end

    requests.append({
        "updateDimensionProperties": {
            "range": {"sheetId": sheet_id, "dimension": "COLUMNS", "startIndex": 0, "endIndex": 1},
            "properties": {"pixelSize": 108},
            "fields": "pixelSize",
        }
    })
    for ci in range(1, COLS):
        requests.append({
            "updateDimensionProperties": {
                "range": {"sheetId": sheet_id, "dimension": "COLUMNS", "startIndex": ci, "endIndex": ci + 1},
                "properties": {"pixelSize": 102},
                "fields": "pixelSize",
            }
        })

    batch_format(svc, sid, requests)

    svc.spreadsheets().batchUpdate(
        spreadsheetId=sid,
        body={
            "requests": [{
                "updateSheetProperties": {
                    "properties": {
                        "sheetId": sheet_id,
                        "gridProperties": {"frozenRowCount": 2, "frozenColumnCount": 0},
                    },
                    "fields": "gridProperties.frozenRowCount,gridProperties.frozenColumnCount",
                }
            }]
        },
    ).execute()
    print(f"formatted '{TAB}'")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--format-only",
        action="store_true",
        help="Apply formatting only (does not overwrite your data)",
    )
    ap.add_argument(
        "--push-from-pbs",
        action="store_true",
        help="Replace sheet data from PBS/trainers.txt (explicit overwrite)",
    )
    ap.add_argument("--upload", action="store_true", help=argparse.SUPPRESS)
    ap.add_argument("--spreadsheet", default="")
    ap.add_argument("--pbs-only", action="store_true", help="Skip scripted random trainers")
    args = ap.parse_args()

    trainers = build_scripted_trainers()
    if not args.pbs_only:
        trainers.extend(parse_trainers_txt())

    values, row_meta = build_sheet(trainers)
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
        upload(values, row_meta, url, push_data=False)
    elif args.push_from_pbs:
        if not url:
            sys.exit("No spreadsheet URL")
        print(f"pushing from PBS to {url}")
        upload(values, row_meta, url, push_data=True)


if __name__ == "__main__":
    main()
