#!/usr/bin/env python3
# Copyright 2026 Ylian Saint-Hilaire
# Licensed under the Apache License, Version 2.0 (the "License");
# http://www.apache.org/licenses/LICENSE-2.0
#
# Builds the HTCommander offline Winlink packet-gateway database from the
# Winlink CMS gateway-status feed.
#
# HTCommander only supports 1200-baud VHF/UHF packet Winlink gateways, so the
# builder keeps just the fields the app needs to show a gateway on the map and
# let the user tune to it:
#
#   * callsign-stationid  (base callsign + AX.25 SSID, e.g. "KG4MRA-10")
#   * location            (latitude / longitude)
#   * frequency           (Hz; baud/mode are implied — always Packet 1200)
#
# Everything else in the feed (comments, timestamps, operating hours, antenna,
# radio range, grid squares, non-1200/non-packet channels, ...) is discarded.
#
# The output is a compact, sorted, read-only binary file (`.wdb`) that the app
# downloads and reads directly. The layout is documented in
# `docs/Winlink-Gateways.md`; keep the Dart reader in lock-step with it.
#
# Usage:
#   # Download the live PUBLIC packet feed and build the database:
#   python build_winlink_db.py --download --out winlink_packet.wdb --compress
#
#   # Build from a previously saved feed response (JSON or JSONP):
#   python build_winlink_db.py --input feed.json --out winlink_packet.wdb --compress
#
# Outputs alongside --out:
#   <out>       the binary database
#   <out>.xz    xz-compressed database (with --compress; this is what the app downloads)
#   winlink_packet_manifest.json  manifest describing the (compressed) download

import argparse
import datetime
import hashlib
import json
import lzma
import os
import re
import struct
import sys
import urllib.request

# The public CMS gateway-status endpoint used by https://winlink.org/RMSChannels.
# The `key` is the public API key embedded in that page. We omit the JSONP
# `callback` parameter so the endpoint returns plain JSON.
WINLINK_STATUS_URL = "https://cms.winlink.org/gateway/status"
WINLINK_PUBLIC_KEY = "F37B2075C6EF48D19F4886B9A985456E"

# ── binary format constants (see docs/Winlink-Gateways.md) ──────────────────
MAGIC = int.from_bytes(b"WLGW", "little")  # 0x57474C57
FORMAT_VERSION = 1
HEADER_SIZE = 32
RECORD_SIZE = 14  # 5 (callsign+ssid) + 3 (lat) + 3 (lon) + 3 (freq)

# Callsign packing: base-37 over up to 6 characters, then × 16 + SSID (0..15).
CALL_MAX_LEN = 6
MAX_SSID = 15

# Location quantisation: 1e-4 degrees ≈ 11 m, which is far finer than a gateway
# location needs and still leaves every value inside a 24-bit field.
COORD_SCALE = 10000
LAT_OFFSET = 90     # stored value = (lat + 90) * COORD_SCALE  → 0..1_800_000
LON_OFFSET = 180    # stored value = (lon + 180) * COORD_SCALE → 0..3_600_000

# Frequency quantisation: 100 Hz units (every real Winlink frequency lands on a
# 100 Hz boundary) keeps the value inside a 24-bit field up to 1.6 GHz.
FREQ_SCALE = 100

# Amateur bands (Hz) an HT can realistically work FM packet on. Channels whose
# frequency is outside every band are dropped as feed noise (the live feed
# carries the odd 101 MHz / 245 MHz test entry). Disable with --no-band-filter.
AMATEUR_BANDS_HZ = (
    (28_000_000, 29_700_000),    # 10 m
    (50_000_000, 54_000_000),    # 6 m
    (144_000_000, 148_000_000),  # 2 m
    (222_000_000, 225_000_000),  # 1.25 m
    (420_000_000, 450_000_000),  # 70 cm
)


# ── feed parsing ────────────────────────────────────────────────────────────

def build_feed_url(history_hours, key):
    from urllib.parse import urlencode
    params = urlencode({
        "historyHours": history_hours,
        "mode": "packet",
        "serviceCodes": "PUBLIC",
        "format": "json",
        "key": key,
    })
    return f"{WINLINK_STATUS_URL}?{params}"


def download_feed(history_hours, key):
    url = build_feed_url(history_hours, key)
    req = urllib.request.Request(url, headers={"User-Agent": "HTCommander-winlink-db/1"})
    with urllib.request.urlopen(req, timeout=120) as resp:
        return resp.read().decode("utf-8", "replace")


def parse_feed(text):
    """Returns the ``Gateways`` list from a feed response.

    Tolerates a JSONP wrapper (``callback({...})``) in case the endpoint ever
    returns one.
    """
    text = text.strip()
    if not text.startswith("{"):
        m = re.search(r"\(\s*(\{.*\})\s*\)\s*;?\s*$", text, re.DOTALL)
        if not m:
            raise ValueError("could not find a JSON object in the feed response")
        text = m.group(1)
    data = json.loads(text)
    gateways = data.get("Gateways")
    if gateways is None:
        raise ValueError("feed response has no 'Gateways' array")
    return gateways


