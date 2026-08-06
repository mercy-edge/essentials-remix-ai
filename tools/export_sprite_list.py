#!/usr/bin/env python3
"""
Build a romhack-style Sprite List tab from PBS pokemon + forms data,
with Pokemon Showdown gen5 sprite IMAGE formulas, types, and BST.

Usage:
  python tools/export_sprite_list.py                  # write ContentTracker/Sprite_List.csv
  python tools/export_sprite_list.py --upload         # also push to linked Google Sheet
  python tools/export_sprite_list.py --upload --spreadsheet URL
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PBS = ROOT / "PBS"
OUT = ROOT / "ContentTracker"
SHEET_URL_FILE = OUT / "spreadsheet_url.txt"
SHOWDOWN_BASE = "https://play.pokemonshowdown.com/sprites/gen5"

# Essentials internal id → Showdown base slug overrides
SPECIES_SLUG_OVERRIDES = {
    "NIDORANF": "nidoranf",
    "NIDORANM": "nidoranm",
    "FARFETCHD": "farfetchd",
    "SIRFETCHD": "sirfetchd",
    "MRMIME": "mrmime",
    "MIMEJR": "mimejr",
    "MRRIME": "mrrime",
    "TYPE_NULL": "typenull",
    "PORYGON2": "porygon2",
    "PORYGONZ": "porygonz",
    "HOOH": "hooh",
    "FLABEBE": "flabebe",
    "JANGMOO": "jangmoo",
    "HAKAMOO": "hakamoo",
    "KOMMOO": "kommoo",
    "TAPUKOKO": "tapukoko",
    "TAPULELE": "tapulele",
    "TAPUBULU": "tapubulu",
    "TAPUFINI": "tapufini",
    "GREATTUSK": "greattusk",
    "SCREAMTAIL": "screamtail",
    "BRUTEBONNET": "brutebonnet",
    "FLUTTERMANE": "fluttermane",
    "SLITHERWING": "slitherwing",
    "SANDYSHOCKS": "sandyshocks",
    "IRONTREADS": "irontreads",
    "IRONBUNDLE": "ironbundle",
    "IRONHANDS": "ironhands",
    "IRONJUGULIS": "ironjugulis",
    "IRONMOTH": "ironmoth",
    "IRONTHORNS": "ironthorns",
    "WOCHIEN": "wochien",
    "CHIENPAO": "chienpao",
    "TINGLU": "tinglu",
    "CHIYU": "chiyu",
    "ROARINGMOON": "roaringmoon",
    "IRONVALIANT": "ironvaliant",
    "WALKINGWAKE": "walkingwake",
    "IRONLEAVES": "ironleaves",
    "GOUGINGFIRE": "gougingfire",
    "RAGINGBOLT": "ragingbolt",
    "IRONBOULDER": "ironboulder",
    "IRONCROWN": "ironcrown",
    "TERAPAGOS": "terapagos",
}

# Exact FormName → showdown suffix (leading hyphen omitted; "" = base sprite)
FORM_SUFFIX = {
    "Alolan": "alola",
    "Galarian": "galar",
    "Hisuian": "hisui",
    "Paldean": "paldea",
    "Paldean (Combat Breed)": "paldea",
    "Paldean (Blaze Breed)": "paldeafire",
    "Paldean (Aqua Breed)": "paldeawater",
    "Mega Charizard X": "megax",
    "Mega Charizard Y": "megay",
    "Mega Mewtwo X": "megax",
    "Mega Mewtwo Y": "megay",
    "Mega Raichu X": "megax",
    "Mega Raichu Y": "megay",
    "Mega Garchomp Z": "megaz",
    "Mega Lucario Z": "megaz",
    "Mega Absol Z": "megaz",
    "Primal Kyogre": "primal",
    "Primal Groudon": "primal",
    "Ash-Greninja": "ash",
    "Origin Forme": "origin",
    "Therian Forme": "therian",
    "Therian Form": "therian",
    "Sky Forme": "sky",
    "Attack Forme": "attack",
    "Defense Forme": "defense",
    "Speed Forme": "speed",
    "Blade Forme": "blade",
    "Complete Forme": "complete",
    "10% Forme": "10",
    "Pirouette Forme": "pirouette",
    "Resolute Form": "resolute",
    "Female": "f",
    "Mega Floette": "mega",
    "Eternal Flower": "eternal",
    "White Kyurem": "white",
    "Black Kyurem": "black",
    "Dawn Wings": "dawnwings",
    "Dusk Mane": "duskmane",
    "Ultra Necrozma": "ultra",
    "Dusk Form": "dusk",
    "Midnight Form": "midnight",
    "School Form": "school",
    "Busted Form": "busted",
    "Totem": "totem",
    "Ice Rider": "icerider",
    "Shadow Rider": "shadowrider",
    "Crowned Sword": "crowned",
    "Crowned Shield": "crowned",
    "Rapid Strike Style": "rapidstrike",
    "Single Strike Style": "single",
    "Ice Face": "ice",
    "Noice Face": "noice",
    "Hangry Mode": "hangry",
    "Full Belly Mode": "",
    "Zen Mode": "zen",
    "Galarian Zen Mode": "galarzen",
    "Galarian Standard Mode": "galar",
    "Sunny Form": "sunny",
    "Rainy Form": "rainy",
    "Snowy Form": "snowy",
    "Sunshine Form": "sunshine",
    "East Sea": "east",
    "West Sea": "",
    "Heat Rotom": "heat",
    "Wash Rotom": "wash",
    "Frost Rotom": "frost",
    "Fan Rotom": "fan",
    "Mow Rotom": "mow",
    "Blue-Striped": "bluestriped",
    "White-Striped": "whitestriped",
    "Red-Striped": "",
    "Plant Cloak": "",
    "Sandy Cloak": "sandy",
    "Trash Cloak": "trash",
    "Overcast Form": "",
    "Sunshine Form": "sunshine",
    "Land Forme": "",
    "Sky Forme": "sky",
    "Hoopa Confined": "",
    "Hoopa Unbound": "unbound",
    "Average Size": "",
    "Small Size": "small",
    "Large Size": "large",
    "Super Size": "super",
    "50% Forme": "",
    "Hero Form": "hero",
    "Roaming Form": "roaming",
    "Bloodmoon Ursaluna": "bloodmoon",
    "Wellspring Mask": "wellspring",
    "Hearthflame Mask": "hearthflame",
    "Cornerstone Mask": "cornerstone",
    "Teal Mask": "",
    "Terastal Form": "terastal",
    "Stellar Form": "stellar",
    "Family of Four": "",
    "Family of Three": "three",
    "Two-Segment Form": "",
    "Three-Segment Form": "three",
    "Curly Form": "",
    "Droopy Form": "droopy",
    "Stretchy Form": "stretchy",
    "Low Key Form": "lowkey",
    "Amped Form": "",
    "Original Color": "original",
    "Antique Form": "antique",
    "Phony Form": "",
    "Mega Magearna (Original Color)": "megaoriginal",
    "Spiky-Eared": "spikyeared",
    "Active Mode": "active",
    "Gulping Form": "gulping",
    "Gorging Form": "gorging",
    "Pom-Pom Style": "pompom",
    "Pa'u Style": "pau",
    "Sensu Style": "sensu",
    "Baile Style": "",
}


def title_type(t: str) -> str:
    if not t:
        return ""
    special = {
        "ELECTRIC": "Electric",
        "PSYCHIC": "Psychic",
        "FIGHTING": "Fighting",
        "FLYING": "Flying",
        "POISON": "Poison",
        "GROUND": "Ground",
        "ROCK": "Rock",
        "BUG": "Bug",
        "GHOST": "Ghost",
        "STEEL": "Steel",
        "FIRE": "Fire",
        "WATER": "Water",
        "GRASS": "Grass",
        "ICE": "Ice",
        "DRAGON": "Dragon",
        "DARK": "Dark",
        "FAIRY": "Fairy",
        "NORMAL": "Normal",
        "QMARKS": "???",
    }
    return special.get(t.upper(), t.title())


def species_slug(species_id: str) -> str:
    if species_id in SPECIES_SLUG_OVERRIDES:
        return SPECIES_SLUG_OVERRIDES[species_id]
    return re.sub(r"[^a-z0-9]", "", species_id.lower())


def form_suffix(form_name: str, species_id: str) -> str:
    if not form_name:
        return ""
    if form_name in FORM_SUFFIX:
        return FORM_SUFFIX[form_name]

    # Unown letters
    if species_id == "UNOWN" and len(form_name) == 1:
        ch = form_name.lower()
        if ch == "!":
            return "exclamation"
        if ch == "?":
            return "question"
        return ch

    # Mega / Primal with species in name
    m = re.match(r"^Mega (.+) X$", form_name, re.I)
    if m:
        return "megax"
    m = re.match(r"^Mega (.+) Y$", form_name, re.I)
    if m:
        return "megay"
    if form_name.startswith("Mega "):
        return "mega"
    if form_name.startswith("Primal "):
        return "primal"

    # Vivillon / Flabebe / Minior / Furfrou / etc. — slugify form words
    # "Meadow Pattern" → meadow, "Blue Flower" → blue, "Bug Type" → bug
    name = form_name
    for junk in (
        " Forme", " Form", " Pattern", " Flower", " Cloak", " Size",
        " Mode", " Style", " Drive", " Trim", " Plumage", " Core",
        " Mask", " Breed", " Cream", " Swirl", " Type",
    ):
        name = name.replace(junk, "")
    name = name.replace("Type: ", "").replace("Type:", "")
    slug = re.sub(r"[^a-z0-9]", "", name.lower())
    # Drop redundant species prefix if present
    base = species_slug(species_id)
    if slug.startswith(base):
        slug = slug[len(base) :]
    return slug


def showdown_id(species_id: str, form_name: str) -> str:
    base = species_slug(species_id)
    suf = form_suffix(form_name, species_id)
    if not suf:
        return base
    # Showdown uses no hyphen for some compound suffixes like paldeafire
    # but uses hyphen for regional/mega: geodude-alola, charizard-megax
    if suf in ("megax", "megay", "megaz", "primal", "alola", "galar", "hisui",
               "paldea", "paldeafire", "paldeawater", "mega", "origin",
               "therian", "sky", "attack", "defense", "speed", "blade",
               "complete", "10", "pirouette", "ash", "unbound", "ultra",
               "dawnwings", "duskmane", "white", "black", "zen", "galarzen",
               "heat", "wash", "frost", "fan", "mow", "sandy", "trash",
               "sunny", "rainy", "snowy", "sunshine", "east", "f",
               "dusk", "midnight", "school", "busted", "icerider",
               "shadowrider", "crowned", "rapidstrike", "noice", "hangry",
               "hero", "roaming", "bloodmoon", "wellspring", "hearthflame",
               "cornerstone", "terastal", "stellar", "three", "droopy",
               "stretchy", "lowkey", "original", "antique", "spikyeared",
               "gulping", "gorging", "pompom", "pau", "sensu", "bluestriped",
               "whitestriped", "small", "large", "super", "active",
               "megaoriginal"):
        # paldeafire is showdown's toID of "Paldea-Fire" → actually "tauros-paldeablaze" etc.
        mapping = {
            "paldeafire": "paldeablaze",
            "paldeawater": "paldeaaqua",
            "dawnwings": "dawnwings",
            "duskmane": "duskmane",
            "galarzen": "galarzen",
            "rapidstrike": "rapidstrike",
            "icerider": "icerider",
            "shadowrider": "shadowrider",
            "bluestriped": "bluestriped",
            "whitestriped": "whitestriped",
            "spikyeared": "spikyeared",
            "pompom": "pompom",
            "megaoriginal": "mega-original",
        }
        suf = mapping.get(suf, suf)
        return f"{base}-{suf}"
    return f"{base}-{suf}"


def parse_pbs_species_files(paths):
    """Return ordered list of (species_id, data_dict) for form-0 entries."""
    species = []
    current_id = None
    current = None

    def flush():
        nonlocal current_id, current
        if current_id and current is not None:
            species.append((current_id, current))
        current_id = None
        current = None

    for path in paths:
        if not path.is_file():
            continue
        for raw in path.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            m = re.match(r"^\[([A-Z0-9_]+)\]$", line)
            if m:
                flush()
                current_id = m.group(1)
                current = {}
                continue
            if current is None:
                continue
            m = re.match(r"^(\w+)\s*=\s*(.*)$", line)
            if m:
                current[m.group(1)] = m.group(2).strip()
    flush()
    return species


def parse_pbs_forms(paths):
    """Return list of (species_id, form_num, data_dict)."""
    forms = []
    current_key = None
    current = None

    def flush():
        nonlocal current_key, current
        if current_key and current is not None:
            forms.append((*current_key, current))
        current_key = None
        current = None

    for path in paths:
        if not path.is_file():
            continue
        for raw in path.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            m = re.match(r"^\[([A-Z0-9_]+),(\d+)\]$", line)
            if m:
                flush()
                current_key = (m.group(1), int(m.group(2)))
                current = {}
                continue
            if current is None:
                continue
            m = re.match(r"^(\w+)\s*=\s*(.*)$", line)
            if m:
                current[m.group(1)] = m.group(2).strip()
    flush()
    return forms


def stats_from(data: dict):
    """PBS order HP,Atk,Def,Spe,SpA,SpD → return HP,Atk,Def,SpA,SpD,Spe,BST."""
    raw = data.get("BaseStats", "0,0,0,0,0,0")
    parts = [int(x.strip()) for x in raw.split(",")]
    while len(parts) < 6:
        parts.append(0)
    hp, atk, defense, spe, spa, spd = parts[:6]
    bst = hp + atk + defense + spe + spa + spd
    return hp, atk, defense, spa, spd, spe, bst


def types_from(data: dict):
    types = [t.strip() for t in data.get("Types", "NORMAL").split(",") if t.strip()]
    t1 = title_type(types[0]) if types else "Normal"
    t2 = title_type(types[1]) if len(types) > 1 else ""
    if t2 == t1:
        t2 = ""
    return t1, t2


def merge_form(base: dict, override: dict) -> dict:
    merged = dict(base)
    merged.update(override)
    return merged


def build_rows():
    base_paths = [
        PBS / "pokemon.txt",
        PBS / "pokemon_base_Gen_9_Pack.txt",
    ]
    form_paths = [
        PBS / "pokemon_forms.txt",
        PBS / "pokemon_forms_Gen_9_Pack.txt",
    ]

    bases = parse_pbs_species_files(base_paths)
    base_map = {sid: data for sid, data in bases}
    forms = parse_pbs_forms(form_paths)

    # Group forms by species
    forms_by_species = {}
    for sid, fnum, fdata in forms:
        forms_by_species.setdefault(sid, []).append((fnum, fdata))
    for sid in forms_by_species:
        forms_by_species[sid].sort(key=lambda x: x[0])

    rows = []
    headers = [
        "Sprite", "Dex#", "Species ID", "Form", "Name", "Form Name",
        "Type 1", "Type 2", "HP", "Attack", "Defense", "Sp. Atk", "Sp. Def", "Speed", "BST",
        "Showdown ID", "Sprite URL",
    ]
    rows.append(headers)

    for dex, (sid, base) in enumerate(bases, start=1):
        # Form 0
        entries = [(0, {}, base.get("FormName", ""))]
        for fnum, fdata in forms_by_species.get(sid, []):
            entries.append((fnum, fdata, fdata.get("FormName", f"Form {fnum}")))

        for fnum, fdata, form_name in entries:
            data = merge_form(base, fdata) if fnum else base
            name = data.get("Name", sid.title())
            disp_form = form_name if fnum else (base.get("FormName", "") or "-")
            display = name if fnum == 0 and not base.get("FormName") else (
                f"{name} ({disp_form})" if disp_form and disp_form != "-" else name
            )
            t1, t2 = types_from(data)
            hp, atk, defense, spa, spd, spe, bst = stats_from(data)
            sd_id = showdown_id(sid, form_name if fnum else "")
            url = f"{SHOWDOWN_BASE}/{sd_id}.png"
            # Row number in sheet = header(1) + current data index; filled after list built
            rows.append([
                None,  # Sprite formula filled below
                dex,
                sid,
                fnum,
                display,
                disp_form if fnum else "-",
                t1,
                t2,
                hp,
                atk,
                defense,
                spa,
                spd,
                spe,
                bst,
                sd_id,
                url,
            ])

    # Sprite column references URL column Q so locale comma/semicolon issues are avoided
    for i in range(1, len(rows)):
        row_num = i + 1  # 1-based sheet row
        rows[i][0] = f"=IMAGE(Q{row_num})"
    return rows


def write_csv(rows):
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / "Sprite_List.csv"
    with path.open("w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        for row in rows:
            w.writerow(row)
    print(f"wrote {path} ({len(rows)-1} pokemon/forms)")
    return path


def upload(rows, spreadsheet: str):
    # Lazy import bridge helpers
    sys.path.insert(0, str(ROOT / "tools"))
    from sheets_bridge import get_sheets_service, spreadsheet_id

    svc, _, _ = get_sheets_service()
    sid = spreadsheet_id(spreadsheet)
    tab = "Sprite List"

    meta = svc.spreadsheets().get(spreadsheetId=sid).execute()
    existing = {sh["properties"]["title"]: sh["properties"]["sheetId"] for sh in meta.get("sheets", [])}
    row_count = max(len(rows) + 10, 1500)
    col_count = max(len(rows[0]), 20)
    if tab not in existing:
        resp = svc.spreadsheets().batchUpdate(
            spreadsheetId=sid,
            body={
                "requests": [
                    {
                        "addSheet": {
                            "properties": {
                                "title": tab,
                                "index": 1,
                                "gridProperties": {
                                    "rowCount": row_count,
                                    "columnCount": col_count,
                                },
                            }
                        }
                    }
                ]
            },
        ).execute()
        sheet_id = resp["replies"][0]["addSheet"]["properties"]["sheetId"]
    else:
        sheet_id = existing[tab]
        svc.spreadsheets().values().clear(spreadsheetId=sid, range=f"'{tab}'").execute()
        svc.spreadsheets().batchUpdate(
            spreadsheetId=sid,
            body={
                "requests": [
                    {
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
                    }
                ]
            },
        ).execute()

    # Convert all cells to strings for API; formulas start with =
    values = [[("" if c is None else c) for c in row] for row in rows]

    # Batch in chunks to stay under payload limits
    chunk = 400
    for i in range(0, len(values), chunk):
        part = values[i : i + chunk]
        start_row = i + 1
        svc.spreadsheets().values().update(
            spreadsheetId=sid,
            range=f"'{tab}'!A{start_row}",
            valueInputOption="USER_ENTERED",
            body={"values": part},
        ).execute()
        print(f"  uploaded rows {start_row}-{start_row + len(part) - 1}")

    # Format: freeze header, set row height for sprites, bold header, autosize-ish widths
    requests = [
        {
            "updateSheetProperties": {
                "properties": {
                    "sheetId": sheet_id,
                    "gridProperties": {"frozenRowCount": 1},
                },
                "fields": "gridProperties.frozenRowCount",
            }
        },
        {
            "updateDimensionProperties": {
                "range": {
                    "sheetId": sheet_id,
                    "dimension": "ROWS",
                    "startIndex": 1,
                    "endIndex": len(values),
                },
                "properties": {"pixelSize": 56},
                "fields": "pixelSize",
            }
        },
        {
            "updateDimensionProperties": {
                "range": {
                    "sheetId": sheet_id,
                    "dimension": "COLUMNS",
                    "startIndex": 0,
                    "endIndex": 1,
                },
                "properties": {"pixelSize": 64},
                "fields": "pixelSize",
            }
        },
        {
            "repeatCell": {
                "range": {
                    "sheetId": sheet_id,
                    "startRowIndex": 0,
                    "endRowIndex": 1,
                },
                "cell": {
                    "userEnteredFormat": {
                        "backgroundColor": {"red": 0.15, "green": 0.2, "blue": 0.28},
                        "textFormat": {"bold": True, "foregroundColor": {"red": 1, "green": 1, "blue": 1}},
                    }
                },
                "fields": "userEnteredFormat(backgroundColor,textFormat)",
            }
        },
        {
            "autoResizeDimensions": {
                "dimensions": {
                    "sheetId": sheet_id,
                    "dimension": "COLUMNS",
                    "startIndex": 1,
                    "endIndex": 15,
                }
            }
        },
    ]
    svc.spreadsheets().batchUpdate(spreadsheetId=sid, body={"requests": requests}).execute()
    print(f"formatted '{tab}' ({len(values)-1} rows)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--upload", action="store_true")
    ap.add_argument("--spreadsheet", default="")
    args = ap.parse_args()

    rows = build_rows()
    write_csv(rows)

    if args.upload:
        url = args.spreadsheet.strip()
        if not url and SHEET_URL_FILE.is_file():
            url = SHEET_URL_FILE.read_text(encoding="utf-8").strip()
        if not url:
            sys.exit("No spreadsheet URL. Pass --spreadsheet or save ContentTracker/spreadsheet_url.txt")
        print(f"uploading to {url}")
        upload(rows, url)


if __name__ == "__main__":
    main()
