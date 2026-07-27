#!/usr/bin/env python3
# Copyright 2026 Ylian Saint-Hilaire
# Licensed under the Apache License, Version 2.0 (the "License");
# http://www.apache.org/licenses/LICENSE-2.0
#
# Tests for the .cdb reader and the overlay/diff pipeline in build_fcc_db.py.
#
# Runs standalone (``python src/tools/test_build_fcc_db.py``) or under pytest
# (``python -m pytest src/tools/test_build_fcc_db.py``).

import json
import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_fcc_db as b  # noqa: E402

BUILDER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "build_fcc_db.py")


def _item(call, name, city, zipc, state, opclass, status, expire):
    return (
        b._pack_key(call),
        b._encode_name(name),
        city,
        zipc,
        state,
        b._pack_cs(opclass, status),
        b._date_to_days(expire),
    )


def _base_canon(rec):
    # Canonical tuple as read back from a .cdb record (drop the leading key).
    return (rec[1], rec[2], rec[3], rec[4], rec[5], rec[6])


def _sorted_items(items):
    return sorted(items, key=lambda x: x[0])


# ── unit-level: reader + overlay ────────────────────────────────────────────

def test_reader_round_trip():
    items = _sorted_items([
        _item("W1AW", "ARRL HQ", "NEWINGTON", "06111", "CT", "E", "A", 20301231),
        _item("K7VZT", "DOE JOHN", "SEATTLE", "98101", "WA", "G", "A", 20281115),
        _item("AB1CDE", "SMITH JANE", "BOSTON", "02108", "MA", "T", "A", 0),
        _item("N0CALL", "TEST STATION", "", "", "", "N", "E", 0),
    ])
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, "x.cdb")
        b._write_cdb(items, path, 20260101)
        with open(path, "rb") as f:
            buf = f.read()
        read_back = list(b.iter_cdb_canonical(buf))
    assert len(read_back) == len(items)
    for it, rb in zip(items, read_back):
        assert rb[0] == it[0]
        assert _base_canon(rb) == b._canonical_new(it)


def test_overlay_captures_new_and_changed_only():
    base = _sorted_items([
        _item("W1AW", "ARRL HQ", "NEWINGTON", "06111", "CT", "E", "A", 20301231),
        _item("K7VZT", "DOE JOHN", "SEATTLE", "98101", "WA", "G", "A", 20281115),
        _item("AB1CDE", "SMITH JANE", "BOSTON", "02108", "MA", "T", "A", 0),
        _item("N0CALL", "TEST STATION", "", "", "", "N", "E", 0),
    ])
    new = _sorted_items([
        _item("W1AW", "ARRL HQ", "NEWINGTON", "06111", "CT", "E", "A", 20301231),
        _item("K7VZT", "DOE JOHN", "TACOMA", "98402", "WA", "G", "A", 20281115),
        _item("AB1CDE", "SMITH JANE", "BOSTON", "02108", "MA", "T", "A", 0),
        _item("W9NEW", "NEW HAM", "CHICAGO", "60601", "IL", "T", "A", 20350101),
    ])
    with tempfile.TemporaryDirectory() as d:
        base_path = os.path.join(d, "base.cdb")
        ov_path = os.path.join(d, "ov.cdb")
        b._write_cdb(base, base_path, 20260101)
        with open(base_path, "rb") as f:
            base_buf = f.read()
        count = b.build_overlay(base_buf, new, ov_path, 20260108)
        with open(ov_path, "rb") as f:
            ov_buf = f.read()

    ov_keys = {r[0] for r in b.iter_cdb_canonical(ov_buf)}
    assert count == 2
    assert ov_keys == {b._pack_key("K7VZT"), b._pack_key("W9NEW")}

    # Overlay applied over the baseline reproduces `new` for every key in `new`.
    merged = {r[0]: r for r in b.iter_cdb_canonical(base_buf)}
    for r in b.iter_cdb_canonical(ov_buf):
        merged[r[0]] = r
    for it in new:
        assert _base_canon(merged[it[0]]) == b._canonical_new(it)


def test_overlay_is_empty_for_identical_inputs():
    items = _sorted_items([
        _item("W1AW", "ARRL HQ", "NEWINGTON", "06111", "CT", "E", "A", 20301231),
        _item("K7VZT", "DOE JOHN", "SEATTLE", "98101", "WA", "G", "A", 20281115),
    ])
    with tempfile.TemporaryDirectory() as d:
        base_path = os.path.join(d, "base.cdb")
        ov_path = os.path.join(d, "ov.cdb")
        b._write_cdb(items, base_path, 20260101)
        with open(base_path, "rb") as f:
            base_buf = f.read()
        assert b.build_overlay(base_buf, items, ov_path, 20260101) == 0