def _in_amateur_band(freq_hz):
    return any(lo <= freq_hz <= hi for lo, hi in AMATEUR_BANDS_HZ)


def _split_callsign(callsign):
    """Splits ``BASE-SSID`` into (base, ssid). Returns None if it cannot be
    represented (base too long, bad characters or SSID out of range)."""
    base, _, ssid_s = callsign.partition("-")
    base = base.strip().upper()
    if ssid_s:
        if not ssid_s.isdigit():
            return None
        ssid = int(ssid_s)
    else:
        ssid = 0
    if ssid > MAX_SSID:
        return None
    if not (1 <= len(base) <= CALL_MAX_LEN) or not base.isalnum():
        return None
    if not all(("A" <= c <= "Z") or ("0" <= c <= "9") for c in base):
        return None
    return base, ssid


def _encode_call_key(base, ssid):
    key = 0
    for c in base:
        code = (ord(c) - ord("A") + 1) if c.isalpha() else (ord(c) - ord("0") + 27)
        key = key * 37 + code
    return key * 16 + ssid


def distill(gateways, band_filter=True):
    """Turns the raw feed into a sorted, de-duplicated list of records.

    Each record is a ``(call_key, lat_q, lon_q, freq_q)`` tuple. A gateway with
    several 1200-baud packet channels yields one record per distinct frequency.
    Returns ``(records, gateway_count, dropped)``.
    """
    seen = set()
    records = []
    stations = set()
    dropped = {"callsign": 0, "no_channels": 0, "band": 0, "coord": 0}

    for gw in gateways:
        callsign = (gw.get("Callsign") or "").strip()
        split = _split_callsign(callsign)
        if split is None:
            dropped["callsign"] += 1
            continue
        base, ssid = split
        call_key = _encode_call_key(base, ssid)

        lat = gw.get("Latitude")
        lon = gw.get("Longitude")
        if lat is None or lon is None or not (-90 <= lat <= 90) or not (-180 <= lon <= 180):
            dropped["coord"] += 1
            continue
        lat_q = round((lat + LAT_OFFSET) * COORD_SCALE)
        lon_q = round((lon + LON_OFFSET) * COORD_SCALE)

        freqs = []
        for ch in gw.get("GatewayChannels") or []:
            if str(ch.get("Baud")) != "1200":
                continue
            if "packet" not in str(ch.get("SupportedModes", "")).lower():
                continue
            freq = ch.get("Frequency")
            if not isinstance(freq, (int, float)) or freq <= 0:
                continue
            freq = int(round(freq))
            if band_filter and not _in_amateur_band(freq):
                dropped["band"] += 1
                continue
            freqs.append(freq)

        if not freqs:
            dropped["no_channels"] += 1
            continue

        station_has_channel = False
        for freq in freqs:
            freq_q = round(freq / FREQ_SCALE)
            row = (call_key, lat_q, lon_q, freq_q)
            if row in seen:
                continue
            seen.add(row)
            records.append(row)
            station_has_channel = True
        if station_has_channel:
            stations.add(call_key)

    records.sort()
    return records, len(stations), dropped


# ── binary writer ───────────────────────────────────────────────────────────

def pack_records(records):
    """Serialises the sorted record list to the on-disk records payload."""
    buf = bytearray(len(records) * RECORD_SIZE)
    off = 0
    for call_key, lat_q, lon_q, freq_q in records:
        buf[off:off + 5] = call_key.to_bytes(5, "big")
        buf[off + 5:off + 8] = lat_q.to_bytes(3, "big")
        buf[off + 8:off + 11] = lon_q.to_bytes(3, "big")
        buf[off + 11:off + 14] = freq_q.to_bytes(3, "big")
        off += RECORD_SIZE
    return bytes(buf)


def write_wdb(out_path, records, source_date):
    payload = pack_records(records)
    header = bytearray(HEADER_SIZE)
    struct.pack_into("<I", header, 0, MAGIC)
    struct.pack_into("<H", header, 4, FORMAT_VERSION)
    struct.pack_into("<H", header, 6, 0)  # flags
    struct.pack_into("<I", header, 8, len(records))
    struct.pack_into("<I", header, 12, source_date & 0xFFFFFFFF)
    struct.pack_into("<I", header, 16, HEADER_SIZE)  # recordsOffset
    with open(out_path, "wb") as f:
        f.write(header)
        f.write(payload)
    return payload


# ── binary reader (verification / tests) ────────────────────────────────────

