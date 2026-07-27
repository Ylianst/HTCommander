# 90,000 Hams North of the Border: Compacting the Canadian Callsign Database

*How HTCommander reuses the same `.cdb` format it built for the FCC to ship
Canada's amateur licence data offline — and the handful of encoding changes the
Canadian data shape forced, from alphanumeric postal codes to qualification
bitmasks.*

---

## Standing on the FCC post's shoulders

This is a companion to
[*1.6 Million Hams in Your Pocket: Compacting the FCC Callsign Database*](fcc-callsign-compaction.md).
That post explains the `.cdb` ("Callsign DataBase") format in full — a sorted,
binary-searchable index next to a seek-into records block, with a stack of
encoding tricks (base-37 packed keys, an offset-free index, dictionaries for
repetitive fields, and xz for the download). If you haven't read it, start there;
this post assumes it.

The goal here was narrower: add **Canadian** amateur callsigns to the same
offline lookup, on the same mobile devices, with the **same aggressive
compaction** — without forking the format or the reader, and without letting the
Canadian pipeline destabilize the US one. What follows is only what's *different*
about Canada.

## A different source, a fraction of the size

The US data comes from the FCC's Universal Licensing System: a weekly ZIP of
several pipe-delimited `.dat` files (`HD`, `EN`, `AM`) that you join on a system
id to reconstruct ~1.59 million licences.

Canada's comes from **ISED** (Innovation, Science and Economic Development
Canada). It's simpler in every dimension:

- **One file, not three.** The download
  (`https://apc-cap.ic.gc.ca/datafiles/amateur_delim.zip`, ~2.3 MB) contains a
  single `amateur_delim.txt` — no join step.
- **Semicolon-delimited, with a header row** naming the columns. The FCC files
  are pipe-delimited and header-less, decoded against a published column spec.
- **UTF-8, not Latin-1.** Canadian names carry French accents ("Sauvé",
  "André"), and the file is genuine UTF-8; the reader decodes them as-is.
- **~92,000 records, not 1.6 million.** About one-seventeenth the size.

Each row is one operator (or club): callsign, given name, surname, address,
city, province, postal code, five qualification flags, and a block of club
fields. That's the whole schema.

## The big idea: one format, a header flag

The `.cdb` reader in
[`callsign_database.dart`](../../src/lib/callsign/callsign_database.dart) is the
single most valuable thing to *not* duplicate. So the Canadian database uses the
**exact same format**, version 2, byte-for-byte — same header, same
dictionaries, same key block, same record layout. One reader parses both.

The trick that makes that possible is a single bit. The header has always
carried a 16-bit `flags` field that was reserved and written as zero. Canada
turns on bit 0:

```
flagCanada = 0x0001
```

When the reader sees that bit, it decodes two fields differently (postal code and
qualifications, below). When it's clear — every US database ever built — the
reader takes exactly the path it always did. The US pipeline didn't change; its
output is still byte-identical to before. The flag is the entire coupling surface
between the two.

This also keeps the isolation promise at the *code* level, not just the pipeline:
a Canadian quirk can only ever affect the `flagCanada` branch.

## What carries over unchanged

Most of the FCC tricks are country-agnostic and applied to Canada verbatim:

- **Base-37 packed keys.** Canadian callsigns (VA/VE/VO/VY/VG/CY… prefixes) are
  the same uppercase-alphanumeric, ≤ 8-character shape, so they pack into the
  same 6-byte sortable key, and the callsign is still reconstructed from the key
  rather than stored.
- **The offset-free index** (lengths + prefix sum), the **city dictionary**, and
  the **province dictionary** (which is literally the FCC "state" dictionary
  holding two-letter codes — `ON`, `QC`, `BC` instead of `WA`, `CT`).
- **xz for the download.**

Three tricks needed rework. Here they are.

## Change 1: Postal codes aren't numbers

The FCC trick "ZIP as a number" packs `06111` or a 9-digit ZIP+4 into a `u32` and
reconstructs it by zero-padding. Canadian postal codes break that on the first
character: they're **alphanumeric**, in a fixed `A1A 1B1` shape —
letter · digit · letter · digit · letter · digit.

But that rigid shape is itself compressible. Each position is one of only 26
letters or 10 digits, so a code is really six small digits in **alternating
bases**. Pack them by interleaving base-26 and base-10:

```
value = 0
for each (letter, digit) pair:
  value = value * 26 + (letter - 'A')   // 0..25
  value = value * 10 + (digit - '0')    // 0..9
```

The maximum is $26^3 \times 10^3 = 17{,}576{,}000 < 2^{25}$, so a whole postal
code still fits the **same `u32` field** the ZIP used — no record grew by a byte.
`0xFFFFFFFF` remains the "none" sentinel (many records have a blank postal code),
and the reader formats the result back as `A1A 1B1`. A code stored with or
without its space round-trips identically, because packing ignores spaces.

So the field is physically the same four bytes; only its *interpretation* — chosen
by `flagCanada` — differs.

## Change 2: Qualifications, not class + status

An FCC record has an operator **class** (Technician, General, Extra…) and a
**status** (Active, Expired, Cancelled), packed as a two-byte `(class, status)`
pair into a shared dictionary and referenced by a one-byte index.

Canada has neither. It has **qualifications**, and an operator can hold several
at once. The ISED file exposes five independent flag columns:

| Column | Qualification |
|--------|---------------|
| A | Basic |
| B | 5 wpm Morse |
| C | 12 wpm Morse |
| D | Advanced |
| E | Basic with Honours |

