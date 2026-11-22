# Getting Audio Off the Main Thread: Moving the Radio Pipeline to Its Own Isolate

*A design note that started life **before** we wrote any code — the plan and the
reasoning behind it — now updated with what we found actually building it.
HTCommander decodes Bluetooth audio, plays it, demodulates data, and decodes SSTV
images, and until recently it did all of that on the same thread that paints the
user interface. This is the story of why that's a problem, why the honest fix is a
dedicated audio isolate, and the one hard lesson that reshaped the design.*

**Transmit follow-up:** the historical platform-channel discussion below describes
the initial isolate split. The current engine can send Bluetooth writes directly
from its background isolate, but native scheduling dependencies remain. See
[Keeping Bluetooth Transmit Audio Continuous When the Computer Is Busy](bluetooth-audio-transmit-worker.md)
for the current path, native sender implementation, and platform validation work.

**Native Windows receive playback:** the Bluetooth reader now feeds the shared
speaker output without a Flutter/Dart round trip. It calls the same C++ framing
and SBC codec used by the audio isolate, holds 60 ms of initial PCM, then queues
PCM directly to the shared Windows player. All Windows `waveOut` device work
and buffer completion handling run on a dedicated worker, not the platform
window's message loop. Dart still controls mute, selected radio, channel mute,
volume and device selection. Other platforms retain the isolate playback path.

The existing audio isolate continues decoding independently for recording,
modem/SSTV processing, metering and browser mirroring. This deliberately costs
a second receive decode on Windows in exchange for preserving those consumers
without making local listening wait for them. Received playback events are
tagged so the host mirrors them to browsers but does not feed the speaker twice;
local transmit monitoring and other audio sources still use the shared player.
Device ownership remains reference-counted by `PcmPlayer`; native Bluetooth
playback does not open a second competing output device.

The Dart codec's synchronous receive callbacks cannot reenter receive, encode or
reset while its shared native input arena is in use. Such calls throw a
`StateError` instead of overwriting the remaining input. Disposal from either the
decode-mask or packet callback stops delivery before another native access;
callback exceptions release the receive guard.

Windows Bluetooth teardown closes admission to background operations, cancels
socket I/O, and joins every reader, writer and method reply before unregistering
channels. This includes connections already removed from the active maps.
Detached-window native audio plugins are owned by their Flutter registrar and
destroyed before its messenger, not retained until process exit.

**Windows audio scheduling:** the native speaker-output worker and the audio
RFCOMM reader (which also runs receive SBC decoding) register with Windows MMCSS
under its `Audio` task at `AVRT_PRIORITY_HIGH`. Registration is scoped to each
thread's lifetime and reverted on exit. If MMCSS registration is unavailable,
the thread logs the failure and tries `THREAD_PRIORITY_ABOVE_NORMAL`, restoring
its previous priority on exit. Priority-setting and cleanup failures are logged.
The Classic control-channel reader, BLE reconnect workers, Dart isolates and
overall process priority are unchanged. This improves scheduling under CPU load;
it cannot prevent Bluetooth adapter contention or recover missing radio samples.

**Windows receive playback catch-up:** native radio-only speaker queues now
recover when admitted audio would exceed 200 ms. Admission invalidates old
playback submissions immediately; the output worker resets the WinMM queue and
keeps only the newest chunk (at most its final 60 ms). Repeated catch-ups also
remove stale pending submission commands while the worker is busy. This can
produce a brief audible skip, but avoids preserving an accumulated playback
delay. Recording, visualization, browser mirroring and modem decoding keep their
original samples. Queues containing non-radio PCM retain the existing 800 ms
admission cap rather than flushing another source's audio. Reset failures are
logged and disable output admission until the device is set up again.

**Receive decoder workers:** DART and packet-modem (AFSK/PSK, including HDLC and
FX.25) reception now runs in a persistent worker per modem instance. SSTV and
buffered radiosonde reception have separate persistent workers. Native DSP calls
run inside those workers too: native code is faster, but a synchronous FFI call
would still block whichever isolate calls it. XARA retains its existing worker.
The synchronous decoder cores remain available for reference tests and tools.

Each receive worker admits only one command to its isolate mailbox at a time.
The host-side FIFO, including startup and in-flight work, is bounded by both PCM
bytes and command count: two seconds for each modem, four seconds for SSTV, and
twelve seconds for radiosondes (256 commands, or 512 for radiosondes). An overrun
is logged, invalidates queued/stale results, and recreates the affected decoder;
it never silently joins samples across dropped audio. Decoder failures are
reported rather than replaying consumed audio on the UI isolate. Shutdown
discards late results and releases decoder resources on the owning worker.
Web, which does not receive local radio audio, retains an ordered local fallback
because Dart isolates are unavailable there.

