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
#   python build_fcc_db.py --download --out fcc_amateur.cdb --compress
#
#   # Build from an already-extracted ULS directory (containing EN.dat/HD.dat/AM.dat):
#   python build_fcc_db.py --uls-dir ./l_amat --out fcc_amateur.cdb --compress
#
# Outputs alongside --out:
#   <out>            the binary database
#   <out>.xz         xz-compressed database (when --compress is given; this is what the app downloads)
#   fcc_amateur_manifest.json   manifest describing the (compressed) download
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
import lzma
import os
import shutil
import struct
import sys
import tempfile
import urllib.request
import zipfile

FCC_URL = "https://data.fcc.gov/download/pub/uls/complete/l_amat.zip"

MAGIC = 0x42444348  # "HCDB" little-endian
FORMAT_VERSION = 2
HEADER_SIZE = 64
# Callsigns are packed into a base-37 key: KEY_CHARS characters fit in KEY_BYTES.
KEY_CHARS = 8
KEY_BYTES = 6
# Base date that record expiration dates are stored relative to (as a u16 day
# count). Written into the header so the reader never assumes a fixed epoch.
EPOCH_DATE = 20000101
EPOCH = datetime.date(2000, 1, 1)

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
    mapping each callsign to a tuple of its distilled fields:
    ``(index key, name_blob, city, zip, state, cs_packed, days)`` where
    ``name_blob`` is the encoded name, ``cs_packed`` is the packed (class,
    status) pair and ``days`` is the expiration as a day-count since EPOCH. The
    city, zip and state are kept as raw values and dictionary-encoded later.

    Only the distilled data is held in memory: each member is decompressed and
    parsed line by line (see ``_open_from_zip``), unneeded columns are dropped,
    and the name is packed straight to bytes. The large raw ``.dat`` members are
    never materialized in full.
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

    # EN: name + address. Encode the text portion to bytes immediately and keep
    # the small dictionary-bound fields alongside it, deduplicating by callsign
    # (last entry wins).
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
        key = _pack_key(callsign)
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
            _encode_name(name),
            _get(c, EN_CITY),
            _get(c, EN_ZIP),
            _get(c, EN_STATE).upper()[:2],
            _pack_cs(am.get(uid, ""), head[1]),
            _date_to_days(head[2]),
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


def _char_byte(s):
    return ord(s[0]) if s else 0


def _pack_cs(operator_class, status):
    """Packs a (class, status) pair into a single int for dictionary keying."""
    return (_char_byte(operator_class) << 8) | _char_byte(status)


