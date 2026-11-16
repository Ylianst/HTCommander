# Keeping Bluetooth Transmit Audio Continuous When the Computer Is Busy

*Implementation and design notes, November 2026.*

**Implementation update:** modem data and SSTV now have a prepared-job path:
the Dart audio isolate prepares the complete waveform, and a persistent native
sender owns pacing, ordered writes, cancellation, and the end marker. Native
implementations are included for Windows, Android, macOS, and Linux. Live voice
and explicitly held streams retain their streaming path; web and iOS are
unchanged. Platform builds and receiver-side stress testing remain essential;
the architecture alone is not evidence that radio dropouts have been eliminated.

**Native codec update:** preparation and reception now use one shared C++ SBC
codec and Bluetooth framer on all four audio platforms. Encoding and framing
share a batched FFI entry point; parsing, unescaping, and decoding share another.
The persistent transmit workers and their ownership rules remain unchanged.

When a voice transmission briefly stutters, the listener may still understand
it. When a modem waveform or SSTV image stutters, the receiver loses something
it cannot necessarily reconstruct: symbols, synchronization, or part of a scan
line. A busy computer should not turn a correctly generated waveform into an
interrupted transmission.

HTCommander originally moved SBC encoding and transmit pacing into a background
Dart isolate. That was an important improvement, but it did not make the entire
path to the radio independent of platform-thread scheduling. This proposal takes
the next step: prepare a complete data transmission, then let one native sender
own its timing and Bluetooth writes.

The platforms covered here are Windows, Android, macOS, and Linux. Web and iOS
have no radio audio channel in HTCommander and are outside this proposal.

## The path that motivated this change

Both software-modem data frames and SSTV arrive at the radio audio layer as
precomputed 32 kHz, 16-bit, mono PCM. The audio engine converts that PCM into SBC,
escapes and frames the encoded bytes for the radio, and sends them over its
Bluetooth Classic RFCOMM audio connection.

The important implementation points are:

- [AudioEngine](../../src/lib/radio/audio_engine.dart) coordinates native SBC
  conversion and prepared jobs from a dedicated Dart isolate, and still paces
  live voice.
- [RadioAudio](../../src/lib/radio/radio_audio.dart) hands PCM to that isolate.
- [SoftwareModem](../../src/lib/radio/software_modem.dart) marks modem
  transmissions with `isDataFrame`.
- [The communications tab](../../src/lib/widgets/comms_tab.dart) marks SSTV
  transmissions with `isBulkData`.

Before the prepared-job change, the engine already invoked the Bluetooth method
channel directly from its
background isolate. It does **not** relay each transmit write through the Dart
UI isolate. However, a background Dart caller does not automatically make the
native method handler independent of the platform UI thread.

There was already batching: four radio packets were combined into one Bluetooth
write. With the current configuration, an SBC frame represents 4 ms of audio,
six frames fit in a normal packet, and four full packets represent 96 ms.
Consequently, a sustained transmission needs approximately ten method-channel
round trips per second, with faster bursts while building its buffering lead.
Partial packets and the end marker are smaller.

The original platform paths differed:

| Platform | Original native transmit behavior |
| --- | --- |
| Windows | The method handler starts a new detached thread for every audio write. That thread initializes COM, calls `WriteBytes` and `StoreAsync().get()`, returns the result, and exits. |
| Android | A dedicated audio method channel uses Flutter's background task queue and writes to the Bluetooth socket output stream. It avoids the Android UI thread, but still requires one Dart/native round trip per batch. |
| macOS | The normal method-channel handler submits data through `IOBluetoothRFCOMMChannel.writeAsync`. Acceptance of that asynchronous write is not a playback acknowledgment. |
| Linux | The platform-thread method handler calls a blocking `write` loop on the RFCOMM socket. A slow write can block the platform thread, and a busy platform thread can delay the next write. |

These are identifiable scheduling dependencies, not proof that every observed
dropout originates there. Bluetooth interference, firmware behavior, and host
driver delays remain possible causes.

## The goal is no application handoff between batches

We cannot promise literally zero thread switches. General-purpose operating
systems schedule threads, Bluetooth stacks use their own workers, and I/O can
block. Preventing the scheduler from running is neither practical nor desirable.