# ── CLI-level: promote vs overlay-only + manifest v2 ────────────────────────

def _hd(uid, call, status, expire):
    c = [""] * 9
    c[0], c[1], c[4], c[5], c[8] = "HD", uid, call, status, expire
    return "|".join(c)


def _en(uid, call, first, last, city, state, zipc):
    c = [""] * 19
    c[0], c[1], c[4] = "EN", uid, call
    c[8], c[10], c[16], c[17], c[18] = first, last, city, state, zipc
    return "|".join(c)


def _am(uid, opclass):
    c = [""] * 6
    c[0], c[1], c[5] = "AM", uid, opclass
    return "|".join(c)


def _write_uls(path, rows):
    os.makedirs(path, exist_ok=True)
    hd, en, am = [], [], []
    for uid, call, status, expire, first, last, city, state, zipc, cls in rows:
        hd.append(_hd(uid, call, status, expire))
        en.append(_en(uid, call, first, last, city, state, zipc))
        am.append(_am(uid, cls))
    for name, lines in (("HD.dat", hd), ("EN.dat", en), ("AM.dat", am)):
        with open(os.path.join(path, name), "w", encoding="latin-1") as f:
            f.write("\n".join(lines) + "\n")


def _run(uls_dir, out, source_date, baseline=None, manifest=None, threshold=0.20):
    cmd = [sys.executable, BUILDER, "--uls-dir", uls_dir, "--out", out,
           "--compress", "--source-date", str(source_date),
           "--base-url", "http://x/", "--promote-threshold", str(threshold)]
    if baseline:
        cmd += ["--baseline", baseline]
    if manifest:
        cmd += ["--current-manifest", manifest]
    subprocess.run(cmd, check=True, capture_output=True, text=True)


def test_cli_promote_then_overlay_then_promote():
    base_rows = [
        ("1", "W1AW", "A", "12/31/2030", "", "ARRL", "NEWINGTON", "CT", "06111", "E"),
        ("2", "K7VZT", "A", "11/15/2028", "JOHN", "DOE", "SEATTLE", "WA", "98101", "G"),
        ("3", "AB1CDE", "A", "", "JANE", "SMITH", "BOSTON", "MA", "02108", "T"),
    ]
    new_rows = base_rows[:2] + [
        ("2", "K7VZT", "A", "11/15/2028", "JOHN", "DOE", "TACOMA", "WA", "98402", "G"),
        ("3", "AB1CDE", "A", "", "JANE", "SMITH", "BOSTON", "MA", "02108", "T"),
        ("4", "W9NEW", "A", "01/01/2035", "NEW", "HAM", "CHICAGO", "IL", "60601", "T"),
    ]
    # de-dup rows on uid (last wins) to mimic real ULS shape
    new_rows = list({r[0]: r for r in new_rows}.values())

    with tempfile.TemporaryDirectory() as d:
        out = os.path.join(d, "fcc_amateur.cdb")
        manifest = os.path.join(d, "fcc_amateur_manifest.json")

        _write_uls(os.path.join(d, "uls1"), base_rows)
        _run(os.path.join(d, "uls1"), out, 20260101)
        m = json.load(open(manifest))
        assert m["schemaVersion"] == 2
        assert m["sourceDate"] == 20260101
        assert m["overlay"]["recordCount"] == 0
        assert m["overlay"]["sourceDate"] == 20260101

        _write_uls(os.path.join(d, "uls2"), new_rows)
        _run(os.path.join(d, "uls2"), out, 20260108,
             baseline=out + ".xz", manifest=manifest, threshold=0.99)
        m = json.load(open(manifest))
        assert m["sourceDate"] == 20260101  # baseline carried forward
        assert m["overlay"]["sourceDate"] == 20260108
        assert m["overlay"]["recordCount"] == 2

        _run(os.path.join(d, "uls2"), out, 20260108,
             baseline=out + ".xz", manifest=manifest, threshold=0.0)
        m = json.load(open(manifest))
        assert m["sourceDate"] == 20260108  # promoted
        assert m["overlay"]["recordCount"] == 0


def _main():
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
        print(f"{t.__name__}: OK")
    print(f"ALL OK ({len(tests)} tests)")


if __name__ == "__main__":
    _main()
