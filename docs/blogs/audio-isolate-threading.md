# Getting Audio Off the Main Thread: Moving the Radio Pipeline to Its Own Isolate

*A design note that started life **before** we wrote any code — the plan and the
reasoning behind it — now updated with what we found actually building it.
HTCommander decodes Bluetooth audio, plays it, demodulates data, and decodes SSTV
images, and until recently it did all of that on the same thread that paints the
user interface. This is the story of why that's a problem, why the honest fix is a
dedicated audio isolate, and the one hard lesson that reshaped the design.*

---

> **Update (build notes).** Phase 1 has landed: SBC decode, WAV recording and the
> transmit pacing loop now run in a dedicated background isolate. Along the way we
> hit a wall that changed the architecture — **you cannot play audio from a
> background isolate** — and the reasons are worth a section of their own (see
> *“The hard lesson”* below). The plan sections are kept as originally written;
> the findings correct them where reality disagreed.

---

## The symptom: audio that stutters when the UI is busy

The bug report is easy to reproduce. Open HTCommander, start receiving audio, then
drag the window, resize a panel, or scroll a long list. The audio hitches. Not the
radio, not the Bluetooth link — the *playback* itself breaks up, precisely while
the interface is doing something expensive.

That timing is the whole clue. If audio glitches exactly when the UI is busy, then
audio and the UI are competing for the same resource. In a Flutter app, that
resource is the **main isolate** — the single thread that runs your Dart code and
drives the widget rebuild/layout/paint cycle. Whatever else is running there has
to wait its turn.

And right now, *everything* audio runs there.

## Where the time actually goes

Follow an incoming audio frame through the app and every stop is on the main
isolate:

```
Bluetooth RFCOMM bytes
  → EventChannel delivers them to the main isolate
    → frame extraction / unescaping
      → SBC decode  (pure-Dart codec, real CPU)
        → volume scaling → feed the speaker
          → dispatch "AudioDataAvailable" on the DataBroker
             → software modem demodulation  (per-sample AFSK / PSK / DART)
             → SSTV monitor  (tone detection, image decode)
             → WAV recording, metering, waveform UI
```

Two things about that pipeline make it fragile.

**First, the DataBroker dispatch is synchronous.** HTCommander's `DataBroker` is a
publish/subscribe hub, and when audio publishes an `AudioDataAvailable` event the
broker calls every subscriber *inline, in a plain loop, on the calling thread*.
So the software modem's demodulator and the SSTV decoder don't run "later" or
"in the background" — they run **inside** the audio frame handler, one after
another, before control returns. A single 80 ms audio frame can trigger tens of
thousands of per-sample demodulator iterations right there in the hot path.

**Second, none of it yields to the UI.** The frame handler is one long
synchronous call. While it runs, the main isolate cannot rebuild a widget or paint
a pixel — and while the UI is mid-paint, that same handler cannot run to feed the
next block of audio to the speaker. They take turns, and whoever is mid-task makes
the other wait. That mutual blocking *is* the stutter.

There's a telling comment buried in the DSP port, in `audio_buffer.dart`:

> *the original C# used lock objects for thread safety. The Dart port is single
> threaded (per isolate), so the locks are omitted.*

The demodulator was originally written to run on its own thread. When it was
ported to Dart, the locks were dropped — correctly, because there was only one
thread now. But that also quietly moved a genuinely multi-threaded DSP workload
onto the UI thread. We never gave it a thread of its own back. This plan is about
returning it.

## Why "just make it async" isn't enough

The tempting quick fix is to sprinkle `async`/`await` around and hope the work
interleaves with the UI. It won't help, and it's worth being precise about why.

`async` in Dart does **not** create a new thread. An `await` only yields at
suspension points; the CPU-bound loop between two awaits still runs to completion
on the same isolate, still blocking paint. You can chop a demodulator into smaller
async chunks, but that just trades one long stall for many small ones and adds
scheduling jitter — bad for a real-time audio stream that wants steady, on-time
delivery. Audio doesn't want to be *fair*; it wants to be *uninterrupted*.