The achievable goal is more specific:

> Once a prepared transmission starts, delivering its next audio batch must not
> require a UI event, a Dart timer, a new thread, or another platform-channel call.

Replacing Windows' per-write threads with a persistent worker is useful, but
insufficient on its own. If that worker still waits for the platform thread to
deliver the next 96 ms, the scheduling dependency remains.

## Prepare first, transmit second

For modem data and SSTV, the entire PCM waveform is already available before
transmission. We should exploit that:

```text
Preparation, before the first radio packet:
  Complete PCM waveform
    -> background SBC encoding
    -> escaped radio packets + sample counts
    -> native-owned transmit job

During transmission:
  Persistent native sender
    -> monotonic pacing
    -> ordered RFCOMM writes
    -> ordered end-of-audio marker

Outside the timing-critical path:
  Progress, history, recording, and optional local monitoring
```

The first prepared-job implementation kept the existing Dart SBC encoder.
Moving encoding to native code was not necessary to remove it from the
real-time sending loop. The subsequent shared-codec implementation reduces
preparation cost and receive-side work without changing the sender contract.

Each prepared job should contain the framed bytes, packet boundaries, and the
number of PCM samples represented by each packet. Pace by samples, not encoded
byte count: framing escapes change wire size without changing audio duration.
At 32 kHz, 3,200 samples always represent 100 ms.

Preserve the current codec settings: bitpool 18, SNR allocation for modem data,
and loudness allocation for SSTV and voice. This is a transport change, not a
waveform or bitrate experiment.

Native code takes ownership of the payload in one transfer before transmission.
Jobs are bounded to 16 MiB of encoded data and 200,000 batches; PCM input is
limited to 96 MiB. Oversized or invalid jobs fail explicitly rather than
silently falling back to streaming. Bounded pre-transmission staging is a
possible future extension if these limits prove insufficient.

Preparing SBC can add startup delay. Keep preparation cancellable and repeat the
existing channel-busy/deadline checks before committing a modem transmission to
the sender. Moving work earlier must not accidentally cause a transmission over
a station that started speaking while preparation was running.

## One native codec, with fused Bluetooth framing

The shared [C++ implementation](../../src/native/radio_audio_codec.cpp) exports a
small [C ABI](../../src/native/radio_audio_codec.h). The
[Dart bindings](../../src/lib/sbc/radio_audio_codec_native.dart) call it directly
from the audio isolate. These are synchronous FFI calls on the calling thread:
there is no new codec thread, platform-channel request, or platform-specific
codec implementation.

The transmit operation accepts little-endian PCM and returns the final escaped
Bluetooth byte stream, batch lengths, and sample counts together. It preserves
the existing wire format: 32 kHz mono, 16 blocks, eight subbands, bitpool 18,
six SBC frames per full packet, and four packets per full write. Modem data uses
SNR allocation; voice and SSTV use loudness allocation.

Prepared jobs convert up to 98,304 PCM bytes per FFI call: 16 full write batches,
or 1.536 seconds of audio. The Dart isolate yields between these chunks so
cancellation and radio-state changes can still be handled. Live voice converts
one write batch at a time. An incomplete 256-byte PCM frame remains with the
Dart caller, preserving streamed-chunk behavior.

Receive input is copied into reusable native input storage, rather than a
growing Dart list that is shifted for every packet. Native parsing retains
split delimiters and escape sequences across calls, bounds an unfinished
packet to 64 KiB, and reports malformed input explicitly. One completed packet
can contain multiple SBC frames; they are decoded in the same native call.
A valid decoded prefix survives a bad trailing frame.

The receive API deliberately returns one packet at a time. Dart re-evaluates
half-duplex state before decoding the next packet, including when an end marker
and opposite-direction audio arrive in one Bluetooth chunk. Ignored TX echoes
or RX packets do not advance synthesis history. The decoder retains support for
four/eight subbands, all SBC sample rates and channel modes, and mSBC; the
existing left-channel playback behavior is unchanged.

Filter history and codec work buffers are reused within a per-engine context.
There are no per-SBC-frame Dart codec objects or separate Dart escaping passes.
Returned PCM and transmit bytes are copied into owned Dart typed arrays before
native output storage is reused, which keeps asynchronous sends and receive
pre-roll safe. Resetting receive framing does not reset the transmit encoder.
Native load or API failures are explicit errors, not silent Dart-codec fallback.

