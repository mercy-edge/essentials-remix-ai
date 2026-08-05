# Documentation sheets

Run & Bun-style reference docs generated from PBS data.

## Available Pokémon

| File | Use |
|------|-----|
| `Available_Pokemon.html` | Offline browser view with **local sprites**, types, full base stats, and **BST**. Filter box included. Upload to Google Drive if you want a shareable link. |
| `Essentials_Remix_AI_Pokemon.xlsx` | Spreadsheet for Google Sheets import (`File → Import → Upload`). Includes sprite thumbnails, types, stats, BST, By Type, and BST Tiers tabs. |
| `pokemon_google_sheet.json` | Stores the live Google Sheet ID/URL after sync. |

### Regenerate locally

```bash
pip install -r tools/requirements-docs.txt
python3 tools/generate_pokemon_docs.py
```

### Live Google Sheet sync

```bash
# One-time: enable Sheets + Drive APIs, download a service-account JSON key
# Save as docs/sheets/google-service-account.json (gitignored)
# Optional: export GOOGLE_SHEETS_SHARE_EMAIL=you@gmail.com

python3 tools/sync_pokemon_google_sheets.py
```

The live sheet uses PokéAPI sprite URLs via `IMAGE()` so sprites show in Google Sheets. The HTML/xlsx backups use the game's own `Graphics/Pokemon` sprites.
