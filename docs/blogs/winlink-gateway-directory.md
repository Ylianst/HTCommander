# Every Winlink Gateway in 12 KB: An Offline RMS Directory

*How HTCommander pulls the live Winlink gateway list twice a week, boils each
station down to three facts, and ships the whole world's packet RMS network as a
file smaller than this blog post — then reads it back to drop gateways on the
map.*

---

## The problem

Winlink lets hams pass email over radio, and the on-ramp is a **gateway** (an
RMS — Radio Mail Server): another station listening on a known frequency that
relays your message into the Winlink network. To use one you need three things:
its **callsign**, its **location** (is it in range?), and its **frequency**.

Winlink publishes all of this at [winlink.org/RMSChannels](https://winlink.org/RMSChannels),
backed by a JSON feed from the CMS. That feed is perfect for a live web page and
wrong for a handheld in the field: it is large, verbose, and — worst of all —
*online*. The whole point of packet Winlink is to work where there is no
Internet.

So HTCommander ships an **offline directory**: download it once (over any
connection you happen to have), and from then on the app can show you nearby
gateways and their frequencies on the map with the network unplugged. The design
has two jobs, the same two as the [offline callsign
database](fcc-callsign-compaction.md):

1. **Be tiny** — so the download is painless and the file is trivial to cache.
2. **Cost the Winlink servers almost nothing** — one scheduled fetch, not one
   per user.

Everything below follows from those goals. The builder is
[`build_winlink_db.py`](../../src/tools/build_winlink_db.py); the reader is
[`winlink_gateway_database.dart`](../../src/lib/winlink/winlink_gateway_database.dart);
they must agree on every byte, and a Python↔Dart round-trip test keeps them
honest.

## What the feed gives us, and what we throw away

A single gateway in the feed looks like this (trimmed):

```json
{
  "Callsign": "KG4MRA-10",
  "BaseCallsign": "KG4MRA",
  "Latitude": 37.5688421,
  "Longitude": -77.4663340,
  "HoursSinceStatus": 0,
  "LastStatus": "Wed, 16 Sep 2026 21:49:00 UTC",
  "Comments": "Metropolitan Repeater Association",
  "RequestedMode": "Packet",
  "GatewayChannels": [
    {
      "SupportedModes": "Packet 1200",
      "Baud": "1200",
      "Frequency": 145030000,
      "Gridsquare": "FM17GN",
      "OperatingHours": "00-23",
      "RadioRange": "11",
      "Antenna": "Omni",
      "ServiceCode": "PUBLIC"
    }
  ]
}
```

HTCommander only supports **1200-baud VHF/UHF packet**, so the builder keeps just
what the app actually uses and discards the rest:

| Field | Source | Notes |
|-------|--------|-------|
| callsign-stationid | `Callsign` | base call + AX.25 SSID, e.g. `KG4MRA-10` |
| location | `Latitude` / `Longitude` | map placement, nearest-gateway search |
| frequency | `GatewayChannels[].Frequency` | one record per distinct 1200 packet channel |

Everything else — comments, timestamps, operating hours, antenna, radio range,
grid squares, service code, and every non-1200/non-packet channel — is dropped.
Crucially, **baud and mode are implied**: every record is Packet 1200, so those
fields cost *zero* bytes. Channels are filtered on `Baud == "1200"` and a
`SupportedModes` that contains `Packet`, and frequencies outside the amateur
VHF/UHF bands are discarded as feed noise (the live feed carries the occasional
101 MHz or 245 MHz test entry).

A recent build distils **~1,190 gateways / ~1,250 channels** down to **17.6 KB
raw, 12.3 KB compressed**.

## The compaction strategy

Each channel becomes a fixed **14-byte record**. Fixed-size, sorted records keep
the format trivial to read and binary-searchable, and the repetition (a
gateway's callsign and location repeated across its channels) is exactly what the
whole-file compressor eats for lunch.

| Bytes | Field | Encoding |
|------:|-------|----------|
| 5 | callsign + SSID | `base37(call) × 16 + ssid`, big-endian u40 |
| 3 | latitude | `round((lat + 90) × 10000)`, big-endian u24 |
| 3 | longitude | `round((lon + 180) × 10000)`, big-endian u24 |
| 3 | frequency | `round(freqHz / 100)`, big-endian u24 |

### Trick 1: pack the callsign *and* the SSID into one integer

An amateur base callsign is at most six characters from a 36-symbol alphabet
(`A–Z`, `0–9`). Packing it base-37 (reserving 0 as a "no character" value) fits
in 32 bits: `37⁶ = 2,565,726,409 < 2³²`. The AX.25 SSID is 0–15 — four bits. Rather
than spend a whole extra byte on it, we fold it into the low nibble:

```
key = 0
for c in base:            # 'A'..'Z' -> 1..26, '0'..'9' -> 27..36
    key = key * 37 + code(c)
callKey = key * 16 + ssid  # 0..15
```

That is at most `2.57e9 × 16 + 15 ≈ 4.1e10`, which lives comfortably in **5
bytes** (40 bits). Store it **big-endian** and a byte-wise sort of the records is
a sort by callsign, then SSID — so the file is already an ordered index you can
binary-search. SSID 0 is displayed as a bare callsign (`KH6UU`), not `KH6UU-0`.

### Trick 2: coordinates as scaled integers

A gateway does not move, and you are choosing which station to call — you do not
need survey-grade precision. Quantising each coordinate to **1e-4 degrees**
(~11 metres) is far finer than necessary and keeps both values inside a 24-bit
field:

- `latQ = round((lat + 90) × 10000)` → `0 … 1,800,000` (fits in 21 bits)
- `lonQ = round((lon + 180) × 10000)` → `0 … 3,600,000` (fits in 22 bits)

Three bytes each, big-endian, and lexicographic order still equals numeric order.

### Trick 3: frequency in 100 Hz units

Frequencies arrive as Hz (`145030000`). Every real Winlink frequency lands on a
100 Hz boundary — even the oddballs like `430987500` — so dividing by 100 is
lossless and shrinks a value that would need 29 bits as raw Hz down to 23:
`470 MHz / 100 = 4,700,000 < 2²⁴`. Another three bytes.

### Trick 4: xz for the download

Everything above shrinks the *uncompressed* file to 14 bytes per channel. The
**download** gets one more lever: xz/LZMA over the whole thing. Because a
gateway's five callsign bytes and six location bytes repeat verbatim across its
channels, and neighbouring gateways share frequency and prefix patterns, xz finds
plenty to squeeze — 17.6 KB becomes 12.3 KB. The app already depends on the
`archive` package (an `XZDecoder` one-liner), and the builder writes the stream
with Python's stdlib `lzma`, so identical input produces a byte-identical
archive.

## The pipeline: a robot, twice a week

We must never point thousands of app installs at the Winlink CMS. Instead a
single **GitHub Action**
([`deploy-winlink-db.yaml`](../../.github/workflows/deploy-winlink-db.yaml)) does
the fetching for everyone:

```
Winlink CMS feed  ──(Mon & Thu)──►  build_winlink_db.py
                                          │  distil + pack + xz
                                          ▼
              ┌───────────────────────────┴───────────────────────┐
              ▼                                                     ▼
   winlink_packet.wdb.xz                          winlink_packet_manifest.json
   (rolling GitHub Release asset)                 (committed → GitHub Pages)
```

The binary goes to a **rolling release** so it never bloats git history; only a
tiny JSON **manifest** — pointing at that asset, with the version, size, MD5, and
counts — is committed and served from GitHub Pages. The app reads the manifest
first, then downloads the asset if it is newer.

The clever bit is **change detection**. The feed's status timestamps churn every
few minutes, but the *directory* — who is a gateway, where, on what frequency —
barely changes day to day. So the manifest carries a `recordsMd5`: the MD5 of the
uncompressed **records payload only**. The workflow rebuilds, compares the new
`recordsMd5` against the committed one, and if nothing meaningful moved it skips
the release upload, the commit, and the Pages deploy entirely. Two runs a week
that usually do nothing is exactly the load profile we want.

## Using it in the app

On the Dart side the file is tiny enough to skip binary search altogether:
[`WinlinkGatewayDatabase.fromBytes`](../../src/lib/winlink/winlink_gateway_database.dart)
parses the whole thing into memory and **groups** the sorted records — because a
station's channels are contiguous (same callsign key) — into one
`WinlinkGateway` per callsign carrying all of its frequencies. Decoding the
callsign key just runs the packing in reverse:

```dart
final ssid = callKey & 0xF;
var k = callKey >> 4;
// pop base-37 digits off k to rebuild 'KG4MRA', then append '-10' if ssid != 0
```

[`WinlinkGatewayService`](../../src/lib/services/winlink_gateway_service.dart)
manages the lifecycle the same way the callsign service does: load the cached
file at startup, and (opt-in) refresh in the background over Wi-Fi/wired
connections only, throttled to once every few days and gated on the same
`recordsMd5` so an unchanged directory is never re-downloaded. Downloads reuse
the bundled-Mozilla-CA-roots TLS fallback, so an outdated OS trust store can't
silently break the fetch. You can trigger a download or flip on
auto-update from **Settings → Winlink**.

Once loaded, the Map tab draws the gateways behind a **Show Winlink Gateways**
toggle. Rendering ~1,200 pins at once would be wasteful, so the layer is
**viewport-culled** — `withinBounds` returns only the stations inside the current
camera rectangle — gated to zoom level 6 and up, and capped at 400 markers. Tap
one and you get its callsign and the list of frequencies to tune to.

## The format, precisely

For anyone implementing a reader, here is the whole v1 layout. The header is
little-endian; the multi-byte fields inside each record are big-endian.

**Header (32 bytes):**

| Off | Type | Field |
|----:|------|-------|
| 0  | u32 | magic `0x57474C57` ("WLGW") |
| 4  | u16 | formatVersion = 1 |
| 6  | u16 | flags (reserved) |
| 8  | u32 | recordCount |
| 12 | u32 | sourceDate (`YYYYMMDD`, UTC) |
| 16 | u32 | recordsOffset (= 32) |
| 20 | …  | reserved (zero) to byte 32 |

**Records** — `recordCount` × 14 bytes, sorted ascending:

| Off | Type | Field |
|----:|------|-------|
| 0  | u40 BE | `base37(callsign) × 16 + ssid` |
| 5  | u24 BE | `round((lat + 90) × 10000)` |
| 8  | u24 BE | `round((lon + 180) × 10000)` |
| 11 | u24 BE | `round(freqHz / 100)` |

**Manifest (JSON):**

| Field | Meaning |
|-------|---------|
| `version` / `sourceDate` | build date / data date |
| `url`, `compressed`, `sizeBytes`, `md5` | the download and its integrity check |
| `recordCount` / `gatewayCount` | channel rows / distinct stations |
| `recordsMd5` | MD5 of the uncompressed records payload (change-detection key) |

## The ledger

- **Input:** the live Winlink CMS PUBLIC packet feed (hundreds of KB of JSON).
- **Output:** a 14-byte-per-channel binary — **~17.6 KB raw, ~12.3 KB xz** for
  the whole world's 1200-baud packet RMS network.
- **Cost to Winlink:** one scheduled fetch, twice a week, that usually publishes
  nothing because the station set didn't change.
- **Cost to the user:** a ~12 KB download, cached, then pure-offline map lookups.

Not bad for a directory you can carry into a field with no cell signal — which is
exactly where you'd want to reach a Winlink gateway in the first place.

**Related:** [Compacting the FCC Callsign Database](fcc-callsign-compaction.md) ·
[Offline Winlink Gateway Directory](../Winlink-Gateways.md) ·
[`build_winlink_db.py`](../../src/tools/build_winlink_db.py) ·
[`winlink_gateway_database.dart`](../../src/lib/winlink/winlink_gateway_database.dart)
