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


def _distill_sorted(open_dat):
    """Parses the ULS input into the distilled, key-sorted record set that both
    the full build and the overlay diff consume.

    Each item is ``(key, name_blob, city, zip, state, cs_packed, days)`` and the
    list is sorted ascending by ``key`` (the callsign index key), as the on-disk
    index requires for binary search.
    """
    by_call = _collect_encoded(open_dat)
    items = sorted(by_call.values(), key=lambda it: it[0])
    by_call.clear()
    return items


def _write_cdb(items, out_path, source_date, flags=0):
    """Writes the distilled, **already key-sorted** ``items`` to ``out_path`` as
    a ``.cdb`` file and returns the record count.

    The header, sorted index and record section are streamed to the file without
    a second full-size copy. ``items`` are tuples of
    ``(key, name_blob, city, zip, state, cs_packed, days)``.
    """
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
        struct.pack_into("<H", header, 6, flags & 0xFFFF)
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


def build_streaming(open_dat, out_path, source_date):
    """Builds the full database from a ULS input and writes it to ``out_path``.

    Returns the record count. Kept as the single-call entry point used by the
    from-scratch build; the overlay path reuses ``_distill_sorted`` and
    ``_write_cdb`` directly so it can diff before writing.
    """
    items = _distill_sorted(open_dat)
    return _write_cdb(items, out_path, source_date)


# ── .cdb reader (for overlay diffs) ─────────────────────────────────────────
# A minimal reader that decodes a ``.cdb`` back into canonical logical records,
# used to diff a previously published baseline against a freshly built database.
# It must stay in lock-step with ``_write_cdb`` above.


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
    states = []
    off = hdr["stateOffset"]
    for i in range(hdr["stateCount"]):
        states.append(buf[off + i * 2:off + i * 2 + 2].rstrip(b"\x00")
                      .decode("ascii", "ignore"))
    cs_values = []
    off = hdr["classStatusOffset"]
    for i in range(hdr["classStatusCount"]):
        o = off + i * 2
        cs_values.append((buf[o] << 8) | buf[o + 1])
    cities = []
    off = hdr["cityOffset"]
    for _ in range(hdr["cityCount"]):
        ln = buf[off]
        off += 1
        cities.append(buf[off:off + ln].decode("utf-8"))
        off += ln
    return states, cs_values, cities


def iter_cdb_canonical(buf):
    """Yields one canonical tuple per record, **in ascending key order** (the
    order records are stored in). Each tuple is
    ``(key, name_blob, city, state, cs_packed, zip_u32, days)`` — the same shape
    the diff compares a freshly built record against.
    """
    hdr = read_cdb_header(buf)
    states, cs_values, cities = _read_dicts(buf, hdr)
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
        si = buf[p + 3]
        csi = buf[p + 4]
        zip_u32 = _u32(buf, p + 5)
        days = _u16(buf, p + 9)
        city = cities[ci] if ci < len(cities) else ""
        state = states[si] if si < len(states) else ""
        cs_packed = cs_values[csi] if csi < len(cs_values) else 0
        yield (key, name_blob, city, state, cs_packed, zip_u32, days)
        rec_off += length


def _canonical_new(item):
    """The canonical comparison tuple for a freshly distilled ``item``
    ``(key, name_blob, city, zip, state, cs_packed, days)``. ZIP is compared in
    its packed form so encoder-equivalent source strings compare equal."""
    return (item[1], item[2], item[4], item[5], _pack_zip(item[3]), item[6])


def build_overlay(baseline_buf, new_items, out_path, source_date):
    """Writes an overlay ``.cdb`` containing only the records that are new or
    changed relative to the ``baseline_buf`` (uncompressed baseline bytes).

    ``new_items`` is the distilled, key-sorted record set of the freshly built
    full database. The baseline is streamed once via ``iter_cdb_canonical`` and
    merge-joined against ``new_items`` on the sorted key, so peak memory stays
    bounded by the record set already held for the full build. Deletions
    (keys present only in the baseline) are intentionally not represented.

    Returns the overlay record count.
    """
    baseline = iter_cdb_canonical(baseline_buf)
    b = next(baseline, None)
    overlay = []
    for it in new_items:
        key = it[0]
        while b is not None and b[0] < key:
            b = next(baseline, None)  # baseline-only key => a deletion, ignored
        if b is not None and b[0] == key:
            base_canon = (b[1], b[2], b[3], b[4], b[5], b[6])
            if base_canon != _canonical_new(it):
                overlay.append(it)
            b = next(baseline, None)
        else:
            overlay.append(it)  # key absent from the baseline => new record
    # ``overlay`` preserves the ascending-key order of ``new_items``.
    return _write_cdb(overlay, out_path, source_date)


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
        items = _distill_sorted(opener)
        count = _write_cdb(items, args.out, source_date)
    finally:
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
            # No baseline to diff against (first run): promote immediately.
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
                                     "fcc_amateur_manifest.json")
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
    (``fcc_amateur.cdb`` -> ``fcc_amateur_overlay.cdb``)."""
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
