#!/usr/bin/env python3
"""Validate Google Sheets credentials and print service account email for sharing."""
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

try:
    from sync_google_sheets import load_credentials, load_config, SCOPES
    creds = load_credentials()
    info = json.loads(creds.to_json())
    email = info.get("client_email", "(unknown)")
    project = info.get("project_id", "(unknown)")
    print("OK — credentials loaded")
    print(f"  Project:         {project}")
    print(f"  Service account: {email}")
    share = os.environ.get("GOOGLE_SHEETS_SHARE_EMAIL")
    if share:
        print(f"  Will share with: {share}")
    else:
        print("  WARNING: GOOGLE_SHEETS_SHARE_EMAIL not set (you may not see the sheet)")
    cfg = load_config()
    if cfg.get("spreadsheet_url"):
        print(f"  Existing sheet:  {cfg['spreadsheet_url']}")
    print("\nNext: python3 tools/sync_google_sheets.py --export")
except SystemExit as e:
    print(e)
    sys.exit(1)