### Building the same source on each platform

The application [native-asset build hook](../../src/hook/build.dart) compiles
the same C++17 source and bundles its library through Dart/Flutter:

| Platform | Native codec build | Bluetooth sender |
| --- | --- | --- |
| Windows | MSVC, packaged DLL | Existing persistent COM/MTA worker |
| Linux | Target C++ toolchain, shared library | Existing persistent socket writer |
| Android | NDK Clang for the target ABI; statically linked C++ runtime | Existing persistent socket writer |
| macOS | Apple Clang and libc++ | Existing RFCOMM owner thread/run loop |

This avoids four copies of the codec or manual platform-specific codec build
lists. The build hook tracks the shared headers as well as the source, so table
changes invalidate cached builds. Web does not import FFI; iOS and web do not
build this radio-audio library.

### Measured cost and SIMD

The initial Windows x64 AOT comparison processed the same 60-second PCM clip
with both allocation modes, three trials each. These timings include Bluetooth
framing/unframing and typed-array handling, but no Bluetooth I/O:

| Path | Dart median | Native median | Approximate speedup |
| --- | ---: | ---: | ---: |
| Encode + frame, loudness | 745 ms | 157 ms | 4.7x |
| Encode + frame, SNR | 967 ms | 213 ms | 4.5x |
| Unframe + decode, loudness | 637 ms | 161 ms | 4.0x |
| Unframe + decode, SNR | 675 ms | 176 ms | 3.8x |

These are measurements from one shared Windows host, not performance promises
for every CPU or platform. Earlier codec-only timings exclude the additional
framing and data-handling work and are not directly comparable.

### Further CPU optimization

The shared codec now replaces division-based signed shifts with portable
unsigned-shift arithmetic that preserves negative rounding exactly. Bit readers
and writers use reservoirs instead of processing every bit individually.
These changes benefit encoding and decoding on every supported audio platform.

The encoder's cosine transform additionally uses SSE2 on x86/x64 targets with
SSE2 enabled, or NEON on ARM targets with NEON enabled. Other targets retain the
scalar implementation; selection happens at compile time, without requiring
AVX2 or a runtime dispatch layer. Windows/Linux x64 and Intel Macs use SSE2;
Apple Silicon and ARM64 Android/Linux builds use NEON. ARM32 uses NEON only when
enabled by its target toolchain.

The fixed-point output remains exact. A compile-time coefficient-bound check
proves that the transform's narrower 32-bit accumulators, including rounding,
cannot overflow for saturated 16-bit inputs. The scalar implementation uses the
same bounds and arithmetic.

A second Windows x64 measurement compared the previous native DLL with the
optimized DLL packaged by the Windows application build. Each operation
processed 61.44 seconds of deterministic PCM, with five interleaved trials.
These are median native-call wall times, excluding Dart/FFI copies and Bluetooth
I/O:

| Native operation | Previous | Optimized | Thread-cycle reduction |
| --- | ---: | ---: | ---: |
| Encode + frame, loudness | 86.489 ms | 50.644 ms | 41.4% |
| Encode + frame, SNR | 91.700 ms | 51.836 ms | 43.4% |
| Unframe + decode, loudness | 86.156 ms | 53.442 ms | 38.0% |
| Unframe + decode, SNR | 90.970 ms | 58.088 ms | 36.4% |

Cycle reductions use Windows per-thread cycle counters, not elapsed-time
estimates. This native-only comparison has a different scope from the earlier
Dart-versus-native AOT table; the absolute times should not be compared between
tables. These are shared-host x64 results, not measured ARM speedups or
end-to-end transmission gains.

### Smaller buffers and fewer PCM copies

- Receive PCM storage starts at 1,536 bytes instead of eagerly reserving
  2,097,152 bytes for every context. It grows as needed and is reused. Explicit
  growth limits prevent vector capacity overshoot beyond the existing 2 MiB
  worst-case PCM requirement.
- The fixed 16 KiB receive-format array becomes a small reusable vector,
  initially reserving four entries (16 bytes). It still reports every unique
  format in first-seen order and clears the list between packets.
