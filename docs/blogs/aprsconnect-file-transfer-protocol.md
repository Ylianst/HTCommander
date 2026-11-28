# Files Over Radio: APRSConnect's PACSAT Protocol and a Path Into Comms

*A byte-level guide to APRSConnect's file-transfer format, its half-duplex
conversation, and the work needed to make HTCommander exchange files with it.*

**Research date: 27 November 2026.** This article began as documentation and an
integration plan. The first native Comms implementation is now present; its
scope and remaining interoperability gates are described in section 13.
The APRSConnect documentation
consulted was marked **17 November 2026**. No APRSConnect implementation source
or interoperability capture was available for this investigation.

## The important discovery

APRSConnect does not send files as long APRS chat messages. It uses the
**PACSAT Broadcast Protocol**, the **PACSAT File Header (PFH)**, and Broadcast
Protocol updates 1 and 2. Harold Price, NK6K, and Jeff Ward, K8KA, originally
developed these formats for amateur store-and-forward satellites. APRSConnect
uses them between ground stations, adding permission to receive, explicit
completion reports, repair requests, and half-duplex channel scheduling.

That distinction determines the integration:

- Carry **binary AX.25 UI frames**, not APRS message text.
- Use PID **`0xBB`** for file data and file requests, and **`0xBD`** for directory
  frames containing the offer.
- Address the data and offer frames to **`QST-1`**, even for a file intended for
  just one person. The actual recipient is in the PFH.
- Address requests back to the sender's exact on-air callsign and SSID.
- Recover missing **byte ranges**, not missing APRS message numbers.
- Do not start sending the body until someone accepts.
- Keep the transfer on a compatible radio link, never APRS-IS.

A PACSAT parser alone is therefore not enough. The APRSConnect scheduling and
completion rules are part of practical interoperability.

## What this article treats as evidence

The descriptions below separate three kinds of information:

1. **PACSAT standard:** field encodings, checksums, frame structures, and
   corrected flag definitions, from the original documents.
