#!/usr/bin/env python3
"""
Generate a Run & Bun-style available Pokémon documentation sheet.

Outputs:
  docs/sheets/Essentials_Remix_AI_Pokemon.xlsx  — spreadsheet (sprites, types, BST)
  docs/sheets/Available_Pokemon.html            — offline HTML view with sprites

Usage:
  python3 tools/generate_pokemon_docs.py
  python3 tools/generate_pokemon_docs.py --no-images   # faster xlsx, no embedded sprites
"""

from __future__ import annotations

import argparse
import base64
import io
import re
from dataclasses import dataclass
from datetime import date
from pathlib import Path

from openpyxl import Workbook
from openpyxl.drawing.image import Image as XLImage
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter
from PIL import Image as PILImage

ROOT = Path(__file__).resolve().parents[1]
PBS = ROOT / "PBS"
GRAPHICS = ROOT / "Graphics" / "Pokemon"
OUT_DIR = ROOT / "docs" / "sheets"
OUT_XLSX = OUT_DIR / "Essentials_Remix_AI_Pokemon.xlsx"
OUT_HTML = OUT_DIR / "Available_Pokemon.html"

TYPE_COLORS = {
    "NORMAL": "A8A878",
    "FIRE": "F08030",
    "WATER": "6890F0",
    "ELECTRIC": "F8D030",
    "GRASS": "78C850",
    "ICE": "98D8D8",
    "FIGHTING": "C03028",
    "POISON": "A040A0",
    "GROUND": "E0C068",
    "FLYING": "A890F0",
    "PSYCHIC": "F85888",
    "BUG": "A8B820",
    "ROCK": "B8A038",
    "GHOST": "705898",
    "DRAGON": "7038F8",
    "DARK": "705848",
    "STEEL": "B8B8D0",
    "FAIRY": "EE99AC",
}

FONT_TITLE = Font(name="Arial", size=18, bold=True, color="FFFFFF")
FONT_SECTION = Font(name="Arial", size=11, bold=True, color="FFFFFF")
FONT_HEADER = Font(name="Arial", size=10, bold=True, color="FFFFFF")
FONT_BODY = Font(name="Arial", size=10)
FONT_NOTE = Font(name="Arial", size=9, italic=True, color="6B7280")

FILL_TITLE = PatternFill("solid", fgColor="1E3A5F")
FILL_SECTION = PatternFill("solid", fgColor="2563EB")
FILL_HEADER = PatternFill("solid", fgColor="374151")
FILL_ALT = PatternFill("solid", fgColor="F3F4F6")
FILL_WHITE = PatternFill("solid", fgColor="FFFFFF")

THIN = Side(style="thin", color="D1D5DB")
BORDER_ALL = Border(left=THIN, right=THIN, top=THIN, bottom=THIN)
CENTER = Alignment(horizontal="center", vertical="center", wrap_text=True)
LEFT = Alignment(horizontal="left", vertical="center", wrap_text=True)

STAT_KEYS = ("HP", "Atk", "Def", "SpA", "SpD", "Spe")
ICON_SIZE = 40  # px in spreadsheet / HTML thumb


@dataclass
class SpeciesRow:
    dex: int
    species_id: str
    form: int
    name: str
    form_name: str
    types: list[str]
    stats: list[int]
    bst: int
    generation: str
    flags: str
    abilities: str
    hidden_ability: str
    sprite_key: str  # file stem under Graphics/Pokemon


def parse_pbs_sections(path: Path) -> list[tuple[str, dict[str, str]]]:
    """Parse Essentials PBS into (section_id, fields) list."""
    if not path.is_file():
        return []
    sections: list[tuple[str, dict[str, str]]] = []
    current_id: str | None = None
    current: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        m = re.match(r"^\[(.+)\]$", line)
        if m:
            if current_id is not None:
                sections.append((current_id, current))
            current_id = m.group(1).strip()
            current = {}
            continue
        if current_id is None or "=" not in line:
            continue
        key, val = [p.strip() for p in line.split("=", 1)]
        current[key] = val
    if current_id is not None:
        sections.append((current_id, current))
    return sections