- On the measured Windows x64 build, the context structure itself shrinks from
  82,880 to 66,520 bytes, separately from its allocated buffers. These are
  structure sizes and allocation capacities, not guaranteed RSS reductions.
- PCM materialized from `TransferableTypedData` is already exclusively owned by
  the audio isolate and no longer needs another whole-clip snapshot. Public
  callers with ordinary byte arrays still receive snapshot semantics.
- Local transmit monitoring queues byte views of engine-owned PCM rather than
  eagerly copying the entire clip into another sample array. This avoids that
  allocation but retains the original backing buffer until monitoring drains.
- Recording/observer messages no longer make an extra temporary byte copy
  immediately before `TransferableTypedData` makes its required transfer copy.

Native output snapshots remain intentional: asynchronous sends and receive
pre-roll can outlive the next codec call. The Windows build hook also enables
C++ exception unwinding so allocation failures clean up correctly.

Faster codec work reduces CPU and preparation delay; keeping it out of the
prepared sender's pacing loop is still what removes the per-batch Dart
scheduling dependency. It does not prevent OS scheduling or Bluetooth-stack
stalls.

Validation includes native-versus-Dart byte/PCM comparisons, all SBC channel
modes and sample rates, mSBC, split/coalesced framing, malformed input, synthesis
state/reset behavior, and background-isolate loading. The focused codec and
audio/modem suites cover 70 passing tests on Windows, along with Windows and web
builds. One XARA beacon timeout during concurrent builds passed when the XARA
suite was rerun without those builds. New regression cases cover growing PCM
and format buffers, output lifetimes, PCM ownership, monitoring, and prepared
wire equivalence.

Native checks produce the same result hash under MSVC SSE2, Linux SSE2 and
scalar builds with ASan/UBSan, and an ARM64 NEON executable run under QEMU.
They exercise extreme signed shifts, randomized bit packing, 10,000 generated
SBC/mSBC configurations (skipping invalid combinations), split framing, and
maximum-packet PCM capacity. Emulation verifies ARM64 arithmetic, not
real-device performance. Android and macOS application packaging and
physical-radio stress tests still require those platforms.

## One ownership model for all four platforms

The shared contract distinguishes:

- **Accepted:** native code owns a valid job, not that RF transmission is done.
- **Sending:** the sender is submitting packets according to its pacing clock.
- **Submitted:** the ordered audio bytes and end marker reached the transport's
  submission/completion boundary, not necessarily the radio's speaker.
- **Cancelled or failed:** a terminal result with an explicit reason.

A job identifier prevents a late completion from an old connection or cancelled
job from updating a newer transmission.

The implemented `sendPreparedAudio` method takes `address`, `jobId`, `data`,
`lengths`, `samples`, and `leadMs`. The two parallel `Int32List` arrays describe
the boundaries and sample counts of the concatenated batches. Its pending method
result resolves only at terminal submission or cancellation, with `status`,
`samplesSent`, `writes`, `elapsedMs`, `maxWriteMs`, `maxGapMs`, and
`maxBehindMs`; native failures return method errors. Acceptance is internal, not
a separate early success response. `cancelPreparedAudio(address, jobId)` signals
only the matching job. No repeated Dart requests or replies drive its pacing.

Only the sender may write job audio or its end marker to that connection.
Cancellation signals the sender, discards unsent data, and arranges an ordered
stop. It must not launch a competing write from another thread. Connection
shutdown must wake the worker and invalidate pending work.

Recording and monitoring must preserve their intended behavior, but file writes,
PCM copying, and broker notifications do not belong in the sender's pacing loop.
Prepare recording data separately and deliver lossless observer data outside the
critical path; throttle UI progress instead of reporting every packet.

Currently the confirmed PCM prefix is delivered to recording/history observers
in bounded chunks after the native result arrives. This preserves sample order
without making the sender wait for observers, but changes when transmit waveform
updates appear. Optional local monitoring uses its separate Dart playback pump.
Fine-grained progress events are not part of this implementation.

### Windows: a persistent MTA sender

Implementation belongs in the
[Windows Bluetooth plugin](../../src/windows/runner/bluetooth_classic_plugin.cpp).

