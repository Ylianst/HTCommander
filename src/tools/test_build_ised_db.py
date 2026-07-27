#!/usr/bin/env python3
# Copyright 2026 Ylian Saint-Hilaire
# Licensed under the Apache License, Version 2.0 (the "License");
# http://www.apache.org/licenses/LICENSE-2.0
#
# Tests for the .cdb reader and the overlay/diff pipeline in build_ised_db.py.
#
# Runs standalone (``python src/tools/test_build_ised_db.py``) or under pytest.

import json
import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_ised_db as b  # noqa: E402

BUILDER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "build_ised_db.py")


def _item(call, name, city, postal, province, qual_mask):
    return (
        b._pack_key(call),
        b._encode_name(name),
        city,
        postal,
        province,
        qual_mask,
    )


def _sorted(items):
    return sorted(items, key=lambda x: x[0])


# ── unit-level: reader + overlay ────────────────────────────────────────────

def test_reader_round_trip():
    items = _sorted([
        _item("VE3ABC", "JOHN DOE", "TORONTO", "M5V3L9", "ON", b.QUAL_BASIC),
        _item("VA7XYZ", "JANE ROE", "VANCOUVER", "V6B1A1", "BC",
              b.QUAL_BASIC | b.QUAL_ADVANCED),
        _item("VE1QQQ", "SAM SMITH", "HALIFAX", "", "NS", 0),
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
        assert (rb[1], rb[2], rb[3], rb[4], rb[5]) == b._canonical_new(it)


def test_overlay_captures_new_and_changed_only():
    base = _sorted([
        _item("VE3ABC", "JOHN DOE", "TORONTO", "M5V3L9", "ON", b.QUAL_BASIC),
        _item("VA7XYZ", "JANE ROE", "VANCOUVER", "V6B1A1", "BC", b.QUAL_BASIC),
        _item("VE1QQQ", "SAM SMITH", "HALIFAX", "", "NS", 0),
    ])
    new = _sorted([
        _item("VE3ABC", "JOHN DOE", "TORONTO", "M5V3L9", "ON", b.QUAL_BASIC),
        # VA7XYZ upgrades qualifications:
        _item("VA7XYZ", "JANE ROE", "VANCOUVER", "V6B1A1", "BC",
              b.QUAL_BASIC | b.QUAL_ADVANCED),
        _item("VE1QQQ", "SAM SMITH", "HALIFAX", "", "NS", 0),
        # new record:
        _item("VE9NEW", "NEW HAM", "MONCTON", "E1C1A1", "NB", b.QUAL_BASIC),
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
    assert ov_keys == {b._pack_key("VA7XYZ"), b._pack_key("VE9NEW")}


def test_overlay_is_empty_for_identical_inputs():
    items = _sorted([
        _item("VE3ABC", "JOHN DOE", "TORONTO", "M5V3L9", "ON", b.QUAL_BASIC),
        _item("VA7XYZ", "JANE ROE", "VANCOUVER", "V6B1A1", "BC", b.QUAL_BASIC),
    ])
    with tempfile.TemporaryDirectory() as d:
        base_path = os.path.join(d, "base.cdb")
        ov_path = os.path.join(d, "ov.cdb")
        b._write_cdb(items, base_path, 20260101)
        with open(base_path, "rb") as f:
            base_buf = f.read()
        assert b.build_overlay(base_buf, items, ov_path, 20260101) == 0


# ── CLI-level: promote vs overlay-only + manifest v2 ────────────────────────

HEADER = ("callsign;first_name;surname;;city;prov;postal;"
          "qual_a;qual_b;qual_c;qual_d;qual_e;club;club2;;clubcity;clubprov;clubpostal")


def _row(call, first, surname, city, prov, postal, quals):
    c = [""] * 18
    c[0], c[1], c[2] = call, first, surname
    c[4], c[5], c[6] = city, prov, postal
    if "A" in quals:
        c[7] = "X"
    if "D" in quals:
        c[10] = "X"
    return ";".join(c)


def _write_txt(path, rows):
    with open(path, "w", encoding="utf-8") as f:
        f.write(HEADER + "\n")
        for r in rows:
            f.write(r + "\n")


def _run(txt, out, source_date, baseline=None, manifest=None, threshold=0.20):
    cmd = [sys.executable, BUILDER, "--txt-file", txt, "--out", out,
           "--compress", "--source-date", str(source_date),
           "--base-url", "http://x/", "--promote-threshold", str(threshold)]
    if baseline:
        cmd += ["--baseline", baseline]
    if manifest:
        cmd += ["--current-manifest", manifest]
    subprocess.run(cmd, check=True, capture_output=True, text=True)


def test_cli_promote_then_overlay_then_promote():
    base_rows = [
        _row("VE3ABC", "JOHN", "DOE", "TORONTO", "ON", "M5V3L9", "A"),
        _row("VA7XYZ", "JANE", "ROE", "VANCOUVER", "BC", "V6B1A1", "A"),
        _row("VE1QQQ", "SAM", "SMITH", "HALIFAX", "NS", "", "A"),
    ]
    new_rows = [
        _row("VE3ABC", "JOHN", "DOE", "TORONTO", "ON", "M5V3L9", "A"),
        _row("VA7XYZ", "JANE", "ROE", "VANCOUVER", "BC", "V6B1A1", "AD"),
        _row("VE1QQQ", "SAM", "SMITH", "HALIFAX", "NS", "", "A"),
        _row("VE9NEW", "NEW", "HAM", "MONCTON", "NB", "E1C1A1", "A"),
    ]
    with tempfile.TemporaryDirectory() as d:
        out = os.path.join(d, "ised_amateur.cdb")
        manifest = os.path.join(d, "ised_amateur_manifest.json")

        _write_txt(os.path.join(d, "t1.txt"), base_rows)
        _run(os.path.join(d, "t1.txt"), out, 20260101)
        m = json.load(open(manifest))
        assert m["schemaVersion"] == 2
        assert m["sourceDate"] == 20260101
        assert m["overlay"]["recordCount"] == 0

        _write_txt(os.path.join(d, "t2.txt"), new_rows)
        _run(os.path.join(d, "t2.txt"), out, 20260108,
             baseline=out + ".xz", manifest=manifest, threshold=0.99)
        m = json.load(open(manifest))
        assert m["sourceDate"] == 20260101  # baseline carried forward
        assert m["overlay"]["sourceDate"] == 20260108
        assert m["overlay"]["recordCount"] == 2

        _run(os.path.join(d, "t2.txt"), out, 20260108,
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