def parse_stats(raw: str | None) -> list[int] | None:
    if not raw:
        return None
    parts = [p.strip() for p in raw.split(",")]
    if len(parts) != 6:
        return None
    try:
        return [int(p) for p in parts]
    except ValueError:
        return None


def parse_types(raw: str | None) -> list[str]:
    if not raw:
        return []
    return [t.strip().upper() for t in raw.split(",") if t.strip()]


def sprite_stem(species_id: str, form: int) -> str:
    return species_id if form == 0 else f"{species_id}_{form}"


def resolve_sprite_path(stem: str, kind: str = "Icons") -> Path | None:
    folder = GRAPHICS / kind
    candidates = [
        folder / f"{stem}.png",
        folder / f"{stem.split('_')[0]}.png",
    ]
    for c in candidates:
        if c.is_file():
            return c
    return None


def load_base_species() -> list[SpeciesRow]:
    rows: list[SpeciesRow] = []
    dex = 0
    for path in (PBS / "pokemon.txt", PBS / "pokemon_base_Gen_9_Pack.txt"):
        for sid, fields in parse_pbs_sections(path):
            # Skip form-style IDs if any sneak into base files
            if "," in sid:
                continue
            stats = parse_stats(fields.get("BaseStats"))
            if not stats:
                continue
            dex += 1
            types = parse_types(fields.get("Types"))
            name = fields.get("Name") or sid.title()
            rows.append(
                SpeciesRow(
                    dex=dex,
                    species_id=sid,
                    form=0,
                    name=name,
                    form_name="",
                    types=types,
                    stats=stats,
                    bst=sum(stats),
                    generation=fields.get("Generation", ""),
                    flags=fields.get("Flags", ""),
                    abilities=fields.get("Abilities", "").replace(",", " / "),
                    hidden_ability=fields.get("HiddenAbilities", ""),
                    sprite_key=sid,
                )
            )
    return rows


def load_forms(base_by_id: dict[str, SpeciesRow]) -> list[SpeciesRow]:
    """Merge form overrides onto base species; keep forms with distinct identity."""
    forms: list[SpeciesRow] = []
    for path in (PBS / "pokemon_forms.txt", PBS / "pokemon_forms_Gen_9_Pack.txt"):
        for section_id, fields in parse_pbs_sections(path):
            m = re.match(r"^([A-Z0-9_]+),(\d+)$", section_id)
            if not m:
                continue
            sid, form_n = m.group(1), int(m.group(2))
            base = base_by_id.get(sid)
            if not base:
                continue
            form_name = fields.get("FormName") or f"Form {form_n}"
            stats = parse_stats(fields.get("BaseStats")) or list(base.stats)
            types = parse_types(fields.get("Types")) or list(base.types)
            # Skip cosmetic-only forms that don't change combat identity
            # (same types + same stats + no FormName mega/regional cue still listed if FormName set)
            abilities = fields.get("Abilities", base.abilities.replace(" / ", ","))
            hidden = fields.get("HiddenAbilities", base.hidden_ability)
            forms.append(
                SpeciesRow(
                    dex=base.dex,
                    species_id=sid,
                    form=form_n,
                    name=base.name,
                    form_name=form_name,
                    types=types,
                    stats=stats,
                    bst=sum(stats),
                    generation=fields.get("Generation", base.generation),
                    flags=fields.get("Flags", base.flags),
                    abilities=abilities.replace(",", " / "),
                    hidden_ability=hidden,
                    sprite_key=sprite_stem(sid, form_n),
                )
            )
    return forms


def display_name(row: SpeciesRow) -> str:
    if row.form_name:
        return f"{row.name} ({row.form_name})"
    return row.name


def type_fill(type_id: str) -> PatternFill:
    return PatternFill("solid", fgColor=TYPE_COLORS.get(type_id.upper(), "9CA3AF"))


