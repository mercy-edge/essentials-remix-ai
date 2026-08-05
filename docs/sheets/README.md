# Project documentation sheets

Run & Bun-style **whole-project** reference docs generated from PBS data.

## Architecture

```
Available Pokémon  ← canonical sprite / type / BST catalog
        ↑
        │  Species ID lookup (xlsx icons / Sheets INDEX/MATCH)
        │
Wild Encounters · Trainer Battles · Trainer Party · Static Battles
```

Other tabs do **not** store their own sprite copies long-term — they reference
the Available Pokémon sheet by `Species ID`. That way one catalog drives the
entire project doc as encounters and trainers expand.

## Outputs

| File | Use |
|------|-----|
| `Essentials_Remix_AI_Project.xlsx` | Full project workbook |
| `Essentials_Remix_AI_Pokemon.xlsx` | Alias of the same workbook (compat) |
| `Available_Pokemon.html` | Offline filterable catalog with local sprites |
| `project_google_sheet.json` | Live Google Sheet ID/URL after sync |

### Tabs

1. **Index** — hub overview  
2. **Available Pokémon** — sprite, name, types, base stats, **BST**, Species ID  
3. **By Type** / **BST Tiers** — catalog rollups  
4. **Wild Encounters** — location tables with catalog sprite / type / BST  
5. **Encounter Summary** — per-area checklist  
6. **Trainer Battles** — lead sprite + party lines (types/BST from catalog)  
7. **Trainer Party** — one row per party member (sprite via catalog)  
8. **Static Battles** — scripted wild fights  

## Regenerate

```bash
pip install -r tools/requirements-docs.txt
python3 tools/generate_project_docs.py
# aliases still work:
python3 tools/generate_pokemon_docs.py
```

## Live Google Sheet

```bash
# docs/sheets/google-service-account.json  (gitignored)
# export GOOGLE_SHEETS_SHARE_EMAIL=you@gmail.com
python3 tools/sync_project_google_sheets.py
```

In the live sheet, encounter/trainer Sprite cells use:

```
=IFERROR(INDEX('Available Pokémon'!$A:$A, MATCH("<Species ID>",'Available Pokémon'!$R:$R,0)),"")
```

so they stay tied to the catalog as the project grows.