2. **APRSConnect profile:** application behavior explicitly published on its
   [Files by radio](https://aprsconnect.com/docs/files-by-radio) page.
3. **HTCommander proposal:** implementation choices suggested here, not claims
   about APRSConnect's unpublished internals.

Where a published description leaves an exact algorithm unspecified, the
article says so. The worked bytes are independently calculated examples, not
packets captured from APRSConnect. Do not mistake them for proof that another
implementation accepts every field choice.

## 1. What an operator sees

The sender selects a file, a connected radio channel, and either **one station**
or **everyone listening**. A conversation can prefill the destination. The
recipient sees an offer with the name, size, estimated duration, and sender,
and can accept or decline it. An always-accept list can automate consent for
selected stations.

APRSConnect's published limit is **1,474,560 bytes of transmitted body**, after
compression when used. This is 1,440 KiB, the traditional "1.44 MB" floppy size.
It is not the maximum total PFH-plus-body size and not the maximum original
size of a compressible file.

Its approximate 1200-baud estimates are:

| Example | Size | Published elapsed estimate |
| --- | ---: | --- |
| Text page | 2 KB | Under a minute |
| Small photograph | 15 KB | 3-5 minutes |
| One-page PDF | 100 KB | 20-35 minutes |
| Maximum transmitted body | 1.44 MB | 4-8 hours |

The page gives roughly **80 bytes/second on a clean 1200-baud channel**, and
roughly five times the speed with a capable 9600-baud TNC. These are estimates,
not a guaranteed rate. Gaps, offers, requests, lost frames, channel contention,
and TNC transmit delay all consume time.

There are separate pause, resume, cancel, retry, and check-again operations.
Cancel is not resumable. Queueing a second file does not begin another
simultaneous outgoing transfer. Received files remain local to the device and
are not included in APRSConnect's sync or backup.

**Frequency matters more than the progress bar:** arrange an appropriate local
packet frequency with the other operator. Do not occupy the shared APRS
calling/beacon frequency, such as 144.390 MHz in North America, for a
multi-minute file transfer. Frequencies and permitted operation are regional.

## 2. The stack: where these bytes belong

```text
Original file
    -> optional gzip of the body
    -> uncompressed PFH + transmitted body
    -> PACSAT directory/data/request information fields
    -> AX.25 UI frames
    -> binary-capable TNC or compatible audio modem
    -> radio
```

The AX.25 UI control byte is **`0x03`** with Poll/Final clear. The source,
destination, any digipeater addresses, control byte, and PID belong to AX.25,
not to the PACSAT information field.

| Purpose | AX.25 destination | PID | PACSAT information |
| --- | --- | ---: | --- |
| Offer or check-in | `QST-1` | `0xBD` | Directory header + PFH fragment + CRC |
| File piece | `QST-1` | `0xBB` | Data header + file fragment + CRC |
| Accept, decline, repair, completion | Sender's callsign-SSID | `0xBB` | Request header + optional holes |

Both endpoints must use a compatible physical modem. Being able to transport
AX.25 bytes inside DART or XARA would not make those waveforms receivable by
an APRSConnect AFSK 1200 station.

APRSConnect lists Bluetooth/USB TNCs, built-in TNC radios, KISS over TCP, and its
audio modem as supported paths. A **KISS TCP connection to a radio TNC** is
still a radio path; it is not APRS-IS. Text-only LoRa APRS links are excluded.
Support in APRSConnect is not evidence that HTCommander already supports each
of those devices.

### Two CRCs, at different layers

The over-the-air AX.25 frame has an HDLC frame check sequence. A KISS TNC
normally removes it before delivering the frame to the host.

PACSAT directory and data frames also have a CRC **inside the AX.25 information
field**, protecting the bytes delivered through the TNC/host connection. Keep
that inner CRC when submitting an AX.25 packet. Do not append another AX.25
FCS to a host packet whose modem adds it.

If using a KISS transport, its delimiters, port/command byte, and escaping are
also outside PACSAT. Binary `0xC0` and `0xDB` bytes must survive that transport
unchanged after unescaping. Base64, UTF-8 conversion, APRS third-party
encapsulation, and line-oriented TNC monitor text are not substitutes.

## 3. The file object: PFH followed by body

All PACSAT multibyte integers are **unsigned little-endian**, except the
two-byte transmitted XMODEM CRC, which is **high byte first**.

The file transferred is:

```text
AA 55
    mandatory header items
    extended header items
    optional/experimental header items
00 00 00
    transmitted body bytes
```

Every item has the same type-length-value structure:

| Component | Bytes | Meaning |
| --- | ---: | --- |
| ID | 2 | LE item identifier |
| Length | 1 | Number of value bytes, 0-255 |
| Value | Length | Encoded item value |

The terminator is **ID zero and length zero**: exactly `00 00 00`. The
two-byte `AA 55` signature is not itself a TLV.

IDs with bit 15 set are experimental/user-defined. Unknown items can be skipped
using their length. A length is in **bytes**, particularly for UTF-8 names;
it is not a character count. Do not split an oversized string into repeated
items unless a documented convention permits it.

The original specification requires mandatory items immediately after the
signature, in ascending ID order. If the extended header is present, all its
items must appear immediately after the mandatory header, in ascending order,
except for repeated destination/downloader/download-time triplets. Optional
items do not require ascending order.

### Mandatory items

APRSConnect says it writes every mandatory and extended item.

| ID | Name | Value size | Interpretation |
| ---: | --- | ---: | --- |
| `0x0001` | `file_number` | 4 | File ID; match the ID used by data/directory frames |
| `0x0002` | `file_name` | 8 | PACSAT internal base name, space-padded |
| `0x0003` | `file_ext` | 3 | PACSAT internal extension, space-padded |
| `0x0004` | `file_size` | 4 | **Total PFH + transmitted body** byte count |
| `0x0005` | `create_time` | 4 | File creation time |
| `0x0006` | `last_modified_time` | 4 | Last modification time |
| `0x0007` | `seu_flag` | 1 | Legacy storage error status: 0 none, 1 corrected, 2 uncorrectable |
| `0x0008` | `file_type` | 1 | `0x00` plain text; APRSConnect uses `0xFF` for other types |
| `0x0009` | `body_checksum` | 2 | Sum of transmitted body bytes modulo 65,536 |
| `0x000A` | `header_checksum` | 2 | PFH byte sum with its two value bytes treated as zero |
| `0x000B` | `body_offset` | 2 | Offset of first body byte, equal to PFH length |

The header's 16-bit `body_offset` limits PFH length to 65,535 bytes even though
`file_size` is 32-bit. Data frames have only a 24-bit file offset. The
APRSConnect body limit is much smaller than that offset space, but all three
constraints still need validation.

The legacy upload rules initialize `file_number` to zero so a satellite server
can assign it, and leave the 8.3 internal name blank. APRSConnect's ground
sender plays the serving role: **do not blindly apply satellite-upload
initialization rules to its already-offered file**. Its file-ID generation and
internal 8.3 naming policies are not published.

### Extended items

| ID | Name | Value size | Interpretation |
| ---: | --- | ---: | --- |
| `0x0010` | `source` | Variable | Printable ASCII originator identifier |
| `0x0011` | `ax25_uploader` | 6 | Base callsign only, no SSID, right-padded with spaces |
| `0x0012` | `upload_time` | 4 | Time associated with the completed file |
| `0x0013` | `download_count` | 1 | Legacy download count |
| `0x0014` | `destination` | Variable | APRSConnect recipient callsign-SSID, or `ALL` |
| `0x0015` | `ax25_downloader` | 6 | Base downloader callsign; blank before download |
| `0x0016` | `download_time` | 4 | Legacy per-destination completed-download time |
| `0x0017` | `expire_time` | 4 | Legacy absolute file expiry timestamp |
| `0x0018` | `priority` | 1 | Legacy message priority |

The six-character uploader/downloader fields **cannot represent an SSID**.
Use the AX.25 source/destination and the profile's `destination` string for
station matching. `N0CALL` and `N0CALL-9` are different destinations.

PACSAT permits multiple `0x0014/0x0015/0x0016` triplets. APRSConnect documents
one named recipient or `ALL`, not arbitrary multi-recipient PFHs. Do not add
multi-destination sending to the initial HTCommander compatibility profile.

The original data standard and PFH use four-byte UNIX seconds since
**1970-01-01 UTC**. Update 2's directory prose instead says **1980-01-01**:
this is an actual inconsistency in the reference material. APRSConnect says
its directory sends the upload time twice, but does not explicitly resolve
the epoch in its profile. Use PFH UNIX seconds for the proposed implementation,
keep both directory values as raw integers, and verify them against a capture
before treating directory times as calendar dates.

### Relevant optional items and APRSConnect extensions

| ID | Name | Value size | APRSConnect use |
| ---: | --- | ---: | --- |
| `0x0019` | `compression_type` | 1 | `0x00` none; `0xFF` for its gzip escape |
| `0x0020` | `bbs_message_type` | 1 | Legacy optional BBS message classification |
| `0x0021` | `bulletin_id_number` | Variable | Legacy optional bulletin identifier |
| `0x0022` | `title` | Variable | Legacy optional subject/title |
| `0x0023` | `keywords` | Variable | Legacy optional search keywords |
| `0x0024` | `file_description` | Variable | MIME type when `file_type = 0xFF` |
| `0x0025` | `compression_description` | Variable | ASCII `gzip (RFC 1952)` when compressed |
| `0x0026` | `user_file_name` | Variable | End-user filename, not the internal 8.3 name |
| `0x8001` | Body SHA-256 | 32 | Raw digest of the transmitted body, **not hexadecimal text** |
| `0x8002` | UTF-8 filename | Variable | Added when the filename is not plain ASCII |
| `0x8003` | Original size | 4 | LE size before compression, compressed files only |

Items `0x0020-0x0023` are listed to make a decoder intelligible; the APRSConnect
page does not promise to emit them. Treat `0x8001-0x8003` as the APRSConnect
meaning of experimental IDs, not globally reserved PACSAT assignments.

For a non-ASCII name, HTCommander should prefer the valid UTF-8 extension for
display and saving. APRSConnect's exact ASCII fallback in `user_file_name`,
truncation behavior, and treatment of filenames beyond 255 encoded bytes are
not published.

### Building and checking the PFH

Let `H` be the finalized PFH length, including signature and terminator, and
`B` the length of the transmitted body:

```text
body_offset   = H
file_size     = H + B
body_checksum = sum(transmitted_body_bytes) mod 65536
header_checksum = sum(PFH bytes, with only the two checksum
                      value bytes replaced by zero) mod 65536
```

The header checksum includes the checksum item's ID and length, the body
checksum value, the signature, every other item, and the terminator. It is not
a CRC, and checking whether the complete PFH sums to zero is incorrect.

An encoder should prepare the transmitted body first, calculate its checksum
and digest, serialize the PFH with a zero header checksum, fill the total size
and body offset, then calculate and insert the header checksum. Do not change
metadata after that without recalculating the PFH checksum.

A receiver needs a complete, structurally valid PFH before trusting a filename,
destination, size, compression method, or allocation request. Check fixed
item lengths, bounded TLV walks, the terminator, required items, checksum,
body offset, and total size. Duplicate mandatory items and conflicting
security-relevant extensions should be explicit errors, not "last one wins."

## 4. Compression is a body property

APRSConnect uses gzip only if it shrinks the body by **at least 5% and at least
64 bytes**. Both conditions apply. For original length `O` and gzip length `G`,
an integer expression matching that description is:

```text
G <= O - 64  AND  20 * G <= 19 * O
```

This expression is an implementation interpretation of the published threshold,
not a recovered APRSConnect source expression.

When compressed:

- PFH stays uncompressed.
- `compression_type = 0xFF`.
- `compression_description = "gzip (RFC 1952)"`.
- Item `0x8003` records the original size.
- The additive body checksum and SHA-256 cover the **gzip bytes as sent**.
- `file_size` includes the PFH and gzip body, not the inflated body.

Use a gzip wrapper, not raw DEFLATE, zlib, ZIP, or the legacy PACSAT PKZIP
compression code. Update 2 also clarifies that text remains `file_type = 0x00`
with a nonzero compression type; the obsolete `0x0A` "compressed text" code is
not the right way to identify gzip text.

The published receiver rejects decompression exceeding **50 MB**, or a result
whose length differs from `0x8003`. The exact decimal/binary interpretation of
that 50 MB guard is not given. HTCommander should use a documented conservative
byte limit and enforce it **during streaming inflation**, not after allocating
the full output. An advertised original size is not permission to allocate it.

APRSConnect can also resize photographs before transfer: small is 480 pixels
on the long side, resized copies are JPEGs, and image metadata is removed.
That is preprocessing, not a PACSAT wire feature. A receiver simply receives
the resulting file.

## 5. Data frames: PID `0xBB`

Offsets in the following tables start at the **AX.25 information field**, after
the PID. APRSConnect uses this normal, byte-offset data layout:

| Offset | Size | Field |
| ---: | ---: | --- |
| 0 | 1 | Flags: `0x02` normally, `0x22` on the piece containing the last file byte |
| 1 | 4 | File ID, LE |
| 5 | 1 | PFH `file_type` |
| 6 | 3 | File byte offset, LE24 |
| 9 | `n` | Up to **245 bytes** from PFH + transmitted body |
| `9+n` | 2 | XMODEM CRC, high byte then low byte |

Maximum information length in this layout is `9 + 245 + 2 = 256` bytes.
With two AX.25 addresses and no digipeaters, the host AX.25 packet is
`14 + 1 + 1 + 256 = 272` bytes before the modem adds FCS and framing.
An implementation must not interpret 245 as the maximum whole AX.25 frame.

The **corrected** Update 1 flags are:

```text
bit 0      L: optional length field present
bit 1      Of: 1 = byte offset; 0 = legacy block number
bits 2-3   version: 0
bit 4      0: server/data frame, not a request
bit 5      E: the piece contains the file's final byte
bits 6-7   reserved: 0
```

Thus `0x02` means byte offsets, no optional length field, not EOF. `0x22`
sets EOF as well. The earlier uncorrected flags drawing is not safe to
implement.

PACSAT also defines a two-byte LE **valid-bit length** after the offset when
`L=1`. It is a bit count, not a byte count. APRSConnect's published profile
does not use it or block-number mode. A first implementation should explicitly
recognize those unsupported variants rather than parse them with the
normal nine-byte header.

The offset is relative to the **entire file**, not just the original content.
The file's first transmitted byte is `AA`, offset zero. If `body_offset` is
189, the original body starts at offset 189. A frame can straddle PFH and body.
EOF alone is not proof that earlier bytes arrived.

### Inner CRC parameters

Use **CRC-16/XMODEM**:

| Parameter | Value |
| --- | --- |
| Polynomial | `0x1021` |
| Initial register | `0x0000` |
| Input/output reflection | False |
| Final XOR | `0x0000` |
| Check for ASCII `123456789` | `0x31C3` |
| Transmitted byte order | Big-endian/high byte first |

Calculate it over the complete PACSAT data header and data, excluding the
CRC bytes themselves. Do not include AX.25 addresses, control, PID, or FCS.
Equivalently, running this CRC over the information bytes **including** the
two appended CRC bytes produces zero. Directory frames use the same rule.

## 6. Directory frames: PID `0xBD`

A directory frame carries the PFH, not a separate JSON or text offer:

| Offset | Size | Field |
| ---: | ---: | --- |
| 0 | 1 | Directory flags |
| 1 | 4 | File ID, LE |
| 5 | 4 | Offset into the PFH, LE32 |
| 9 | 4 | `t_old`, LE32 |
| 13 | 4 | `t_new`, LE32 |
| 17 | `n` | PFH bytes at that offset |
| `17+n` | 2 | XMODEM CRC, high byte first |

The offset is **32-bit**, unlike the 24-bit offset in a data frame.
Do not reuse a data-header parser.

Directory flags from Update 2:

```text
bits 0-1   type: 0 = PFH broadcast
bits 2-3   version: 0
bit 4      0 = server generated
bit 5      E: last byte is the PFH's last byte
bit 6      N: newest file
bit 7      reserved: 0
```

APRSConnect specifies **`0x60` on the last PFH frame**, setting both E and N.
Its documentation does not give the exact flags on preceding fragments.
Require the supported type/version and use E to recognize the last fragment;
do not assume every directory fits in one frame.

It places the file's upload time in both `t_old` and `t_new`. Satellite PACSAT
uses those fields to describe gaps in a directory timeline; APRSConnect uses
the PFH broadcast as an **offer and periodic check-in** instead.

With a chosen 256-byte AX.25 information-field ceiling, directory fragments
can contain at most `256 - 17 - 2 = 237` PFH bytes. That is derived framing
arithmetic, **not a published APRSConnect directory chunk-size constant**.

Reassemble directory fragments by sender, file ID, and PFH offset. They may
arrive out of order or repeatedly. Once validated, their bytes can also fill
the corresponding range at the beginning of the file object; they are the
same PFH, not an alternative header.

PACSAT Update 2 defines PID `0xBD` directory **requests** too, with a different
layout and time ranges. APRSConnect does not document needing them for this
feature. Do not treat every PID `0xBD` packet as a directory broadcast without
checking destination and flags, or implement satellite directory discovery as
a prerequisite for ground-to-ground files.

## 7. Requests: PID `0xBB`, addressed to the sender

| Offset | Size | Field |
| ---: | ---: | --- |
| 0 | 1 | `0x10` start, `0x11` stop, or `0x12` hole list |
| 1 | 4 | File ID, LE |
| 5 | 2 | Requested maximum data-piece size, LE16 |
| 7 | `5*k` | Hole entries, only for `0x12` |

Each hole is:

| Relative offset | Size | Field |
| ---: | ---: | --- |
| 0 | 3 | First missing file byte, LE24 |
| 3 | 2 | Number of missing bytes, LE16 |

The corrected flags set bit 4 to identify a client request; bits 0-1 are
command 0, 1, or 2; bits 2-3 are version zero; bits 5-7 are reserved.

**There is no inner PACSAT CRC on a request.** The original protocol defines
requests as header + data, not header + data + CRC, and APRSConnect's request
description adds none. The radio AX.25 FCS still protects them on the air.

The published profile gives no special meaning to a requested piece size of
zero. HTCommander should initially request 245 and reject invalid sizes
explicitly rather than infer an undocumented sentinel.

### The empty hole list is a completion report

This is an essential APRSConnect addition:

```text
0x12 + file ID + requested maximum piece size + NO hole entries
    = "I have every byte"
```

It is not a request for the whole file, a keepalive, or "nothing missing in the
portion I happened to observe." During check-ins a receiver reports **all
missing ranges in the entire file**, including bytes not sent yet, so the
answer stays nonempty until the file is complete.

A receiver continuing a partial transfer sends a hole list, not a fresh start.
`0x11` is a negative/stop response; it must not be used casually as a
local-pause command when the other application may interpret it as decline.

### Representing larger or fragmented holes

One entry can encode at most 65,535 missing bytes. Split a larger interval
into consecutive entries. For example, a missing 100,000-byte span at offset
500 becomes `(500, 65535)` followed by `(66035, 34465)`.

For a 256-byte information ceiling, a request fits at most
`floor((256 - 7) / 5) = 49` entries, using 252 bytes. More holes require
multiple requests; the original protocol permits this. APRSConnect's exact
policy for combining multipart replies and detecting when a check-in answer
is finished is not published.

Use sorted, nonoverlapping half-open intervals `[start, end)` internally:
subtract each validated incoming range, merge adjacent holes, and serialize
bounded chunks. Reject zero-length entries, truncated tuples, arithmetic
overflow, and spans outside the offered file. Do not turn a truncated
multipart hole list into an empty completion report.

## 8. The conversation, from offer to completion

### A normal one-to-one transfer

```text
Sender                                      Receiver
  | -- BD directory/PFH offer -------------> |
  |                                         | validate PFH; show offer
  | <--------- BB request START ------------ | operator accepts
  | -- BB data pieces, about 15 s of air ---> |
  | -- BD PFH check-in --------------------> |
  |                                         | wait 0.5 s + response spread
  | <--------- BB HOLE LIST ---------------- |
  | -- subsequent data / repairs ----------> |
  | -- BD PFH check-in --------------------> |
  | <--------- BB empty HOLE LIST ---------- | all bytes received
  |                                         | verify; publish complete file
  | <--------- repeat completion ----------- | 15 s later
  | <--------- repeat completion ----------- | another 15 s later
```

The ordering of whole-file integrity verification relative to the first
empty-hole response is not specified by the public profile. HTCommander
should avoid presenting success until verification passes; preferably finish
verification before transmitting its success-shaped completion report. Test
that this does not delay the reply outside the peer's response window.

### Initial offers and declines

- Only the offer goes out before acceptance.
- The offer is repeated at 10-second intervals, three times, and abandoned
  after two minutes without a response.
- The phrasing does not completely establish whether "three times" counts
  the initial offer. Verify the observed count; do not derive an exact
  four-packet requirement from that sentence alone.
- A receiver that declined repeats its stop response if it hears another
  offer within one minute. After that minute it treats an offer as fresh.
- The receiver expires an offer ten minutes after last hearing its header.
- It retains only the newest **five unanswered offers per sender**, and
  **twenty unanswered offers overall**.
- It stores no pieces of a **named-recipient** file before accepting it.
  The page does not fully specify pre-consent buffering for `ALL` files.

Offer expiration is a local "last heard" timer, not simply the PFH's
`expire_time`. A transfer abandoned by its sender after two minutes can still
have an unexpired offer card on another station.

### Bursts and check-ins

APRSConnect's sender uses bursts of about **15 seconds of airtime**, separated
by **two seconds**. It checks in after the first burst, then after roughly
every minute of airtime. A check-in appends the PFH to the end of the burst
and waits for a response.

The receiver replies **half a second after the final PFH frame**, spreading
its answer over another **150 ms** for a named recipient, or **three seconds**
for everyone-listening transfers. Its hole list is generated when sent,
not when the response timer was first armed.

The public description does not identify the exact random distribution or
multipart scheduling implied by "spread." It is not permission to use a
fixed simultaneous timer for every broadcast receiver.

The sender continues as soon as the reply arrives; for a broadcast it waits
for every station still receiving to answer. With no answer:

1. Wait **four seconds** for one recipient, **seven seconds** for broadcast.
2. Send the header alone again, up to **two** retries.
3. If link speed has not yet been measured, allow up to **four additional**
   retries with successively doubled waits: the radio may still be draining
   bytes already submitted to it.
4. Carry on after the unanswered check-in.
5. Stop after **three consecutive missed check-ins**.

These are not ordinary "retry every data packet three times" rules. Most data
is sent without per-piece acknowledgement; holes repair losses collectively.

### Requests outside a check-in

A start, stop, or reminder not answering a just-received PFH waits for channel
quiet lasting the greater of:

- **two seconds**, or
- **1.6 frame times**.

After hearing anyone, a sender holds its next burst for **half a second**.
A receiver that has requested data and heard nothing repeats its request
every **20 seconds**, six times. The exact reset criteria and whether the
initial request is counted in those six are not published.

### Finishing, including broadcast

A one-to-one sender finishes immediately upon the intended receiver's empty
hole list. A receiver sends its complete-byte report **three times**, at
15-second intervals, to tolerate a lost completion response.

An everyone-listening file starts once **one station accepts**. Stations
joining later receive the remaining data and request what they missed.
The sender ends when every accepting station reports complete, or when
**five consecutive offers bring no request**.

Track receiver identities individually. A completion from one listener is not
completion for all listeners, and a decline from one listener must not cancel
everyone else's transfer. The exact pruning of silent broadcast participants
needs capture-based verification; it is not fully defined by the page.

### Sharing the channel with another sender

APRSConnect sends only one outgoing file at a time. Subsequent files wait
**unannounced**, rather than advertising queued offers on the channel.

If pieces of another station's file were heard in the previous **20 seconds**:

- A local file not yet started waits.
- If both files are already under way, the station whose callsign sorts first
  continues; the other holds its file.

The published wording says callsign order, but does not specify case
normalization or whether an SSID participates in comparison. Normalize
on-air identifiers consistently and confirm the comparison with peers.
This turn-taking is in addition to carrier sensing; neither substitutes for
the other.

## 9. Timing must follow radio airtime, not host queue time

APRSConnect measures the link in two ways:

- **Receiver:** spacing between pieces in a burst.
- **Sender:** arrival of a check-in answer, which indicates that the peer
  heard the final PFH after the sender's radio transmitted the preceding queue.

It starts from 1200 baud or a previous measurement remembered for that radio.
Measured rate determines the burst size and timing.

For HTCommander, the critical trap is declaring a burst finished when a
Bluetooth write or TNC command completes. The radio may still have seconds of
queued RF data. A response timer started then can expire while the radio is
still transmitting, and the receiver cannot answer into that transmission.

At 1200 bits/second, a full data frame with two addresses is about
`(272 + 2) * 8 / 1200 = 1.83` seconds **before** flags, bit stuffing, TX delay,
and other overhead. That is raw serialization arithmetic, not the
application's measured 80-byte/second throughput.

An initial payload-budget approximation is:

```text
pieces_per_burst ~= floor(15 * measured_payload_bytes_per_second
                         / piece_payload_bytes)
```

At 80 bytes/second and 245-byte pieces it suggests four full pieces.
It is only a planning estimate: PACSAT/AX.25 overhead, header fragmentation,
and the rate estimator's units must be accounted for before using it as a
scheduler. APRSConnect does not publish its estimator, smoothing, outlier
handling, or precise burst-budget formula.

Use a monotonic clock for timers, bounded transmit queues, and modem/radio
completion information where available. Distinguish **submitted**, **actually
transmitted**, and **confirmed by receiver** in both state and UI. Never
let a successful host submission stand in for delivery.

## 10. Recovery and durable state

APRSConnect retains partial received files across app closure. On restart
they appear as **No signal**, and do not transmit immediately: the operator
may have changed frequency. They continue when the sender is heard again or
the receiver explicitly retries.

If both apps closed and the sender offers the same file again, APRSConnect
says the receiver resumes rather than requesting consent again. However,
the public protocol does **not** disclose how that identity is recognized
after a sender restart: stable file ID, body digest, PFH comparison, or
another policy. Do not match files by name and size alone.

Published recovery timers:

| Situation | Behavior |
| --- | --- |
| Receiver hears nothing for three minutes | Show No signal; keep partial data; Retry can request again |
| Sender stops for lack of response | Keep sent state; operator can Resume |
| Late start/hole list within ten minutes of sender stopping for lack of response | Automatically resume |
| Later request, or sender application was closed | Operator must restart sending |
| Radio disconnects | Pause; auto-continue if it reconnects within two minutes |
| Every piece sent but completion not confirmed | Check again sends another completion inquiry |
| Cancel | Not resumable |

For HTCommander, persist at least:

- Local transfer ID, direction, sender's full AX.25 identity, file ID, PFH,
  digest, destination, and compression metadata.
- Selected radio, region/channel, and sufficient frequency/modem context to
  avoid silently resuming on a different link.
- Accepted/declined status, received byte intervals, last heard times,
  outstanding requests, and completed/failed/paused state.
- The actual transmitted file object for sending, and partial stored bytes for
  receiving, with crash-safe consistency between data and interval state.

A sensible runtime key is `(link context, sender callsign-SSID, file ID)`.
The link component avoids mixing identical IDs heard on separate frequencies.
For restart matching, use validated content identity and metadata under an
explicit policy; verify how APRSConnect behaves before promising cross-app
resume compatibility.

Gzip output can vary with encoder metadata such as timestamps. Persist the
compressed bytes of an outgoing transfer instead of regenerating them during
Resume: a changed compressed body has a different SHA-256 and different holes.

## 11. Receive integrity and safe file handling

APRSConnect says a file is shown only when the PFH checksum, body checksum, and
SHA-256 all match. For compressed files, decompression follows verification of
the transmitted body.

The proposed HTCommander completion path is:

1. Validate each directory/data inner CRC before using its bytes.
2. Reassemble and validate the PFH; enforce sizes and recipient policy.
3. Fill only valid ranges for an accepted transfer.
4. Ensure coverage of every byte in `[0, file_size)`, not merely that summed
   received packet lengths equal `file_size`.
5. Check the transmitted body's additive checksum and SHA-256.
6. If compressed, decode the supported gzip profile with bounded output and
   exact original-size checking.
7. Atomically promote a verified file to received storage and update its card.

Duplicated and overlapping data cannot increase completion progress. If an
overlap disagrees with stored bytes despite valid frame CRCs, surface a
conflict rather than silently overwriting it. The same sender/file-ID pair
with a different PFH/digest is not automatically the same transfer.

Checksums and SHA-256 provide **integrity, not sender authentication**.
An unauthenticated station can transmit a replacement body and its matching
digest, or forge a start, stop, or completion request. Always-accept is
convenience, not proof of identity. Existing APRS message authentication does
not automatically sign these binary frames.

Treat filenames, MIME descriptions, and images as untrusted:

- Save into an application-controlled directory, stripping paths and unsafe
  filesystem characters; never write an offered absolute path.
- Avoid silently overwriting an existing file with the same display name.
- Do not execute or automatically launch received content.
- Bound partial-file disk usage, concurrent receive sessions, headers, holes,
  requests, decompressed output, and preview resources.
- Report unsupported compression, checksum failure, invalid size, disk errors,
  and stale links explicitly.

The public profile does not define a dedicated "checksum failed" wire message.
Keep the failure visible locally and determine repair/restart behavior from
real peers; do not invent an error packet and call it interoperable.

## 12. Worked bytes for a small text file

This synthetic example uses:

```text
AX.25 sender:     N0CALL-9
PFH destination:  K1ABC-7
File ID:          0x12345678
Filename:         hi.txt
Body:             48 69 0A                 ("Hi" plus LF)
Timestamp:        1700000000               (0x6553F100)
Compression:      none
PFH length:       189                      (0x00BD)
Total file size:  192                      (0x000000C0)
Body checksum:    0x00BB
Header checksum:  0x24D4
Body SHA-256:     c01a4cfa25cb895cdd0bb25181ba9c162
                 2e93895a6de6f533a7299f70d6b0cfb
```

The chosen PFH leaves the internal 8.3 name blank, sets uploader to `N0CALL`,
leaves downloader blank, uses zero download count/time/expiry/priority, and
includes `compression_type = 0`. These are example choices, not recovered
APRSConnect initialization values.

Complete PFH, broken at item boundaries:

```text
AA 55
01 00 04 78 56 34 12
02 00 08 20 20 20 20 20 20 20 20
03 00 03 20 20 20
04 00 04 C0 00 00 00
05 00 04 00 F1 53 65
06 00 04 00 F1 53 65
07 00 01 00
08 00 01 00
09 00 02 BB 00
0A 00 02 D4 24
0B 00 02 BD 00
10 00 08 4E 30 43 41 4C 4C 2D 39
11 00 06 4E 30 43 41 4C 4C
12 00 04 00 F1 53 65
13 00 01 00
14 00 07 4B 31 41 42 43 2D 37
15 00 06 20 20 20 20 20 20
16 00 04 00 00 00 00
17 00 04 00 00 00 00
18 00 01 00
19 00 01 00
26 00 06 68 69 2E 74 78 74
01 80 20 C0 1A 4C FA 25 CB 89 5C DD
         0B B2 51 81 BA 9C 16 22 E9 38
         95 A6 DE 6F 53 3A 72 99 F7 0D
         6B 0C FB
00 00 00
```

A single directory frame's information field is:

```text
60                         flags: final PFH fragment, newest
78 56 34 12                file ID
00 00 00 00                PFH offset
00 F1 53 65                t_old
00 F1 53 65                t_new
<the 189 PFH bytes above>
1A 5E                      XMODEM CRC of those 17 + 189 bytes
```

It goes to `QST-1`, PID `0xBD`, with 208 information bytes.
The receiver accepts by sending this seven-byte information field to
`N0CALL-9`, PID `0xBB`:

```text
10 78 56 34 12 F5 00
```

`F5 00` requests a maximum piece size of 245. If the directory supplied the
whole PFH but the body is missing, the receiver's hole request is:

```text
12 78 56 34 12 F5 00 BD 00 00 03 00
                     \ offset 189 / \ 3 /
```

A data frame carrying those three body bytes is:

```text
22 78 56 34 12 00 BD 00 00 48 69 0A 2F 81
```

Here `22` sets byte-offset mode and EOF; `00` is text type; `BD 00 00`
is offset 189; `2F 81` is the inner CRC. A sender could also send PFH and body
together in a data piece at offset zero; this repair example deliberately
sends only the missing body.

The completion report, again with **no inner CRC**, is:

```text
12 78 56 34 12 F5 00
```

These vectors were calculated independently using SHA-256, packed LE integers,
and CRC-16/XMODEM, including the `123456789 -> 0x31C3` check. They are useful
codec fixtures; real-peer captures remain necessary.

## 13. Where this fits in HTCommander's Comms tab

### Current implementation

The native application now has **Transfer File...** in the Comms menu. Choose
a file and the destination's exact callsign/SSID, then press **Transmit**.
One outgoing chat card represents the queued offer and subsequent transfer.
Incoming named-recipient and `ALL` offers are handled independently of the
selected tab and appear as cards with **Accept / Reject**. Accepted transfers
show byte progress, **Cancel**, and **Resume** after a pause or loss of signal.
A completed incoming card offers **Save file...**.

The implementation consists of the
[PACSAT codec](../../src/lib/file_transfer/pacsat.dart),
[transfer engine](../../src/lib/file_transfer/file_transfer_engine.dart),
[host radio/storage handler](../../src/lib/handlers/file_transfer_handler.dart),
[send dialog](../../src/lib/dialogs/file_transfer_dialog.dart), and
[chat card](../../src/lib/widgets/file_transfer_card.dart).
It uses the existing radio packet submission path with explicit PID and modem
encoding, rather than BSS Chat. Per-transfer cancellation removes only matching
queued packets; a packet already submitted to the modem/radio can still go out.

Outgoing content and partial incoming files are retained in the application
support `file-transfers` directory. Queue confirmation follows durable storage.
Completed receives are checksum/SHA-256 verified, bounded-inflated if needed,
and saved before their success response becomes eligible to transmit.
Restored active sessions are paused and do not transmit merely because the app
opened. A matching live offer or explicit Resume can continue a receive.
Live radio interruption can resume within two minutes when the same radio,
region, channel and frequencies are available again.

Initial scope is **one-to-one sending** and reception of named or `ALL` files
over hardware or software AFSK 1200. Broadcast sending, other modem encodings,
and browser-based transfer controls are not enabled. Offers heard on the
APRS channel can be displayed, but transmission/acceptance on that channel is
blocked; move both stations to their agreed packet channel and re-offer.
The new UI strings use the localization catalog, with English fallback where
translations have not yet been supplied.

Focused [tests](../../src/test/file_transfer_test.dart) cover independent wire
fixtures, gzip and UTF-8 metadata, byte-hole repair, partial-state restoration,
lossy two-station exchanges, chat buttons, and the native broker/storage path.
These verify the implementation without claiming that APRSConnect peer testing
or over-the-air validation has already happened. The capture-based gates in
section 14 still apply, particularly multipart repair semantics, physical TNC
drain timing, and same-file identity across sender restarts.

### Existing pieces that can be reused

The inspected Dart application already has:

- [`AX25Packet.uiBytes`](../../src/lib/radio/ax25_packet.dart) for binary UI
  information fields. Its default PID is `0xF0`, so set `packet.pid` explicitly
  to `0xBB` or `0xBD`. Its serializer writes addresses, control, PID, and data,
  but not an over-the-air FCS.
- [`TransmitDataFrameData`](../../src/lib/radio/radio.dart) and the
  `TransmitDataFrame` broker event for packet submission with channel, region,
  and encoding selection.
- [`CommsHandler`](../../src/lib/handlers/comms_handler.dart) consuming
  `UniqueDataFrame` and maintaining decoded communications history.
- [`CommsTab`](../../src/lib/widgets/comms_tab.dart) rendering `TextReady`
  history, attachments such as SSTV pictures/recordings, and send-media actions.
- [`FrameDeduplicator`](../../src/lib/handlers/frame_deduplicator.dart) merging
  repeated raw frame observations before `UniqueDataFrame`.

These were the integration points identified before implementation.
BSS Chat is not a PACSAT transport.

### Specific traps in the current paths

**Dispatch before text parsing.** Comms currently tries BSS, then AX.25/APRS,
then a raw text/binary history fallback. Recognize supported PACSAT PIDs and
frame forms before that fallback, or each file piece can become a noisy
"binary data" chat entry. Keep raw packets in capture while updating one
transfer card.

**Review receive eligibility.** The Comms receive path skips ordinary frames
from the channel named `APRS`, and skips non-satellite assigned usages.
A new file handler must have an explicit radio/channel routing policy,
not inherit these text-history filters accidentally.

**Deduplication is not file reassembly.** The inspected deduplicator uses raw
frame hex as a global key with a three-second window. It suppresses historical
frames, but does not key that cache by radio/channel. That can discard the
same bytes on a second link and can hide valid repeated control observations.
Evaluate a link-aware live subscription policy for transfers. Keep interval
deduplication separate, and never let replayed capture traffic trigger live
acceptance or requests.

**Choose the actual modem and VFO.** `TransmitDataFrameData.encoding` can carry
an explicit encoding. Otherwise modem selection follows settings and lock
state; software modes transmit through the audio path on VFO A, while hardware
defaulting can select VFO B in dual-watch operation. A compatibility dialog
must bind the selected channel and AFSK-compatible path, not inherit DART/XARA
or an unintended VFO.

**Host acceptance is not generic delivery feedback.** The inspected transmit
event handler publishes `AprsTransmitResult` only for `aprs-outbox:` tags.
PACSAT needs its own explicit submission/failure and queue-drain contract.
Do not reuse that tag prefix just to get an unrelated APRS event.

**Attachments need an explicit representation.** Existing Comms logic permits
empty text for recordings, pictures, and identifiers, and its SSTV image path
is specific to `Picture`. Arbitrary files and incoming offers need a dedicated
transfer/attachment representation rather than pretending every file is SSTV.

Those observations describe the local worktree inspected for this article;
several related APRS/radio files already had uncommitted edits. Implementation
should recheck their contracts rather than assume this snapshot is permanent.

### Proposed architecture

Keep the initial design small:

1. **Pure PACSAT codec:** PFH TLVs, data/directory/request parsing and encoding,
   LE24 helpers, checksums, and profile validation.
2. **Transfer engine behind the broker:** accepted sessions, byte intervals,
   sender queue, receiver requests, pacing, participant state, and persistence.
3. **Radio adapter:** explicit link selection, binary submission, live receive,
   carrier/airtime observations, disconnect and failure feedback.
4. **Comms presentation:** send-file dialog, incoming offer, progress/state card,
   verified attachment, and operator actions.

Put transfer ownership outside widget lifecycle. Switching tabs must not stop
a session, and rebuilding a widget must not restart a request timer.

Use a single card per transfer, with separate **submitted/sent** and
**receiver-confirmed** progress. For broadcasts, show per-participant state
rather than invent one ambiguous acknowledgement percentage. Include original
size, transmitted size, radio/channel, estimated duration, measured/unmeasured
speed, repair activity, and the reason for a pause or failure.

Suggested sender states:

```text
Queued -> WaitingForChannel -> Offering -> Sending <-> CheckIn
                                      -> AwaitingCompletion -> Completed
             active states -> Paused / NoResponse / Declined / Canceled / Failed
```

Suggested receiver states:

```text
Offered -> Accepted -> Receiving -> Verifying -> Completed
        -> Declined / Expired
        accepted/receiving -> NoSignal -> Receiving
        receiving/verifying -> Failed
```

These names are a proposal, not published APRSConnect enum names. Model timer
epochs so a response cancels old retries, and a stale callback cannot revive
a canceled transfer.

Expose **Send file by radio** alongside existing media actions, with a
destination selector and compatible connected radio selector. Disable it for
APRS-IS and internet pseudo-radios. Put QSY/airtime guidance before confirmation.
Consent should default to manual; always-accept must be an explicit per-station
choice. Keep Pause, Cancel, Resume, Retry, and Check again semantically distinct.

### A staged implementation that proves the right thing

1. Implement codecs and bounded PFH/file validation with the fixtures above.
2. Receive named-recipient offers and files, manual accept/decline only, on
   AFSK 1200. Verify the final bytes and hash from APRSConnect.
3. Add one-to-one sending, pacing, repair, and explicit completion. Test the
   reverse direction against APRSConnect, not just another HTCommander.
4. Add persistence, reconnect behavior, restart matching, and cancel cleanup.
5. Add `ALL` with multiple receivers, late joiners, randomized responses, and
   competing senders.
6. Add optional image preprocessing, always-accept, and faster compatible TNCs
   only after the baseline wire behavior is verified.

The final compatibility target is both named and everyone-listening transfers;
the stages reduce debugging ambiguity, not the scope of the eventual feature.

## 14. Verification checklist for that implementation

### Codec and integrity cases

- Exact encode/decode of the worked PFH and three request forms.
- Data/directory CRC, reversed CRC bytes, corrupt payload, truncated headers,
  unknown flags/versions, and explicit rejection of unsupported length/block mode.
- PFH signature, mandatory ordering/lengths, unknown TLV skipping, missing
  terminator, duplicate/conflicting fields, and invalid body/total offsets.
- Out-of-order, duplicate, overlapping, conflicting, and PFH/body-straddling
  pieces; EOF before earlier data; gaps at both ends.
- Hole lengths 65,535 and 65,536, 49 versus 50 holes, multipart requests,
  zero-length holes, and out-of-file ranges.
- Gzip saves exactly 64 bytes, misses 64 bytes, meets exactly 5%, and misses
  5%; correct checksums of compressed rather than original bytes.
- Decompression cap, false original size, corrupt gzip, UTF-8 filenames,
  dangerous paths, unsupported methods, and missing SHA-256.

### Session and channel cases

- No body before acceptance; exact SSID matching; repeated declines.
- A check-in hole list includes the **unsent tail**; it cannot falsely complete.
- Lost start, lost repairs, lost completion, late completion, and final
  acknowledgement repeats; three missed check-ins stop the sender.
- Slow TNC queue draining; unknown-rate extended waits; link-speed changes.
- Requests use channel-quiet timing, and hearing another station delays bursts.
- Radio reconnect inside/outside two minutes; app restart with no unsolicited
  transmission; resume only on an appropriate link.
- Broadcast with two receivers, one decline, one late joiner, a silent
  participant, and a missing multipart response.
- Two simultaneous senders, callsign tie-breaking, and one queued file that
  remains unannounced.
- Same file ID on different links, live duplicates, and capture replay that
  never starts a real transfer.
- Explicit disk/submission failures and cancellation during queued transmission.

### Capture-based compatibility gates

Record APRSConnect transfers in both directions and inspect raw binary AX.25
bytes, with radio/channel, timestamps, PID, flags, and CRCs preserved. Test
text, random binary, a compressible file, a Unicode name, and a PFH requiring
multiple directory fragments.

Before calling the implementation compatible, resolve:

| Unpublished or ambiguous detail | Evidence needed |
| --- | --- |
| File-ID generation and same-file identity after restart | Re-offers before/after closing the sender, compare PFH and IDs |
| Exact internal names and metadata initialization | Decode offers from several file types |
| Directory fragment size and non-final flags | Capture a long-header offer |
| Directory timestamp epoch | Compare raw values with PFH upload time and actual date |
| Maximum requested piece size semantics | Requests and replies at smaller negotiated sizes |
| Multipart hole-list replacement/union and answer completion | Deliberately fragmented loss with more than 49 holes |
| Response spreading and measured-rate algorithm | Timestamped bursts and replies on slow and fast links |
| Initial offer/retry counts and retry-timer reset events | Controlled losses of start/header/request responses |
| Broadcast participant pruning and stop handling | Multiple independent receiving stations |
| Integrity-failure signaling and completion timing | Corrupted reconstructed content in an isolated test setup |
| Non-ASCII fallback, overlong names, exact inflation cap | Boundary-size files and filenames |
| On-air digipeater path and AX.25 command-bit conventions | Direct and configured-path captures |

APRSConnect exposes packet-log/capture export in its
[Packets documentation](https://aprsconnect.com/docs/packet-log). Confirm that
the exported format preserves these binary PIDs and bytes; do not rely on a
pretty APRS text rendering for a binary protocol.

## 15. What not to mix into compatibility

This is not Winlink, AX.25 connected-mode file upload, BSS, SSTV, or an APRS
message attachment convention. PACSAT's FTL0 connected upload, satellite
PBLIST status messages, directory timeline requests, and Broadcast Update 3
are not prerequisites established by APRSConnect's published profile.

Avoid adding an HTCommander-only envelope, signature trailer, compression
code, or file-type interpretation to "improve" compatibility. Such extensions
would need explicit negotiation and a separately documented format.

Also, binary and compression do not mean encryption. All operators must follow
their license and jurisdiction's content rules. APRSConnect specifically warns
against password-protected/encrypted files under US Part 97 rules prohibiting
encoding intended to obscure meaning. A filename, MIME type, and valid hash
are not a compliance check.

## Sources and further reading

Primary APRSConnect profile:

- [Files by radio](https://aprsconnect.com/docs/files-by-radio) - operator
  workflow, supported transports, limits, gzip profile, extensions, scheduling,
  repair, persistence, and completion behavior.
- [Packet log](https://aprsconnect.com/docs/packet-log) - capture and inspection
  workflow for interoperability testing.

Original PACSAT documents, hosted by Chris Thompson, G0KLA/AC2CZ:

- [PACSAT File Header Definition](https://www.g0kla.com/pacsat/fhead.txt) -
  item IDs, ordering, widths, filename fields, and additive checksums.
- [PACSAT Broadcast Protocol](https://www.g0kla.com/pacsat/broadcst.txt) -
  binary data/request layouts and XMODEM CRC.
- [Broadcast Protocol Update 1](https://www.g0kla.com/pacsat/bdcastu1.txt) -
  corrected data/request flag bits.
- [Broadcast Protocol Update 2](https://www.g0kla.com/pacsat/bdcastu2.txt) -
  directory frame format and compressed-text clarification; the hosted copy
  is labeled a 4 November 1991 draft.
- [PACSAT Data Specification Standards](https://www.g0kla.com/pacsat/dataspec.txt) -
  packed structures, integer widths, little-endian representation, and time.
- [Ground station and document index](https://www.g0kla.com/pacsat/index.php) -
  links to the full suite and an independent ground-station implementation.
- [1990 PFH proceedings paper](https://files.tapr.org/meetings/CNC_1990/CNC1990-PacSatFileHeader-K8KA-NK6K.pdf) -
  original ARRL conference publication.
- [RFC 1952: GZIP file format](https://www.rfc-editor.org/rfc/rfc1952) -
  the compression wrapper named by the profile.

HTCommander integration references:

- [`AX25Packet`](../../src/lib/radio/ax25_packet.dart)
- [`Radio` and `TransmitDataFrameData`](../../src/lib/radio/radio.dart)
- [`CommsHandler`](../../src/lib/handlers/comms_handler.dart)
- [`CommsTab`](../../src/lib/widgets/comms_tab.dart)
- [`FrameDeduplicator`](../../src/lib/handlers/frame_deduplicator.dart)

The practical conclusion: **reuse PACSAT's wire format, implement
APRSConnect's consent/repair/timing profile, and prove both directions against
the actual peer before exposing a success state in Comms.**