def icon_png_bytes(stem: str, size: int = ICON_SIZE) -> bytes | None:
    path = resolve_sprite_path(stem, "Icons") or resolve_sprite_path(stem, "Front")
    if not path:
        return None
    im = PILImage.open(path).convert("RGBA")
    # Essentials icons are typically 2-frame horizontal sheets (e.g. 128x64)
    if path.parent.name == "Icons" and im.width >= im.height * 2:
        im = im.crop((0, 0, im.height, im.height))
    im = im.resize((size, size), PILImage.Resampling.NEAREST)
    buf = io.BytesIO()
    im.save(buf, format="PNG")
    return buf.getvalue()


def pokeapi_sprite_url(dex: int, form: int, form_name: str) -> str:
    """Best-effort public sprite URL for Google Sheets IMAGE()."""
    base = f"https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/{dex}.png"
    if form == 0:
        return base
    slug = form_name.lower()
    # Common regional / mega patterns → leave base dex sprite as fallback
    return base


def write_index_sheet(wb: Workbook, base_count: int, form_count: int, total: int):
    ws = wb.active
    ws.title = "Index"
    ws.sheet_view.showGridLines = False
    ws.merge_cells("A1:F1")
    ws["A1"] = "Essentials Remix AI — Available Pokémon"
    ws["A1"].font = FONT_TITLE
    ws["A1"].fill = FILL_TITLE
    ws["A1"].alignment = LEFT
    ws.row_dimensions[1].height = 32

    lines = [
        ("Generated", str(date.today())),
        ("Base species", str(base_count)),
        ("Alternate forms", str(form_count)),
        ("Total rows", str(total)),
        ("", ""),
        ("How to use", ""),
        (
            "Google Sheets",
            "Upload Essentials_Remix_AI_Pokemon.xlsx via File → Import, "
            "or run: python3 tools/sync_pokemon_google_sheets.py",
        ),
        (
            "Offline HTML",
            "Open Available_Pokemon.html in a browser (sprites + filter box).",
        ),
        (
            "Columns",
            "Sprite, Dex #, Name, Types, HP/Atk/Def/SpA/SpD/Spe, BST",
        ),
        (
            "Note",
            "Lists every species/form defined in PBS (pokemon.txt + Gen 9 pack + forms). "
            "BST = sum of the six base stats.",
        ),
    ]
    r = 3
    for label, value in lines:
        ws.cell(r, 1, label).font = Font(name="Arial", size=10, bold=True)
        ws.cell(r, 2, value).font = FONT_BODY
        ws.merge_cells(start_row=r, start_column=2, end_row=r, end_column=6)
        ws.cell(r, 2).alignment = LEFT
        r += 1
    ws.column_dimensions["A"].width = 16
    for col in range(2, 7):
        ws.column_dimensions[get_column_letter(col)].width = 18


