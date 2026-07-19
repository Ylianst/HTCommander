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
import shutil
import struct
import sys
import tempfile
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


def _collect_encoded(open_dat):
    """Streams HD/AM/EN, joins them on the unique system id, and returns a dict
    mapping each callsign to its ``(index key, encoded record bytes)``.

    Only the distilled data is held in memory: each member is decompressed and
    parsed line by line (see ``_open_from_zip``), unneeded columns are dropped,
    and every matched record is packed straight to bytes. The large raw ``.dat``
    members are never materialized in full.
    """
    # HD: callsign + status + expiration, keyed by unique id. Stored as a compact
    # tuple to keep the join table small.
    hd = {}
    for line in open_dat("HD.dat"):
        c = _split(line)
        uid = _get(c, HD_UNIQUE_ID)
        if not uid:
            continue
        hd[uid] = (
            _get(c, HD_CALLSIGN).upper(),
            _get(c, HD_LICENSE_STATUS).upper()[:1],
            _parse_date(_get(c, HD_EXPIRED_DATE)),
        )

    # AM: operator class, keyed by unique id. Only ids present in HD are kept
    # (the EN pass only ever looks up such ids), which bounds this table.
    am = {}
    for line in open_dat("AM.dat"):
        c = _split(line)
        uid = _get(c, AM_UNIQUE_ID)
        if uid in hd:
            am[uid] = _get(c, AM_OPERATOR_CLASS).upper()[:1]

    # EN: name + address. Encode each joined record to bytes immediately,
    # deduplicating by callsign (last entry wins).
    by_call = {}
    for line in open_dat("EN.dat"):
        c = _split(line)
        uid = _get(c, EN_UNIQUE_ID)
        head = hd.get(uid)
        if head is None:
            continue
        callsign = head[0] or _get(c, EN_CALLSIGN).upper()
        if not callsign:
            continue
        key = _make_key(callsign)
        if key is None:
            continue

        entity = _get(c, EN_ENTITY_NAME)
        if entity:
            name = entity
        else:
            name = " ".join(
                p for p in (
                    _get(c, EN_FIRST_NAME),
                    _get(c, EN_MI),
                    _get(c, EN_LAST_NAME),
                ) if p
            )

        by_call[callsign] = (
            key,
            encode_record(
                callsign,
                name,
                _get(c, EN_CITY),
                _get(c, EN_STATE).upper()[:2],
                _get(c, EN_ZIP),
                am.get(uid, ""),
                head[1],
                head[2],
            ),
        )

    return by_call


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
    buf += struct.pack("<H", len(b))
    buf += b


def _char_byte(s):
    return ord(s[0]) if s else 0


def encode_record(callsign, name, city, state, zip_code, operator_class,
                  status, expire):
    buf = bytearray()
    _write_string(buf, callsign)
    _write_string(buf, name)
    _write_string(buf, city)
    _write_string(buf, state)
    _write_string(buf, zip_code)
    buf.append(_char_byte(operator_class))
    buf.append(_char_byte(status))
    buf += struct.pack("<I", expire & 0xFFFFFFFF)
    return bytes(buf)


def build_streaming(open_dat, out_path, source_date):
    """Builds the database and writes it directly to ``out_path``.

    The only state held in memory is the distilled record set (already packed to
    bytes); the header, sorted index and record section are streamed to the file
    without a second full-size copy. Returns the record count.
    """
    by_call = _collect_encoded(open_dat)
    # Sorting is the one step that needs the whole (distilled) set at once, as
    # the index must be ordered by callsign key for binary search.
    items = sorted(by_call.values(), key=lambda kb: kb[0])
    by_call.clear()
    count = len(items)
    records_offset = HEADER_SIZE + count * INDEX_ENTRY_SIZE

    with open(out_path, "wb") as f:
        header = bytearray(HEADER_SIZE)
        struct.pack_into("<I", header, 0, MAGIC)
        struct.pack_into("<H", header, 4, FORMAT_VERSION)
        struct.pack_into("<H", header, 6, 0)
        struct.pack_into("<I", header, 8, count)
        struct.pack_into("<I", header, 12, HEADER_SIZE)
        struct.pack_into("<I", header, 16, records_offset)
        struct.pack_into("<I", header, 20, source_date & 0xFFFFFFFF)
        f.write(header)

        # Index: sorted 8-byte key + absolute record offset.
        cursor = records_offset
        for key, blob in items:
            f.write(key)
            f.write(struct.pack("<I", cursor))
            cursor += len(blob)

        # Records section, in the same sorted order.
        for _key, blob in items:
            f.write(blob)

    return count


# ── ULS input helpers ───────────────────────────────────────────────────────

def _open_from_zip(zf):
    def opener(name):
        try:
            raw = zf.open(name)
        except KeyError:
            return []
        # zf.open returns a lazily-decompressing stream, so the (large) member
        # is decompressed incrementally and never held in full.
        return io.TextIOWrapper(raw, encoding="latin-1")
    return opener


def _download_to_tempfile(url):
    """Streams ``url`` to a temporary file and returns ``(path, last_modified)``.

    Downloading to a seekable file (rather than reading it all into memory) keeps
    peak memory bounded and lets ``zipfile`` seek to the central directory. The
    caller is responsible for deleting the returned file.
    """
    fd, path = tempfile.mkstemp(suffix=".zip")
    last_modified = None
    try:
        with os.fdopen(fd, "wb") as out, urllib.request.urlopen(url) as resp:
            last_modified = resp.headers.get("Last-Modified")
            shutil.copyfileobj(resp, out, 1 << 20)
    except BaseException:
        os.remove(path)
        raise
    return path, last_modified


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
    tmp_zip = None
    zf = None
    try:
        if args.download:
            print(f"Downloading {FCC_URL} ...")
            tmp_zip, last_modified = _download_to_tempfile(FCC_URL)
            if last_modified:
                try:
                    dt = email.utils.parsedate_to_datetime(last_modified)
                    fcc_date = dt.year * 10000 + dt.month * 100 + dt.day
                    print(f"  FCC Last-Modified: {last_modified} -> {fcc_date}")
                except (TypeError, ValueError):
                    pass
            zf = zipfile.ZipFile(tmp_zip)
            opener = _open_from_zip(zf)
        elif args.zip_file:
            zf = zipfile.ZipFile(args.zip_file)
            opener = _open_from_zip(zf)
        else:
            opener = _open_from_dir(args.uls_dir)

        if args.source_date:
            source_date = args.source_date
        elif fcc_date:
            source_date = fcc_date
        else:
            source_date = int(datetime.date.today().strftime("%Y%m%d"))

        print(f"Building database (data date {source_date}) ...")
        count = build_streaming(opener, args.out, source_date)
    finally:
        if zf is not None:
            zf.close()
        if tmp_zip and os.path.exists(tmp_zip):
            os.remove(tmp_zip)

    size = os.path.getsize(args.out)
    print(f"Wrote {args.out} ({size:,} bytes, {count:,} records)")

    if args.zip:
        with open(args.out, "rb") as f:
            db_bytes = f.read()
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
