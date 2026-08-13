# Decoding Distress: 406 MHz SARSAT Beacons in HTCommander

*How a handheld FM radio can pick a satellite distress beacon out of the air, and
how HTCommander turns that half-second burst into a country, a beacon ID, and a
position on a map. This post covers what COSPAS-SARSAT is, what a first-generation
406 MHz beacon actually transmits (phase-modulated, not FM), why decoding it on a
Benshi is a strange fit, the two demodulators (coherent and FM-demod) and BCH
error-correction we built in pure Dart, how we proved it works — synthetically and
then on a real beacon recording — and how it surfaces as its own Comms message
type and a map marker.*

---

## What is SARSAT?

**COSPAS-SARSAT** is the international satellite system that finds people in
distress. The name is a mouthful from two Cold-War-era programs that merged:
**SARSAT** (Search And Rescue Satellite-Aided Tracking, from the US, Canada, and
France) and **COSPAS** (the Russian equivalent). Today it is a single global
network, and it is the reason a life raft in the middle of an ocean can be found.

The pieces on the ground are **406 MHz distress beacons**. They come in three
flavours, all doing the same job for different vehicles:

| Beacon | Used by | Trigger |
|---|---|---|
| **EPIRB** | Ships / life rafts | Water immersion or manual |
| **ELT** | Aircraft | Crash G-force or manual |
| **PLB** | People (hikers, pilots) | Manual only |

When one activates, it transmits a short digital **burst — about half a second,
once every ~50 seconds — on 406 MHz**. A constellation of satellites (in low,
medium, and geostationary orbits) hears that burst, relays it to ground stations,
and those stations decode the beacon's identity and, if the beacon has a GPS
receiver, its position. A rescue coordination centre is alerted with a unique
15-character beacon ID that maps to a registered owner, and help is dispatched.

Two important framing facts for what follows:

- **406.0–406.1 MHz is a protected, satellite-monitored distress band.** You
  never transmit there. Everything in this post is **receive-only**, and the
  right way to experiment is with the official *test* beacons and recordings.
- The old analog **121.5 MHz** homing signal is no longer satellite-monitored
  (since 2009). The digital 406 MHz message is the whole game now.

---

## What a first-generation beacon actually sends

There are two generations of 406 beacon. The classic **first generation (FGB,
spec C/S T.001)** — sometimes called *v1g* — is what HTCommander decodes. The
newer **second generation (SGB, T.018)** uses direct-sequence spread-spectrum
OQPSK and needs raw IQ from an SDR to demodulate; it is out of scope here (and
for an FM audio path, out of reach).

A v1g beacon is deceptively simple on paper and surprisingly awkward in
practice. The transmission is:

1. An **unmodulated carrier** for the first 160 ms (so receivers can lock on).
2. Then the message: **144 bits** (long format) or **112 bits** (short) sent at
   **400 bits per second**.

The tricky part is *how* those bits are carried. The data is **biphase-L
(Manchester) encoded** and used to **phase-modulate the carrier by ±1.1 radians**.
That is **PSK — phase-shift keying — not FM, and not audio tones.** The carrier's
phase swings a little more than ±63° with every half-bit. There's no 1200/2200 Hz
AFSK, no clean tone to detect; the information lives in the *angle* of the
carrier.

The 144-bit frame is laid out like this:

| Bits (1-indexed) | Field |
|---|---|
| 1–15 | Bit sync — fifteen `1`s |
| 16–24 | Frame sync — `000101111` (normal) or `011010000` (self-test) |
| 25 | Format flag (1 = long/144, 0 = short/112) |
| 26 | Protocol flag |
| 27–36 | Country code (10 bits) |
| 37–40 | Protocol code |
| 26–85 | **15-hex beacon ID** (the unique identifier) |
| 86–106 | **BCH-1** error-correction parity (21 bits) |
| 107–132 | Position / protocol data (PDF-2) |
| 133–144 | **BCH-2** error-correction parity (12 bits) |