The only way to run Dart code truly in parallel with the UI is a second
**isolate** — Dart's model of an independent worker with its own memory and event
loop, communicating by message passing. That's the real fix.

## The plan: a dedicated audio isolate

We're going to move the whole receive pipeline into one long-lived background
isolate and leave the main isolate to do what it's good at — driving the UI.

```
 MAIN ISOLATE (UI)                         AUDIO ISOLATE (DSP + playback)
 ─────────────────                         ──────────────────────────────
 EventChannel receives BT bytes  ──raw──▶  frame extract / unescape
 forwards them (zero-copy)                 SBC decode
                                           feed the speaker  (real-time)
 re-dispatches to DataBroker  ◀─batched──  software modem demod  → data frames
 (recording, STT, waveform UI)             SSTV decode           → images
 control (mode, mute, volume) ──events──▶  (consumed in-isolate, no round trip)
```

The division of labour follows one rule: **the real-time path lives in the
isolate; the UI gets updates when it can take them.** Concretely:

- **The audio isolate owns the clock-sensitive work** — SBC decode and, crucially,
  feeding the speaker. Playback is now driven by a thread that never has to stop
  to paint a frame, so it stays on time no matter what the UI is doing.
- **The modem and SSTV decoders move in too**, and they consume the decoded PCM
  *right there* in the isolate. No broker round-trip, no synchronous fan-out on
  the UI thread. When they produce something meaningful — a decoded AX.25 frame, a
  finished SSTV image — that result is sent to the main isolate as a message.
- **The DataBroker dispatch becomes non-real-time.** The isolate batches full,
  lossless PCM (say every 100–200 ms) and ships it back to the main isolate, which
  publishes `AudioDataAvailable` for the things that genuinely live on the UI side:
  the waveform display, the WAV recorder, and speech-to-text. None of those need
  sample-immediate delivery; they need *complete, in-order* audio, which batching
  preserves.

That last point is exactly the trade the problem allows. Playback and
demodulation must be prompt. The broker fan-out — the recording, the scope, the
transcription — does not. So we make the prompt part prompt, and let the rest
arrive in tidy batches a fraction of a second later.

## The hard lesson: you can't play audio from a background isolate

Most of the pipeline is pure Dart — the SBC decoder, the modem, the SSTV
decoder — and pure Dart moves between isolates without ceremony. The catch is the
speaker.

Playback goes through a **platform channel** to native code (a small PCM player
plugin on Windows, macOS, and Linux; `flutter_pcm_sound` on Android). The original
plan leaned on a Flutter 3.7 feature: capture a `RootIsolateToken` on the main
isolate, hand it to the worker, call
`BackgroundIsolateBinaryMessenger.ensureInitialized(token)`, and then invoke the
player's `MethodChannel` straight from the worker. We built exactly that — and the
app crashed the instant it opened the audio device:

```
Unsupported operation: Background isolates do not support setMessageHandler().
Messages from the host platform always go to the root isolate.
```

Here's the asymmetry we'd missed. A background isolate can **send** to the
platform — `invokeMethod` calls are proxied to the platform thread just fine. What
it *cannot* do is **receive**: no `EventChannel` streams, no `setMethodCallHandler`,
no native-to-Dart callbacks. As the error says plainly, messages *from* the host
platform always go to the root isolate, full stop.

And our PCM player needs to receive. It exposes a **drain callback** — the native
side tells Dart “the buffer has fallen below the threshold, send more” — over an
`EventChannel`. That callback is how we apply back-pressure and decide when to drop
a chunk to catch up. It is native-to-Dart, so it simply cannot be wired up from a
background isolate. (The same is true of `flutter_pcm_sound` on Android, whose feed
callback rides a method channel the same way.) The player, in other words, is
inherently a root-isolate citizen.

So we took the fallback the plan had already reserved, and it turned out to be the
better design anyway: **the player stays on the root isolate; the isolate does the
CPU work and hands finished PCM back for the host to feed.**

