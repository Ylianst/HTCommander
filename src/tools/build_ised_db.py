#!/usr/bin/env python3
# Copyright 2026 Ylian Saint-Hilaire
# Licensed under the Apache License, Version 2.0 (the "License");
# http://www.apache.org/licenses/LICENSE-2.0
#
# Builds the HTCommander offline Canadian callsign database from the ISED
# (Innovation, Science and Economic Development Canada) amateur radio data
# extract.
#
# The output is the same compact, sorted, read-only binary file (`.cdb`) that
# the US/FCC builder produces, so the app's reader
# (`src/lib/callsign/callsign_database.dart`) can consume both. The only
# differences are Canadian field encodings, signalled by the `flagCanada` bit
# in the header:
#   * postal codes are packed as alphanumeric Canadian codes (A1A1B1), not
#     numeric ZIPs;
#   * the class byte of each class/status dictionary entry holds a qualification
#     bitmask (Basic/5wpm/12wpm/Advanced/Honours) instead of an FCC class letter;
#   * Canadian certificates never expire, so the expire field is always 0.
#
# Usage:
#   # Download the latest ISED amateur extract and build the database:
#   python build_ised_db.py --download --out ised_amateur.cdb --compress
#
#   # Build from an already-downloaded amateur_delim.zip:
#   python build_ised_db.py --zip-file ./amateur_delim.zip --out ised_amateur.cdb --compress
#
#   # Build from an already-extracted amateur_delim.txt:
#   python build_ised_db.py --txt-file ./amateur_delim.txt --out ised_amateur.cdb --compress
#
# Outputs alongside --out:
#   <out>            the binary database
#   <out>.xz         xz-compressed database (when --compress is given; this is what the app downloads)
#   ised_amateur_manifest.json   manifest describing the (compressed) download
#
# ISED data source (weekly amateur extract):
#   https://apc-cap.ic.gc.ca/datafiles/amateur_delim.zip
# The archive contains a UTF-8, ";"-delimited amateur_delim.txt with a header
# row. Column order is documented in readme_amat_delim.txt shipped alongside it.

import argparse
import datetime
import email.utils
import hashlib
import io
import json
import lzma
import os
import struct
import sys
import tempfile
import urllib.request
import zipfile

ISED_URL = "https://apc-cap.ic.gc.ca/datafiles/amateur_delim.zip"
ISED_TXT_NAME = "amateur_delim.txt"

MAGIC = 0x42444348  # "HCDB" little-endian
FORMAT_VERSION = 2
HEADER_SIZE = 64
# Header flag: records use Canadian (ISED) field encoding. Must match
# CallsignDatabase.flagCanada in callsign_database.dart.
FLAG_CANADA = 0x0001
# Callsigns are packed into a base-37 key: KEY_CHARS characters fit in KEY_BYTES.
KEY_CHARS = 8
KEY_BYTES = 6
# Canadian certificates do not expire; the expire field is always 0. The epoch
# is still written for format compatibility with the shared reader.
EPOCH_DATE = 20000101

# ── ISED record parsing ─────────────────────────────────────────────────────
# amateur_delim.txt is ";"-delimited with a leading header row. Column indices
# (0-based) per readme_amat_delim.txt.

COL_CALLSIGN = 0
COL_FIRST_NAME = 1
COL_SURNAME = 2
COL_CITY = 4
COL_PROVINCE = 5
COL_POSTAL = 6
COL_QUAL_A = 7   # Basic
COL_QUAL_B = 8   # 5 wpm Morse
COL_QUAL_C = 9   # 12 wpm Morse
COL_QUAL_D = 10  # Advanced
COL_QUAL_E = 11  # Basic with Honours
COL_CLUB_NAME = 12
COL_CLUB_NAME_2 = 13
COL_CLUB_CITY = 15
COL_CLUB_PROVINCE = 16
COL_CLUB_POSTAL = 17

# Qualification bitmask bits. Must match callsign_database.dart.
QUAL_BASIC = 0x01     # A
QUAL_5WPM = 0x02      # B
QUAL_12WPM = 0x04     # C
QUAL_ADVANCED = 0x08  # D
QUAL_HONOURS = 0x10   # E


def _split(line):
    return line.rstrip("\r\n").split(";")


def _get(cols, idx):
    return cols[idx].strip() if idx < len(cols) else ""