Those two BCH fields matter enormously. A beacon burst is short, faint, and
one-shot; the two BCH ("CRC") codes let a receiver **detect and correct** a
handful of bit errors and, just as importantly, *know for certain* when it has a
clean frame versus noise. We lean on them hard.

---

## Why this is a strange fit for a Benshi

HTCommander drives Benshi-class FM handhelds (UV-Pro, GA-5WB, VR-N76, …). Two
things make 406 decoding an odd match — and one surprising thing makes it
possible at all.

**The frequency is (just) out of band.** 406 MHz sits below the 70 cm amateur
band. But many of these radios have **wideband receive** that happily covers
406 MHz, and the app already stores and tunes frequencies as raw Hz. So *tuning*
there is plausible on a lot of hardware.

**The modulation is wrong for the radio.** The radio is an FM voice set. It does
its own FM demodulation internally and streams **SBC-compressed audio** to the
app over Bluetooth. Feeding a *phase-modulated* PSK signal through an *FM*
demodulator and a lossy voice codec is not how a textbook 406 receiver works — a
proper one uses SSB/coherent detection or raw IQ from an SDR.

**But it works anyway, within limits.** The community (F4EHY's decoders, the
`rtl_fm` + 12 kHz filter recipe) has long shown that a 406 burst *can* be pulled
out of an FM-demodulated audio stream: the phase transitions survive as
detectable features. It's the weaker of the two approaches — the reference
`dec406` project measures roughly 62% decode rate through FM audio versus ~75%
with coherent IQ — but it is real. That's the door HTCommander walks through:
the beacon is decodable from audio, and audio is exactly what the radio gives us.

The honest caveat, stated up front: a stock Benshi's SBC-compressed,
post-de-emphasis audio sits at the *low* end of that quality range. This feature
is a genuine "best-effort" decoder, not a certified receiver.

---

## The demodulators, step by step

A 406 beacon can reach us in two very different audio *shapes*, so the
demodulator ([`sarsat_1g_demodulator.dart`](../../src/lib/sarsat/sarsat_1g_demodulator.dart))
runs **two independent front-ends** and keeps whichever produces a BCH-valid
frame.

### Path 1 — coherent (phase tone)

Recorded on an SSB/CW receiver — or a discriminator / `rtl_fm` feed that keeps
the tone intact — the beacon looks like exactly what it physically is: a ±1.1 rad
phase-modulated carrier. We treat it as one:

1. **DC block.** Remove the mean.
2. **Carrier estimate.** A ±1.1 rad PSK signal still has a strong *residual
   carrier* component (it isn't ±90°, so the carrier is only reduced, not
   suppressed). We sweep candidate frequencies and pick the one whose baseband
   DC magnitude peaks — that's the carrier.
3. **Quadrature mix + low-pass.** Multiply by cosine and sine at the estimated
   carrier to drop to baseband I/Q, then a boxcar low-pass sized to null the
   `2×carrier` image.
4. **De-rotate.** Rotate the baseband so the residual carrier lands on the real
   axis. Now the modulation sits cleanly around zero, swinging to +1.1 or −1.1
   radians — the phase *is* the data.
5. **Matched-filter sync.** Correlate the known 24-bit sync pattern (fifteen
   `1`s plus the frame sync) against the recovered phase to find exactly where a
   frame starts.
6. **Biphase-L slice.** At each sync anchor, integrate the phase over each
   half-bit and Manchester-decode to bits, at 400 bps, trying both polarities.

