# The Radio's Secret Handshake: Reverse-Engineering the BSS Protocol

*APRS is an open book. But Baofeng/BTech radios also speak a second, undocumented
binary language for text, location, and "ring my radio" alerts — called BSS.
Here's a field note on what it is, how it's framed, and how HTCommander decodes
and speaks it.*

---

## Two languages on one channel

HTCommander talks to its radios in two messaging dialects. The first is
**APRS** — the venerable, thoroughly-documented amateur packet standard. The
second is **BSS**, a compact binary format that appears to be proprietary to
Baofeng / BTech and comes with no public specification at all. If you want your
app to show a text message a UV-Pro user sent from the radio's own keypad, or to
answer that radio's "where are you?" query, you have to speak BSS.

So we reverse-engineered it. This post is the working documentation: a
byte-level tour of the frame format, the field catalog, the request commands,
and — in the house tradition — an honest ledger of the parts we still haven't
fully pinned down.

## One byte that changes everything

BSS rides inside the same AFSK frames that carry AX.25 packets, so the first job
of a decoder is telling the two apart. BSS makes that trivial: **every BSS packet
begins with the byte `0x01`.** AX.25 frames never start that way, so a single
byte at offset zero is enough to route a frame to the right parser:

```
data[0] == 0x01  →  it's BSS
```

Everything after that leading `0x01` is a stream of self-describing fields.

## Length-type-value, all the way down

BSS is a **TLV** format — a run of *length / type / value* triplets, one after
another, until the frame runs out. Each field looks like:

```
[length][type][value bytes...]
```

The one detail that trips people up: **the length byte counts the type byte
too.** A field with a length of `0x07` is *seven bytes total* — one type byte
plus six bytes of value. So `value length = length − 1`. Get that off by one and
every field after it desyncs.

Because each field announces its own size, a decoder never has to guess where a
field ends, and — crucially — it can skip over field types it doesn't recognize
and keep going. More on that below.

## Decoding a real packet by hand

Here's an actual BSS packet as it comes off the air:

```
0107204B4B37565A540121062468656C6C6F072514C72DC7CDF1
```

Walk it left to right. The first byte is `01`, so it's BSS. After that, read a
length, a type, then that many value bytes, and repeat:

```
01                      // BSS marker
07 20 4B4B37565A54      // len 7 → type 0x20 (From),    "KK7VZT"
01 21                   // len 1 → type 0x21 (To),       "" (empty)
06 24 68656C6C6F        // len 6 → type 0x24 (Message),  "hello"
07 25 14C72DC7CDF1      // len 7 → type 0x25 (Location),  raw GPS bytes
```

That's a text message *"hello"* from `KK7VZT` with a position attached. The
`To` field is present but empty here — an oddity that shows up sometimes;
usually the field is simply absent rather than zero-length.

## The `0x85` sentinel: a message ID, not a length

There's one exception to the tidy length-type-value rhythm. If the "length" byte
reads **`0x85`**, it isn't a length at all — it's a marker announcing a
**message ID**, carried in the next two bytes, most-significant byte first:

```
85 00 07                // Message ID = 0x0007
```

The decoder special-cases it: see `0x85`, read two bytes as a big-endian
integer, advance three bytes, carry on. The message ID is a sequence number,
and it earns its keep mostly on *requests* (below): if the same request arrives
twice — a common thing on a noisy channel — the receiver can match the ID and
ignore the duplicate instead of, say, ringing twice.

When HTCommander builds a packet, the ID is written right after the callsign
field, before everything else.

## The field catalog

These are the field types decoded so far, keyed by their type byte:

| Type   | Name             | Value                                             |
| ------ | ---------------- | ------------------------------------------------- |
| `0x20` | Callsign (From)  | Source callsign, e.g. `KK7VZT` or `KK7VZT-0`      |
| `0x21` | Destination (To) | Addressee callsign (often absent for broadcasts)  |
| `0x24` | Message          | UTF-8 text                                        |
| `0x25` | Location         | Packed binary GPS fix (see below)                 |
| `0x27` | Location Request | A callsign string — "tell me where you are"       |
| `0x28` | Call Request     | A callsign string — "ring this radio"             |