**History WAV recordings:** clip creation and byte/duration accounting remain
immediate, but the comms handler no longer opens, writes, renames or deletes
recordings synchronously inside audio callbacks. A shared FIFO uses asynchronous
file I/O, coalescing adjacent events over 20 ms into batches up to 64 KiB.
Its 1 MiB allocation budget includes
in-flight writes; at most 32 clips may be opening/draining. Borrowed audio slices
are copied before returning to the producer. Overflow or an I/O failure explicitly
logs a failed clip and prevents partial/gapped audio from being added to history;
there is no synchronous fallback or silent frame dropping. Close drains PCM,
patches the exact RIFF/data sizes, flushes and closes before renaming or publishing
history; short clips are discarded after drain. `CommsHandler.flush()` finalizes
the current clip and waits for pending recording/history persistence, covering
the existing desktop-close and mobile-background hooks. Synchronous `dispose()`
initiates the same drain as a best effort; callers terminating the process must
await `flush()` first. Focused regressions: `flutter test
test/wav_recording_writer_test.dart` from `src`.

Modem frames are returned immediately when decoded, without waiting for an
audio-end marker or unrelated image/telemetry work. FX.25 suppression and its
700 ms plain-HDLC fallback timer live with the decoder. Channel and lock metadata
is captured when PCM is submitted, so a retune while decoding is queued does not
relabel earlier frames. SSTV sends start/progress/image events and partial image
snapshots; source locking and end-of-run finalization happen in queue order,
including VIS detection that has not yet reached the UI. Radiosonde flushes are
also ordered with PCM, with the originating device/channel carried back with each fix.
Its stateful family decoders retain calibration across normal receive runs.

`getNativeAudioPlaybackStats` on the Bluetooth method channel reports cumulative
packet, decoded/queued/dropped sample and decode-error counts, the last native
playback error, and current shared output queue depth. Receive-end/stop logs
include these diagnostics, plus shared-output underrun, overflow and driver-error
counters. Queued samples mean accepted for playback, not confirmed audible
samples. The output underrun counter records completion-driven queue drains,
including normal ends of audio runs; it is not by itself a count of audible
glitches. Native transmit writers update half-duplex state directly, so a busy
UI does not delay turn-around. Native playback protects against host scheduling
delays, not missing source samples, Bluetooth disconnects, or audio interruptions
caused by retuning the radio. Hardware listening and UI-stall comparisons remain
necessary to measure the improvement on a particular machine.

The same diagnostics include `bufferedMs`, lifetime `peakBufferedMs`,
`outputCatchups` (requested queue recoveries), and `outputDiscardedFrames`.
Discarded frames include pending submissions, clipped input tails' discarded
prefixes, and reset driver buffers; a reset buffer's already-played prefix is
included because queue accounting is at buffer granularity. These shared-output
counters are cumulative across device reconfiguration. At native radio format,
32 frames represent 1 ms. Compare logs before and after a CPU-load event to
identify queue growth and recovery; the existing receive-end/stop logs publish
the values without additional UI work on the audio thread.

The standalone Windows regression tests use no radio and the output-worker
tests mock WinMM rather than opening a real audio device. From an MSVC Developer
Command Prompt, compile the following in a scratch directory (adjust source
paths to the checkout):

```bat
cl /nologo /std:c++17 /EHsc /W4 /WX /DNOMINMAX native_radio_playback_test.cpp radio_audio_playback.cpp radio_audio_codec.cpp
cl /nologo /std:c++17 /EHsc /W4 /WX /DNOMINMAX /D_WINMM_ /Fe:native_pcm_output_test.exe native_pcm_output.cpp native_pcm_output_test.cpp /link user32.lib avrt.lib
cl /nologo /std:c++17 /EHsc /W4 /WX /DNOMINMAX audio_thread_priority_test.cpp
cl /nologo /std:c++17 /EHsc /W4 /WX native_thread_group_test.cpp
```

