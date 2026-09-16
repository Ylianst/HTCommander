# Offline Winlink Packet Gateway Directory

HTCommander ships a tiny, fully-offline directory of **Winlink 1200-baud packet
gateways** so a user can find a nearby RMS and the frequency to tune to without
any Internet access. It is built and published the same way as the
[offline callsign database](Callsign-Country-Data.md): a scheduled GitHub Action
rebuilds a compact binary, uploads it as a rolling-release asset, and commits a
small manifest that the app reads to discover and download the current file.

- **Feed:** `https://cms.winlink.org/gateway/status` (the data behind
  <https://winlink.org/RMSChannels>)
- **Build tool:** `src/tools/build_winlink_db.py`
- **Workflow:** `.github/workflows/deploy-winlink-db.yaml`
- **Manifest (committed / Pages):** `docs/winlink/winlink_packet_manifest.json`
- **Binary (rolling release asset):**
  `releases/download/winlink-db/winlink_packet.wdb.xz`

To be gentle on the Winlink servers the workflow runs only **twice a week**
(Mondays and Thursdays) and on demand, and it skips publishing when the
distilled station set has not changed.

## What we keep (and why the file is ~12 KB)

The live feed is large and verbose — every gateway carries comments, status
timestamps, operating hours, antenna type, radio range, grid squares and one or
more channels at various bauds/modes. HTCommander only supports 1200-baud
VHF/UHF packet, so the builder throws almost all of that away and keeps just the
three things the app needs:

| Field | Source | Notes |
|-------|--------|-------|
| callsign-stationid | `Callsign` | base callsign + AX.25 SSID, e.g. `KG4MRA-10` |
| location | `Latitude` / `Longitude` | for map placement and nearest-gateway search |
| frequency | `GatewayChannels[].Frequency` | one record per distinct 1200 packet channel |

Baud and mode are **implied** — every record is Packet 1200 — so they cost zero
bytes. Channels that are not `Baud == "1200"` + `SupportedModes` containing
`Packet` are dropped, as are frequencies outside the amateur VHF/UHF bands
(the feed carries the odd 101 MHz / 245 MHz test entry).

A recent build distils ~1200 gateways / ~1250 channels into **17.6 KB raw /
12.3 KB xz-compressed**.

## Compaction strategy

Each channel becomes a fixed **14-byte** record. Fixed-size, sorted records keep
the format trivial to read and binary-searchable, and the repetition (shared
callsign/location bytes across a gateway's channels) compresses away under xz.

| Bytes | Field | Encoding |
|------:|-------|----------|
| 5 | callsign + SSID | `base37(call) * 16 + ssid`, big-endian u40 |
| 3 | latitude | `round((lat + 90) * 10000)`, big-endian u24 (~11 m) |
| 3 | longitude | `round((lon + 180) * 10000)`, big-endian u24 (~11 m) |
| 3 | frequency | `round(freqHz / 100)`, big-endian u24 (100 Hz units) |

- **Callsign** — the base callsign (≤ 6 alphanumeric characters) is packed
  base-37 (`A–Z` → 1–26, `0–9` → 27–36), then multiplied by 16 and OR-ed with
  the SSID (0–15). The whole 40-bit key is stored big-endian so a byte-wise sort
  equals a sort by callsign then SSID. SSID 0 is displayed as a bare callsign.
- **Location** — quantised to 1e-4° (~11 m), far finer than a gateway location
  needs, and both offsets keep the value inside a 24-bit field.
- **Frequency** — every real Winlink frequency lands on a 100 Hz boundary, so
  100 Hz units keep it exact while fitting 24 bits.

Big-endian multi-byte fields mean lexicographic byte order equals numeric order,
so the records are simply sorted ascending and can be binary-searched in place.

### File layout (`.wdb`)

All values little-endian in the 32-byte header, big-endian inside records.

```
Header (32 bytes)
  0  u32  magic        = "WLGW"  (0x57474C57)
  4  u16  formatVersion = 1
  6  u16  flags        = 0
  8  u32  recordCount
 12  u32  sourceDate   (YYYYMMDD, UTC)
 16  u32  recordsOffset (= 32)
 20  ...  reserved (zero)

Records: recordCount × 14 bytes, sorted ascending (see table above)
```

### Manifest

```jsonc
{
  "schemaVersion": 1,
  "version": "2026.09.16",   // build date, YYYY.MM.DD
  "sourceDate": 20260916,     // data date, UTC
  "url": ".../winlink-db/winlink_packet.wdb.xz",
  "compressed": true,
  "sizeBytes": 12344,         // compressed download size
  "md5": "…",                // md5 of the download (integrity)
  "recordCount": 1255,        // channel records
  "gatewayCount": 1193,       // distinct stations
  "recordsMd5": "…"          // md5 of the uncompressed records payload
}
```

`recordsMd5` is the change-detection key: it depends only on the distilled
stations/locations/frequencies, not on the feed's ever-changing status
timestamps, so the workflow can skip republishing when nothing meaningful moved.

## Rebuilding by hand

```powershell
cd src\tools
python build_winlink_db.py --download `
  --out ..\..\docs\winlink\winlink_packet.wdb `
  --compress `
  --base-url "https://github.com/Ylianst/HTCommander/releases/download/winlink-db/"
```

Or from a saved feed response (`--input feed.json`, JSON or JSONP). Run the
tests with `python src\tools\test_build_winlink_db.py`.
