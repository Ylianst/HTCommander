# Whitening the Signal: Why a Modem Scrambles Its Own Data

*Seventh in our series on running data over FM voice radios. So far we've chased
phase noise, argued with the SBC codec, and shortened codes. This time we tackle
a quieter problem — what happens when the data you're sending is *boring*, and why
every serious modem deliberately scrambles its own bits before putting them on the
air.*

---

## The problem with sending zeros

Radios don't like patterns. Send a long run of the same byte — a file full of
zeros, a padded frame, an idle keep-alive — and a naïve modem faithfully turns it
into a long run of the same symbol. That sounds harmless. It isn't.

For a QAM modem like DART, a repetitive bit stream causes four separate
headaches at once:

- **Spectral lines.** A periodic symbol pattern concentrates energy at a few
  frequencies instead of spreading it across the band. Those spikes eat into your
  peak power budget and can even splatter outside the intended passband.
- **PAPR blows up.** Our whole waveform choice — DFT-spread OFDM — exists to keep
  the peak-to-average power ratio low so the radio's limiter doesn't crush us. A
  pathological repeating pattern can undo that and hand back a high crest factor.
- **The constellation collapses.** If the coded bits barely change, the QAM
  symbols pile onto a handful of constellation points. Now the decision-directed
  channel refinement and the pilot-based phase tracker — the very machinery we
  built in [Part 4](dart-phase-noise-and-pilots.md) — are trying to estimate the
  channel from a signal that never exercises most of the constellation.
- **Recovery loops starve.** Timing and carrier recovery live on *transitions*. A
  DC-like stream gives them nothing to lock to.

The fix is almost paradoxical: to make the data robust, you first make it look
like **random noise**. That's scrambling — also called *energy dispersal* or
*whitening*. You XOR the data against a known pseudo-random bit sequence before
transmit, and XOR it back at the receiver. The channel sees a nice flat,
noise-like spectrum regardless of what the user actually sent; the receiver
undoes the scramble and gets the real bytes back.

## "But doesn't LDPC already randomize things?"

This was our first instinct too — DART already runs every payload through an LDPC
encoder and a block interleaver. Surely that scrambles the bits enough?

No, and the reason is worth stating clearly because it decides *where* the
scrambler has to go. LDPC is **linear**: the all-zero input encodes to the
all-zero codeword. Feed the encoder a block of zeros and you get a block of
zeros out the other side — parity and all. The interleaver just shuffles those
zeros into different zeros. So an all-zero payload sails straight through FEC and
interleaving and still maps to the same constellation point over and over.

That single fact rules out the tempting option of scrambling the *user* bytes
before the encoder. To actually whiten the **transmitted symbols**, the scrambler
has to sit **after** LDPC and interleaving — right before the constellation
mapper. Whiten the coded bits, and even an all-zero payload produces a
full-entropy symbol stream.

## The two families of scrambler

There are two classic ways to build one, and the choice matters a lot for a
FEC-protected link.

### Multiplicative (self-synchronizing) — the G3RUH approach

If you've done 9600-baud packet radio, you've already met this one. The **G3RUH**
scrambler — standard on 9600-baud AX.25, and already implemented elsewhere in
HTCommander for exactly that mode — uses the polynomial:

```
x^17 + x^12 + 1
```

It's *multiplicative* (or *self-synchronizing*): the transmitted bit is fed back
into the shift register. The beautiful property is that the receiver's
descrambler needs no frame sync at all — it locks itself automatically after a
handful of bits, no matter where it started listening. That's perfect for a
continuous, unframed bit stream like classic 9600 FSK, which has no preamble to
anchor to.

But it has a nasty side effect: **error multiplication**. Because each received
bit is fed back through the taps, a *single* channel bit error produces several
descrambled errors — one for each feedback tap, so three errors per bit for
`x^17 + x^12 + 1`. On raw 9600 that's a minor annoyance. In front of a **soft
LDPC decoder** it's a disaster: it corrupts the log-likelihood ratios and turns
one weak bit into a small burst of wrong ones, precisely the input FEC is worst
at. Self-synchronizing scramblers and modern soft FEC are a bad marriage.

### Additive (frame-synchronous) — reset every frame

The other family is *additive* (or *frame-synchronous*). Here the pseudo-random
sequence is generated independently — a plain LFSR, **reset to a fixed seed at the
start of every frame** — and simply XORed onto the data. There's no feedback from
the channel, so:

- **No error multiplication.** One channel error stays exactly one error. FEC
  sees the clean, additive-noise picture it was designed for.