def _decode_call_key(call_key):
    ssid = call_key & 0xF
    k = call_key >> 4
    chars = []
    while k > 0:
        code = k % 37
        k //= 37
        if 1 <= code <= 26:
            chars.append(chr(ord("A") + code - 1))
        else:
            chars.append(chr(ord("0") + code - 27))
    base = "".join(reversed(chars))
    return f"{base}-{ssid}" if ssid else base


def read_wdb(buf):
    """Decodes a ``.wdb`` back into ``(callsign, lat, lon, freq_hz)`` tuples."""
    if len(buf) < HEADER_SIZE or struct.unpack_from("<I", buf, 0)[0] != MAGIC:
        raise ValueError("not a Winlink gateway database (bad magic)")
    version = struct.unpack_from("<H", buf, 4)[0]
    if version != FORMAT_VERSION:
        raise ValueError(f"unsupported .wdb version {version}")
    count = struct.unpack_from("<I", buf, 8)[0]
    off = struct.unpack_from("<I", buf, 16)[0]
    out = []
    for _ in range(count):
        call_key = int.from_bytes(buf[off:off + 5], "big")
        lat_q = int.from_bytes(buf[off + 5:off + 8], "big")
        lon_q = int.from_bytes(buf[off + 8:off + 11], "big")
        freq_q = int.from_bytes(buf[off + 11:off + 14], "big")
        off += RECORD_SIZE
        out.append((
            _decode_call_key(call_key),
            lat_q / COORD_SCALE - LAT_OFFSET,
            lon_q / COORD_SCALE - LON_OFFSET,
            freq_q * FREQ_SCALE,
        ))
    return out


# ── driver ──────────────────────────────────────────────────────────────────

def main(argv=None):
    ap = argparse.ArgumentParser(description="Build the offline Winlink packet-gateway database.")
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--download", action="store_true",
                     help="Download the live PUBLIC packet feed from the Winlink CMS.")
    src.add_argument("--input", help="Read a saved feed response (JSON or JSONP) instead.")
    ap.add_argument("--history-hours", type=int, default=168,
                    help="Include gateways heard within this many hours (download only; default 168).")
    ap.add_argument("--key", default=WINLINK_PUBLIC_KEY, help="Winlink CMS API key.")
    ap.add_argument("--out", required=True, help="Output .wdb path.")
    ap.add_argument("--compress", action="store_true", help="Also write an xz-compressed .wdb.xz.")
    ap.add_argument("--no-band-filter", action="store_true",
                    help="Keep frequencies outside the amateur VHF/UHF bands.")
    ap.add_argument("--source-date", type=int, default=None,
                    help="Data date as YYYYMMDD (defaults to today, UTC).")
    ap.add_argument("--manifest", default=None,
                    help="Manifest path (defaults to winlink_packet_manifest.json next to --out).")
    ap.add_argument("--base-url", default="",
                    help="Base URL the compressed download is published under (for the manifest).")
    args = ap.parse_args(argv)

    if args.download:
        text = download_feed(args.history_hours, args.key)
    else:
        with open(args.input, "r", encoding="utf-8", errors="replace") as f:
            text = f.read()

    gateways = parse_feed(text)
    records, gateway_count, dropped = distill(gateways, band_filter=not args.no_band_filter)
    if not records:
        print("Refusing to write an empty database (feed parsing produced no records).", file=sys.stderr)
        return 2

    source_date = args.source_date or int(datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d"))
    payload = write_wdb(args.out, records, source_date)
    records_md5 = hashlib.md5(payload).hexdigest()

    download_path = args.out
    compressed = False
    if args.compress:
        download_path = args.out + ".xz"
        with open(args.out, "rb") as fin, open(download_path, "wb") as fout:
            fout.write(lzma.compress(fin.read(), preset=9 | lzma.PRESET_EXTREME))
        compressed = True

    size_bytes = os.path.getsize(download_path)
    with open(download_path, "rb") as f:
        file_md5 = hashlib.md5(f.read()).hexdigest()

    version = datetime.datetime.strptime(str(source_date), "%Y%m%d").strftime("%Y.%m.%d")
    url = (args.base_url + os.path.basename(download_path)) if args.base_url else os.path.basename(download_path)
    manifest = {
        "schemaVersion": 1,
        "version": version,
        "sourceDate": source_date,
        "url": url,
        "compressed": compressed,
        "sizeBytes": size_bytes,
        "md5": file_md5,
        "recordCount": len(records),
        "gatewayCount": gateway_count,
        "recordsMd5": records_md5,
    }
    manifest_path = args.manifest or os.path.join(os.path.dirname(args.out) or ".",
                                                  "winlink_packet_manifest.json")
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")

    print(f"Gateways: {gateway_count}  Channels/records: {len(records)}")
    print(f"Dropped: {dropped}")
    print(f"Uncompressed: {os.path.getsize(args.out)} bytes  "
          f"Download ({'xz' if compressed else 'raw'}): {size_bytes} bytes")
    print(f"records md5: {records_md5}")
    print(f"Wrote {args.out} and {manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
