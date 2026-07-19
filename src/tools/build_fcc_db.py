#!/usr/bin/env python3
# Copyright 2026 Ylian Saint-Hilaire
# Licensed under the Apache License, Version 2.0 (the "License");
# http://www.apache.org/licenses/LICENSE-2.0
#
# Builds the HTCommander offline callsign database from the FCC ULS amateur
# license dump.
#
# The output is a compact, sorted, read-only binary file (`.cdb`) that the app
# downloads and binary-searches directly. The layout MUST match the reader in
# `src/lib/callsign/callsign_database.dart`.
#
# Usage:
#   # Download the latest weekly amateur dump and build the database:
#   python build_fcc_db.py --download --out fcc_amateur.cdb --zip
#
#   # Build from an already-extracted ULS directory (containing EN.dat/HD.dat/AM.dat):
#   python build_fcc_db.py --uls-dir ./l_amat --out fcc_amateur.cdb --zip
#
# Outputs alongside --out:
#   <out>            the binary database
#   <out>.zip        zipped database (when --zip is given; this is what the app downloads)
#   fcc_amateur_manifest.json   manifest describing the (zip) download
#
# FCC data source (weekly complete amateur dump):
#   https://data.fcc.gov/download/pub/uls/complete/l_amat.zip
# Record layouts: FCC "Public Access Database Definitions". Column indices below
# follow that spec; verify them if the FCC schema changes.

import argparse
import datetime
import email.utils
import hashlib
import io
import json
import os
import struct
import sys
import urllib.request
import zipfile

FCC_URL = "https://data.fcc.gov/download/pub/uls/complete/l_amat.zip"

MAGIC = 0x42444348  # "HCDB" little-endian
FORMAT_VERSION = 1
HEADER_SIZE = 64
KEY_LENGTH = 8
INDEX_ENTRY_SIZE = 12  # 8-byte key + uint32 offset

# ── FCC record parsing ──────────────────────────────────────────────────────
# Files are pipe-delimited. Column indices (0-based) per the FCC PUBACC spec.

# HD.dat: header / license status
HD_UNIQUE_ID = 1
HD_CALLSIGN = 4
HD_LICENSE_STATUS = 5
HD_EXPIRED_DATE = 8  # mm/dd/yyyy

# EN.dat: entity (name / address)
EN_UNIQUE_ID = 1
EN_CALLSIGN = 4
EN_ENTITY_NAME = 7
EN_FIRST_NAME = 8
EN_MI = 9
EN_LAST_NAME = 10
EN_CITY = 16
EN_STATE = 17
EN_ZIP = 18

# AM.dat: amateur-specific (operator class)
AM_UNIQUE_ID = 1
AM_CALLSIGN = 4
AM_OPERATOR_CLASS = 5


def _split(line):
    return line.rstrip("\r\n").split("|")


def _get(cols, idx):
    return cols[idx].strip() if idx < len(cols) else ""


def _parse_date(s):
    # FCC dates are mm/dd/yyyy; return integer YYYYMMDD or 0.
    s = s.strip()
    if not s:
        return 0
    try:
        dt = datetime.datetime.strptime(s, "%m/%d/%Y")
        return dt.year * 10000 + dt.month * 100 + dt.day
    except ValueError:
        return 0