Callsigns and messages are plain strings; the location field is a binary blob.

## Requests: "where are you?" and "ring!"

Two of the field types aren't data at all — they're *commands* aimed at another
station, and they're where the message ID pulls its weight.

A **location request** (`0x27`) carries the target callsign and asks that radio
to report its position:

```
01                      // BSS marker
07 20 4B4B37565A54      // From "KK7VZT"
85 00 05                // Message ID = 0x0005
09 27 4B4B37565A542D37  // Location request → "KK7VZT-7"
```

A **call request** (`0x28`) is the fun one: it makes the target radio *beep like
an incoming phone call*.

```
01                      // BSS marker
07 20 4B4B37565A54      // From "KK7VZT"
85 00 02                // Message ID = 0x0002
09 28 4B4B37565A542D37  // Call request → "KK7VZT-7"
```

In both, the `09` length means type + eight bytes of callsign (`KK7VZT-7`), and
the message ID lets the receiver reject a retransmitted request so a single
"ring" doesn't turn into three.

## Inside the location field

The location field (`0x25`) is a packed binary GPS fix. At minimum it carries
**latitude and longitude**, and it can be extended with **altitude, speed, and
heading**:

```
0D 25 14C72DC7CDF1002A00000151   // len 13 → type 0x25, 12 bytes of GPS
```

The length tells you how much is there, so a receiver can take just the
lat/long from a short field or the full kinematic set from a long one.

This is also the honest edge of what we've mapped. HTCommander's decoder
currently surfaces the **raw location bytes** and doesn't yet crack the exact
fixed-point scaling of each sub-field — so positions from BSS packets aren't
plotted the way APRS positions are. The framing is solid; the interior number
format of this one field is the piece still on the workbench.

## Building a BSS packet

Encoding is the mirror image of decoding: write `0x01`, then emit each present
field as length-type-value with `length = value.length + 1`. HTCommander writes
them in a fixed order — callsign, message ID, destination, message, location,
location request, call request — which keeps generated packets consistent and
easy to diff against captures.

Empty fields are simply skipped, which is why a real "From-only" ident packet is
just the marker, one callsign field, and nothing else.

## Forward-compatible by accident (and on purpose)

Because every field is self-sizing, an unknown type byte isn't fatal — you read
its length, skip its value, and move on. HTCommander leans into this: any field
type it doesn't recognize is preserved verbatim in a raw-fields map and
**re-emitted on encode**. That means a packet round-trips losslessly even if it
contains something we haven't decoded yet, and it leaves room to learn new field
types without breaking old ones. For a protocol we're mapping as we go, that
graceful-degradation property is worth a lot.

## The honest ledger

What we're confident about:

- The `0x01` marker and the length-includes-type TLV framing.
- The `0x85` message-ID sentinel (two bytes, big-endian) and its use for
  de-duplicating requests.
- Six field types: callsign, destination, message, location, location request,
  and call request — and that the two request types trigger a position report
  and an audible "ring" respectively.

What's still open:

- The exact fixed-point layout of the location field's latitude, longitude,
  altitude, speed, and heading sub-fields.
- Whatever other field types exist that we simply haven't seen on the air yet —
  which is exactly why unknown fields are preserved rather than dropped.

BSS turned out to be a small, sensible protocol hiding behind zero documentation:
a marker byte, self-describing fields, one clever sentinel for message IDs, and a
couple of remote-command verbs. Enough of it is mapped that HTCommander can read
a UV-Pro's text messages, answer its location queries, and — if you like — make a
friend's radio ring from across town.

---

**Related:** [BSS Protocol notes](../BSS-Protocol.md) ·
[Every Command a Benshi Radio Understands](radio-command-protocol.md)
