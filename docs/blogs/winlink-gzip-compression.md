# GZIP Over Winlink: A Small Extension With Some Important Edges

*How wl2k-go's experimental GZIP message compression works, and how we could
add compatible support to HTCommander without breaking ordinary Winlink mail.*

**Status:** Implemented in HTCommander, November 2026 (see
[the implementation update](#update-how-htcommander-implemented-it) at the
end). The first half of this post documents wl2k-go's behavior. GZIP support in
this experiment is not evidence that production Winlink CMS or RMS software
supports it.

## The idea: change the compressor, not the mail system

Winlink B2F normally compresses messages with **LZHUF**. The experimental
extension in [wl2k-go](https://github.com/la5nta/wl2k-go) substitutes **GZIP**,
using two explicit protocol signals:

- A **`G` capability** in the station identification (SID) line says that the
  station can handle GZIP proposals.
- An **`FD` proposal**, instead of `FC`, says that this particular message's
  compressed payload is a GZIP stream.

Everything around that payload remains B2F: message serialization, proposal
responses, binary blocks, transfer checksum, and session turn-taking.
It is not HTTP content encoding, a ZIP attachment, or compression of the whole
connection.

The attraction is a standard, widely available codec. Better compression would
also save airtime, but **GZIP is not guaranteed to beat LZHUF**. Small messages
pay for GZIP's wrapper, and already-compressed attachments may gain little.
We should measure representative serialized messages before claiming a speedup.

## 1. How wl2k-go enables and negotiates it

The [upstream experiment description][go-readme] documents the runtime switch:

```powershell
$env:GZIP_EXPERIMENT = '1'
```

Set this in the process environment before launching the application that uses
wl2k-go. Only the exact value `1` enables the experiment.

In [the handshake implementation][go-handshake], the normal capability string
is `B2FHM$`. Enabling the experiment inserts `G` **before the terminal `$`**:

```text
[Application-Version-B2FHMG$]
```

The application name and version are supplied by the caller; `G` belongs to the
capability field, not the name. The remote SID parser uppercases that field.

For outbound messages, [the session's proposal selection][go-session] chooses:

| Local experiment | Remote SID contains `G` | Outbound format |
|---|---|---|
| Off | Either | `FC`, LZHUF |
| On | No | `FC`, LZHUF |
| On | Yes | `FD`, GZIP |

This is capability-based fallback **before proposing the message**. There is no
compress-both-and-pick-the-smaller policy: when negotiated, wl2k-go selects GZIP
even if LZHUF would produce fewer bytes.

An important implementation detail: the switch gates **advertisement and
outbound selection**, not all decoding. The inbound code recognizes `FD` and
permits GZIP proposals even when the local environment switch is off, and does
not require the sender's SID to contain `G`. That receive-side permissiveness is
an observation about this implementation, not a requirement to copy it.

## 2. What goes into a GZIP payload

The [message code][go-message] first serializes a complete Winlink message:
headers, the blank line separating headers from content, body bytes, and any
attachment sections. The proposal's uncompressed size is the length of those
serialized bytes, **not just the body length**.

In [the proposal code][go-proposal], a `GzipProposal` selects Go's
`compress/gzip` writer at `gzip.BestCompression` (level 9). Closing the writer
finishes the stream before its bytes and length are saved in the proposal.
Other proposal codes use the existing B2 LZHUF writer.

The payload layouts are different:

```text
FC: [B2 CRC16: 2 bytes] [original length: 4 bytes, LE] [LZHUF data]
FD: [GZIP header] [DEFLATE data] [CRC32: 4 bytes, LE] [ISIZE: 4 bytes, LE]
```

An ordinary GZIP stream starts with `1F 8B`; its compression-method byte is `08`.
The GZIP trailer carries the uncompressed-data CRC32 and original size modulo
2^32. **Do not prepend the LZHUF CRC16/length header to an FD payload.**
Likewise, raw DEFLATE or a zlib-wrapped stream is not a substitute for GZIP.

On reception, wl2k-go selects the decompressor **from the proposal code**:
`D` uses `gzip.NewReader`, while `C` uses the B2 LZHUF reader. The decompressed
bytes then go through the ordinary Winlink message parser.

The format does not require byte-identical compressor output between Go and
Dart. Different valid GZIP headers and DEFLATE choices are acceptable; decoding,
lengths, checksums, and recovered message bytes must agree.

## 3. Proposals and checksums

A GZIP proposal has the same fields as a type-C proposal:

```text
FD EM <MID> <uncompressed-size> <compressed-size> 0\r
```

Here `FD` is the two-character wire command; `D` is the proposal code.
The [upstream parser][go-proposal] accepts message types `EM` and `CM`.
Its outbound constructor uses `EM`.

- **MID:** the message identifier.
- **Uncompressed size:** the complete serialized message byte count.
- **Compressed size:** the complete GZIP stream byte count, including its
  header and trailer, but **excluding B2F binary framing**.
- **Final `0`:** the field emitted by upstream for both C and D proposals.
  Keep it as-is; do not reinterpret it as a compression-level selector.

As [the B2F transfer code][go-b2f] shows, proposal blocks still end in
`F> XX\r`. `XX` is the two-digit hexadecimal additive checksum:

```text
XX = (-sum(all proposal-line bytes, including each trailing CR)) & 0xFF
```

Compute it over the actual lines sent. Replacing `FC` with `FD` changes the
checksum even when all other fields are identical. A receiver must not
reconstruct every line with a hard-coded `FC` prefix.

The receiver responds with the existing `FS` answer string, one answer per
proposal. wl2k-go sends `+` for accept, `-` for reject, and `=` for defer; its
parser also accepts equivalent forms such as `Y`, `N`, and `H`.
No GZIP-specific acceptance command is added.

## 4. Binary transfer is still B2F

After acceptance, the same binary envelope carries either codec:

```text
01 <header-length> <title> 00 <ASCII offset> 00
02 <length> <compressed bytes...>
02 <length> <compressed bytes...>
...
04 <checksum>
```

The one-byte header length counts the title, offset, and their two NUL
terminators. wl2k-go word-encodes the title for ASCII transport. The checksum
after `04` is the two's complement of the sum of the **transmitted compressed
payload bytes**, modulo 256; it excludes block markers and lengths.

wl2k-go currently sends at most **125 payload bytes** per data block.
Its receiver understands a zero data-block length as **256 bytes**. These
chunking choices are independent of compression and are not GZIP record
boundaries.

For normal zero-offset reception, upstream verifies both the outer checksum and
that the accumulated compressed payload length equals the proposal's compressed
size, then decompresses it. GZIP validation supplies another integrity check
through its CRC32/trailer; it does not replace the outer B2F checksum.

Keep the initial implementation at **offset zero**. Although the common sender
can slice its compressed buffer at a requested offset, upstream's ordinary
receive path expects offset zero and does not assemble a retained prefix for
resuming. A GZIP suffix alone is not independently decompressible.

## Where HTCommander stands today

The current implementation already has the right layers, but assumes LZHUF at
several boundaries:

| Area | Current behavior | Needed for GZIP |
|---|---|---|
| [Mail codec][ht-mail] | Serializes mail, LZHUF-compresses it, frames it; decodes via LZHUF | Explicit per-message codec selection around unchanged serialization |
| [Compression utilities][ht-utils] | Implements B2 LZHUF and its CRC16 | Preserve this path; add a separate GZIP branch |
| [Winlink client][ht-client] | Sends a fixed SID, emits/accepts `FC`, saves proposal fields without the command | Parse remote SID, negotiate, retain `C`/`D`, and dispatch by proposal |
| [Local BBS][ht-bbs] | Has its own banner, proposal handling, and mail encode/decode calls | Apply the same negotiation and proposal rules per connected station |
| [CMS relay][ht-relay] | Relays CMS protocol traffic rather than decoding mail | Preserve endpoint capabilities and payload bytes; do not invent support |

The client feeds TCP, AX.25, and XARA traffic into the common stream processor.
The codec change belongs above those transports; it does not call for changing
the modem, AX.25 framing, or radio firmware.

### A prerequisite: distinguish payload size from transfer size

There is a concrete interoperability trap in
[`WinLinkMail.encodeMailToBlocks`][ht-mail]. It currently reports
`compressedSize = output.length`, where `output` includes the binary header,
data-block markers/lengths, and final checksum. Both client and local BBS put
that value in their proposals.

wl2k-go instead advertises `len(compressedData)` and compares that value against
the **payload bytes only** at receive time. An HTCommander FD proposal that
continues advertising the framed length would therefore fail upstream's length
check, even with a perfectly valid GZIP stream.

The implementation must expose or clearly distinguish:

```text
uncompressedSize = serializedMail.length
compressedSize   = compressedPayload.length
transferSize     = framedOutput.length
```

Use the payload size in **both FC and FD** proposals; retain framed size for
transfer accounting where needed. Update both senders together and regression
test existing FC sessions. This is a directly coupled compatibility correction,
not a reason to rewrite the LZHUF codec.

## A practical implementation plan

### Step 1: make the message codec explicit

Add a small codec selector, for example `lzhuf` / `gzip`, to
[`encodeMailToBlocks` and `decodeBlocksToEmail`][ht-mail], keeping LZHUF as the
default for existing callers. Decode should also receive the proposal's expected
uncompressed and compressed sizes.

The pipeline should become:

```text
Send:    serialize mail -> selected compressor -> common B2F framing
Receive: common B2F framing -> selected decompressor -> deserialize mail
```

Reuse the existing [`archive` dependency][ht-pubspec], which already provides
`GZipEncoder` and `GZipDecoder`; [mail backup/import][ht-backup] uses them today.
No new package or native library is inherently required. Use a valid GZIP
encoder, optionally at level 9 to follow upstream's policy, and explicitly
verify decoder checksum behavior for the installed package version.

The existing decoder reads the expected LZHUF length from payload bytes 2-5.
That must stay **inside the LZHUF branch**: in GZIP those bytes are header
metadata, not a length. Check the actual decompressed length against the
proposal, with a bounded decode rather than trusting GZIP's ISIZE.

### Step 2: retain proposals, not just their arguments

Both [the client][ht-client] and [local BBS][ht-bbs] currently store proposal
argument strings and reconstruct `FC ...\r` for checksum validation.
Preserve the exact received proposal line for checksumming, together with parsed
code, MID, sizes, and message type. A small shared typed proposal representation
would prevent the client and server from implementing different rules.

Accept both `FC` and `FD` through that common path. Choose the decoder per
accepted proposal, not once for the session, so mixed C/D batches stay correctly
associated with their payloads. Validate numeric fields and limits before
accepting; unsupported proposals must get an explicit defer or protocol error,
not disappear and misalign the `FS` responses.

### Step 3: negotiate before preparing outbound mail

For each new client session or local-BBS connection:

1. Reset the stored remote capabilities.
2. Parse the capability field of the remote SID, not arbitrary banner text.
3. Advertise `G` only when the experimental feature is enabled and decoding is
   ready. Keep `$` last.
4. Choose GZIP only when locally enabled and the remote SID advertises `G`.
   Otherwise send ordinary FC/LZHUF.
5. Cache the exact encoded payload/blocks used to build the proposal so the
   accepted transfer agrees with its declared codec and sizes.

Use an opt-in experimental setting, default **off**, snapshotted for the session.
An environment variable alone would not be a suitable cross-platform user
setting for HTCommander.

For a first release, receive policy should also be explicit: defer unsolicited
FD proposals while the experiment is disabled, and support either C or D while
enabled. This is deliberately stricter than wl2k-go's permissive receive path.
Never advertise `G` before both encoding and decoding are usable.

Keep existing authentication unchanged. The only required SID change is the
capability flag; changing the currently advertised application identity is a
separate decision.

### Step 4: keep local BBS and CMS relay behavior distinct

In local P2P mode HTCommander is the mail endpoint. Its banner, inbound handler,
outbound proposals, and extraction path all need the same codec support as the
client, with capabilities held **per BBS link**, not globally.

In relay mode the far endpoint is the CMS. The BBS currently forwards the CMS
SID when available and uses a non-GZIP fallback banner otherwise.
**Do not add `G` to that relay banner just because HTCommander can decode GZIP
locally.** The relay does not terminate and transcode the mail protocol.

If both endpoints support the experiment, FD lines and binary bytes should pass
through unchanged. Exercise the relay's text/binary mode transitions with real
accepted-proposal responses; do not assume pass-through means it is already
verified for every peer's `FS` spelling.

### Step 5: make malformed input fail visibly

The current framing/decoding path needs a few tightly related safeguards before
we expose another codec:

- Treat a zero STX length as 256 and bounds-check every header, block, and EOT
  checksum byte across fragmented receives.
- Enforce compressed-size and decompressed-size limits, stop bounded inflation
  when the output limit is reached, and verify both lengths against the proposal.
- Validate the outer checksum and GZIP integrity checks before parsing or storing
  the message. Do not retry failed GZIP bytes as LZHUF.
- Preserve remaining buffered bytes and drain complete accepted messages in
  order, including multiple messages delivered in one transport callback.
- Distinguish incomplete input, successful completion, and decoding failure.
  Currently the client's extraction failure can return the same completion
  signal that makes its caller send `FF`; a bad GZIP message must instead log
  the failure, notify the user, and take an explicit error/disconnect path.

The Go implementation also has limitations worth not copying: decompression
errors in `Proposal.Data` panic, and that method does not independently enforce
the proposal's uncompressed-size limit.

## How we would prove compatibility

Extend the existing [mail tests][ht-mail-tests] and
[client session tests][ht-client-tests], plus local-BBS tests, rather than adding
a second protocol test framework.

| Test | Required result |
|---|---|
| Feature off; feature on with no remote `G` | Normal SID/FC behavior; legacy LZHUF fixtures still decode |
| Feature on with remote `G` | Advertise `G` before `$`, propose FD, send a valid GZIP stream |
| Disconnect and reconnect to a non-GZIP peer | No capability leakage; return to FC |
| Mixed FC/FD batch | Exact-line proposal checksum; one response per proposal; correct decoder for each accepted message |
| Go-produced FD fixture decoded by Dart | Recover exact serialized bytes, body, Unicode text, and binary attachment data |
| Dart-produced FD fixture read by wl2k-go | Upstream accepts payload size, outer checksum, GZIP stream, and message |
| Corrupt/truncated GZIP with recomputed outer checksum | GZIP failure remains visible; no inbox insertion or success-shaped session completion |
| Incorrect sizes or excessive inflated output | Bounded, explicit failure without uncontrolled allocation |
| Fragmented/coalesced transport input | Headers, 256-byte data blocks, EOT, multiple messages, and trailing control lines remain aligned |
| Local BBS and transparent relay sessions | Per-link negotiation in local mode; no capability invention or transcoding in relay mode |

Compare decoded bytes, not compressed-byte equality. Include a text-only
Go-produced message: upstream serialization and HTCommander's serializer do
not add exactly the same trailing separators, so an HTCommander-only round trip
is not sufficient evidence of interoperability.

Start with fixtures and a controlled peer running wl2k-go with
`GZIP_EXPERIMENT=1`, not a production CMS assumption. Log codec, payload size,
framed size, and errors without logging credentials. Benchmark actual airtime
separately from compression ratio: block overhead, radio turnaround, retries,
and modem throughput all matter.

## The bottom line

The extension itself is refreshingly small: **advertise `G`, propose `FD`, put a
standard GZIP stream inside ordinary B2F blocks**. HTCommander already has the
codec dependency and shared transport path.

The real work is carrying the proposal code end-to-end, correcting the
payload-size contract, negotiating separately for each endpoint, and proving
that malformed or fragmented input cannot be mistaken for successful delivery.
Do those pieces first, keep the experiment opt-in, and ordinary FC/LZHUF peers
can continue operating without knowing GZIP exists.

## Update: how HTCommander implemented it

The implementation follows the plan above, with a few concrete choices:

- **Setting:** *Settings → Winlink → Use GZIP compression with compatible
  stations*, stored as `WinlinkGzipCompression`, **enabled by default**. Turning
  it off restores the exact pre-GZIP SIDs and FC-only behavior.
- **Client (TCP, AX.25, XARA):** HTCommander adds `G` to its SID **only when the
  server's SID already contains `G`**. Against the CMS and every RMS that does
  not advertise GZIP, the client sends byte-for-byte the same SID as before.
- **Local BBS:** the banner advertises `G` when the setting is on, and mail is
  sent as FD only to a station whose SID also contains `G`. In CMS relay mode the
  BBS still forwards the CMS's own SID and never invents `G`.
- **Receiving:** FD is accepted only in a session where HTCommander advertised
  `G`; otherwise it is answered with `H` (defer), keeping the `FS` answers
  aligned with the proposals.
- **Sizes:** both FC and FD proposals now carry the compressed **payload** size,
  not the framed transfer size, matching wl2k-go and other B2F software.
- **Integrity:** GZIP is decoded with CRC32 verification and is bounded by, and
  must exactly match, the proposed uncompressed size. A message that fails to
  decode (GZIP or LZHUF) now ends the session without acknowledging it, so the
  sender keeps it and retries instead of treating it as delivered.

The shared negotiation and proposal parsing live in
[`winlink_proposal.dart`][ht-proposal], and are covered by
[codec tests][ht-gzip-tests], client session tests, and BBS tests.

## Source notes

Reviewed local wl2k-go revision
`efde6fbcb7bc8d6519fd8018ec544c793d4ef48d` and HTCommander revision
`a13a74fd456a705dca5db816358bb12cc6d9f7f7`. Upstream links below are pinned to
the inspected revision; HTCommander links point to the working source tree.

[go-readme]: https://github.com/la5nta/wl2k-go/blob/efde6fbcb7bc8d6519fd8018ec544c793d4ef48d/README.md#gzip-experiment
[go-handshake]: https://github.com/la5nta/wl2k-go/blob/efde6fbcb7bc8d6519fd8018ec544c793d4ef48d/fbb/handshake.go
[go-session]: https://github.com/la5nta/wl2k-go/blob/efde6fbcb7bc8d6519fd8018ec544c793d4ef48d/fbb/wl2k.go
[go-proposal]: https://github.com/la5nta/wl2k-go/blob/efde6fbcb7bc8d6519fd8018ec544c793d4ef48d/fbb/proposal.go
[go-b2f]: https://github.com/la5nta/wl2k-go/blob/efde6fbcb7bc8d6519fd8018ec544c793d4ef48d/fbb/b2f.go
[go-message]: https://github.com/la5nta/wl2k-go/blob/efde6fbcb7bc8d6519fd8018ec544c793d4ef48d/fbb/message.go
[ht-mail]: ../../src/lib/winlink/winlink_mail.dart
[ht-utils]: ../../src/lib/winlink/winlink_utils.dart
[ht-client]: ../../src/lib/winlink/winlink_client.dart
[ht-bbs]: ../../src/lib/handlers/bbs_handler.dart
[ht-relay]: ../../src/lib/winlink/winlink_gateway_relay.dart
[ht-pubspec]: ../../src/pubspec.yaml
[ht-backup]: ../../src/lib/widgets/mail_tab.dart
[ht-mail-tests]: ../../src/test/winlink_mail_test.dart
[ht-client-tests]: ../../src/test/winlink_client_test.dart
[ht-proposal]: ../../src/lib/winlink/winlink_proposal.dart
[ht-gzip-tests]: ../../src/test/winlink_gzip_test.dart