def _qual_mask(cols):
    """Builds the qualification bitmask from the five qualification columns.
    A cell is considered "held" whenever it is non-empty."""
    mask = 0
    if _get(cols, COL_QUAL_A):
        mask |= QUAL_BASIC
    if _get(cols, COL_QUAL_B):
        mask |= QUAL_5WPM
    if _get(cols, COL_QUAL_C):
        mask |= QUAL_12WPM
    if _get(cols, COL_QUAL_D):
        mask |= QUAL_ADVANCED
    if _get(cols, COL_QUAL_E):
        mask |= QUAL_HONOURS
    return mask


def _collect_encoded(lines):
    """Parses the ISED extract and returns a dict mapping each callsign to a
    distilled tuple ``(index key, name_blob, city, postal, province,
    qual_mask)``. City, postal and province are kept raw and dictionary-encoded
    later. The last row for a callsign wins."""
    by_call = {}
    for line in lines:
        cols = _split(line)
        callsign = _get(cols, COL_CALLSIGN).upper()
        if not callsign or callsign == "CALLSIGN":
            continue  # skip the header row / blank lines
        key = _pack_key(callsign)
        if key is None:
            continue

        first = _get(cols, COL_FIRST_NAME)
        surname = _get(cols, COL_SURNAME)
        name = " ".join(p for p in (first, surname) if p)
        # Club stations carry their name in the club columns instead.
        if not name:
            name = " ".join(
                p for p in (_get(cols, COL_CLUB_NAME), _get(cols, COL_CLUB_NAME_2)) if p
            )

        city = _get(cols, COL_CITY) or _get(cols, COL_CLUB_CITY)
        province = (_get(cols, COL_PROVINCE) or _get(cols, COL_CLUB_PROVINCE)).upper()[:2]
        postal = _get(cols, COL_POSTAL) or _get(cols, COL_CLUB_POSTAL)

        by_call[callsign] = (
            key,
            _encode_name(name),
            city,
            postal,
            province,
            _qual_mask(cols),
        )

    return by_call


# ── Binary encoding (must match callsign_database.dart) ─────────────────────

def _pack_key(callsign):
    # Packs a callsign into a sortable base-37 integer: padding = 0, '0'-'9' =
    # 1-10, 'A'-'Z' = 11-36, real characters in the high digits so the packed
    # integers sort identically to the zero-padded callsigns. Returns None when
    # the callsign has no usable characters.
    value = 0
    n = 0
    for ch in callsign.upper():
        if n >= KEY_CHARS:
            break
        if ch == "-":
            break
        if "0" <= ch <= "9":
            code = ord(ch) - 48 + 1
        elif "A" <= ch <= "Z":
            code = ord(ch) - 65 + 11
        else:
            continue
        value = value * 37 + code
        n += 1
    if n == 0:
        return None
    for _ in range(n, KEY_CHARS):
        value *= 37
    return value


def _write_string16(buf, s):
    b = s.encode("utf-8")[:0xFFFF]
    buf += struct.pack("<H", len(b))
    buf += b


def _write_string8(buf, s):
    b = s.encode("utf-8")[:0xFF]
    buf += struct.pack("<B", len(b))
    buf += b


def _encode_name(name):
    # The only variable-length field kept inline in a record.
    buf = bytearray()
    _write_string16(buf, name)
    return bytes(buf)


POSTAL_NONE = 0xFFFFFFFF


def _pack_postal(postal):
    """Packs a Canadian postal code (A1A1B1: letter-digit-letter-digit-letter-
    digit) into a u32 by interleaving base-26 letters and base-10 digits, or
    POSTAL_NONE when it does not match that fixed pattern. Spaces are ignored."""
    s = postal.upper().replace(" ", "")
    if len(s) != 6:
        return POSTAL_NONE
    value = 0
    for i, ch in enumerate(s):
        if i % 2 == 0:  # letter
            if not ("A" <= ch <= "Z"):
                return POSTAL_NONE
            value = value * 26 + (ord(ch) - 65)
        else:  # digit
            if not ("0" <= ch <= "9"):
                return POSTAL_NONE
            value = value * 10 + (ord(ch) - 48)
    return value