Replace the `DoSendAudio` thread-per-write pattern for prepared jobs with one
long-lived audio sender per active audio connection:

1. Initialize a multithreaded COM apartment once on that worker.
2. Transfer a prepared job into a synchronized, bounded queue.
3. Let the worker own audio `DataWriter` operations and serialize them.
4. Use a monotonic clock and interruptible waits for pacing and cancellation.
5. Shut down the worker safely before releasing its connection state.

The initial method-channel call may still arrive on the platform thread. That
is acceptable before TX starts; no further platform calls should be required to
keep the current job moving. Completion and progress can return to Flutter later
without blocking transmission.

`StoreAsync().get()` can still wait on the OS Bluetooth stack. The implementation
allows one outstanding ordered write and waits up to five seconds for it.
A timeout cancels that operation and closes the socket, failing the job rather
than risking continuation of a partially submitted stream. Normal cancellation
wakes pacing waits and stops between completed batches; it does not interrupt a
write by injecting a competing end marker.

Windows MMCSS multimedia scheduling is a possible measured follow-up, not a
substitute for removing handoffs. Do not start with real-time process priority
or a spinning thread.

### Android: build on the existing background path

The [Android Bluetooth plugin](../../src/android/app/src/main/kotlin/com/meshcentral/htcommander/BluetoothClassicPlugin.kt)
already keeps audio method calls off the UI thread through a background task
queue. Preserve that improvement.

For prepared jobs, add an application-owned persistent sender thread that owns
the audio socket writes. The method handler validates and transfers the job,
then returns; the sender handles the whole transmission without repeated Dart
calls. Flutter's background task queue should not be treated as a guarantee of
one permanent OS thread for the lifetime of a transmission.

Use `SystemClock.elapsedRealtimeNanos()` for a monotonic transmission timeline,
with waits that can be interrupted for cancellation. Serialize existing streaming
writes and prepared jobs so the two paths cannot interleave.

Blocking `OutputStream.write` still depends on the Bluetooth stack. Cancellation
needs a documented response when it is blocked; do not casually close the socket
just to interrupt a wait, because that changes connection behavior. Any use of
Android audio thread priority should be profiled for battery use and system
responsiveness, rather than treated as a correctness guarantee.

### macOS: a dedicated Bluetooth run loop

Implementation belongs in the
[macOS Bluetooth handler](../../src/macos/Runner/AppDelegate.swift).

The original `writeAsync` API made this more than a simple thread-pool change.
The implementation establishes the separate audio channel on a persistent native
owner thread with a run loop, and performs prepared-job writes there with
`writeSync`. Its buffers remain alive until each call returns, and transfers are
split according to the channel MTU and API length limits. There is no per-batch
Flutter callback or main-run-loop pacing timer.

This deliberately trades asynchronous-buffer lifetime complexity for synchronous
flow-control waits on the dedicated owner. Cancellation stops between batches;
it cannot forcibly interrupt a blocked `writeSync`. Its responsiveness under
Bluetooth flow control requires testing.

If IOBluetooth returns an endpoint shared with the control channel, legacy
streaming remains available, but native prepared jobs reject it before writing
any bytes: taking over that endpoint's delegate/run loop could break control
traffic. Only this specific `UNSUPPORTED_CONNECTION` preflight rejection selects
legacy paced writes, with an explicit warning that UI-stall protection is
unavailable. The already-prepared SBC bytes are reused, and their sender still
serializes cancellation and the stop marker. Busy, disconnected, invalid, or
failed writes never trigger an automatic retry. A fully independent shared
endpoint needs a separate verified ownership design.

Preserve the existing macOS connection lifecycle: disabling audio currently
suppresses forwarding rather than closing the RFCOMM channel, because closing it
can also disturb the control connection on some radios. Cancelling a job must
not silently change that behavior.

This platform requires an explicit validation milestone: demonstrate that an
already-started job continues during a blocked main run loop. If the
channel arrangement cannot do that, report the limitation rather than claiming
that a background queue solved it.

### Linux: move socket writes out of the GTK loop

Implementation belongs in the
[Linux Bluetooth plugin](../../src/linux/runner/bluetooth_classic_plugin.cc).

