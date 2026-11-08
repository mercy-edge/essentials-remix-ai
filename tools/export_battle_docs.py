#!/usr/bin/env python3
"""Unified entry: local xlsx and/or live Google Sheets."""
import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    p = argparse.ArgumentParser(description="Battle documentation export")
    p.add_argument("--google", action="store_true", help="Sync to Google Sheets")
    p.add_argument("--export", action="store_true", help="With --google, also save .xlsx backup")
    p.add_argument("--xlsx-only", action="store_true", help="Only generate local .xlsx")
    args = p.parse_args()

    if args.google or (not args.xlsx_only):
        try:
            cmd = [sys.executable, str(ROOT / "tools/sync_google_sheets.py")]
            if args.export or not args.xlsx_only:
                cmd.append("--export")
            subprocess.check_call(cmd)
        except subprocess.CalledProcessError as e:
            if args.google:
                raise SystemExit(e.returncode)
            print("Google Sheets sync skipped (no credentials). Generating local xlsx only.")

    if args.xlsx_only or not args.google:
        subprocess.check_call([sys.executable, str(ROOT / "tools/generate_battle_docs.py")])


if __name__ == "__main__":
    main()