def load_records(open_dat):
    """open_dat(name) -> iterable of decoded text lines for the given .dat file."""
    # HD: status + expiration, keyed by unique id.
    hd = {}
    for line in open_dat("HD.dat"):
        c = _split(line)
        uid = _get(c, HD_UNIQUE_ID)
        if not uid:
            continue
        hd[uid] = {
            "callsign": _get(c, HD_CALLSIGN).upper(),
            "status": _get(c, HD_LICENSE_STATUS).upper()[:1],
            "expire": _parse_date(_get(c, HD_EXPIRED_DATE)),
        }

    # AM: operator class, keyed by unique id.
    am = {}
    for line in open_dat("AM.dat"):
        c = _split(line)
        uid = _get(c, AM_UNIQUE_ID)
        if uid:
            am[uid] = _get(c, AM_OPERATOR_CLASS).upper()[:1]

    # EN: name + address, keyed by unique id. Join everything here.
    records = {}
    for line in open_dat("EN.dat"):
        c = _split(line)
        uid = _get(c, EN_UNIQUE_ID)
        if not uid or uid not in hd:
            continue
        head = hd[uid]
        callsign = head["callsign"] or _get(c, EN_CALLSIGN).upper()
        if not callsign:
            continue

        entity = _get(c, EN_ENTITY_NAME)
        if entity:
            name = entity
        else:
            first = _get(c, EN_FIRST_NAME)
            mi = _get(c, EN_MI)
            last = _get(c, EN_LAST_NAME)
            name = " ".join(p for p in [first, mi, last] if p)

        records[callsign] = {
            "callsign": callsign,
            "name": name,
            "city": _get(c, EN_CITY),
            "state": _get(c, EN_STATE).upper()[:2],
            "zip": _get(c, EN_ZIP),
            "operator_class": am.get(uid, ""),
            "status": head["status"],
            "expire": head["expire"],
        }

    return records


# ── Binary encoding (must match callsign_database.dart) ─────────────────────

def _make_key(callsign):
    key = bytearray(KEY_LENGTH)
    n = 0
    for ch in callsign.upper():
        if n >= KEY_LENGTH:
            break
        if ch == "-":
            break
        if ch.isdigit() or ("A" <= ch <= "Z"):
            key[n] = ord(ch)
            n += 1
    if n == 0:
        return None
    return bytes(key)


def _write_string(buf, s):
    b = s.encode("utf-8")[:0xFFFF]
    buf.write(struct.pack("<H", len(b)))
    buf.write(b)


def _char_byte(s):
    return ord(s[0]) if s else 0


def encode_record(r):
    buf = io.BytesIO()
    _write_string(buf, r["callsign"])
    _write_string(buf, r["name"])
    _write_string(buf, r["city"])
    _write_string(buf, r["state"])
    _write_string(buf, r["zip"])
    buf.write(bytes([_char_byte(r["operator_class"])]))
    buf.write(bytes([_char_byte(r["status"])]))
    buf.write(struct.pack("<I", r["expire"] & 0xFFFFFFFF))
    return buf.getvalue()


def build_database(records, source_date):
    keyed = []
    for r in records.values():
        key = _make_key(r["callsign"])
        if key is not None:
            keyed.append((key, r))
    keyed.sort(key=lambda kr: kr[0])

    records_offset = HEADER_SIZE + len(keyed) * INDEX_ENTRY_SIZE
    record_blobs = []
    offsets = []
    cursor = records_offset
    for _, r in keyed:
        offsets.append(cursor)
        blob = encode_record(r)
        record_blobs.append(blob)
        cursor += len(blob)

    out = io.BytesIO()
    # Header (64 bytes).
    header = bytearray(HEADER_SIZE)
    struct.pack_into("<I", header, 0, MAGIC)
    struct.pack_into("<H", header, 4, FORMAT_VERSION)
    struct.pack_into("<H", header, 6, 0)
    struct.pack_into("<I", header, 8, len(keyed))
    struct.pack_into("<I", header, 12, HEADER_SIZE)
    struct.pack_into("<I", header, 16, records_offset)
    struct.pack_into("<I", header, 20, source_date & 0xFFFFFFFF)
    out.write(header)

    # Index.
    for (key, _), offset in zip(keyed, offsets):
        out.write(key)
        out.write(struct.pack("<I", offset))

    # Records.
    for blob in record_blobs:
        out.write(blob)

    return out.getvalue(), len(keyed)


# ── ULS input helpers ───────────────────────────────────────────────────────

def _open_from_zip(zf):
    def opener(name):
        try:
            data = zf.read(name)
        except KeyError:
            return []
        return io.TextIOWrapper(io.BytesIO(data), encoding="latin-1")
    return opener


def _open_from_dir(path):
    def opener(name):
        full = os.path.join(path, name)
        if not os.path.exists(full):
            return []
        return open(full, "r", encoding="latin-1")
    return opener


