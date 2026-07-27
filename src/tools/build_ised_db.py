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


def _distill_sorted(lines):
    """Parses the ISED input into the distilled, key-sorted record set that both
    the full build and the overlay diff consume.

    Each item is ``(key, name_blob, city, postal, province, qual_mask)`` and the
    list is sorted ascending by ``key`` (as the on-disk index requires).
    """
    by_call = _collect_encoded(lines)
    items = sorted(by_call.values(), key=lambda it: it[0])
    by_call.clear()
    return items


def _write_cdb(items, out_path, source_date):
    """Writes the distilled, **already key-sorted** ``items`` to ``out_path`` as
    a Canadian (``flagCanada``) ``.cdb`` file and returns the record count.

    ``items`` are tuples of ``(key, name_blob, city, postal, province,
    qual_mask)``.
    """
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


def build_streaming(lines, out_path, source_date):
    """Builds the full Canadian database from an ISED input and writes it to
    ``out_path``. Returns the record count. The overlay path reuses
    ``_distill_sorted`` and ``_write_cdb`` directly so it can diff before
    writing."""
    items = _distill_sorted(lines)
    return _write_cdb(items, out_path, source_date)


# ── .cdb reader (for overlay diffs) ─────────────────────────────────────────
# A minimal reader that decodes a Canadian ``.cdb`` back into canonical logical
# records, used to diff a previously published baseline against a freshly built
# database. It must stay in lock-step with ``_write_cdb`` above.


def _u16(buf, off):
    return buf[off] | (buf[off + 1] << 8)


def _u32(buf, off):
    return int.from_bytes(buf[off:off + 4], "little")


def read_cdb_header(buf):
    """Parses and validates a ``.cdb`` header, returning it as a dict."""
    if len(buf) < HEADER_SIZE:
        raise ValueError("callsign database is too small")
    if _u32(buf, 0) != MAGIC:
        raise ValueError("not a callsign database (bad magic)")
    version = _u16(buf, 4)
    if version != FORMAT_VERSION:
        raise ValueError(f"unsupported callsign database version {version}")
    return {
        "flags": _u16(buf, 6),
        "count": _u32(buf, 8),
        "keysOffset": _u32(buf, 12),
        "lengthsOffset": _u32(buf, 16),
        "recordsOffset": _u32(buf, 20),
        "sourceDate": _u32(buf, 24),
        "epochDate": _u32(buf, 28),
        "stateCount": _u16(buf, 32),
        "classStatusCount": _u16(buf, 34),
        "stateOffset": _u32(buf, 36),
        "classStatusOffset": _u32(buf, 40),
        "cityCount": _u32(buf, 44),
        "cityOffset": _u32(buf, 48),
    }


def _read_dicts(buf, hdr):
    provinces = []
    off = hdr["stateOffset"]
    for i in range(hdr["stateCount"]):
        provinces.append(buf[off + i * 2:off + i * 2 + 2].rstrip(b"\x00")
                         .decode("ascii", "ignore"))
    quals = []
    off = hdr["classStatusOffset"]
    for i in range(hdr["classStatusCount"]):
        o = off + i * 2
        quals.append((buf[o] << 8) | buf[o + 1])
    cities = []
    off = hdr["cityOffset"]
    for _ in range(hdr["cityCount"]):
        ln = buf[off]
        off += 1
        cities.append(buf[off:off + ln].decode("utf-8"))
        off += ln
    return provinces, quals, cities


def iter_cdb_canonical(buf):
    """Yields one canonical tuple per record, **in ascending key order**. Each
    tuple is ``(key, name_blob, city, province, qual_mask, postal_u32)`` — the
    shape the diff compares a freshly built record against."""
    hdr = read_cdb_header(buf)
    provinces, quals, cities = _read_dicts(buf, hdr)
    count = hdr["count"]
    keys_off = hdr["keysOffset"]
    lengths_off = hdr["lengthsOffset"]
    rec_off = hdr["recordsOffset"]
    for i in range(count):
        key = int.from_bytes(buf[keys_off + i * 6:keys_off + i * 6 + KEY_BYTES],
                             "big")
        length = _u16(buf, lengths_off + i * 2)
        name_len = _u16(buf, rec_off)
        name_blob = bytes(buf[rec_off:rec_off + 2 + name_len])
        p = rec_off + 2 + name_len
        ci = buf[p] | (buf[p + 1] << 8) | (buf[p + 2] << 16)
        pi = buf[p + 3]
        qi = buf[p + 4]
        postal_u32 = _u32(buf, p + 5)
        city = cities[ci] if ci < len(cities) else ""
        province = provinces[pi] if pi < len(provinces) else ""
        qual_mask = (quals[qi] >> 8) if qi < len(quals) else 0
        yield (key, name_blob, city, province, qual_mask, postal_u32)
        rec_off += length


