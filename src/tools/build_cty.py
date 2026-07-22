#!/usr/bin/env python3
# Copyright 2026 Ylian Saint-Hilaire
# Licensed under the Apache License, Version 2.0 (the "License");
# http://www.apache.org/licenses/LICENSE-2.0
#
# Builds the HTCommander offline callsign -> country table from AD1C's Amateur
# Radio Country Files (country-files.com). The output is a small, gzip-compressed
# JSON asset bundled directly into the app (NOT downloaded at runtime), so that
# looking up which country/entity a callsign belongs to always works offline on
# every platform, even when the (large) FCC license database is not installed.
#
# The layout MUST match the reader in `src/lib/callsign/callsign_country.dart`.
#
# Usage:
#   # Download the latest "Big CTY" file and build the asset:
#   python build_cty.py --download --out ../assets/callsign/cty.json.gz
#
#   # Build from an already-downloaded cty.csv:
#   python build_cty.py --csv ./cty.csv --out ../assets/callsign/cty.json.gz
#
# Data source (free to use, courtesy of Jim Reisert AD1C):
#   https://www.country-files.com/bigcty/cty.csv
#
# cty.csv line format (comma-separated, one entity per line):
#   PrimaryPrefix,CountryName,DXCC,Continent,CQZone,ITUZone,Lat,Lon,GMT,AliasList;
# The alias list is space-separated. A token beginning with '=' is a full
# callsign (exact match); other tokens are prefixes. Tokens may carry override
# modifiers: (cq) [itu] <lat/lon> {continent} ~tz~ which are stripped here (we
# key country lookups on the entity, which the overrides never change).

import argparse
import gzip
import json
import os
import re
import sys
import urllib.request

DEFAULT_URL = "https://www.country-files.com/bigcty/cty.csv"

# Strips the CT9 override modifiers that may trail an alias/exact token.
_MODIFIER_RE = re.compile(r"\([^)]*\)|\[[^\]]*\]|<[^>]*>|\{[^}]*\}|~[^~]*~")


def _clean_token(token: str) -> str:
    """Remove override modifiers and stray punctuation from an alias token."""
    token = _MODIFIER_RE.sub("", token)
    return token.strip().strip(";").strip()


def _download(url: str) -> str:
    print(f"Downloading {url} ...")
    req = urllib.request.Request(url, headers={"User-Agent": "HTCommander-build-cty"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        data = resp.read()
    text = data.decode("utf-8", errors="replace")
    print(f"  {len(data):,} bytes")
    return text


def build(csv_text: str) -> dict:
    """Parse cty.csv text into the compact country lookup structure."""
    # Entity table interned by DXCC number: dxcc -> index.
    dxcc_to_index = {}
    countries = []  # [name, continent, dxcc, cqZone, ituZone]
    prefixes = {}   # prefix string -> country index
    exact = {}      # full callsign -> country index

    def intern(name, continent, dxcc, cq, itu):
        idx = dxcc_to_index.get(dxcc)
        if idx is None:
            idx = len(countries)
            dxcc_to_index[dxcc] = idx
            countries.append([name, continent, dxcc, cq, itu])
        return idx

    for raw in csv_text.splitlines():
        line = raw.strip()
        if not line:
            continue
        parts = line.split(",", 9)
        if len(parts) < 10:
            continue
        primary, name, dxcc_s, continent, cq_s, itu_s, _lat, _lon, _gmt, aliases = parts
        name = name.strip()
        continent = continent.strip()
        try:
            dxcc = int(dxcc_s)
            cq = int(cq_s)
            itu = int(itu_s)
        except ValueError:
            continue
        idx = intern(name, continent, dxcc, cq, itu)

        for token in aliases.split():
            is_exact = token.startswith("=")
            if is_exact:
                token = token[1:]
            key = _clean_token(token)
            if not key:
                continue
            if is_exact:
                exact.setdefault(key, idx)
            else:
                prefixes.setdefault(key, idx)

    return {
        "source": "AD1C Amateur Radio Country Files (country-files.com)",
        "countries": countries,
        "prefixes": prefixes,
        "exact": exact,
    }


def main(argv=None):
    ap = argparse.ArgumentParser(description="Build the HTCommander callsign->country asset.")
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--download", action="store_true", help="Download cty.csv from country-files.com")
    src.add_argument("--csv", help="Path to a local cty.csv file")
    ap.add_argument("--url", default=DEFAULT_URL, help="Override the download URL")
    ap.add_argument(
        "--out",
        default=os.path.join(os.path.dirname(__file__), "..", "assets", "callsign", "cty.json.gz"),
        help="Output path for the gzipped JSON asset",
    )
    args = ap.parse_args(argv)

    if args.download:
        csv_text = _download(args.url)
    else:
        with open(args.csv, "r", encoding="utf-8", errors="replace") as f:
            csv_text = f.read()

    data = build(csv_text)

    out_path = os.path.abspath(args.out)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)

    payload = json.dumps(data, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    with gzip.open(out_path, "wb", compresslevel=9) as f:
        f.write(payload)

    print(f"Countries : {len(data['countries']):,}")
    print(f"Prefixes  : {len(data['prefixes']):,}")
    print(f"Exact     : {len(data['exact']):,}")
    print(f"Raw JSON  : {len(payload):,} bytes")
    print(f"Gzipped   : {os.path.getsize(out_path):,} bytes -> {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