The one subtlety worth calling out is **timing**. At a 400 bps symbol rate, even
a tiny error in the assumed samples-per-bit accumulates over a 144-bit frame and
*slips* a bit — the front of the frame decodes perfectly and the tail turns to
mush. Locking the symbol clock precisely (we anchor on the matched-filter sync
and use the exact samples-per-bit for the file's sample rate) is what makes the
whole frame land.

### Path 2 — FM-demod (autocorrelation)

Here's the catch that Path 1 alone can't handle: a Benshi (and `rtl_fm -M fm`)
hands us **FM-demodulated** audio, where the beacon's phase transitions arrive as
a transition-pulse waveform, not a clean tone — and the coherent chain simply
can't lock onto it. That's the audio shape that actually matters for real-world
reception, so we ported the reference `dec406` `capture_trame` slicer: a
delay-and-multiply **autocorrelation at one-bit lag** that finds the 15-bit sync
run and reconstructs the frame straight from the transition timing. It decodes
the FM-demod waveform the coherent path can't — **and self-test beacons fall out
of it for free**, because it never hard-codes a frame-sync pattern.

Both paths hand their candidate 144- (or 112-) bit frame to the same decoder.

---

## Error correction and the frame decoder

Once we have candidate bits, the decoder
([`sarsat_1g_decoder.dart`](../../src/lib/sarsat/sarsat_1g_decoder.dart)) does the
real work, ported bit-for-bit from the reference `dec406_v1g.c` so the field
layout and polynomials match exactly:

- **BCH-1 / BCH-2 check and correct.** The two codes are computed with the
  standard COSPAS-SARSAT generator polynomials. If a frame doesn't validate, we
  try flipping up to three bits in the protected span until it does. Because
  BCH-1 has 21 parity bits, a *passing* frame is proof — a random 21-bit match is
  a one-in-two-million accident, so "BCH OK" means "this is a real beacon
  message," not noise dressed up as one.
- **Field parsing.** Country code, protocol classification (Standard Location,
  User-Location, ELT-DT, National, RLS, Ship Security, Test…), the **15-hex
  beacon ID** (with the protocol-dependent default-position masks the spec
  requires), an identification string (MMSI, aircraft address, serial), and —
  for the location protocols — a **decoded latitude/longitude**.

The result is a small `Sarsat1gFrame` object: BCH status, country, protocol,
hex ID, and position.

---

## How we proved it works

We had no 406 transmitter on the bench (and you can't just key one up on a
protected distress band), so verification started entirely self-contained \u2014 and
then, when a real recording turned up, gained a genuine on-air check. Four layers,
all in the test suite
([`sarsat_1g_test.dart`](../../src/test/sarsat_1g_test.dart)):

**1. Golden frames from an oracle encoder.** The reference BCH isn't a textbook
systematic code, so we couldn't just hand-write parity bits. Instead we built a
BCH *encoder* by solving the parity with Gaussian elimination over GF(2), using
the reference CRC as an oracle — and verified it reproduces the exact parity of a
known-good published beacon frame (`8E3301E2402B002BBA863609670908`). With that,
we can mint valid frames carrying any fields we like — including a Standard
Location frame at a *known* 43.75° N, 7.25° E — and assert the decoder reads them
back correctly.

**2. Error-correction tests.** Inject 1, 2, and 3 bit errors into the protected
field and confirm the decoder corrects exactly that many and recovers the
original beacon ID.

**3. A round-trip modulator.** We wrote the *inverse* of the demodulator — a
small modulator that renders a frame as an ideal ±1.1 rad biphase-L PSK tone — and
feed it straight back through the demodulator. It must recover the frame **exactly**,
at 32 kHz, 37.5 kHz, and 48 kHz sample rates, and it still decodes with additive
noise (~13 dB SNR). This is the strongest test: it exercises the entire
audio → carrier → phase → bits → fields chain end-to-end, and it's fully
reproducible with no external files.

There's even a streaming test that feeds the monitor 256-byte PCM chunks — the
exact cadence the audio engine delivers — then flushes, to prove the real-time
buffering path decodes a burst the same way the batch path does.

**4. And then, a real beacon.** Someone supplied a genuine recording of a 406
self-test beacon (`Sarsat.wav` — FM-demodulated, 32 kHz mono). Dropped straight
through the production demodulator it decodes cleanly, with **both BCH fields
valid**: a France (country 227) ELT-DT self-test beacon, hex ID
`1C72091A2B3FDFF`. It's the case that exercises the FM-demod path *and* self-test
sync on a real signal — and it's now a committed test fixture, so the real-signal
path is a permanent regression, not a one-off.

---

## Wiring it into HTCommander

The decoder and demodulator are standalone libraries; a thin **monitor**
([`sarsat_monitor.dart`](../../src/lib/sarsat/sarsat_monitor.dart)) glues them to
the live audio pipeline, mirroring how the Morse and SSTV decoders already work.
It buffers received PCM for the length of a burst and runs the batch demodulator
on *flush* (the end of the audio run), emitting a decoded frame for every valid
message it finds.

### It turns itself on

The first version had a "Decode SARSAT 406" checkbox, then a check on the tuned
frequency. But a frequency gate turned out to be too rigid: **training beacons
don't have to live on 406 MHz** — one operator's test transmitter runs on
434 MHz. So instead of a switch or a hard-coded band, the monitor is always
allocated but only *fed audio* from a channel the operator has **named
`sarsat`** (case-insensitive):

```dart
if (usage == null &&
    !transmit &&
    channelName.toLowerCase() == 'sarsat') {
  // ...buffer this burst for decoding...
}
```

Make a channel called "SARSAT" on whatever frequency your beacon uses — 406 MHz
for the real thing, 434 MHz for a trainer — and decoding self-activates while
that channel is selected. Switch to any other channel and it stops. No setting to
remember, and no assumption about frequency.

### It shows up as its own message type

When a beacon decodes, it lands in the Comms tab as a distinct message type — a
red **SOS** icon and a `SARSAT` label — carrying the hex ID, the country **by
name** (not just the numeric code), the protocol, and, when present, the
position. Opening its details breaks the frame down field by field, right down to
the raw hex.

Because a beacon repeats every ~50 s, a busy channel would otherwise flood the
tab, so we **coalesce** repeats of the same beacon ID within a minute into a
single bubble that counts them: the header reads **“SARSAT ×5”** while the bubble
keeps the latest decode. And because it flows through the same message model as
APRS, a beacon that reports coordinates gets the same treatment — a tappable
**“Show Location…”**, and a red **SOS marker dropped on the Map tab**.

There's also a Debug-tab helper to replay a `.wav` into the app as if it were
received on VFO A, so the whole decode → message → map path can be exercised from
a file without a radio on the bench.

---

## The honest ledger

What works today, and what's still on the bench:

- ✅ **v1g frame decode** — BCH check + up to 3-bit correction, country,
  protocol, 15-hex ID, and position for the common location protocols.
- ✅ **Two demodulators** — coherent (phase tone) and FM-demod (autocorrelation),
  verified end-to-end by round-trip *and* on a real FM-demodulated recording.
- ✅ **Surfaces cleanly** — auto-activates on a channel named `sarsat`, a distinct
  Comms message type with country name and “×N” coalescing, and an SOS map marker.
- ⚠️ **Real FM audio, at scale, is still the open question.** One genuine
  FM-demod recording decodes cleanly, but a stock Benshi's SBC-compressed,
  de-emphasized audio is the weakest link and its reliability across many
  real-world bursts is unproven. A raw discriminator or `rtl_fm` feed will
  always do better.
- ⚠️ **Self-test beacons** are handled by the FM-demod path (which is the one
  that matters for real FM audio); the coherent path's matched filter still only
  anchors on the *normal* frame sync.
- ⚠️ **Position parsing covers Standard Location and User-Location**; the other
  location protocols (ELT-DT, National, RLS…) are classified but not yet fully
  geo-decoded, so an ELT-DT self-test won't plot a pin even though everything
  else about it decodes.
- ❌ **Second-generation (SGB) beacons** — DSSS/OQPSK, needs IQ, not attempted.

And the standing rule, worth repeating: this is **receive-only**. 406 MHz is a
distress band. Decode the official test beacons, learn how the system works, and
never transmit there.

---

**Related:** [Keying by Hand: Morse Key Support](morse-key-support.md) ·
[Getting Audio Off the Main Thread](audio-isolate-threading.md)