Sources: [receive pipeline test](../../src/test/native_radio_playback_test.cpp)
and [output worker test](../../src/windows/runner/tests/native_pcm_output_test.cpp).
The [scheduling test](../../src/windows/runner/tests/audio_thread_priority_test.cpp)
substitutes MMCSS calls to check registration cleanup and the thread-priority
fallback without depending on the MMCSS service. The
[thread ownership test](../../src/windows/runner/tests/native_thread_group_test.cpp)
checks retired callbacks, late-start rejection and teardown waiting. Run all four executables after
compiling. The Flutter routing regression lives in
[native_radio_audio_test.dart](../../src/test/native_radio_audio_test.dart).
The [Bluetooth plugin test](../../src/windows/runner/tests/bluetooth_classic_plugin_test.cpp)
uses a fake Flutter messenger to check null method arguments, in-flight reply
teardown and channel unregistration. Link it with the runner's Bluetooth, native
PCM output, playback and codec objects, the Flutter wrapper/import libraries, and
`windowsapp.lib`, `winmm.lib`, `user32.lib`, `avrt.lib`; put
`windows\flutter\ephemeral` on `PATH` for `flutter_windows.dll`.

---

> **Update (build notes).** Phase 1 has landed: SBC decode, WAV recording and the
> transmit pacing loop now run in a dedicated background isolate. Along the way we
> hit a wall that changed the architecture — **you cannot play audio from a
> background isolate** — and the reasons are worth a section of their own (see
> *“The hard lesson”* below). The plan sections are kept as originally written;
> the findings correct them where reality disagreed.

**Half-duplex turn-around:** the audio frame parser must keep draining a Bluetooth
read when it skips audio from the opposite direction. An end-of-audio marker and
the next received burst can be coalesced in that same read. Returning early leaves
those frames queued and can prevent the software modem from hearing a reply.
Regression tests cover both receive-to-transmit and transmit-to-receive overlap;
overlapping audio remains ignored while transmitting, but subsequent end markers
and audio are processed. After local transmission finishes, a received-audio frame
also closes a lingering transmit-echo run if its end marker was missing or arrived
before a late echo. This recovery is logged; it prevents that stale run from
suppressing every subsequent received burst.
Starting local TX also closes a receive run whose end marker never arrived, so
TX has its own start/end events and its duration cannot inflate later RX timing
statistics.

**Receive diagnostics:** packet-arrival duration minus decoded SBC duration is an
observed audio shortfall, not proof of Bluetooth packet loss. Windows queues
RFCOMM reads before delivering them on the Flutter platform thread; platform
delivery and isolate scheduling can delay or batch arrivals. Missing run
delimiters and rejected SBC frames can also distort the comparison. Shortfall
reports include received packet/payload counts, decoded frame/sample counts, SBC
formats, and decode-error/discarded-byte counts. SBC rejections are logged with
their reason; valid decoded prefixes retain their existing delivery behavior.
Decoded duration uses each frame's advertised sample rate. These diagnostics do
not establish whether a transport gap originated at the radio, Bluetooth, or host.

**APRS/data routing:** a received PCM packet's non-empty channel name selects the
modem pipeline. A packet tagged `House` must reach the general modem even if a
later status notification reports the APRS channel; a packet tagged `APRS` still
goes only to the APRS modem. Cached status is used only when the packet has no
channel tag. This prevents late APRS telemetry from swallowing XARA replies.

---

## Native DSP buffer ownership

SSTV PCM reception uploads little-endian PCM16 directly into a reusable native
byte buffer. Normalization is fused into native demodulation, and the Dart image
decoder consumes a borrowed view of the native frequency output before the next
block or decoder disposal. This removes the intermediate Dart double PCM buffer
and the native-to-Dart output copy. The float-sample API keeps its existing
in-place behavior; web/iOS and explicit Dart-reference decoders retain portable
PCM conversion. Native DSP calls remain non-leaf, including large blocks.

Telemetry monitors retain native recording contexts between runs. Radiosonde
decoding uploads each recording once for all six formats and shares one cached
DC-removed prefix sum between matched-filter formats. SARSAT uploads once for
both front ends. New uploads invalidate recording-derived caches. Contexts are
explicitly disposed with their monitors and have native finalizers; compact
candidate frames are copied into owned Dart lists before native results are
freed. Reuse reduces allocation churn, not necessarily retained process RSS.

For comparisons, run `dart run tool/benchmark_telemetry.dart native sonde
test/radiosonde_samples/DFM09_32k.wav` and repeat with `native-copy` to use separate
uploads per format. `dart run benchmark/sstv_receive_benchmark.dart` compares
float and direct-PCM native reception against the Dart reference.

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