```
 MAIN ISOLATE (UI + plugins)               AUDIO ISOLATE (pure-Dart DSP)
 ─────────────────────────                 ────────────────────────────
 EventChannel receives BT bytes  ──raw──▶  frame extract / unescape
 forwards them (zero-copy)                 SBC decode  (real CPU)
 feed the speaker  ◀───PCM───────────────  volume-scale + record
 relay to Bluetooth  ◀──framed TX────────  transmit SBC encode + pacing
 re-dispatch to DataBroker  ◀──events────  (modem + SSTV land here in Phase 2)
 control (mode, mute, volume) ──cmds────▶
```

The crucial realisation is that **feeding the device is cheap** — it's a single
`invokeMethod` that hands a buffer to native code, which has its own audio thread
and its own ring buffer (about 125 ms of it). What was expensive, and what actually
caused the stutter, was the *SBC decode and demodulation* sitting in front of that
feed. Move those off the UI isolate and the main isolate has almost nothing left to
do per frame — so even mid-paint it can service the feed promptly and the ring
buffer never underruns. We get the win without the player ever leaving the root
isolate. As a bonus, the isolate now makes **zero platform-channel calls at all**,
which sidesteps the whole class of background-messaging problems.

Two platforms opt out entirely by design: **iOS and web have no audio channel in
HTCommander**, so there's nothing to move; the isolate is simply never spawned
there.

## Doing it in phases (so we can stop and check)

We're deliberately not landing this as one giant commit. The pipeline has real
consequences — a broken modem means dropped packets, a broken playback means dead
audio — so the plan is staged to be verifiable at each step:

1. **Infrastructure + SBC decode + transmit — DONE.** We stood up the isolate, the
   message protocol, and the zero-copy byte transfer, and moved SBC decode/encode,
   WAV recording and the transmit pacing loop into it. This is where we learned the
   playback lesson above and settled the final split (DSP in the isolate, player on
   the host). The primary symptom — playback that hitches under UI load — is
   addressed, because the heavy decode no longer shares the UI thread.
2. **Move the software modem and SSTV — next.** The bigger refactor, because the
   modem is deeply wired into the broker for its settings and its transmit path
   (including the carrier-sense that keeps it from transmitting over someone else).
   Moving the whole modem in — receive, transmit, and channel-busy detection
   together — keeps that logic self-consistent, with a thin proxy on the main
   isolate bridging the control events both directions. These are pure Dart, so
   unlike the player they move into the isolate cleanly.
3. **Clean up and profile.** Remove the now-dead in-line paths and confirm on a
   DevTools timeline that the audio work really has left the UI thread.

Staging it this way meant the first tangible win — audio that doesn't hitch —
arrived early and independently, and it's also where the architecture got its one
big correction before we built anything on top of it.

## What "done" looks like

We'll know it worked when:

- Dragging, resizing, and scrolling the UI no longer disturbs playback, and a
  DevTools timeline shows the audio work off the UI thread.
- AFSK1200, PSK2400, and DART still decode over the air, and the existing modem
  streaming test still passes — the DSP is pure Dart and shouldn't change, only
  *where* it runs.
- SSTV still auto-detects and saves images; recorded WAV files are gap-free and
  in order; speech-to-text still transcribes.
- Transmit still keys up, still senses a busy channel before transmitting, and the
  peer still receives our frames.
- iOS and web behave exactly as before.

That's the bar: the same radio, the same decoders, the same recordings — just no
longer fighting the paint loop for a thread. We'll report how the real timeline
looks once the first phase is in.

---

*Architecture: Flutter/Dart. The receive/transmit DSP — SBC decode/encode, WAV
recording and the transmit pacing loop — now runs in a dedicated background
isolate; the software modem and SSTV follow in Phase 2. The PCM player stays on the
root isolate because background isolates can send to the platform but cannot
receive from it (no `EventChannel`/callback delivery), so the isolate hands decoded
PCM back to the host to feed. The isolate makes no platform-channel calls at all.
Windows / macOS / Linux / Android only; iOS and web have no audio channel and keep
the current path.*
