# Keeping Bluetooth Transmit Audio Continuous When the Computer Is Busy

*Implementation and design notes, November 2026.*

**Implementation update:** modem data and SSTV now have a prepared-job path:
the Dart audio isolate encodes the complete waveform, and a persistent native
sender owns pacing, ordered writes, cancellation, and the end marker. Native
implementations are included for Windows, Android, macOS, and Linux. Live voice
and explicitly held streams retain their streaming path; web and iOS are
unchanged. Platform builds and receiver-side stress testing remain essential;
the architecture alone is not evidence that radio dropouts have been eliminated.

When a voice transmission briefly stutters, the listener may still understand
it. When a modem waveform or SSTV image stutters, the receiver loses something
it cannot necessarily reconstruct: symbols, synchronization, or part of a scan
line. A busy computer should not turn a correctly generated waveform into an
interrupted transmission.

HTCommander already moves SBC encoding and transmit pacing into a background
Dart isolate. That was an important improvement, but it does not make the entire
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

- [AudioEngine](../../src/lib/radio/audio_engine.dart) owns SBC encoding and
  pacing in a dedicated Dart isolate.
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

Keep the existing Dart SBC encoder initially. Moving encoding to native code is
not necessary to remove it from the real-time sending loop and would introduce
an additional codec implementation to maintain.

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
