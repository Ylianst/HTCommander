# Offline Winlink Gateway Directory

HTCommander ships a compact, fully-offline directory of **Winlink 1200-baud packet
and VARA-FM gateways** so a user can find a nearby RMS and the frequency to tune to without
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

The download fetches both `mode=packet` and `mode=varafm` using the public CMS
key embedded in RMSChannels. The existing key works for both feeds; `--key`
can override it if Winlink changes it. JSONP callbacks are unnecessary. Both
requests use `serviceCodes=PUBLIC` and a 168-hour history by default. A failed
request or empty feed aborts the build before publishing a partial directory.

## What we keep

The live feed is large and verbose — every gateway carries comments, status
timestamps, operating hours, antenna type, radio range, grid squares and one or
more channels at various bauds/modes. The builder keeps these fields:

| Field | Source | Notes |
|-------|--------|-------|
| callsign-stationid | `Callsign` | base callsign + AX.25 SSID, e.g. `KG4MRA-10` |
| location | `Latitude` / `Longitude` | for map placement and nearest-gateway search |
| frequency | `GatewayChannels[].Frequency` | one record per distinct station/frequency pair |
| modes | `GatewayChannels[].SupportedModes` / `Baud` | Packet 1200, VARA-FM, or both |

Packet channels require `Baud == "1200"` and `SupportedModes` containing
`Packet`. Both `VARA FM` and `VARA FM WIDE` are retained regardless of the
feed's baud field. Other modes (including VARA HF and packet 9600) are dropped,
as are frequencies outside the existing amateur-band filter.

Stations merge by normalized full callsign **including SSID**, not by base
callsign or proximity. Frequencies merge in 100 Hz units and their mode bits
are OR-ed. Different SSIDs remain separately addressable stations. If duplicate
station entries disagree on coordinates, the lexicographically smallest
quantized `(latitude, longitude)` pair is used consistently for all channels,
making the result independent of feed order.

## Compaction strategy

Each channel becomes a fixed **15-byte** record. Fixed-size, sorted records keep
the format trivial to read and binary-searchable, and the repetition (shared
callsign/location bytes across a gateway's channels) compresses away under xz.

| Bytes | Field | Encoding |
|------:|-------|----------|
| 5 | callsign + SSID | `base37(call) * 16 + ssid`, big-endian u40 |
| 3 | latitude | `round((lat + 90) * 10000)`, big-endian u24 (~11 m) |
| 3 | longitude | `round((lon + 180) * 10000)`, big-endian u24 (~11 m) |
| 3 | frequency | `round(freqHz / 100)`, big-endian u24 (100 Hz units) |
| 1 | modes | bit 0 = Packet 1200, bit 1 = VARA-FM; 3 = both |

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
  4  u16  formatVersion = 2
  6  u16  flags        = 0
  8  u32  recordCount
 12  u32  sourceDate   (YYYYMMDD, UTC)
 16  u32  recordsOffset (= 32)
 20  ...  reserved (zero)

Records: recordCount × 15 bytes, sorted ascending (see table above)
```

Version 2 adds the mode byte at record offset 14. The current Dart reader also
accepts version 1's 14-byte packet-only records, treating them as mode 1. Older
apps cannot read version 2 and must be upgraded. Manifest schema and download
filenames remain unchanged, including the historical `winlink_packet` prefix.

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
stations/locations/frequencies/modes, not on the feed's ever-changing status
timestamps, so the workflow can skip republishing when nothing meaningful moved.

## Rebuilding by hand

```powershell
cd src\tools
python build_winlink_db.py --download `
  --out ..\..\docs\winlink\winlink_packet.wdb `
  --compress `
  --base-url "https://github.com/Ylianst/HTCommander/releases/download/winlink-db/"
```

Or from saved feed responses (`--input packet.json varafm.json`, JSON or JSONP).
The map groups each station into one marker and labels each frequency's modes.
This directory change does not implement or automatically select a modem.
Run the
tests with `python src\tools\test_build_winlink_db.py`.
