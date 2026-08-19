# HTCommander Technology Blog

Field notes and deep dives on the technology behind **HTCommander** — the
cross-platform app for controlling Benshi handheld radios (BTech UV-Pro,
RadioOddity GA-5WB, Vero VR-N76 / VR-N7500, and friends).

These posts document the engineering as it happens: real-world findings,
protocol reverse-engineering, DSP experiments, and the honest ledger of what
works, what doesn't, and what we still don't know. New topics are added as we go.

---

## DART Modem

Building and tuning **DART** (Data Adaptive Rate Transport), an adaptive OFDM
modem for sending data over ordinary VHF/UHF **FM voice** radios (2 m / 70 cm)
across a Bluetooth (SBC) audio link. Best read in order — each post builds on the
last, walking from the first over-the-air observation down to the root-cause
diagnosis and fix.

1. **[Pushing Data Through FM Voice Radios: Real-World Findings](dart-over-the-air-findings.md)**
   The first over-the-air test on two UV-Pro radios. Which modes work, which fail,
   and the first evidence that the quality ceiling lives in the *audio path* — not
   the RF, band, or transmit level.

2. **[Does SBC Bitpool Matter?](dart-sbc-bitpool.md)**
   The Bluetooth SBC codec adds a small noise floor under the signal. We measure
   how much, and show that raising the bitpool saturates quickly and never moves
   the ceiling.

3. **[Inside SBC: Loudness vs. SNR Bit Allocation](dart-sbc-allocation.md)**
   How SBC spends its bits across subbands, and why its default *loudness*
   allocation is the wrong choice for data — a free quality gain from switching
   data frames to *SNR* allocation.

4. **[Chasing a Ghost: Proving (and Fixing) the Real Limiter](dart-phase-noise-and-pilots.md)**
   Building a phase-noise channel model and a phase-drift meter to turn "it's
   probably phase noise" into a measurement — then fixing it with pilot-aided
   phase tracking, recovering a rung of throughput, and showing the remaining
   ceiling is raw SNR (a link-budget problem), not DSP.

5. **[The Bits You Already Know: Code Shortening for Short Frames](dart-code-shortening.md)**
   A lopsided constellation reveals that short frames are mostly known
   zero-padding. Telling the decoder those bits are known (code shortening) buys
   5+ dB of margin on short frames — for free, and scaling exactly with how short
   the frame is.

6. **[Is 125 Microseconds Enough? A Look at Inter-Symbol Interference](dart-inter-symbol-interference.md)**
   Building a multipath echo channel to test whether DART's deliberately-short
   cyclic prefix is big enough. It finds the classic ISI knee at the CP boundary,
   confirms the SBC/audio path adds no dispersion the CP misses, and shows the
   short-CP bet was safe.

7. **[Whitening the Signal: Why a Modem Scrambles Its Own Data](dart-scrambling.md)**
   Why repetitive data (a frame full of zeros) wrecks spectrum, PAPR, and phase
   tracking — and why the fix is to make the data look like noise first. Compares
   the self-synchronizing G3RUH scrambler against an additive frame-synchronous
   one, and lays out the LDPC-friendly PN15 whitener DART will adopt.

**Related:** [DART Implementation Report](../DART-Implementation-Report.md) ·
[Next-Gen Modem design spec](../NextGenModem.md) ·
[Proposal / rationale](../findings/next-gen-modem-proposal.md)

---

## Firmware Updates

FIguring out the radio's firmware-update path — from
the cloud check that finds an update to the two-phase Bluetooth flash that writes
it into the radio.

1. **[How a Benshi Radio Updates Its Firmware, Step by Step](benshi-firmware-update.md)**
   A walk through the firmware-update path — from the cloud update check and
   patch-based download to the device-paced, two-phase GAIA transfer that streams
   a new image into the radio over Bluetooth.

2. **[Where Does the Firmware Come From? Inside the Benshi Update Server](benshi-firmware-server.md)**
   A field report on the online side — the gRPC check, the patch-based download,
   and the honest ledger of what we've proven and the DID puzzle we still can't
   crack.

---

## Radio Protocol

The low-level language HTCommander and the radio speak to each other.

1. **[Every Command a Benshi Radio Understands: A Complete Protocol Reference](radio-command-protocol.md)**
   A byte-level reference for the whole control protocol — the two Bluetooth
   framings, the command envelope and response bit, the full basic/extended
   opcode set, the bit-packed layout of every important payload (device info,
   settings, channels, HT status, GPS position, BSS, FM radio, buttons), the
   notification model, and the two sub-protocols that ride on top: fragmented TNC
   data carrying AX.25 packets, and the VM firmware-update channel.

