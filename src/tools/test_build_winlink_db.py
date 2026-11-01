#!/usr/bin/env python3
# Copyright 2026 Ylian Saint-Hilaire
# Licensed under the Apache License, Version 2.0 (the "License");
# http://www.apache.org/licenses/LICENSE-2.0
#
# Tests for the Winlink packet-gateway compaction pipeline in build_winlink_db.py.
#
# Runs standalone (``python src/tools/test_build_winlink_db.py``) or under
# pytest (``python -m pytest src/tools/test_build_winlink_db.py``).

import json
import os
import sys
import tempfile
from unittest.mock import patch

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_winlink_db as b  # noqa: E402


def _gateway(callsign, lat, lon, channels):
    return {
        "Callsign": callsign,
        "Latitude": lat,
        "Longitude": lon,
        "GatewayChannels": [
            {"SupportedModes": mode, "Baud": baud, "Frequency": freq}
            for (mode, baud, freq) in channels
        ],
    }


SAMPLE = {
    "Gateways": [
        # A normal 2 m 1200 packet gateway.
        _gateway("KG4MRA-10", 37.5688421, -77.4663340,
                 [("Packet 1200", "1200", 145030000)]),
        # No SSID → treated as SSID 0, displayed without a suffix.
        _gateway("KH6UU", 20.7363082, -156.4659692,
                 [("Packet 1200", "1200", 145090000)]),
        # Multi-frequency gateway: two distinct 1200 packet channels kept, the
        # 9600 channel dropped.
        _gateway("KK6DA-10", 34.1129432, -118.3022661, [
            ("Packet 1200", "1200", 145070000),
            ("Packet 1200", "1200", 431050000),
            ("Packet 9600", "9600", 441075000),
        ]),
        # Out-of-band test junk (101 MHz) → dropped by the band filter.
        _gateway("PH3J-10", 51.9963424, 5.9028851,
                 [("Packet 1200", "1200", 101010000)]),
        # SSID out of range → whole station dropped.
        _gateway("BAD-99", 10.0, 10.0, [("Packet 1200", "1200", 145010000)]),
    ]
}


def _check(cond, msg):
    if not cond:
        raise AssertionError(msg)


def test_distill_and_roundtrip():
    records, gateways, dropped = b.distill(SAMPLE["Gateways"])
    # 3 usable stations: KG4MRA-10 (1), KH6UU (1), KK6DA-10 (2 channels) = 4 rows.
    _check(gateways == 3, f"expected 3 gateways, got {gateways}")
    _check(len(records) == 4, f"expected 4 records, got {len(records)}")
    _check(dropped["band"] == 1, f"expected 1 band drop, got {dropped}")
    _check(dropped["callsign"] == 1, f"expected 1 callsign drop, got {dropped}")

    payload = b.pack_records(records)
    _check(len(payload) == 4 * b.RECORD_SIZE, "payload size mismatch")

    # Serialise a full file and read it back; locations/frequencies must survive
    # the quantisation to within the documented precision.
    import struct
    header = bytearray(b.HEADER_SIZE)
    struct.pack_into("<I", header, 0, b.MAGIC)
    struct.pack_into("<H", header, 4, b.FORMAT_VERSION)
    struct.pack_into("<I", header, 8, len(records))
    struct.pack_into("<I", header, 16, b.HEADER_SIZE)
    decoded = b.read_wdb(bytes(header) + payload)

    by_call = {}
    for call, lat, lon, freq, modes in decoded:
        _check(modes == b.MODE_PACKET, "packet channel lost its mode")
        by_call.setdefault(call, []).append((lat, lon, freq))

    _check("KH6UU" in by_call, "no-SSID callsign lost its bare form")
    _check("KG4MRA-10" in by_call, "KG4MRA-10 missing")
    _check(len(by_call["KK6DA-10"]) == 2, "KK6DA-10 should keep two channels")

    lat, lon, freq = by_call["KG4MRA-10"][0]
    _check(abs(lat - 37.5688421) < 1e-4, f"lat off: {lat}")
    _check(abs(lon - -77.4663340) < 1e-4, f"lon off: {lon}")
    _check(freq == 145030000, f"freq off: {freq}")

    freqs = sorted(f for _, _, f in by_call["KK6DA-10"])
    _check(freqs == [145070000, 431050000], f"KK6DA-10 freqs off: {freqs}")