- **Soft-decision friendly.** Descrambling a *hard* bit is an XOR; descrambling a
  *soft* LLR is even simpler — where the scramble bit is 1 you just **flip the
  sign** of the LLR. It's completely lossless for the decoder.

The one thing it needs is frame synchronization — the receiver has to know where
the frame starts so it can reset its LFSR to the same seed. DART already has
that: the Zadoff-Chu / chirp preamble exists precisely to nail down frame timing.
The cost we'd pay for a self-synchronizing scrambler is a cost we've already paid.

Here's the trade laid out:

| | Multiplicative (G3RUH) | Additive (frame-sync) |
|---|---|---|
| Sync | Self-synchronizing (free) | Needs frame sync |
| Error behavior | **Multiplies** errors ×(taps+1) | **1 error → 1 error** |
| Soft FEC (LDPC) | Corrupts LLRs | Clean LLR sign-flip |
| Best fit | Continuous unframed streams (9600 AX.25) | Framed, FEC'd packets (DART) |

For a framed, LDPC-protected, QAM packet modem the answer isn't close. Additive
wins.

## Picking the polynomial

An additive scrambler is only as good as its sequence length. If the LFSR's
period is shorter than the frame, the "random" pattern repeats within a single
packet — and a repeating pattern is exactly the periodic structure we were trying
to destroy. So the period has to comfortably exceed the longest frame's coded-bit
count.

A DART payload can reach ~1 kB, which after FEC is on the order of 16,000 coded
bits. That immediately disqualifies the popular short generators:

| Polynomial | Name | Period | Verdict for DART |
|---|---|---:|---|
| `x^7 + x^4 + 1` | PN7 | 127 | Repeats ~130×/frame ✗ |
| `x^9 + x^5 + 1` | PN9 (BLE, 802.11) | 511 | Repeats ~30×/frame ✗ |
| `x^15 + x^14 + 1` | PN15 (DVB) | 32,767 | **No repeat within a frame ✓** |
| `x^23 + x^18 + 1` | PN23 (DVB-S) | 8,388,607 | Overkill headroom ✓ |

**PN15** (`x^15 + x^14 + 1`, period 32,767) clears the largest frame with room to
spare and is a well-worn choice — it's the DVB energy-dispersal generator. That's
what DART will adopt. PN23 is the fallback if frames ever grow past PN15's
headroom.

## The plan for DART

Concretely, the scrambler slots into the existing chain at exactly one point on
each side, and nothing else moves.

**Transmit** — after interleaving, before the symbol mapper:

```
payload → CRC-32 → LDPC encode → interleave → [SCRAMBLE] → map → SC-FDMA → PCM
```

**Receive** — after soft demapping, before deinterleaving:

```
PCM → demod → soft-demap (LLRs) → [DESCRAMBLE] → deinterleave → LDPC → CRC
```

The mechanics:

- A **PN15 LFSR**, reset to a fixed constant seed at the start of each frame's
  payload, produces a bit for every coded bit.
- **TX:** XOR that PN sequence onto the interleaved coded bits — the last thing
  that happens in the bit domain before symbols are formed.
- **RX:** descrambling is a **conditional sign-flip** on the soft LLRs (`llr =
  -llr` wherever the PN bit is 1), applied before deinterleave. No hard decisions,
  no loss of soft information going into the LDPC decoder.
- The same generator covers both the OFDM modes (0–5) and the Mode F fallback —
  they share the interleave/deinterleave stage, so they share the scrambler for
  free.

Because it's additive and frame-reset, it's invisible to everything downstream: a
bit error is still one bit error, the LDPC decoder sees exactly the channel it was
designed for, and the constellation, PAPR, and phase-tracking machinery all get a
uniformly-exercised, noise-like symbol stream to work with — even when the user is
sending a megabyte of zeros.

## What we expect to see

Two measurements will tell us it worked, both using tools we already built:

- **PAPR on a worst-case payload.** Encode an all-zero frame and compare the crest
  factor with and without scrambling. Without it, all-zeros is close to the
  worst pattern the modulator can produce; with it, the PAPR should collapse back
  to the same value as random data.
- **No decode regression.** Loopback across all modes, clean and through the SBC
  codec with noise, has to stay green — scrambling must be a pure whitening pass
  that the receiver perfectly undoes, costing nothing in sensitivity.

That's the bar: a flatter spectrum and tamer peaks on pathological data, zero cost
on everything else. We'll report the numbers once it's wired in.

---

*Modem: DART adaptive OFDM (SC-FDMA) + LDPC in HTCommander. The G3RUH
(`x^17 + x^12 + 1`) scrambler referenced here is the same one HTCommander already
uses for 9600-baud AX.25. Seventh in a series.*