def write_pokemon_sheet(wb: Workbook, rows: list[SpeciesRow], embed_images: bool):
    ws = wb.create_sheet("Available Pokémon", 1)
    headers = [
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
    widths = [8, 6, 18, 22, 10, 10, 6, 6, 6, 6, 6, 6, 7, 10, 28, 16, 14, 16]

    for col, (h, w) in enumerate(zip(headers, widths), 1):
        cell = ws.cell(1, col, h)
        cell.font = FONT_HEADER
        cell.fill = FILL_HEADER
        cell.alignment = CENTER
        cell.border = BORDER_ALL
        ws.column_dimensions[get_column_letter(col)].width = w

    ws.freeze_panes = "C2"
    ws.auto_filter.ref = f"A1:R{len(rows) + 1}"

    for i, row in enumerate(rows):
        r = i + 2
        alt = i % 2 == 1
        fill = FILL_ALT if alt else FILL_WHITE
        values = [
            "",  # sprite placeholder
            row.dex,
            row.name,
            row.form_name,
            row.types[0].title() if len(row.types) > 0 else "",
            row.types[1].title() if len(row.types) > 1 else "",
            *row.stats,
            row.bst,
            row.generation,
            row.abilities,
            row.hidden_ability.replace(",", " / ") if row.hidden_ability else "",
            row.flags,
            row.species_id if row.form == 0 else f"{row.species_id},{row.form}",
        ]
        ws.row_dimensions[r].height = 32 if embed_images else 18
        for col, val in enumerate(values, 1):
            cell = ws.cell(r, col, val)
            cell.font = FONT_BODY
            cell.fill = fill
            cell.border = BORDER_ALL
            cell.alignment = CENTER if col != 3 and col != 4 and col < 15 else LEFT

        # Color type cells
        for tcol, tidx in ((5, 0), (6, 1)):
            if tidx < len(row.types):
                c = ws.cell(r, tcol)
                c.fill = type_fill(row.types[tidx])
                c.font = Font(name="Arial", size=9, bold=True, color="FFFFFF")

        # Emphasize BST
        bst_cell = ws.cell(r, 13)
        bst_cell.font = Font(name="Arial", size=10, bold=True)

        if embed_images:
            png = icon_png_bytes(row.sprite_key, ICON_SIZE)
            if png:
                img = XLImage(io.BytesIO(png))
                img.width = ICON_SIZE
                img.height = ICON_SIZE
                # Anchor roughly in column A
                img.anchor = f"A{r}"
                ws.add_image(img)


def write_by_type_sheet(wb: Workbook, rows: list[SpeciesRow]):
    ws = wb.create_sheet("By Type")
    headers = ["Type", "Count", "Avg BST", "Examples (highest BST)"]
    for col, h in enumerate(headers, 1):
        cell = ws.cell(1, col, h)
        cell.font = FONT_HEADER
        cell.fill = FILL_HEADER
        cell.alignment = CENTER
        cell.border = BORDER_ALL
    ws.column_dimensions["A"].width = 12
    ws.column_dimensions["B"].width = 10
    ws.column_dimensions["C"].width = 10
    ws.column_dimensions["D"].width = 60

    buckets: dict[str, list[SpeciesRow]] = {t: [] for t in TYPE_COLORS}
    for row in rows:
        for t in row.types:
            buckets.setdefault(t, []).append(row)

    r = 2
    for t in TYPE_COLORS:
        group = buckets.get(t, [])
        if not group:
            continue
        avg = sum(x.bst for x in group) / len(group)
        top = sorted(group, key=lambda x: (-x.bst, x.name))[:8]
        examples = ", ".join(f"{display_name(x)} ({x.bst})" for x in top)
        vals = [t.title(), len(group), round(avg, 1), examples]
        for col, val in enumerate(vals, 1):
            cell = ws.cell(r, col, val)
            cell.border = BORDER_ALL
            cell.font = FONT_BODY
            if col == 1:
                cell.fill = type_fill(t)
                cell.font = Font(name="Arial", size=10, bold=True, color="FFFFFF")
                cell.alignment = CENTER
        r += 1


def write_bst_tiers_sheet(wb: Workbook, rows: list[SpeciesRow]):
    ws = wb.create_sheet("BST Tiers")
    tiers = [
        ("NU / weak", 0, 399),
        ("RU / mid", 400, 479),
        ("UU / strong", 480, 529),
        ("OU / very strong", 530, 569),
        ("Uber / legendary tier", 570, 9999),
    ]
    headers = ["Tier", "BST range", "Count", "Examples"]
    for col, h in enumerate(headers, 1):
        cell = ws.cell(1, col, h)
        cell.font = FONT_HEADER
        cell.fill = FILL_HEADER
        cell.border = BORDER_ALL
    ws.column_dimensions["A"].width = 22
    ws.column_dimensions["B"].width = 12
    ws.column_dimensions["C"].width = 10
    ws.column_dimensions["D"].width = 70

    for i, (label, lo, hi) in enumerate(tiers):
        group = [x for x in rows if lo <= x.bst <= hi]
        examples = ", ".join(
            display_name(x)
            for x in sorted(group, key=lambda x: (-x.bst, x.name))[:12]
        )
        r = i + 2
        for col, val in enumerate(
            [label, f"{lo}–{hi if hi < 9999 else '∞'}", len(group), examples], 1
        ):
            cell = ws.cell(r, col, val)
            cell.border = BORDER_ALL
            cell.font = FONT_BODY


def generate_html(rows: list[SpeciesRow]) -> str:
    cards = []
    for row in rows:
        png = icon_png_bytes(row.sprite_key, 64)
        if png:
            src = f"data:image/png;base64,{base64.b64encode(png).decode('ascii')}"
            img = f'<img class="sprite" src="{src}" alt="{row.name}" width="64" height="64">'
        else:
            img = '<div class="sprite missing">?</div>'
        t1 = row.types[0] if row.types else ""
        t2 = row.types[1] if len(row.types) > 1 else ""
        type_html = ""
        for t in row.types:
            color = TYPE_COLORS.get(t, "9CA3AF")
            type_html += f'<span class="type" style="background:#{color}">{t.title()}</span>'
        search = " ".join(
            [
                row.name,
                row.form_name,
                t1,
                t2,
                row.species_id,
                row.flags,
                str(row.bst),
            ]
        ).lower()
        cards.append(
            f"""<tr data-search="{_html_escape(search)}">
  <td class="c">{img}</td>
  <td class="c">{row.dex}</td>
  <td><div class="name">{_html_escape(row.name)}</div>
      <div class="form">{_html_escape(row.form_name)}</div></td>
  <td>{type_html}</td>
  <td class="c">{row.stats[0]}</td>
  <td class="c">{row.stats[1]}</td>
  <td class="c">{row.stats[2]}</td>
  <td class="c">{row.stats[3]}</td>
  <td class="c">{row.stats[4]}</td>
  <td class="c">{row.stats[5]}</td>
  <td class="c bst">{row.bst}</td>
</tr>"""
        )

    body = "\n".join(cards)
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Essentials Remix AI — Available Pokémon</title>
<style>
  :root {{
    --bg: #0f172a;
    --panel: #1e293b;
    --text: #e2e8f0;
    --muted: #94a3b8;
    --line: #334155;
    --accent: #38bdf8;
  }}
  * {{ box-sizing: border-box; }}
  body {{
    margin: 0; font-family: "Segoe UI", Tahoma, sans-serif;
    background: linear-gradient(180deg, #0b1224 0%, #111827 40%, #0f172a 100%);
    color: var(--text); min-height: 100vh;
  }}
  header {{
    padding: 28px 24px 16px; border-bottom: 1px solid var(--line);
    background: rgba(15,23,42,.9); position: sticky; top: 0; z-index: 5;
    backdrop-filter: blur(8px);
  }}
  h1 {{ margin: 0 0 6px; font-size: 1.6rem; letter-spacing: .02em; }}
  .sub {{ color: var(--muted); font-size: .95rem; margin-bottom: 14px; }}
  .controls {{ display: flex; flex-wrap: wrap; gap: 10px; align-items: center; }}
  input[type="search"] {{
    flex: 1; min-width: 220px; padding: 10px 12px; border-radius: 8px;
    border: 1px solid var(--line); background: var(--panel); color: var(--text);
  }}
  .count {{ color: var(--muted); font-size: .9rem; }}
  main {{ padding: 16px 24px 48px; overflow-x: auto; }}
  table {{ width: 100%; border-collapse: collapse; min-width: 860px; }}
  th {{
    position: sticky; top: 118px; background: #1e293b; text-align: left;
    padding: 10px 8px; border-bottom: 2px solid var(--accent); font-size: .85rem;
  }}
  td {{ padding: 8px; border-bottom: 1px solid var(--line); vertical-align: middle; }}
  tr:hover td {{ background: rgba(56,189,248,.08); }}
  .c {{ text-align: center; }}
  .name {{ font-weight: 700; }}
  .form {{ color: var(--muted); font-size: .8rem; }}
  .bst {{ font-weight: 800; color: #fbbf24; }}
  .type {{
    display: inline-block; min-width: 64px; text-align: center; margin: 0 3px 3px 0;
    padding: 3px 8px; border-radius: 4px; font-size: .75rem; font-weight: 700;
    color: #fff; text-shadow: 0 1px 1px rgba(0,0,0,.35);
  }}
  .sprite {{ image-rendering: pixelated; background: #0b1224; border-radius: 8px; }}
  .sprite.missing {{
    width: 64px; height: 64px; display: grid; place-items: center;
    background: #334155; border-radius: 8px; color: var(--muted);
  }}
  footer {{ padding: 12px 24px 28px; color: var(--muted); font-size: .85rem; }}
</style>
</head>
<body>
<header>
  <h1>Essentials Remix AI — Available Pokémon</h1>
  <div class="sub">Name · Sprite · Types · Base stat total (BST) · generated {date.today()}</div>
  <div class="controls">
    <input id="q" type="search" placeholder="Filter by name, type, BST, flags…">
    <span class="count"><span id="shown">{len(rows)}</span> / {len(rows)} shown</span>
  </div>
</header>
<main>
<table>
  <thead>
    <tr>
      <th>Sprite</th><th>#</th><th>Name</th><th>Types</th>
      <th>HP</th><th>Atk</th><th>Def</th><th>SpA</th><th>SpD</th><th>Spe</th><th>BST</th>
    </tr>
  </thead>
  <tbody id="rows">
{body}
  </tbody>
</table>
</main>
<footer>
  Source: PBS/pokemon.txt, PBS/pokemon_base_Gen_9_Pack.txt, and form PBS files.
  Upload this HTML to Google Drive, or import the .xlsx into Google Sheets.
</footer>
<script>
const q = document.getElementById('q');
const shown = document.getElementById('shown');
const rows = [...document.querySelectorAll('#rows tr')];
q.addEventListener('input', () => {{
  const term = q.value.trim().toLowerCase();
  let n = 0;
  for (const tr of rows) {{
    const ok = !term || tr.dataset.search.includes(term);
    tr.hidden = !ok;
    if (ok) n++;
  }}
  shown.textContent = n;
}});
</script>
</body>
</html>
"""


def _html_escape(s: str) -> str:
    return (
        s.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def collect_rows() -> tuple[list[SpeciesRow], list[SpeciesRow], list[SpeciesRow]]:
    base = load_base_species()
    by_id = {r.species_id: r for r in base}
    forms = load_forms(by_id)
    # Base first (dex order), then forms after their base (stable)
    all_rows: list[SpeciesRow] = []
    forms_by_base: dict[str, list[SpeciesRow]] = {}
    for f in forms:
        forms_by_base.setdefault(f.species_id, []).append(f)
    for b in base:
        all_rows.append(b)
        for f in sorted(forms_by_base.get(b.species_id, []), key=lambda x: x.form):
            all_rows.append(f)
    return base, forms, all_rows


def build_workbook(rows: list[SpeciesRow], base_count: int, form_count: int, embed_images: bool) -> Workbook:
    wb = Workbook()
    write_index_sheet(wb, base_count, form_count, len(rows))
    write_pokemon_sheet(wb, rows, embed_images=embed_images)
    write_by_type_sheet(wb, rows)
    write_bst_tiers_sheet(wb, rows)
    return wb


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--no-images", action="store_true", help="Skip embedding sprites in xlsx")
    ap.add_argument("--xlsx-only", action="store_true")
    ap.add_argument("--html-only", action="store_true")
    args = ap.parse_args()

    base, forms, rows = collect_rows()
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    if not args.html_only:
        print(f"Building workbook ({len(rows)} rows, images={not args.no_images})…")
        wb = build_workbook(rows, len(base), len(forms), embed_images=not args.no_images)
        wb.save(OUT_XLSX)
        print(f"Wrote {OUT_XLSX.relative_to(ROOT)}")

    if not args.xlsx_only:
        print(f"Building HTML ({len(rows)} rows)…")
        OUT_HTML.write_text(generate_html(rows), encoding="utf-8")
        print(f"Wrote {OUT_HTML.relative_to(ROOT)}")

    print(f"Done — {len(base)} base + {len(forms)} forms = {len(rows)} total")


if __name__ == "__main__":
    main()
