# Essentials Remix — Showdown-style Pokédex website

A local [Pokemon Showdown Dex](https://dex.pokemonshowdown.com/) UI wired to **your** PBS data: species, moves, abilities, learnsets, and wild encounter locations.

## What's included

| Folder | Source | Purpose |
|--------|--------|---------|
| `showdown-dex/` | [Zarel/Pokemon-Showdown-Dex](https://github.com/Zarel/Pokemon-Showdown-Dex) | Dex UI (panels, search, styling) |
| `ps-client/` | [smogon/pokemon-showdown-client](https://github.com/smogon/pokemon-showdown-client) | Reference / optional full client build |
| `showdown-dex/data/` | Generated from `PBS/` | Your game's dex data (JS bundles) |

The dex loads **your data locally** and pulls only the Showdown engine UI (`battledata.js`, search helpers, sprites) from `play.pokemonshowdown.com`.

## Quick start

1. **Export game data** (run after any PBS edit):

   ```bash
   python tools/export_showdown_dex.py
   ```

2. **Preview locally** — from the project root:

   ```bash
   python -m http.server 8080 --directory website/showdown-dex
   ```

   Open [http://localhost:8080/index.html](http://localhost:8080/index.html)

3. **Regenerate when PBS changes** — same command as step 1. Also re-run your existing sheet tools if you use them:

   ```bash
   python tools/export_elwynn_encounters.py --upload
   python tools/import_elwynn_encounters.py --apply
   python tools/export_showdown_dex.py
   ```

## What gets exported

From `PBS/`:

- `pokemon.txt` + Gen 9 pack + forms → `data/pokedex.js`
- `moves.txt` → `data/moves.js`
- `abilities.txt` → `data/abilities.js`
- Level-up / tutor / egg moves → `data/learnsets.js`
- `encounters.txt` + `map_metadata.txt` → `data/encounters.js` (shown on each Pokémon page)

Search indexes and tier tables are generated automatically for the dex UI.

## Hosting (GitHub Pages, Netlify, etc.)

Upload the contents of `website/showdown-dex/` as a static site:

- `index.html` is the entry point
- `data/` must be present (run the exporter before deploy)
- Sprites load from Showdown's CDN (`play.pokemonshowdown.com/sprites/gen5/…`)

**GitHub Pages example:**

```bash
python tools/export_showdown_dex.py
# Copy or symlink showdown-dex/ into your pages branch, then push
```

## Cloning the upstream repos (already done once)

If you need a fresh clone:

```bash
cd website
git clone --depth 1 https://github.com/Zarel/Pokemon-Showdown-Dex.git showdown-dex
git clone --depth 1 https://github.com/smogon/pokemon-showdown-client.git ps-client
```

Then apply this project's custom files (`index.html`, `config/config.js`, patched `js/pokedex-pokemon.js`, and `tools/export_showdown_dex.py` output).

## Customizations in this project

- **`tools/export_showdown_dex.py`** — PBS → Showdown JS exporter
- **`showdown-dex/index.html`** — local data paths + Essentials branding
- **`showdown-dex/js/pokedex-pokemon.js`** — adds a **Wild encounters** table per species
- **`showdown-dex/config/config.js`** — test client config

## Notes

- Item dex entries are empty (`data/items.js` stub); focus is Pokémon, moves, and encounters.
- Type chart is a simplified Gen 9 chart for type pages; battle logic still uses Showdown defaults where needed.
- Tier badges show **OU** for all species (romhack; not competitive tiers).
- For Google Sheets encounter editing, keep using `tools/export_elwynn_encounters.py` / `import_elwynn_encounters.py`, then re-export the dex.