def _version_from_date(source_date):
    """Formats an integer YYYYMMDD as a `YYYY.MM.DD` version string."""
    y = source_date // 10000
    m = (source_date // 100) % 100
    d = source_date % 100
    return f"{y:04d}.{m:02d}.{d:02d}"


def main():
    ap = argparse.ArgumentParser(description="Build the HTCommander offline callsign database")
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--download", action="store_true", help="download the FCC weekly amateur dump")
    src.add_argument("--zip-file", help="path to a downloaded l_amat.zip")
    src.add_argument("--uls-dir", help="path to an extracted ULS directory")
    ap.add_argument("--out", default="fcc_amateur.cdb", help="output database path")
    ap.add_argument("--zip", action="store_true", help="also write a zipped database + manifest")
    ap.add_argument("--base-url", default="https://ylianst.github.io/HTCommander/callsign/",
                    help="base URL where the zip will be hosted (for the manifest)")
    ap.add_argument("--source-date", type=int, default=0,
                    help="explicit data date as YYYYMMDD (overrides the FCC Last-Modified date)")
    ap.add_argument("--version", help="explicit version string (defaults to the source date)")
    args = ap.parse_args()

    # The data date identifies the FCC weekly release. It drives both the
    # version string and the sourceDate embedded in the database, so identical
    # FCC content always produces byte-identical output. Preference order:
    # explicit --source-date, then the download's Last-Modified header, then
    # today's date as a last resort.
    fcc_date = 0
    if args.download:
        print(f"Downloading {FCC_URL} ...")
        with urllib.request.urlopen(FCC_URL) as resp:
            last_modified = resp.headers.get("Last-Modified")
            data = resp.read()
        if last_modified:
            try:
                dt = email.utils.parsedate_to_datetime(last_modified)
                fcc_date = dt.year * 10000 + dt.month * 100 + dt.day
                print(f"  FCC Last-Modified: {last_modified} -> {fcc_date}")
            except (TypeError, ValueError):
                pass
        zf = zipfile.ZipFile(io.BytesIO(data))
        opener = _open_from_zip(zf)
    elif args.zip_file:
        zf = zipfile.ZipFile(args.zip_file)
        opener = _open_from_zip(zf)
    else:
        opener = _open_from_dir(args.uls_dir)

    print("Parsing FCC records ...")
    records = load_records(opener)
    print(f"  {len(records)} callsigns")

    if args.source_date:
        source_date = args.source_date
    elif fcc_date:
        source_date = fcc_date
    else:
        source_date = int(datetime.date.today().strftime("%Y%m%d"))

    print(f"Building database (data date {source_date}) ...")
    db_bytes, count = build_database(records, source_date)

    with open(args.out, "wb") as f:
        f.write(db_bytes)
    print(f"Wrote {args.out} ({len(db_bytes):,} bytes, {count:,} records)")

    if args.zip:
        zip_path = args.out + ".zip"
        entry_name = os.path.basename(args.out)
        # Use a fixed entry timestamp so identical FCC data always yields a
        # byte-identical archive (the default stamps the current time).
        info = zipfile.ZipInfo(entry_name, date_time=(1980, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = 0o644 << 16
        with zipfile.ZipFile(zip_path, "w") as z:
            z.writestr(info, db_bytes, compresslevel=9)
        with open(zip_path, "rb") as f:
            zip_bytes = f.read()
        md5 = hashlib.md5(zip_bytes).hexdigest()
        version = args.version or _version_from_date(source_date)
        manifest = {
            "schemaVersion": 1,
            "version": version,
            "sourceDate": source_date,
            "url": args.base_url.rstrip("/") + "/" + os.path.basename(zip_path),
            "compressed": True,
            "sizeBytes": len(zip_bytes),
            "md5": md5,
            "recordCount": count,
        }
        manifest_path = os.path.join(os.path.dirname(args.out) or ".", "fcc_amateur_manifest.json")
        with open(manifest_path, "w") as f:
            json.dump(manifest, f, indent=2)
        print(f"Wrote {zip_path} ({len(zip_bytes):,} bytes, md5 {md5})")
        print(f"Wrote {manifest_path}")


if __name__ == "__main__":
    sys.exit(main())