def build_streaming(lines, out_path, source_date):
    """Builds the database and writes it directly to ``out_path``. Returns the
    record count."""
    by_call = _collect_encoded(lines)
    # The index must be ordered by callsign key for binary search. Each item is
    # (key, name_blob, city, postal, province, qual_mask).
    items = sorted(by_call.values(), key=lambda it: it[0])
    by_call.clear()
    count = len(items)

    # Build the province, qualification and city dictionaries (sorted for
    # reproducible, byte-identical output). Records reference these by index.
    # The province reuses the "state" dictionary; the qualification mask reuses
    # the "class/status" dictionary (mask in the class byte, status byte 0).
    provinces = sorted({it[4] for it in items})
    qual_values = sorted({it[5] << 8 for it in items})
    cities = sorted({it[2] for it in items})
    if len(provinces) > 0xFFFF or len(qual_values) > 0xFFFF or len(cities) > 0xFFFFFF:
        raise ValueError("dictionary too large for the database format")
    province_index = {s: i for i, s in enumerate(provinces)}
    qual_index = {v: i for i, v in enumerate(qual_values)}
    city_index = {s: i for i, s in enumerate(cities)}

    # City dictionary blob (u8 len + UTF-8 per entry).
    city_blob = bytearray()
    for s in cities:
        _write_string8(city_blob, s)

    state_offset = HEADER_SIZE
    cs_offset = state_offset + len(provinces) * 2
    city_offset = cs_offset + len(qual_values) * 2
    keys_offset = city_offset + len(city_blob)
    lengths_offset = keys_offset + count * KEY_BYTES
    records_offset = lengths_offset + count * 2

    with open(out_path, "wb") as f:
        header = bytearray(HEADER_SIZE)
        struct.pack_into("<I", header, 0, MAGIC)
        struct.pack_into("<H", header, 4, FORMAT_VERSION)
        struct.pack_into("<H", header, 6, FLAG_CANADA)
        struct.pack_into("<I", header, 8, count)
        struct.pack_into("<I", header, 12, keys_offset)
        struct.pack_into("<I", header, 16, lengths_offset)
        struct.pack_into("<I", header, 20, records_offset)
        struct.pack_into("<I", header, 24, source_date & 0xFFFFFFFF)
        struct.pack_into("<I", header, 28, EPOCH_DATE)
        struct.pack_into("<H", header, 32, len(provinces))
        struct.pack_into("<H", header, 34, len(qual_values))
        struct.pack_into("<I", header, 36, state_offset)
        struct.pack_into("<I", header, 40, cs_offset)
        struct.pack_into("<I", header, 44, len(cities))
        struct.pack_into("<I", header, 48, city_offset)
        f.write(header)

        # Province dictionary: 2 bytes per entry (ASCII code, zero-padded).
        for s in provinces:
            b = (s or "").encode("ascii", "ignore")[:2]
            f.write(b + b"\x00" * (2 - len(b)))

        # Qualification dictionary: 2 bytes per entry (maskByte, 0).
        for v in qual_values:
            f.write(bytes(((v >> 8) & 0xFF, v & 0xFF)))

        # City dictionary.
        f.write(city_blob)

        # Keys block: sorted 6-byte big-endian packed keys.
        for it in items:
            f.write(it[0].to_bytes(KEY_BYTES, "big"))

        # Lengths block: u16 byte length of each record, in the same order. A
        # record is name_blob + cityIndex(3) + provinceIndex(1) + qualIndex(1)
        # + postal(4) + expire(2).
        for it in items:
            rec_len = len(it[1]) + 11
            if rec_len > 0xFFFF:
                raise ValueError("record too large for u16 length")
            f.write(struct.pack("<H", rec_len))

        # Records block, in the same sorted order.
        for it in items:
            _key, name_blob, city, postal, province, qual_mask = it
            ci = city_index[city]
            f.write(name_blob)
            f.write(bytes((ci & 0xFF, (ci >> 8) & 0xFF, (ci >> 16) & 0xFF)))
            f.write(bytes((province_index[province], qual_index[qual_mask << 8])))
            f.write(struct.pack("<I", _pack_postal(postal)))
            f.write(struct.pack("<H", 0))  # no expiration for Canadian certs

    return count


# ── ISED input helpers ──────────────────────────────────────────────────────

def _lines_from_zip(zf):
    # The extract is UTF-8. Decode incrementally so the (few MB) member is never
    # held in full.
    raw = zf.open(ISED_TXT_NAME)
    return io.TextIOWrapper(raw, encoding="utf-8")


def _download_to_tempfile(url):
    """Streams ``url`` to a temporary file and returns ``(path, last_modified)``.
    The caller is responsible for deleting the returned file."""
    fd, path = tempfile.mkstemp(suffix=".zip")
    last_modified = None
    try:
        with os.fdopen(fd, "wb") as out, urllib.request.urlopen(url) as resp:
            last_modified = resp.headers.get("Last-Modified")
            while True:
                chunk = resp.read(1 << 20)
                if not chunk:
                    break
                out.write(chunk)
    except BaseException:
        os.remove(path)
        raise
    return path, last_modified