def _canonical_new(item):
    """The canonical comparison tuple for a freshly distilled ``item``
    ``(key, name_blob, city, postal, province, qual_mask)``. Postal is compared
    in its packed form so encoder-equivalent source strings compare equal."""
    return (item[1], item[2], item[4], item[5], _pack_postal(item[3]))


def build_overlay(baseline_buf, new_items, out_path, source_date):
    """Writes an overlay ``.cdb`` containing only the records that are new or
    changed relative to the ``baseline_buf`` (uncompressed baseline bytes).

    The baseline is streamed once via ``iter_cdb_canonical`` and merge-joined
    against the sorted ``new_items`` on the key, so peak memory stays bounded by
    the record set already held for the full build. Deletions (keys present only
    in the baseline) are intentionally not represented. Returns the overlay
    record count.
    """
    baseline = iter_cdb_canonical(baseline_buf)
    b = next(baseline, None)
    overlay = []
    for it in new_items:
        key = it[0]
        while b is not None and b[0] < key:
            b = next(baseline, None)  # baseline-only key => a deletion, ignored
        if b is not None and b[0] == key:
            base_canon = (b[1], b[2], b[3], b[4], b[5])
            if base_canon != _canonical_new(it):
                overlay.append(it)
            b = next(baseline, None)
        else:
            overlay.append(it)  # key absent from the baseline => new record
    # ``overlay`` preserves the ascending-key order of ``new_items``.
    return _write_cdb(overlay, out_path, source_date)


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
    ap.add_argument("--baseline",
                    help="path to the currently published baseline (.cdb or .cdb.xz) to diff "
                         "against; enables overlay/diff output")
    ap.add_argument("--overlay-out",
                    help="overlay database output path (defaults to <out> with an _overlay suffix)")
    ap.add_argument("--current-manifest",
                    help="path to the currently deployed manifest.json; its baseline fields are "
                         "carried forward when the overlay stays below the promote threshold")
    ap.add_argument("--promote-threshold", type=float, default=0.20,
                    help="rebuild a fresh baseline once the overlay grows past this fraction of "
                         "the baseline download size (default 0.20)")
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
        items = _distill_sorted(lines)
        count = _write_cdb(items, args.out, source_date)
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
        version = args.version or _version_from_date(source_date)
        xz_path = args.out + ".xz"
        overlay_out = args.overlay_out or _overlay_path(args.out)
        overlay_xz_path = overlay_out + ".xz"

        # Capture the baseline up front, before the fresh full .xz is written —
        # the workflow may point --baseline at the same path we are about to
        # overwrite, and the diff must see the *previous* baseline.
        baseline_buf = None
        baseline_xz_size = 0
        if args.baseline and os.path.exists(args.baseline):
            baseline_buf, baseline_xz_size = _load_baseline(args.baseline)

        full_xz_bytes = _compress_file(args.out, xz_path)
        full_md5 = hashlib.md5(full_xz_bytes).hexdigest()
        print(f"Wrote {xz_path} ({len(full_xz_bytes):,} bytes, md5 {full_md5})")

        # Decide whether to publish a small overlay on top of the existing
        # baseline, or to promote the freshly built database to a new baseline.
        if baseline_buf is None:
            promote = True
            overlay_count = 0
            print("No baseline provided; promoting the fresh build to baseline.")
        else:
            overlay_count = build_overlay(baseline_buf, items, overlay_out,
                                          source_date)
            overlay_xz_bytes = _compress_file(overlay_out, overlay_xz_path)
            ratio = (len(overlay_xz_bytes) / baseline_xz_size
                     if baseline_xz_size else 1.0)
            promote = ratio > args.promote_threshold
            print(f"Overlay: {overlay_count:,} records, "
                  f"{len(overlay_xz_bytes):,} bytes "
                  f"({ratio:.1%} of the {baseline_xz_size:,}-byte baseline; "
                  f"threshold {args.promote_threshold:.0%}) -> "
                  f"{'PROMOTE' if promote else 'overlay only'}")

        if promote:
            # The new baseline is the freshly built full database, so its overlay
            # is empty by definition. Write and publish that empty overlay so the
            # hosted overlay asset resets alongside the new baseline.
            overlay_count = _write_cdb([], overlay_out, source_date)
            overlay_xz_bytes = _compress_file(overlay_out, overlay_xz_path)
            baseline_obj = {
                "version": version,
                "sourceDate": source_date,
                "url": args.base_url.rstrip("/") + "/" + os.path.basename(xz_path),
                "compressed": True,
                "sizeBytes": len(full_xz_bytes),
                "md5": full_md5,
                "recordCount": count,
            }
        else:
            baseline_obj = _baseline_from_manifest(args.current_manifest)
            if baseline_obj is None:
                raise SystemExit(
                    "overlay stayed below the promote threshold but no valid "
                    "--current-manifest baseline was provided to carry forward")

        overlay_md5 = hashlib.md5(overlay_xz_bytes).hexdigest()
        manifest = {
            "schemaVersion": 2,
            **baseline_obj,
            "overlay": {
                "version": version,
                "sourceDate": source_date,
                "url": args.base_url.rstrip("/") + "/"
                       + os.path.basename(overlay_xz_path),
                "compressed": True,
                "sizeBytes": len(overlay_xz_bytes),
                "md5": overlay_md5,
                "recordCount": overlay_count,
            },
        }
        manifest_path = os.path.join(os.path.dirname(args.out) or ".",
                                     "ised_amateur_manifest.json")
        with open(manifest_path, "w") as f:
            json.dump(manifest, f, indent=2)
        print(f"Wrote {overlay_xz_path} ({len(overlay_xz_bytes):,} bytes, "
              f"md5 {overlay_md5}, {overlay_count:,} records)")
        print(f"Wrote {manifest_path} (schemaVersion 2, "
              f"{'promoted new baseline' if promote else 'overlay update'})")