def test_band_filter_can_be_disabled():
    records, gateways, dropped = b.distill(SAMPLE["Gateways"], band_filter=False)
    # PH3J-10's 101 MHz channel is now kept.
    _check(dropped["band"] == 0, f"band filter should be off: {dropped}")
    _check(gateways == 4, f"expected 4 gateways with filter off, got {gateways}")


def test_merge_modes_per_station_and_frequency():
    feeds = [
        _gateway("KG4MRA-10", 37.5, -77.4, [
            ("Packet 1200", "1200", 145030000),
            ("Packet 9600", "9600", 145050000),
        ]),
        _gateway("KG4MRA-10", 37.5001, -77.4001, [
            ("VARA FM", "0", 145030000),
            ("VARA FM WIDE", "9600", 145070000),
            ("VARA-FM", None, 145070000),
            ("VARA HF", None, 145090000),
        ]),
        _gateway("KH6UU", 20.7, -156.4, [("VARAFM", None, 145090000)]),
    ]
    records, count, _ = b.distill(feeds + feeds)
    _check(count == 2 and len(records) == 3, "stations/frequencies not merged")
    call_key = b._encode_call_key("KG4MRA", 10)
    station = [row for row in records if row[0] == call_key]
    _check([row[4] for row in station] == [3, 2], "channel modes not merged")
    _check(len({row[1:3] for row in station}) == 1, "station locations differ")
    reversed_records, _, _ = b.distill(list(reversed(feeds)))
    _check(records == reversed_records, "merge depends on feed ordering")


def test_feed_urls_select_both_modes():
    from urllib.parse import parse_qs, urlparse
    for mode in ("packet", "varafm"):
        params = parse_qs(urlparse(b.build_feed_url(168, "test", mode)).query)
        _check(params["mode"] == [mode], "wrong feed mode")
        _check(params["serviceCodes"] == ["PUBLIC"], "non-public feed")


def test_download_builds_both_feeds_and_mode_roundtrip():
    vara = {"Gateways": [_gateway("KG4MRA-10", 37.5, -77.4,
                               [("VARA FM WIDE", "9600", 145030000)])]}
    with tempfile.TemporaryDirectory() as directory:
        output = os.path.join(directory, "gateways.wdb")
        with patch.object(b, "download_feed", side_effect=[json.dumps(SAMPLE), json.dumps(vara)]) as download:
            result = b.main(["--download", "--out", output, "--compress"])
        _check(result == 0, "download build failed")
        _check([call.args[2] for call in download.call_args_list] == ["packet", "varafm"],
               "did not download both feeds")
        import lzma
        with open(output + ".xz", "rb") as stream:
            decoded = b.read_wdb(lzma.decompress(stream.read()))
        station = [row for row in decoded if row[0] == "KG4MRA-10"]
        _check(len(station) == 1 and station[0][4] == 3, "merged modes lost in binary")
        with open(os.path.join(directory, "winlink_packet_manifest.json")) as stream:
            manifest = json.load(stream)
        _check(manifest["gatewayCount"] == 3 and manifest["recordCount"] == 4,
               "manifest counts include duplicates")


def test_empty_second_feed_does_not_write_partial_database():
    with tempfile.TemporaryDirectory() as directory:
        output = os.path.join(directory, "gateways.wdb")
        with patch.object(b, "download_feed", side_effect=[json.dumps(SAMPLE), '{"Gateways":[]}']):
            try:
                b.main(["--download", "--out", output])
            except ValueError:
                pass
            else:
                raise AssertionError("empty VARA-FM feed should abort the build")
        _check(not os.path.exists(output), "partial packet-only database written")


def test_jsonp_wrapper_is_stripped():
    text = "jQuery123_456(" + json.dumps(SAMPLE) + ");"
    gws = b.parse_feed(text)
    _check(len(gws) == len(SAMPLE["Gateways"]), "JSONP unwrap changed the count")


def test_deterministic_records_md5():
    r1, _, _ = b.distill(SAMPLE["Gateways"])
    r2, _, _ = b.distill(list(reversed(SAMPLE["Gateways"])))
    import hashlib
    _check(hashlib.md5(b.pack_records(r1)).hexdigest()
           == hashlib.md5(b.pack_records(r2)).hexdigest(),
           "records payload must be independent of feed order")


def _run_all():
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
            print(f"ok  {name}")
    print("all tests passed")


if __name__ == "__main__":
    _run_all()