def _version_from_date(source_date):
    """Formats an integer YYYYMMDD as a `YYYY.MM.DD` version string."""
    y = source_date // 10000
    m = (source_date // 100) % 100
    d = source_date % 100
    return f"{y:04d}.{m:02d}.{d:02d}"


def main():
    ap = argparse.ArgumentParser(
        description="Build the HTCommander offline Canadian callsign database"
    )
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--download", action="store_true", help="download the ISED amateur extract")
    src.add_argument("--zip-file", help="path to a downloaded amateur_delim.zip")
    src.add_argument("--txt-file", help="path to an extracted amateur_delim.txt")
    ap.add_argument("--out", default="ised_amateur.cdb", help="output database path")
    ap.add_argument("--compress", action="store_true", help="also write an xz-compressed database + manifest")
    ap.add_argument("--base-url", default="https://ylianst.github.io/HTCommander/callsign/",
                    help="base URL where the compressed database will be hosted (for the manifest)")
    ap.add_argument("--source-date", type=int, default=0,
                    help="explicit data date as YYYYMMDD (overrides the ISED Last-Modified date)")
    ap.add_argument("--version", help="explicit version string (defaults to the source date)")
    args = ap.parse_args()

    # The data date identifies the ISED release. It drives both the version
    # string and the sourceDate embedded in the database, so identical ISED
    # content always produces byte-identical output. Preference order: explicit
    # --source-date, then the download's Last-Modified header, then today.
    ised_date = 0
    tmp_zip = None
    zf = None
    txt = None
    try:
        if args.download:
            print(f"Downloading {ISED_URL} ...")
            tmp_zip, last_modified = _download_to_tempfile(ISED_URL)
            if last_modified:
                try:
                    dt = email.utils.parsedate_to_datetime(last_modified)
                    ised_date = dt.year * 10000 + dt.month * 100 + dt.day
                    print(f"  ISED Last-Modified: {last_modified} -> {ised_date}")
                except (TypeError, ValueError):
                    pass
            zf = zipfile.ZipFile(tmp_zip)
            lines = _lines_from_zip(zf)
        elif args.zip_file:
            zf = zipfile.ZipFile(args.zip_file)
            lines = _lines_from_zip(zf)
        else:
            txt = open(args.txt_file, "r", encoding="utf-8")
            lines = txt

        if args.source_date:
            source_date = args.source_date
        elif ised_date:
            source_date = ised_date
        else:
            source_date = int(datetime.date.today().strftime("%Y%m%d"))

        print(f"Building database (data date {source_date}) ...")
        count = build_streaming(lines, args.out, source_date)
    finally:
        if txt is not None:
            txt.close()
        if zf is not None:
            zf.close()
        if tmp_zip and os.path.exists(tmp_zip):
            os.remove(tmp_zip)

    size = os.path.getsize(args.out)
    print(f"Wrote {args.out} ({size:,} bytes, {count:,} records)")

    if args.compress:
        with open(args.out, "rb") as f:
            db_bytes = f.read()
        xz_path = args.out + ".xz"
        # xz/LZMA embeds no timestamps, so identical ISED data always yields a
        # byte-identical archive.
        xz_bytes = lzma.compress(db_bytes, preset=9 | lzma.PRESET_EXTREME)
        with open(xz_path, "wb") as f:
            f.write(xz_bytes)
        md5 = hashlib.md5(xz_bytes).hexdigest()
        version = args.version or _version_from_date(source_date)
        manifest = {
            "schemaVersion": 1,
            "version": version,
            "sourceDate": source_date,
            "url": args.base_url.rstrip("/") + "/" + os.path.basename(xz_path),
            "compressed": True,
            "sizeBytes": len(xz_bytes),
            "md5": md5,
            "recordCount": count,
        }
        manifest_path = os.path.join(os.path.dirname(args.out) or ".", "ised_amateur_manifest.json")
        with open(manifest_path, "w") as f:
            json.dump(manifest, f, indent=2)
        print(f"Wrote {xz_path} ({len(xz_bytes):,} bytes, md5 {md5})")
        print(f"Wrote {manifest_path}")


if __name__ == "__main__":
    sys.exit(main())