def _date_to_days(yyyymmdd):
    """Converts an integer YYYYMMDD to days since EPOCH, or 0 (unknown) when the
    date is missing or outside the representable u16 window."""
    if not yyyymmdd:
        return 0
    y = yyyymmdd // 10000
    m = (yyyymmdd // 100) % 100
    d = yyyymmdd % 100
    try:
        dt = datetime.date(y, m, d)
    except ValueError:
        return 0
    days = (dt - EPOCH).days
    if days < 1 or days > 0xFFFF:
        return 0
    return days


def _encode_name(name):
    # The only variable-length field kept inline in a record.
    buf = bytearray()
    _write_string16(buf, name)
    return bytes(buf)


ZIP_NONE = 0xFFFFFFFF


def _pack_zip(zip_code):
    """Packs a ZIP string into a u32: the numeric value of a 5- or 9-digit ZIP,
    or ZIP_NONE when empty or not a plain 5/9-digit code."""
    if not zip_code:
        return ZIP_NONE
    digits = 0
    n = 0
    for ch in zip_code:
        if "0" <= ch <= "9":
            digits = digits * 10 + (ord(ch) - 48)
            n += 1
        elif ch in "- ":
            continue
        else:
            return ZIP_NONE
    if n not in (5, 9):
        return ZIP_NONE
    return digits


def build_streaming(open_dat, out_path, source_date):
    """Builds the database and writes it directly to ``out_path``.

    The only state held in memory is the distilled record set (already packed to
    bytes); the header, sorted index and record section are streamed to the file
    without a second full-size copy. Returns the record count.
    """
    by_call = _collect_encoded(open_dat)
    # Sorting is the one step that needs the whole (distilled) set at once, as
    # the index must be ordered by callsign key for binary search. Each item is
    # (key, name_blob, city, zip, state, cs_packed, days).
    items = sorted(by_call.values(), key=lambda it: it[0])
    by_call.clear()
    count = len(items)

    # Build the state, class/status and city dictionaries (sorted for
    # reproducible, byte-identical output). Records reference these by index.
    states = sorted({it[4] for it in items})
    cs_values = sorted({it[5] for it in items})
    cities = sorted({it[2] for it in items})
    if len(states) > 0xFFFF or len(cs_values) > 0xFFFF or len(cities) > 0xFFFFFF:
        raise ValueError("dictionary too large for the database format")
    state_index = {s: i for i, s in enumerate(states)}
    cs_index = {v: i for i, v in enumerate(cs_values)}
    city_index = {s: i for i, s in enumerate(cities)}

    # City dictionary blob (u8 len + UTF-8 per entry).
    city_blob = bytearray()
    for s in cities:
        _write_string8(city_blob, s)

    state_offset = HEADER_SIZE
    cs_offset = state_offset + len(states) * 2
    city_offset = cs_offset + len(cs_values) * 2
    keys_offset = city_offset + len(city_blob)
    lengths_offset = keys_offset + count * KEY_BYTES
    records_offset = lengths_offset + count * 2

    with open(out_path, "wb") as f:
        header = bytearray(HEADER_SIZE)
        struct.pack_into("<I", header, 0, MAGIC)
        struct.pack_into("<H", header, 4, FORMAT_VERSION)
        struct.pack_into("<H", header, 6, 0)
        struct.pack_into("<I", header, 8, count)
        struct.pack_into("<I", header, 12, keys_offset)
        struct.pack_into("<I", header, 16, lengths_offset)
        struct.pack_into("<I", header, 20, records_offset)
        struct.pack_into("<I", header, 24, source_date & 0xFFFFFFFF)
        struct.pack_into("<I", header, 28, EPOCH_DATE)
        struct.pack_into("<H", header, 32, len(states))
        struct.pack_into("<H", header, 34, len(cs_values))
        struct.pack_into("<I", header, 36, state_offset)
        struct.pack_into("<I", header, 40, cs_offset)
        struct.pack_into("<I", header, 44, len(cities))
        struct.pack_into("<I", header, 48, city_offset)
        f.write(header)

        # State dictionary: 2 bytes per entry (ASCII, zero-padded).
        for s in states:
            b = (s or "").encode("ascii", "ignore")[:2]
            f.write(b + b"\x00" * (2 - len(b)))

        # Class/status dictionary: 2 bytes per entry (classByte, statusByte).
        for v in cs_values:
            f.write(bytes(((v >> 8) & 0xFF, v & 0xFF)))

        # City dictionary.
        f.write(city_blob)

        # Keys block: sorted 6-byte big-endian packed keys.
        for it in items:
            f.write(it[0].to_bytes(KEY_BYTES, "big"))

        # Lengths block: u16 byte length of each record, in the same order. A
        # record is name_blob + cityIndex(3) + stateIndex(1) + csIndex(1)
        # + zip(4) + expire(2).
        for it in items:
            rec_len = len(it[1]) + 11
            if rec_len > 0xFFFF:
                raise ValueError("record too large for u16 length")
            f.write(struct.pack("<H", rec_len))

        # Records block, in the same sorted order.
        for it in items:
            _key, name_blob, city, zip_code, state, cs_packed, days = it
            ci = city_index[city]
            f.write(name_blob)
            f.write(bytes((ci & 0xFF, (ci >> 8) & 0xFF, (ci >> 16) & 0xFF)))
            f.write(bytes((state_index[state], cs_index[cs_packed])))
            f.write(struct.pack("<I", _pack_zip(zip_code)))
            f.write(struct.pack("<H", days))

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
    ap.add_argument("--compress", action="store_true", help="also write an xz-compressed database + manifest")
    ap.add_argument("--base-url", default="https://ylianst.github.io/HTCommander/callsign/",
                    help="base URL where the compressed database will be hosted (for the manifest)")
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

    if args.compress:
        with open(args.out, "rb") as f:
            db_bytes = f.read()
        xz_path = args.out + ".xz"
        # xz/LZMA embeds no timestamps, so identical FCC data always yields a
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
        manifest_path = os.path.join(os.path.dirname(args.out) or ".", "fcc_amateur_manifest.json")
        with open(manifest_path, "w") as f:
            json.dump(manifest, f, indent=2)
        print(f"Wrote {xz_path} ({len(xz_bytes):,} bytes, md5 {md5})")
        print(f"Wrote {manifest_path}")


if __name__ == "__main__":
    sys.exit(main())