Five booleans is a **5-bit bitmask** — a single byte, values 0–31. So the same
class/status dictionary machinery is reused with a different payload: the "class"
byte holds the qualification mask (`Basic=1, 5wpm=2, 12wpm=4, Advanced=8,
Honours=16`) and the status byte is always 0. There are at most 32 distinct
masks, so the dictionary is tiny and every record still references it with one
byte. On read, `flagCanada` tells the decoder to expand that byte back into the
set of qualifications (e.g. `A|C|D` → "Basic, 12 wpm, Advanced") instead of
reading it as a class letter.

## Change 3: Canadian certificates never expire

An FCC licence has an expiration date, stored as a 16-bit day-count from an epoch
in the header. Canadian amateur **certificates don't expire** — once you're
qualified, you're qualified. There's simply no date to store.

Rather than change the record layout (which would break the "one format" goal),
the Canadian builder writes the expire field as **0** ("unknown") for every
record. It costs two bytes per record that always hold zero — and xz erases a
column of identical zeros almost entirely, so the on-disk cost rounds to nothing.
The epoch field in the header comes along for the ride, unused. The UI, seeing a
Canadian source, just doesn't show an expiry row.

## The numbers, measured

The real ISED extract (**91,925 records**), built with the offline tool
[`build_ised_db.py`](../../src/tools/build_ised_db.py):

| Stage | Size | Bytes/record |
|-------|-----:|-------------:|
| ISED `amateur_delim.zip` (source) | ~2.3 MiB | — |
| `.cdb` uncompressed | 3,438,167 B (~3.28 MiB) | ~37.4 |
| **`.cdb.xz` (the download)** | **1,155,652 B (~1.10 MiB)** | **~12.6** |

About **12.6 bytes per record** on the wire — right in line with the FCC v2
build's ~14 bytes/record, on a completely different dataset, through the same
encoder. At ~1.1 MiB the whole country fits in a single, fast, offline download.

Worth being honest about the flip side: at one-seventeenth the FCC's record
count, the *absolute* payoff of squeezing each record is small — a naïve Canadian
build would still be only a few MiB. The real reason to compact it identically
isn't the megabytes; it's that the app carries **one** format, **one** reader, and
**one** lookup path for both countries.

## Searching both at once

With two databases installed, a lookup walks each loaded database and returns the
first hit. US and Canadian callsign spaces don't overlap (different prefixes), so
at most one ever matches — `VE3ABC` resolves in the ISED database, `K7VZT` in the
FCC one — and the result carries which source answered, so the UI can show US
"class + status + expiry" or Canadian "qualifications" appropriately. The bundled
in-memory country/DXCC table still resolves the *country* of any callsign
instantly and offline, independent of either database.

## Kept deliberately separate

The two databases are rebuilt and published by **separate GitHub Actions**. This
is intentional: if ISED changes a column, moves the file, or goes down, the
Canadian job can fail loudly without touching the US database's build or deploy.
The two jobs share only the GitHub Pages concurrency group (so their publishes
never overlap), and each ships its own manifest and its own rolling release
asset. A problem north of the border stays north of the border.

## Incremental updates come along for free

The FCC post describes an upcoming
[**overlay** mechanism](fcc-callsign-compaction.md#whats-next-incremental-updates-via-an-overlay-database)
for shipping weekly changes without re-downloading the whole database: a small
second `.cdb` — same format — that the app searches *first*, falling through to
the baseline on a miss. Because Canada already rides the identical format and
reader, it inherits the entire scheme with no new format work; the overlay is
just a `.cdb` with `flagCanada` set, like its baseline.

The mechanics are the same as the US build, restated for Canada:

- **Cumulative overlay, searched first.** The weekly overlay holds every ISED
  record that changed since the last baseline; a hit there wins, otherwise the
  baseline answers. A device only ever carries two files.
- **Updates supersede, deletes are ignored.** A new qualification, a corrected
  address, or a fresh club record is just a newer record the overlay wins with.
  A certificate removed from the ISED extract keeps showing its stale baseline
  record — cosmetic for offline lookup, and it keeps the client dead simple.
- **A size threshold triggers a fresh baseline.** The Canadian job measures the
  overlay-to-baseline size ratio after each build and, once the cumulative
  overlay grows past a set fraction of the baseline (~20%, the same
  cost-optimal target derived for the FCC build) or on the first run, *promotes*
  the freshly built full database to a new baseline and resets the overlay to
  empty.
- **Still separate, still isolated.** The Canadian overlay is produced and
  published by the Canadian workflow alone, against the Canadian baseline — the
  US and Canadian pipelines remain fully independent, overlays included.

Because Canada is one-seventeenth the FCC's size, the *absolute* saving is modest
(a full Canadian download is already ~1.1 MiB), but the win is the same one that
motivated sharing the format at all: **one** overlay mechanism, **one** reader,
**one** lookup path — now covering incremental updates for both countries.

## The honest ledger

The same caveats as the FCC build apply, plus a couple specific to Canada:

- The postal-code packing assumes the strict `A1A1B1` pattern. Anything else
  (blank, malformed, a foreign address) maps to the "none" sentinel and reads
  back empty — lossless for well-formed Canadian codes, graceful for the rest.
- **All** certificate holders are kept; there's no active/expired axis to filter
  on the way the FCC data has.
- Club stations carry their name in dedicated club columns; the builder falls
  back to those when the individual name/address fields are blank, so clubs still
  show a sensible name and location.

The result: two national callsign databases, US and Canada, sharing one compact
binary format and one binary-search reader — each downloadable in about a second,
searchable instantly, and fully offline in your pocket.

---

**Related:**
[FCC callsign compaction](fcc-callsign-compaction.md) ·
[callsign database reader/writer](../../src/lib/callsign/callsign_database.dart) ·
[Canadian offline builder](../../src/tools/build_ised_db.py)