def _compress_file(src_path, xz_path):
    """xz-compresses ``src_path`` to ``xz_path`` and returns the compressed
    bytes. xz/LZMA embeds no timestamps, so identical input yields a
    byte-identical archive."""
    with open(src_path, "rb") as f:
        raw = f.read()
    xz_bytes = lzma.compress(raw, preset=9 | lzma.PRESET_EXTREME)
    with open(xz_path, "wb") as f:
        f.write(xz_bytes)
    return xz_bytes


def _overlay_path(out_path):
    """Derives the overlay output path from the full database path
    (``ised_amateur.cdb`` -> ``ised_amateur_overlay.cdb``)."""
    root, ext = os.path.splitext(out_path)
    return f"{root}_overlay{ext}"


def _load_baseline(path):
    """Loads a baseline database, returning ``(uncompressed_bytes, xz_size)``.
    ``path`` may be a raw ``.cdb`` or an xz-compressed ``.cdb.xz``; the xz size is
    what the promote-threshold ratio is measured against."""
    with open(path, "rb") as f:
        data = f.read()
    if path.endswith(".xz"):
        return lzma.decompress(data), len(data)
    return data, len(lzma.compress(data, preset=9 | lzma.PRESET_EXTREME))


def _baseline_from_manifest(manifest_path):
    """Extracts the baseline fields from an existing manifest so they can be
    carried forward unchanged when only the overlay is republished. Returns
    ``None`` when the manifest is missing or malformed."""
    if not manifest_path or not os.path.exists(manifest_path):
        return None
    try:
        with open(manifest_path, "r") as f:
            m = json.load(f)
    except (OSError, ValueError):
        return None
    if not m.get("url") or not m.get("sourceDate"):
        return None
    return {
        "version": m.get("version", ""),
        "sourceDate": m["sourceDate"],
        "url": m["url"],
        "compressed": m.get("compressed", True),
        "sizeBytes": m.get("sizeBytes", 0),
        "md5": m.get("md5", ""),
        "recordCount": m.get("recordCount", 0),
    }


if __name__ == "__main__":
    sys.exit(main())