2. **[The Radio's Secret Handshake: Reverse-Engineering the BSS Protocol](bss-protocol.md)**
   A field note on **BSS**, the undocumented Baofeng/BTech binary format for text,
   location, and "ring my radio" alerts — the `0x01` marker that separates it from
   AX.25, the length-includes-type TLV framing, a packet decoded by hand, the
   `0x85` message-ID sentinel, the field catalog and the location-request /
   call-request verbs, and an honest ledger of the location bytes still on the
   workbench.

---

## Sharing & Interop

Making HTCommander features portable between operators and radios.

1. **[A Channel You Can Text: The Channel-Share String](channel-share-string.md)**
   A compact, human-readable one-line format that encodes a whole radio channel —
   frequency, offset, tones, bandwidth, modulation, and flags — so you can drag a
   channel into a chat, send it (even over the air), and have the recipient drop
   it straight into their radio.

---

## APRS

Getting more out of APRS on a handheld — hearing packets the radio's own modem
would have thrown away.

1. **[Two Modems Are Better Than One: Running a Software APRS Modem Alongside the Radio's](aprs-dual-modem.md)**
   How HTCommander decodes APRS twice — once with the radio's built-in hardware
   TNC and once with a software AFSK 1200 modem on the SBC audio stream that adds
   FX.25 forward error correction and CRC-based bit recovery, the deduplicator
   that merges both sources without doubles, how to turn it on from the Audio
   menu, and how the single- vs. double-arrow marks in the Packets tab show which
   modem caught each packet.

---

## Messaging & Security

Trusting what comes off the air — proving who sent a message, without breaking
the no-encryption rules.

1. **[Signing the Airwaves: Authenticating APRS Messages Without Encryption](aprs-message-authentication.md)**
   How HTCommander proves an APRS message really came from who it claims — and
   isn't a replay of an old one — by appending a six-character HMAC-SHA256 token
   keyed by a shared password: the wire format that stays backward compatible,
   the who/what/when string that gets signed, the minute-based freshness window,
   why ACKs must be re-signed, and where key exchange stays out of scope.

---

## Home Automation & Integrations

Connecting HTCommander to the wider ecosystem of tools operators already run.

1. **[Your Radio, on the Dashboard: Home Assistant Integration over MQTT](home-assistant-mqtt.md)**
   How HTCommander publishes each connected radio to Home Assistant as its own
   device — battery, GPS, volume, squelch, scan, channels, and incoming APRS —
   using an MQTT broker and Home Assistant's auto-discovery, plus a step-by-step
   setup guide. Desktop-only (Windows / Linux / macOS).

---

## Troubleshooting & Support

Getting good diagnostics out of the app when something goes wrong.

1. **[It Crashed — Now What? How to Report a Crash in HTCommander](crash-reporting.md)**
   A user-facing guide to capturing what went wrong — exporting the Debug tab
   log, finding the on-disk `htcommander_crash.log` on every platform, running
   from a terminal when the app won't start at all, checking the OS crash
   reporter, and exactly what to include so a report is actionable on the first
   try.

---

## Internet Linking

Bringing internet-linked voice into the same app that drives the radio.

1. **[Radio Over the Internet: Adding EchoLink to HTCommander](echolink-support.md)**
   A full walk through the EchoLink stack in pure Dart — the GSM voice codec, the
   UDP audio/control ports and TCP directory, the RTCP SDES/BYE handshake that
   opens a QSO, how voice and chat are wrapped, what callsign suffixes and node
   numbers mean, a NAT pinhole that quietly eats receive audio, and how to get an
   account and make your first connection.

2. **[Radio and Internet, Two Ways: Planning APRS-IS for HTCommander](aprs-is-integration.md)**
   A design note written before the first line of code — what APRS-IS is, the
   single-line passcode login, the TNC2 ⟷ AX.25 codec that lets internet packets
   reuse the existing APRS pipeline, the full-IGate rules for gating between RF
   and the internet (q-constructs, NOGATE, the "recently heard" list), and the
   receive-only-first test plan.

3. **[Dialing In: Adding AllStarLink Support to HTCommander](allstarlink-support.md)**
   How we speak Asterisk's native **IAX2** protocol from pure Dart to connect to
   an AllStarLink node — the single-UDP-port design, full vs. mini frames, the
   NEW/AUTHREQ/AUTHREP/ACCEPT/ANSWER call handshake, MD5 challenge-response auth,
   GSM and μ-law voice, UDP reliability with sequence numbers and the 0x8000
   timestamp-resync trick, why we connect client-to-node (DVSwitch/iaxRPT style),
   and how to configure a node and make your first call.

4. **[Becoming the Node: Hosting an AllStarLink Node in HTCommander](allstarlink-node-support.md)**
   The other direction — turning HTCommander into a **node** others dial *into*.
   Running the inbound IAX2 server (the handshake in reverse), sharing one socket
   between calls and registration by call-number range, IAX2 registration so the
   network can find you, and the radio relay: bridging 8 kHz call audio to a
   handheld's PTT with half-duplex carrier arbitration so local RF always wins.
   Plus accepting **Web Transceiver** clients safely by validating their portal
   token the way a real `app_rpt` node does.

---

## Voice & CW

Sending and shaping audio through the radio — from the microphone to Morse.

1. **[Keying by Hand: Morse Key Support in HTCommander](morse-key-support.md)**
   How a USB morse key — straight or paddle — plugs in and sends real, hand-timed
   Morse over an ordinary FM handheld: why FM Morse differs from classic CW, how
   we key an FM transmitter that has no "key up," the keyboard-style key bindings
   (`[` / `]` or Left / Right Ctrl), the iambic keyer and WPM timing, the
   low-latency sidetone, and the Off / Test / Live start-and-tail logic.

---

## Satellites

Working amateur radio satellites with a handheld — tracking, passes, and Doppler.

1. **[Working the Birds: Amateur Satellite Support in HTCommander](satellite-tracking.md)**
   How HTCommander tracks the FM "easy sats" — SGP4 orbit propagation via the
   `satellite_observer` package, orbital elements from CelesTrak and transponder
   frequencies from SatNOGS (with a bundled offline seed), the tab and map ground
   track/footprint overlay, Doppler-corrected up/downlink from range-rate — and
   the honest ledger of what's left: driving the radio's own native
   `SET_SATELLITE_INFO` command, whose payload isn't decoded yet.

---

## Emergency Beacons

Pulling life-saving signals out of the air — receive-only, on protected bands.

1. **[Decoding Distress: 406 MHz SARSAT Beacons in HTCommander](sarsat-406-beacon-decoding.md)**
   How a handheld FM radio can pick a satellite distress beacon out of the air:
   what COSPAS-SARSAT is, why a first-generation 406 MHz beacon is
   phase-modulated (not FM), the two demodulators (coherent and FM-demod) and BCH
   error-correction we built in pure Dart, how we proved it works — with a
   round-trip modulator, an oracle-built BCH encoder, and finally a real beacon
   recording that decodes with both BCH fields valid — and how decoding activates
   on a channel named `sarsat` (so a 406 MHz beacon or a 434 MHz trainer both
   work), surfacing a country, a 15-hex beacon ID, and a position as its own
   Comms message type with an SOS map marker.

---

## Weather Balloons

Turning a handheld into an upper-air receiver — decoding the radiosondes that
launch worldwide twice a day.

1. **[Catching Weather Balloons: Radiosonde Decoding in HTCommander](radiosonde-decoding.md)**
   How HTCommander decodes six different radiosonde families from one channel —
   Vaisala **RS41**, Graw **DFM**, Meteomodem **M10/M20**, InterMet **iMet**, and
   Lockheed Martin **LMS6** — each with its own modem (GFSK, Manchester,
   differential Manchester, Bell-202 AFSK, convolutional-coded NRZ) and
   error-correction (Reed–Solomon, Hamming, CRC, a custom checksum) ported to pure
   Dart; why the older **RS92** can't be positioned offline; how it's proved with
   synthetic round-trip tests; and how decoding self-activates on a channel named
   `Radiosonde`, plotting each balloon's climb and descent on the map.

---

## Data & Storage

How HTCommander packs large datasets into small, fast, self-contained files.

1. **[1.6 Million Hams in Your Pocket: Compacting the FCC Callsign Database](fcc-callsign-compaction.md)**
   How the FCC's weekly amateur-license dump becomes a small binary `.cdb` you can
   binary-search offline — and the stack of encoding tricks (base-37 packed keys,
   an offset-free index, epoch-relative dates, state/class/status/city
   dictionaries, numeric ZIPs, and xz) that shrink every record to the bone.

2. **[90,000 Hams North of the Border: Compacting the Canadian Callsign Database](ised-callsign-compaction.md)**
   How the same `.cdb` format is reused for Canada's ISED amateur data behind a
   single header flag — and the three encoding changes the Canadian data forced:
   alphanumeric postal codes packed in alternating bases, qualifications as a
   bitmask instead of class/status, and dropping expiry dates that never exist.

---

## App Architecture

How HTCommander is built under the hood — the threading, plumbing, and design
decisions that keep the radio responsive.

1. **[Getting Audio Off the Main Thread: Moving the Radio Pipeline to Its Own Isolate](audio-isolate-threading.md)**
   Why the whole receive pipeline — SBC decode, software modem, and SSTV — runs on
   the UI thread today and stutters when the interface is busy, and the plan to
   move it into a dedicated background isolate with playback fed straight from the
   worker. Written before the work begins.

---

## Building & Contributing

Getting a full HTCommander development environment running on your own machine.

1. **[Build It Yourself: Compiling HTCommander on Every Platform](building-from-source.md)**
   A start-to-finish guide to installing Flutter and building HTCommander from
   source on Windows, macOS, Linux, Android, iOS, and the web — including the
   exact system packages each desktop target needs (and the GStreamer, BlueZ, and
   PulseAudio libraries Linux trips over first).

---

*More topics coming as the project grows.*
