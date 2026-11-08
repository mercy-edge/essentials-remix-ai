#!/usr/bin/env python3
"""Back-compat entry point — generates the full project docs workbook.

Available Pokémon remains the canonical sprite / type / BST catalog inside
docs/sheets/Essentials_Remix_AI_Project.xlsx (also copied to
Essentials_Remix_AI_Pokemon.xlsx). Encounters and trainers reference that sheet.
"""

from generate_project_docs import main

if __name__ == "__main__":
    main()
