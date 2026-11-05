#!/usr/bin/env python3
"""
Fetch a dated snapshot of Mapping Police Violence (MPV) data.

Saves the unmodified CSV export to data/raw/mpv/mpv_YYYY-MM-DD.csv (gitignored:
MPV is linked, not redistributed) and appends a row to the committed manifest
data/crosswalks/mpv_snapshots.csv, so published outputs trace to a specific
snapshot. scripts/04b_mpv.R reads the newest snapshot.

Source: https://mappingpoliceviolence.org (Campaign Zero). The live data is a
public Airtable shared view; download_mpv_csv() replays its "Download CSV"
button (ported from the jnix.netlify.app police shooting tracker). If the
undocumented endpoint breaks, download the CSV by hand from MPV_SHARE_URL and
run:  python tools/fetch_mpv/fetch_mpv.py --csv path/to/download.csv

Usage (from the project root):  python tools/fetch_mpv/fetch_mpv.py
"""

import argparse
import csv
import hashlib
import io
import json
import re
import sys
import urllib.parse
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd
import requests

MPV_SHARE_URL = 'https://airtable.com/appzVzSeINK1S3EVR/shroOenW19l1m3w0H/tblxearKzw8W7ViN8'
MPV_AIRTABLE_APP_ID = 'appzVzSeINK1S3EVR'
REQUEST_TIMEOUT = 120
# Airtable rejects the default python-requests User-Agent
REQUEST_HEADERS = {
    'User-Agent': ('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                   '(KHTML, like Gecko) Chrome/130.0 Safari/537.36'),
}
# Columns scripts/04b_mpv.R depends on; fail here, not mid-pipeline
REQUIRED_COLUMNS = ['date', 'state', 'agency_responsible', 'ori',
                    'use_of_force', 'off_duty_killing']

ROOT = Path(__file__).resolve().parents[2]
RAW_DIR = ROOT / 'data' / 'raw' / 'mpv'
MANIFEST = ROOT / 'data' / 'crosswalks' / 'mpv_snapshots.csv'


def download_mpv_csv(share_url=MPV_SHARE_URL):
    """Replay the shared view's "Download CSV" button: the share page embeds a
    signed accessPolicy (anonymous downloadCsv on this one view) inside its own
    data URL, which we pass to the view's downloadCsv endpoint. Raises loudly
    on any failure rather than saving a partial file."""
    session = requests.Session()
    session.headers.update(REQUEST_HEADERS)

    page = session.get(share_url, timeout=REQUEST_TIMEOUT)
    page.raise_for_status()
    match = re.search(r'urlWithParams: "([^"]+)"', page.text)
    if not match:
        raise ValueError("Couldn't find the data URL on the Airtable share page; "
                         f"download the CSV manually from {share_url} and use --csv.")
    # The URL is a JS string literal; json decodes its escapes without
    # mangling non-ASCII characters the way unicode_escape would
    data_url = json.loads('"' + match.group(1) + '"')
    view_match = re.search(r'/view/(viw\w+)/', data_url)
    query = dict(urllib.parse.parse_qsl(urllib.parse.urlparse(data_url).query))
    if not view_match or 'accessPolicy' not in query:
        raise ValueError(f"Unexpected Airtable data URL format: {data_url[:200]}")

    response = session.get(
        f"https://airtable.com/v0.3/view/{view_match.group(1)}/downloadCsv",
        params={
            'x-time-zone': 'UTC',
            'x-user-locale': 'en',
            'x-airtable-application-id': MPV_AIRTABLE_APP_ID,
            'accessPolicy': query['accessPolicy'],
            'requestId': query.get('requestId', ''),
        },
        timeout=REQUEST_TIMEOUT,
    )
    response.raise_for_status()
    if len(response.content) < 1_000_000:
        raise ValueError(f"Downloaded file is suspiciously small ({len(response.content)} bytes).")
    return response.content


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('--csv', help='Use a manually downloaded MPV CSV instead of fetching')
    args = parser.parse_args()

    content = Path(args.csv).read_bytes() if args.csv else download_mpv_csv()

    df = pd.read_csv(io.BytesIO(content), low_memory=False)
    missing = [c for c in REQUIRED_COLUMNS if c not in df.columns]
    if missing:
        sys.exit(f"MPV schema changed; missing columns: {missing}")
    dates = pd.to_datetime(df['date'], format='%m/%d/%Y', errors='coerce')
    if dates.isna().any():
        sys.exit(f"{dates.isna().sum()} MPV rows have unparseable dates")

    # UTC date, matching the x-time-zone the export is requested in
    today = datetime.now(timezone.utc).date()
    last_incident = dates.max().date()
    if last_incident > today:
        sys.exit(f"MPV has an incident dated in the future ({last_incident}); check the source.")

    header = ['snapshot_date', 'file', 'sha256', 'rows', 'last_incident_date', 'source']
    manifest_rows = []
    if MANIFEST.exists() and MANIFEST.stat().st_size > 0:
        with MANIFEST.open(newline='') as f:
            manifest_rows = list(csv.DictReader(f))
    if manifest_rows and len(df) < int(manifest_rows[-1]['rows']):
        print(f"Warning: {len(df):,} rows, fewer than the previous snapshot "
              f"({int(manifest_rows[-1]['rows']):,}). MPV may have removed records.")

    RAW_DIR.mkdir(parents=True, exist_ok=True)
    out = RAW_DIR / f'mpv_{today.isoformat()}.csv'
    if out.exists():
        sys.exit(f"{out.name} already exists; raw snapshots are never overwritten.")

    sha = hashlib.sha256(content).hexdigest()
    manifest_rows.append({'snapshot_date': today.isoformat(), 'file': out.name, 'sha256': sha,
                          'rows': len(df), 'last_incident_date': last_incident.isoformat(),
                          'source': 'csv' if args.csv else 'airtable'})

    # Write the snapshot, then replace the manifest atomically; if the manifest
    # step fails, remove the snapshot so a same-day rerun isn't blocked
    out.write_bytes(content)  # unmodified bytes, so the checksum matches the source
    try:
        tmp = MANIFEST.with_suffix('.csv.tmp')
        with tmp.open('w', newline='') as f:
            w = csv.DictWriter(f, fieldnames=header)
            w.writeheader()
            w.writerows(manifest_rows)
        tmp.replace(MANIFEST)
    except Exception:
        out.unlink(missing_ok=True)
        raise

    print(f"Saved {out.relative_to(ROOT)}: {len(df):,} rows, last incident "
          f"{last_incident}, sha256 {sha[:12]}...")


if __name__ == '__main__':
    main()
