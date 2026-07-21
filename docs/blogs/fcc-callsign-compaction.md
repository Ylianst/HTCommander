# 1.6 Million Hams in Your Pocket: Compacting the FCC Callsign Database

*How HTCommander turns the FCC's weekly amateur-license dump into a small,
self-contained file you can binary-search offline — and the pile of encoding
tricks that shrink every record down to the bone.*

---

## The problem

HTCommander can look up any US amateur callsign **offline** — name, license
class, status, city/state/ZIP, expiration — with no server, no SQLite, no
network round-trip. The data comes from the FCC's Universal Licensing System
(ULS): a weekly "complete" amateur dump of pipe-delimited `.dat` files that,
once joined, describes roughly **1.59 million licenses**.

That's a lot of rows to ship to a phone. The naive approaches all disappoint:

- **Bundle a SQLite database** — pulls in a dependency, and the file is large.
- **Ship JSON/CSV** — enormous, slow to parse, and you'd load it all into RAM.
- **Query an online API** — defeats the entire point of *offline* lookup.

So HTCommander uses a purpose-built binary format, the `.cdb` ("Callsign
DataBase"). The design has exactly two jobs:

1. **Be small** — both the download and the on-disk file.
2. **Be searchable in place** — find one callsign out of 1.6 million with a
   handful of reads, without loading the whole thing into memory.

Everything below follows from those two goals. The reader/writer lives in
[`callsign_database.dart`](../../src/lib/callsign/callsign_database.dart); the
offline builder that produces the shipped file is
[`build_fcc_db.py`](../../src/tools/build_fcc_db.py). The two must agree on every
byte, and a round-trip test plus a Python→Dart cross-check keep them honest.

## The shape of a searchable file

The core idea is old and reliable: a **sorted index you binary-search**, next to
a **records section you seek into**.

```
┌───────────────┐
│ Header (64 B) │  magic, counts, section offsets, epoch
├───────────────┤
│ Dictionaries  │  state · class/status · city  (shared lookup tables)
├───────────────┤
│ Keys block    │  one packed key per record, sorted ascending
├───────────────┤
│ Lengths block │  one u16 record length per record
├───────────────┤
│ Records block │  the variable-length record bodies, in key order
└───────────────┘
```

To look up `K7VZT`, we:

1. Pack the callsign into an integer key (more on that below).
2. **Binary-search** the keys block — ~21 comparisons for 1.6 M records.
3. Use the record's position to find its byte offset, then read and decode one
   record body.

Only the keys and a couple of small tables live in memory; the record bodies
stay on disk (or in the downloaded buffer) and are read one at a time. All
multi-byte integers are little-endian unless noted.

## Trick 1: Don't store what you can reconstruct — the callsign

The obvious thing to put in each record is the callsign. But the **index already
contains it** — that's what we binary-search on. Storing it again in the body is
pure duplication.

US amateur callsigns are uppercase `[A-Z0-9]`, six characters or fewer. So the
key *is* the callsign, and the record body omits it entirely. On read we
reconstruct the callsign from the key. That's ~7 bytes/record gone for free.

## Trick 2: Pack the key into base-37

Naively, a key is 8 ASCII bytes (max callsign length, zero-padded). But each
position only ever holds one of 37 things: nothing (padding), a digit `0`–`9`,
or a letter `A`–`Z`. That's a **base-37 digit**.

Eight base-37 digits fit in $37^8 \approx 3.5\times10^{12}$, which needs only 42
bits — so the whole key packs into a **6-byte big-endian integer** instead of 8
bytes.

The clever part is preserving sort order. Binary search needs the packed
integers to sort exactly like the original padded callsigns. We map:

| Symbol      | Code |
|-------------|------|
| padding     | 0    |
| `0`–`9`     | 1–10 |
| `A`–`Z`     | 11–36 |

and place the *real* characters in the **high** digits, so shorter callsigns
(padding in the low digits) sort before longer ones sharing a prefix — the same
result as comparing zero-padded ASCII, because padding (0) is the smallest code.
Store the integer **big-endian** and a plain byte compare on the keys block still
matches integer order. Lookups even get slightly faster: we compare 48-bit ints
instead of walking 8-byte arrays.

```dart
// 'K7VZT' -> value*37 + code, real chars in the high digits, then
// multiply by 37 for each missing character to push padding low.
value = value * 37 + code;   // per character
for (; n < keyChars; n++) value *= 37;   // pad the tail
```

## Trick 3: An index with no offsets

Classic layouts store, per entry, `(key, offset)` — the key to search and the
absolute byte offset of the record. That offset is a `u32`: four bytes × 1.6 M =
~6 MB of pointers.

But the records are written in the **same order as the keys**, back to back. So
we don't need absolute offsets at all — we store each record's **length** as a
`u16` in a separate "lengths block," and reconstruct the offsets by prefix-summing
them once when the file opens. Ten bytes per index entry (`6` key + `2` length…
plus the record itself) instead of twelve, and the length column is far more
compressible than a column of ever-growing absolute offsets.

Splitting keys and lengths into **separate contiguous blocks** (rather than
interleaving them) also helps the compressor: each block is internally
self-similar.

## Trick 4: Dates as 16-bit day counts — with the epoch in the header

License expiration is a date. Stored as `YYYYMMDD` it's a `u32` (4 bytes). But we
don't need absolute precision across all of history — just a few decades around
now. So we store **days since a base date** in a `u16` (2 bytes), where `0` means
"unknown."

The nice touch: the **base date lives in the file header** (`epochDate`), not
hard-coded in the reader. A `u16` day count covers ~179 years, so with a base of
`2000-01-01` the window runs to ~2179. If we ever approach that, a future build
just slides the epoch forward — the reader always honors whatever the header
says. It works "forever" without a format change.

## Trick 5–7: Dictionaries for repetitive fields

Three fields repeat heavily across 1.6 M records. Instead of writing the value in
every record, we write each **distinct** value once in a small dictionary and let
records reference it by a compact index. The dictionaries are built from the data
itself (sorted for reproducible output) and stored in the file, so the reader
never assumes a fixed set — any value the FCC emits is handled.

- **State** — ~60 distinct 2-letter codes. Dictionary of 2-byte entries; each
  record stores a **1-byte** index. (4 bytes → 1.)
- **Class + status** — a handful of single letters each. We pack the *pair*
  `(operatorClass, status)` into one 2-byte dictionary entry and reference it
  with a **single 1-byte** index. (2 bytes → 1, and both fields covered by one
  lookup.)
- **City** — tens of thousands of distinct names, but wildly repetitive
  ("SPRINGFIELD" appears everywhere). A dictionary of `u8 len + UTF-8` names,
  referenced by a **24-bit** index (3 bytes, room for ~16 M cities). This turns a
  ~10-byte inline string into a 3-byte pointer and deduplicates the rest — the
  single biggest raw win.

`name` is deliberately **not** dictionary-encoded: person names are mostly
unique, so a dictionary would buy nothing. It's the one variable-length field
kept inline, and it rides on the whole-file compressor instead.

## Trick 8: ZIP as a number

A ZIP code looks like text but is really an integer: `06111` or a 9-digit
ZIP+4 like `061111234`. We pack it into a fixed **`u32`** (`0xFFFFFFFF` = none),
and reconstruct on read by zero-padding to 5 or 9 digits — the magnitude tells us
which (a 9-digit ZIP is always ≥ 100000). Leading zeros survive the round-trip.
FCC amateur ZIPs are numeric (foreign addresses leave the field blank, which maps
cleanly to the sentinel), so this is lossless in practice, and a fixed-width
number compresses better than a length-prefixed string.

## Trick 9: xz instead of zip for the download

Everything above shrinks the *uncompressed* file. The **download** gets one more
lever: the transport compressor.

The database is overwhelmingly text (names and city dictionary), which compresses
well — but DEFLATE (plain `.zip`) leaves a lot on the table. Switching the
download to **xz/LZMA** typically buys another 25–40% over DEFLATE on this kind of
data. The app already depends on the `archive` package, which ships an
`XZDecoder`, so decoding is a one-liner; the builder writes the stream with
Python's stdlib `lzma`. xz embeds no filenames or timestamps, so identical FCC
input still produces a byte-identical archive.

## The format, precisely

For anyone implementing a reader, here is the whole v2 layout.

**Header (64 bytes):**

| Off | Type | Field |
|----:|------|-------|
| 0  | u32 | magic `0x42444348` ("HCDB") |
| 4  | u16 | formatVersion = 2 |
| 6  | u16 | flags (reserved) |
| 8  | u32 | recordCount |
| 12 | u32 | keysOffset |
| 16 | u32 | lengthsOffset |
| 20 | u32 | recordsOffset |
| 24 | u32 | sourceDate (`YYYYMMDD`, FCC data date) |
| 28 | u32 | epochDate (`YYYYMMDD`, base for expire day counts) |
| 32 | u16 | stateCount |
| 34 | u16 | classStatusCount |
| 36 | u32 | stateOffset |
| 40 | u32 | classStatusOffset |
| 44 | u32 | cityCount |
| 48 | u32 | cityOffset |
| 52 | …  | reserved (zero) to byte 64 |

**Sections, in file order:**

- **State dictionary** — `stateCount` × 2 bytes (ASCII, zero-padded).
- **Class/status dictionary** — `classStatusCount` × 2 bytes: `[classByte,
  statusByte]` (0 = empty).
- **City dictionary** — `cityCount` entries of `u8 len + UTF-8`.
- **Keys block** — `recordCount` × 6-byte big-endian packed base-37 keys,
  sorted ascending.
- **Lengths block** — `recordCount` × `u16` record byte-lengths.
- **Records block** — the bodies, in key order.

**Record body:**

| Type | Field |
|------|-------|
| u16 len + UTF-8 | name |
| u24 | cityIndex → city dictionary |
| u8  | stateIndex → state dictionary |
| u8  | csIndex → class/status dictionary |
| u32 | zip (packed numeric; `0xFFFFFFFF` = none) |
| u16 | expireDate (days since `epochDate`; `0` = unknown) |

The callsign is **not** in the body — it's reconstructed from the key.

## Where the bytes went

Field by field, a typical record shrinks dramatically versus a first-cut
"just write everything" layout:

| Field | Before | After |
|-------|-------:|------:|
| callsign | ~7 B | **0** (from the key) |
| index key | 8 B | **6 B** (base-37) |
| index offset/length | 4 B | **2 B** (length + prefix sum) |
| city | ~10 B | **3 B** (dictionary) |
| state | 4 B | **1 B** (dictionary) |
| class + status | 2 B | **1 B** (packed pair) |
| ZIP | ~7 B | **4 B** (numeric) |
| expire | 4 B | **2 B** (epoch days) |
| name | ~18 B | ~18 B (kept inline) |

That's roughly **half the uncompressed size** of the naive record — before xz,
which then compresses the text-heavy remainder far better than the old zip. The
three dictionaries cost only a few hundred kilobytes total, shared across all 1.6
million records.

## How a lookup actually runs

Putting it together, `lookup("K7VZT-5")`:

1. **Pack** the callsign to a base-37 integer, stopping at the `-` (SSID is
   ignored): `K7VZT`.
2. **Binary-search** the in-memory keys block for that integer → record index.
3. **Offset** = prefix-summed lengths → the record's byte range.
4. **Read + decode** one record body: name inline; city/state/class/status via
   their dictionary indices; ZIP unpacked from its `u32`; expiration expanded
   from `epochDate + days`.
5. The callsign itself is **unpacked from the key**.

One binary search, one small read, a few array indexes. No parsing of 1.6 million
rows, no external database engine.

## Reproducibility and versioning

Two properties make this safe to ship on a schedule:

- **Byte-identical builds.** Given the same FCC data date, the builder emits an
  identical file every time — dictionaries are sorted, the source date is fixed
  from the FCC `Last-Modified` header, and xz carries no timestamps. The CI job
  only republishes when the FCC data actually changes.
- **A version gate.** The header carries `formatVersion`, and the app validates a
  freshly downloaded file *before* installing it. An older app simply refuses a
  newer format rather than misreading it — so the format can keep evolving.

## The honest ledger

A few deliberate trade-offs worth naming:

- The callsign, ZIP, and dictionary tricks assume **US amateur data shape**
  (alphanumeric callsigns ≤ 8 chars, numeric ZIPs, small state/class/status
  alphabets). Values outside those assumptions degrade gracefully — a non-numeric
  ZIP becomes "none," an unmapped index reads as empty — but this format is not a
  general-purpose ULS mirror.
- We keep **all** licenses, including expired and cancelled ones. Filtering to
  active-only would be the single largest size cut available, but it's a product
  decision, not an encoding one — so it stays opt-in for now.
- `name` is left uncompressed inline. A name dictionary was measured and
  discarded: near-zero payoff for real added complexity.

The result is a file that a phone can download quickly, store compactly, and
search instantly — 1.6 million hams, offline, in your pocket.

---

**Related:** [callsign database reader/writer](../../src/lib/callsign/callsign_database.dart) ·
[offline builder](../../src/tools/build_fcc_db.py)
