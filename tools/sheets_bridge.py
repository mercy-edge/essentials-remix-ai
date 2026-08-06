#!/usr/bin/env python3
"""
Google Sheets bridge for chat-driven updates.

Usage:
  python tools/sheets_bridge.py info --spreadsheet <ID_OR_URL>
  python tools/sheets_bridge.py read --spreadsheet <ID_OR_URL> --range "Maps!A1:Z20"
  python tools/sheets_bridge.py write --spreadsheet <ID_OR_URL> --range "Maps!A1" --values-json "[[\"a\",\"b\"]]"
  python tools/sheets_bridge.py append --spreadsheet <ID_OR_URL> --range "Maps!A:Z" --values-json "[[\"row\"]]"
  python tools/sheets_bridge.py ensure-tabs --spreadsheet <ID_OR_URL> --tabs Maps,Encounters,Quests
  python tools/sheets_bridge.py upload-csv --spreadsheet <ID_OR_URL> --tab Maps --csv ContentTracker/Maps.csv

Credentials: .secrets/*service-account*.json (or GOOGLE_APPLICATION_CREDENTIALS).
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SECRETS = ROOT / ".secrets"

SCOPES = [
    "https://www.googleapis.com/auth/spreadsheets",
    "https://www.googleapis.com/auth/drive",
]


def find_credentials() -> Path:
    env = Path(__import__("os").environ.get("GOOGLE_APPLICATION_CREDENTIALS", "") or "")
    if env.is_file():
        return env
    matches = sorted(SECRETS.glob("*.json"))
    if not matches:
        sys.exit(f"No credentials JSON in {SECRETS}. Put your service-account key there.")
    return matches[0]


def spreadsheet_id(value: str) -> str:
    m = re.search(r"/spreadsheets/d/([a-zA-Z0-9-_]+)", value)
    return m.group(1) if m else value.strip()


def apply_clock_skew_workaround():
    """Google rejects JWTs if the PC clock is more than a few minutes off.
    Measure skew against Google's Date header and shift google-auth's utcnow.
    """
    import datetime
    import urllib.request

    import google.auth._helpers as helpers

    if getattr(helpers, "_remix_skew_applied", False):
        return
    try:
        req = urllib.request.Request("https://www.google.com", method="HEAD")
        with urllib.request.urlopen(req, timeout=10) as resp:
            date_hdr = resp.headers.get("Date")
        if not date_hdr:
            return
        google_utc = datetime.datetime.strptime(date_hdr, "%a, %d %b %Y %H:%M:%S %Z")
        google_utc = google_utc.replace(tzinfo=datetime.timezone.utc)
        local_utc = datetime.datetime.now(datetime.timezone.utc)
        skew = local_utc - google_utc
        # Only compensate meaningful skew (>30s). Cap to 2 hours for safety.
        if abs(skew.total_seconds()) < 30 or abs(skew.total_seconds()) > 7200:
            return
        real_utcnow = helpers.utcnow

        def skewed_utcnow():
            return real_utcnow() - skew

        helpers.utcnow = skewed_utcnow
        helpers._remix_skew_applied = True
        print(f"note: compensated clock skew of {int(skew.total_seconds())}s vs Google", file=sys.stderr)
    except Exception as exc:
        print(f"note: clock skew check skipped ({exc})", file=sys.stderr)


def get_sheets_service():
    from google.oauth2 import service_account
    from googleapiclient.discovery import build

    apply_clock_skew_workaround()
    creds_path = find_credentials()
    creds = service_account.Credentials.from_service_account_file(str(creds_path), scopes=SCOPES)
    return build("sheets", "v4", credentials=creds, cache_discovery=False), creds_path, creds.service_account_email


def cmd_info(args):
    svc, creds_path, email = get_sheets_service()
    sid = spreadsheet_id(args.spreadsheet)
    meta = svc.spreadsheets().get(spreadsheetId=sid).execute()
    print(f"credentials: {creds_path}")
    print(f"service_account: {email}")
    print(f"title: {meta.get('properties', {}).get('title')}")
    print(f"spreadsheet_id: {sid}")
    print("tabs:")
    for sh in meta.get("sheets", []):
        props = sh.get("properties", {})
        print(f"  - {props.get('title')} (id={props.get('sheetId')})")


def cmd_read(args):
    svc, _, _ = get_sheets_service()
    sid = spreadsheet_id(args.spreadsheet)
    result = (
        svc.spreadsheets()
        .values()
        .get(spreadsheetId=sid, range=args.range)
        .execute()
    )
    print(json.dumps(result.get("values", []), ensure_ascii=False, indent=2))


def parse_values(args) -> list:
    if args.values_json:
        return json.loads(args.values_json)
    if args.values_file:
        return json.loads(Path(args.values_file).read_text(encoding="utf-8"))
    sys.exit("Provide --values-json or --values-file")


def cmd_write(args):
    svc, _, _ = get_sheets_service()
    sid = spreadsheet_id(args.spreadsheet)
    values = parse_values(args)
    result = (
        svc.spreadsheets()
        .values()
        .update(
            spreadsheetId=sid,
            range=args.range,
            valueInputOption="USER_ENTERED",
            body={"values": values},
        )
        .execute()
    )
    print(json.dumps({"updated": result.get("updatedCells"), "range": result.get("updatedRange")}))


def cmd_append(args):
    svc, _, _ = get_sheets_service()
    sid = spreadsheet_id(args.spreadsheet)
    values = parse_values(args)
    result = (
        svc.spreadsheets()
        .values()
        .append(
            spreadsheetId=sid,
            range=args.range,
            valueInputOption="USER_ENTERED",
            insertDataOption="INSERT_ROWS",
            body={"values": values},
        )
        .execute()
    )
    updates = result.get("updates", {})
    print(json.dumps({"updated": updates.get("updatedCells"), "range": updates.get("updatedRange")}))


def cmd_ensure_tabs(args):
    svc, _, _ = get_sheets_service()
    sid = spreadsheet_id(args.spreadsheet)
    meta = svc.spreadsheets().get(spreadsheetId=sid).execute()
    existing = {sh["properties"]["title"] for sh in meta.get("sheets", [])}
    wanted = [t.strip() for t in args.tabs.split(",") if t.strip()]
    requests = []
    for title in wanted:
        if title not in existing:
            requests.append({"addSheet": {"properties": {"title": title}}})
    if not requests:
        print(json.dumps({"created": [], "existing": sorted(existing)}))
        return
    svc.spreadsheets().batchUpdate(spreadsheetId=sid, body={"requests": requests}).execute()
    print(json.dumps({"created": [t for t in wanted if t not in existing]}))


def cmd_upload_csv(args):
    svc, _, _ = get_sheets_service()
    sid = spreadsheet_id(args.spreadsheet)
    path = Path(args.csv)
    if not path.is_file():
        path = ROOT / args.csv
    rows = []
    with path.open(encoding="utf-8-sig", newline="") as f:
        rows = list(csv.reader(f))
    # Ensure tab exists
    meta = svc.spreadsheets().get(spreadsheetId=sid).execute()
    existing = {sh["properties"]["title"] for sh in meta.get("sheets", [])}
    if args.tab not in existing:
        svc.spreadsheets().batchUpdate(
            spreadsheetId=sid,
            body={"requests": [{"addSheet": {"properties": {"title": args.tab}}}]},
        ).execute()
    # Clear then write
    svc.spreadsheets().values().clear(spreadsheetId=sid, range=f"'{args.tab}'").execute()
    result = (
        svc.spreadsheets()
        .values()
        .update(
            spreadsheetId=sid,
            range=f"'{args.tab}'!A1",
            valueInputOption="USER_ENTERED",
            body={"values": rows},
        )
        .execute()
    )
    print(json.dumps({"tab": args.tab, "rows": len(rows), "updated": result.get("updatedCells")}))


def main():
    p = argparse.ArgumentParser(description="Google Sheets bridge")
    sub = p.add_subparsers(dest="cmd", required=True)

    def add_sheet_arg(sp):
        sp.add_argument("--spreadsheet", required=True, help="Sheet URL or ID")

    sp = sub.add_parser("info")
    add_sheet_arg(sp)
    sp.set_defaults(func=cmd_info)

    sp = sub.add_parser("read")
    add_sheet_arg(sp)
    sp.add_argument("--range", required=True)
    sp.set_defaults(func=cmd_read)

    sp = sub.add_parser("write")
    add_sheet_arg(sp)
    sp.add_argument("--range", required=True)
    sp.add_argument("--values-json")
    sp.add_argument("--values-file")
    sp.set_defaults(func=cmd_write)

    sp = sub.add_parser("append")
    add_sheet_arg(sp)
    sp.add_argument("--range", required=True)
    sp.add_argument("--values-json")
    sp.add_argument("--values-file")
    sp.set_defaults(func=cmd_append)

    sp = sub.add_parser("ensure-tabs")
    add_sheet_arg(sp)
    sp.add_argument("--tabs", required=True, help="Comma-separated tab names")
    sp.set_defaults(func=cmd_ensure_tabs)

    sp = sub.add_parser("upload-csv")
    add_sheet_arg(sp)
    sp.add_argument("--tab", required=True)
    sp.add_argument("--csv", required=True)
    sp.set_defaults(func=cmd_upload_csv)

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