Give each active audio connection a persistent writer thread holding a valid
connection reference. The Flutter/GTK method handler only validates and enqueues
the prepared job; it no longer performs its socket writes inline.

Use a monotonic clock for pacing. For interruptible I/O, consider nonblocking
writes with `poll` and a cancellation wake descriptor, handling partial writes,
`EINTR`, and `EAGAIN` without losing or duplicating bytes. Audit the existing read
loop before changing socket flags: nonblocking mode affects the shared file
description and therefore also affects reads on that socket.

An alternative is to retain blocking I/O with a bounded, tested write timeout.
Choose based on the existing reader and required cancellation latency, not
solely on code size. Marshal notifications back through the GLib main context;
never call Flutter APIs directly from the writer.

## A local queue is not the radio's buffer

The current pacing leads are 10 seconds for modem data and 6 seconds for SSTV.
They express how far audio submission may run ahead of elapsed time. They do
**not** establish that the radio can store that much audio.

Separate two quantities:

1. **Native job backlog:** prepared audio still held safely in computer memory.
2. **Submitted lead:** audio handed to the OS/radio ahead of estimated playback.

The former can hold the complete transmission. The latter must stay within a
measured safe limit. Increasing it indefinitely could overflow a device buffer
or make cancellation unacceptably slow.

Use one monotonic timeline and cumulative sample count per transmission, not a
fresh pacing clock for each input chunk. Account for time spent in writes and
late wakes. If transport flow control prevents delivery at real-time speed, log
that condition explicitly; the queue cannot manufacture missing bandwidth.

Nor can cancellation retract audio already accepted downstream. Measure the
delay from Cancel to actual RF stop and document that separately from how fast
the native worker acknowledges cancellation.

## How we would prove the improvement

First capture the current behavior, then run the same workload with the native
sender. Include CPU saturation, allocation pressure, window dragging/resizing,
and busy UI activity during both long SSTV images and modem bursts.

Collect native timestamps and counters for:

- First audio submission, write starts/completions, and the final marker.
- Audio samples submitted, maximum inter-write gap, and deadline misses.
- Write latency, submitted lead estimates, and bytes remaining locally.
- Cancellation request, sender acknowledgment, disconnects, and terminal errors.

An inter-write gap alone is not proof of an underrun if enough audio was already
buffered. Conversely, successful writes do not prove uninterrupted RF audio.
Validate at the receiver: compare modem decode success for identical payloads
and inspect repeated SSTV images for missing or displaced lines. A receiver-side
recording provides stronger evidence than transmit-side timing alone.

Add focused tests for packet order and sample accounting, cancellation during a
wait or write, partial writes, disconnect/reconnect, stale callbacks, and exactly
one terminal job result. Existing SBC round-trip tests remain useful, but mocked
Bluetooth writes cannot establish real scheduling or radio-buffer behavior.

## Implementation and remaining validation

The prepared-job path, native lifecycle contract, and four native senders are
implemented. Focused Dart tests cover byte-for-byte equivalence with the streaming
encoder for modem and SSTV audio, sample accounting, one-shot submission beyond
the pacing lead, native errors, cancellation, expiry, carrier rechecking, and
unchanged voice streaming.

Software-modem packet deadlines are carried through SBC preparation. The engine
yields during preparation so cancellation and radio-state changes can be handled,
and rechecks reception and expiry before handing a job to native code.

On the Windows development host, the debug application build and targeted Dart
analysis passed, along with 49 focused audio/modem tests. These cover integration
and codec behavior, not Bluetooth timing or receiver-side continuity.
Linux's worker was also compiled
with real GLib/BlueZ and stubbed Flutter APIs, then exercised in seven socketpair
scenarios under ASan/UBSan, including pacing, cancellation, disconnect, partial
writes, and timeout. This is not a full Linux application build.

The remaining acceptance work is platform-native builds where unavailable on
the development host, and the hardware stress procedure above. In particular,
verify actual RF stop latency, safe submitted lead, macOS run-loop independence,
and decode/image integrity under load. Do not equate passing mocked-write tests
with passing these radio-side checks.

The key change is not "more threads" or "a larger buffer." It is removing the
need to obtain another piece of work from another execution context while the
radio is consuming the current transmission. Prepare the waveform, give one
native sender ownership, and let the UI catch up when it can.
