#!/usr/bin/env python3
"""
Find archived police reports in the Wayback Machine.

Historical annual reports and use-of-force reports are usually gone from
today's department websites, but the Internet Archive often kept them. For each
agency in agency_domains.csv, this queries the CDX API for every archived URL
under each URL prefix (current and old domains, e.g. ci.phoenix.az.us), keeps
documents whose path suggests an annual, force, or shooting report, and writes
one row per unique URL with a ready-to-open Wayback link.

Usage (from the project root):
    python tools/historical_ois/wayback_find.py [--slugs phoenix_az,san_antonio_tx]

Input:  tools/historical_ois/agency_domains.csv  (slug, url_prefix, note)
Output: output/tables/wayback_candidates.csv
"""

import argparse
import csv
import re
import sys
import time
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parents[2]
DOMAINS = ROOT / "tools" / "historical_ois" / "agency_domains.csv"
OUT = ROOT / "output" / "tables" / "wayback_candidates.csv"

CDX = "https://web.archive.org/cdx/search/cdx"
HEADERS = {"User-Agent": "agency-level-fatal-OIS research scraper (academic, non-commercial)"}
DELAY = 2.0  # seconds between CDX queries; the archive throttles bursts

# Whole-word-ish terms so "ois" can't match "noise" (the January scanner's bug)
KEEP = re.compile(
    r"(annual|yearly|year[-_ ]?end|use[-_ ]?of[-_ ]?force|\buof\b|force[-_ ]?report|"
    r"shooting|\bois\b|officer[-_ ]?involved|deadly[-_ ]?force|firearm[-_ ]?discharge|"
    r"discharge|internal[-_ ]?affairs|professional[-_ ]?standards|statistic|"
    r"report[s]?/|accountab|transparen|critical[-_ ]?incident)",
    re.I,
)
DOC_EXT = re.compile(r"\.(pdf|doc|docx|xls|xlsx|csv|txt)(\?|$)", re.I)
YEAR = re.compile(r"(?<!\d)(19[6-9]\d|20[0-2]\d)(?!\d)")


def cdx_query(prefix, retries=3):
    """Return CDX rows (timestamp, original, mimetype, statuscode) under a prefix."""
    params = {
        "url": prefix.rstrip("/") + "/*",
        "output": "json",
        "fl": "timestamp,original,mimetype,statuscode",
        "filter": "statuscode:200",
        "collapse": "urlkey",
        "limit": "200000",
    }
    for attempt in range(retries):
        try:
            r = requests.get(CDX, params=params, headers=HEADERS, timeout=120)
            if r.status_code == 429:
                time.sleep(30 * (attempt + 1))
                continue
            r.raise_for_status()
            rows = r.json() if r.text.strip() else []
            return rows[1:] if rows else []
        except (requests.RequestException, ValueError) as e:
            last = e
            time.sleep(10 * (attempt + 1))
    sys.stderr.write(f"  CDX failed for {prefix}: {last}\n")
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--slugs", help="comma-separated slugs to run (default: all)")
    args = ap.parse_args()
    want = set(args.slugs.split(",")) if args.slugs else None

    with open(DOMAINS, newline="", encoding="utf-8") as f:
        targets = [r for r in csv.DictReader(f) if not want or r["slug"] in want]

    out_rows, seen = [], set()
    for t in targets:
        sys.stderr.write(f"{t['slug']}: {t['url_prefix']}\n")
        rows = cdx_query(t["url_prefix"])
        time.sleep(DELAY)
        if rows is None:
            out_rows.append({"slug": t["slug"], "url_prefix": t["url_prefix"],
                             "timestamp": "", "original": "", "mimetype": "",
                             "is_document": "", "years_in_path": "",
                             "wayback_url": "", "note": "CDX query failed"})
            continue
        kept = 0
        for ts, original, mime, _status in rows:
            is_doc = bool(DOC_EXT.search(original)) or mime.startswith("application/")
            if not KEEP.search(original):
                continue
            key = (t["slug"], original.lower().split("?")[0])
            if key in seen:
                continue
            seen.add(key)
            kept += 1
            out_rows.append({
                "slug": t["slug"], "url_prefix": t["url_prefix"],
                "timestamp": ts, "original": original, "mimetype": mime,
                "is_document": is_doc,
                "years_in_path": ";".join(sorted(set(YEAR.findall(original)))),
                "wayback_url": f"https://web.archive.org/web/{ts}id_/{original}",
                "note": "",
            })
        sys.stderr.write(f"  {len(rows)} archived URLs, {kept} kept\n")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(out_rows[0].keys()) if out_rows else ["slug"])
        w.writeheader()
        w.writerows(out_rows)
    sys.stderr.write(f"Wrote {len(out_rows)} rows to {OUT.relative_to(ROOT)}\n")


if __name__ == "__main__":
    main()
