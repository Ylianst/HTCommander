# Native CW spectral front end

`CwDecoder` defaults to a native-asset Goertzel front end on Windows, Linux,
macOS and Android. Web and iOS continue to use Dart. `useNative: false` or
`--define=HT_CW_DART=true` selects the original Dart reference. The decoder's
`usingNative` getter reports the selected implementation. Custom configurations
above 4096 probes or 1,048,576 samples/window also retain the Dart reference.

Only the spectral arithmetic moves to native code. Dart still owns sample
buffering, overlapping-window placement, absolute center timestamps, amplitude
and purity calculation, noise-floor tracking, debounce, idle completion, timing
estimation and Morse text. Native calls return compact energy / maximum power /
peak-probe-index triples for at most 256 complete windows at a time; partial
windows remain buffered and `flush()` does not pad them. Each call uploads the
window span once rather than crossing FFI for individual probes or windows.
Small input chunks may still produce only one complete window.

Probe coefficients are computed once in Dart and copied to native storage.
Native recurrence storage is cleared for every window. SSE2 and AArch64 NEON
process two independent double-precision probes at once; other targets use the
same scalar arithmetic. No reduction reordering, fast-math or fused
multiply-add is enabled. Input, output and recurrence storage are retained
across calls and resets. `dispose()` releases native storage immediately
without emitting pending text; a native finalizer covers abandoned decoders.
Calls after disposal throw. Native errors (allocation, invalid arguments,
non-finite samples) are explicit rather than silently switching backend.

The public low-level `NativeCw.analyze` result is a borrowed view valid only
until the next call or disposal. Processing and allocation calls are non-leaf;
only the constant-time result-pointer getter is leaf.

## Hook integration

`src/hook/build.dart` imports `src/hook/cw.dart` and calls its
`buildCw(input, output)` helper within the Windows/Linux/macOS/Android guard.
It builds `native/cw_dsp.cpp`, tracks `native/cw_dsp.h`, and registers
`package:htcommander/cw_dsp`. Android links the static C++ runtime. No external
DSP dependency is required.

## Validation and measurement

From `src`:

```powershell
dart format lib\radio\cw_decoder.dart lib\radio\native_cw.dart lib\radio\native_cw_ffi.dart lib\radio\native_cw_stub.dart hook\cw.dart test\cw_decoder_test.dart test\native_cw_test.dart benchmark\cw_decoder_benchmark.dart
flutter test test\cw_decoder_test.dart test\native_cw_test.dart
flutter test --dart-define=HT_CW_DART=true test\cw_decoder_test.dart test\native_cw_test.dart
dart run benchmark\cw_decoder_benchmark.dart
```

Tests compare direct per-window native metrics with an independent Dart
recurrence (including odd probe counts), and compare decoder text, WPM and
tone through tiny/large chunks, idle completion, repeated flush and reset.
Signals include clean and off-grid tones, random noise, silence, keyed
out-of-band tones and competing tones.

The benchmark checks text/WPM/tone and chunk-size parity, then reports separate
Dart and native medians after two warmup runs. It includes 640-, 2048- and
65536-sample PCM blocks to expose batching effects. Construction/disposal are
outside the timed streaming interval; conversion, buffering and flush are
inside.

A local JIT run decoding 12.48 seconds of keyed 700 Hz audio measured:

| Samples/block | Dart reference median | Native median |
| --- | --- | --- |
| 640 | 61.52 ms | 27.93 ms |
| 2048 | 61.15 ms | 27.50 ms |

The benchmark's text/WPM/tone parity checks passed. A separate Windows x64 AOT
run measured **72.28 ms Dart versus 28.18 ms native** at 640 samples/block,
and **73.91 ms versus 28.30 ms** at 2048 samples/block, approximately **2.6x**
faster. These are local measurements, not a performance guarantee. Re-run on
the target device in the same execution mode before drawing comparisons.
