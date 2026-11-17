# Slow-Scan Television (SSTV)

![image](https://github.com/Ylianst/HTCommander/blob/main/docs/images/ht-SSTV.png?raw=true)

Handi-Talky Commander has built-in support to transmit and receive SSTV with a wide range of supported formats including Robot36.

On the receive side, incoming SSTV transmissions are automatically detected and will show up on the "Communication" tab as the image is received. Once received, double click on the image to have a larger view of it.

## Receive performance

Windows, Linux, macOS, and Android builds automatically use a native C++
receive DSP engine. Mixing, FIR filtering, FM demodulation, and sync-pulse
detection run in one native call per audio block, with reusable buffers and
streaming state. The FIR uses double-precision SSE2 on x64 and NEON on ARM64,
with a portable scalar implementation for other architectures. No optional CPU
instruction sets are required.

Scan-line two-pass EMA filtering, pixel sampling, and RGB/YUV conversion also
run in one native call per line for RGB, Robot 36/72, PD, HF Fax, and raw modes.
Mode/VIS detection, Robot 36 separator/parity state, HF Fax margin tracking,
image rendering, and receive events remain in Dart. Web and iOS retain the Dart
DSP path. Resetting, completing, or disposing a receiver releases its native
state; a finalizer also protects abandoned decoders.

For comparison or troubleshooting, build with `--dart-define=HT_SSTV_DART=true`
to use the original Dart DSP, or `--dart-define=HT_SSTV_SCALAR=true` to disable
SIMD without disabling the native engine.

`Decoder(useNative: false)` propagates to every receive-mode constructor.
Individual mode constructors also accept `useNative: false`. Native scan-line
storage grows only when required and is reused across calls; `Decoder.dispose`
releases it for every owned mode. Direct mode users should call `dispose`;
finalizers cover abandoned modes. Native allocation, symbol-resolution, and
processing errors are surfaced rather than silently switching implementations.

The scan-line path preserves sample/channel offsets, ties-to-even color
rounding, gamma-compressed grayscale, Robot 36's packed alternating chroma,
and HF Fax's existing buffer-origin behavior. It copies scratch output back to
the caller, including the original untouched prefix/suffix semantics.

A Windows x64 AOT scan-line benchmark measured **1.09-1.21x** improvement
including FFI upload/copyback: Martin 1 **86.82 to 72.69 us/line**, Robot 36
**34.30 to 29.56 us/line**, and raw **59.19 to 49.89 us/line**. All final
pixels and scratch samples matched the Dart reference exactly. These are
scan-line timings, not end-to-end receive or cross-platform guarantees.

From `src`, run the differential tests and the complete-image benchmark:

```powershell
flutter test test\sstv_native_test.dart
flutter test test\sstv_scanline_test.dart
dart run benchmark\sstv_receive_benchmark.dart
dart run benchmark\sstv_scanline_benchmark.dart
```

The benchmark decodes a complete Robot 36 transmission at 32 kHz in 128-sample
blocks, verifies completion, discards a warm-up run, and reports the median of
three runs for Dart, native scalar, and native SIMD. Performance depends on the
CPU, architecture, and Dart compilation mode.

The scan-line microbenchmark reports per-line time and Dart/native speedup
including FFI buffer copies, with a warm-up and five measured runs for seven
representative receive modes. It compares every final pixel and scratch sample
exactly outside the timed region and isolates the
scan-line work from demodulation. No scan-line speedup numbers have yet been
collected for Intel macOS; Apple Silicon measurements are below. The older
Windows full-receive timings below predate the native scan-line path.

An initial Windows x64 AOT run measured 0.227 seconds for
Dart, 0.218 seconds for native scalar, and 0.103 seconds for native SSE2: about
2.2x faster than Dart for the complete receive pipeline.

### Apple Silicon scan-line tuning

The ARM64 scan-line path validates four samples per loop with NEON, retaining
the scalar tail and checked-filter fallback for inputs outside the safe bound.
NaNs and infinities still fail validation. Color conversion uses ARM64's
fixed ties-to-even conversion instruction after clipping, rather than a
floor/fraction/parity sequence. It does not depend on the host rounding mode.
The EMA recurrence, floating-point operation order, FFI ownership, and exact
pixel/scratch output are unchanged. No fast-math, FMA, Apple framework, or
CPU-specific compiler flags are added; the same baseline NEON path also applies
to supported Linux/Android ARM64 builds. Intel/SSE2 and scalar code are unchanged.

On an Apple M1 running macOS 26.6.2 with Flutter 3.50.0 / Dart 3.14.0, five
alternating before/after AOT benchmark invocations measured:

| Scan-line processing | Before | After | Less processing time |
| --- | ---: | ---: | ---: |
| Martin 1 | 74.78 us | 71.83 us | 3.9% |
| Scottie DX | 173.40 us | 169.32 us | 2.4% |
| Robot 36 | 25.22 us | 24.28 us | 3.7% |
| Robot 72 | 50.62 us | 48.68 us | 3.8% |
| PD 290 | 160.44 us | 153.65 us | 4.2% |
| HF Fax | 86.92 us | 83.49 us | 3.9% |
| Raw | 43.46 us | 41.99 us | 3.4% |

Each invocation discards a warm-up and takes the median of five runs; the table
reports medians across the invocations. Timings include FFI copies, and every
final scratch sample and pixel is compared exactly to Dart outside the timed
region. These modest scan-line gains are not a claim of equivalent full-decoder
speedup; shared-machine load affects elapsed times.

```sh
cd src
dart build cli --target=benchmark/sstv_scanline_benchmark.dart --output=build/sstv_scanline_benchmark
build/sstv_scanline_benchmark/bundle/bin/sstv_scanline_benchmark
flutter test test/sstv_scanline_test.dart test/sstv_native_test.dart test/sstv_monitor_test.dart
```

Regression tests cover every SIMD lane and scalar tail, odd counts and offset
views, non-finite input, the checked fallback on either side of the magnitude
bound, clipping, and both even/odd halfway color values.

### Receive hot-path tuning

The SSE2 filter now prepares real/imaginary coefficient pairs once, avoiding
a coefficient broadcast for every tap of every sample. The coefficient data
grows by one double per tap (520 bytes at 32 kHz). Scalar and NEON coefficient
layouts are unchanged; no newer instruction set is required.

Audio blocks that fit strictly inside the scan-line history buffer use a bulk
typed-data copy instead of a per-sample Dart loop. Blocks that reach or cross
the boundary retain the original shifting path, including sync-index
adjustments. Tests cover exact fills, crossings with stereo input, and large
blocks requiring multiple shifts before a complete image.

Repeated paired Windows x64 AOT runs at 32 kHz measured:

| Complete Robot 36 processing | Before | After |
| --- | ---: | ---: |
| Native SIMD decoder, with scope | 103 ms | 96 ms |
| PCM image monitor | 108.32 ms | 98.21 ms |

These are medians across five decoder and four monitor benchmark invocations;
each invocation itself discards a warm-up and takes the median of three runs.
Shared-machine load caused some variation. This is roughly 7% less decoder
processing time and 9% less monitor processing time, not a receive-memory
reduction. Floating-point reduction order, per-sample oscillator normalization,
and the existing `1e-10` differential tolerance are preserved.

### Receive memory

The always-on image monitor no longer allocates or renders an unused scope.
It also starts with an empty image buffer and allocates pixels only after VIS
identifies the image dimensions. Standalone `Decoder` users can still supply a
scope buffer; passing `null` disables only scope output, not detection.

Removing the two speculative 800x616 pixel buffers eliminates 3,942,400 bytes
(3.76 MiB) of idle pixel storage per receiver. During Robot 36 reception, pixels
require 320x240 storage instead, saving about 3.47 MiB versus the previous
scope-plus-image allocation. A retained-buffer audit across 16 Dart-to-JavaScript
decoders confirmed at least the expected idle saving.

PCM input reuses a conversion buffer for normal packets, avoiding about
14.6 MiB/minute of temporary sample storage during continuous 32 kHz reception.
Retained conversion capacity is capped at 4096 samples (32 KiB); larger inputs
use temporary storage rather than permanently growing the pool.

Completed images transfer their exactly-sized pixel buffer to the completion
event before a fresh decoder is created. They remain independent of later
images and resets. Partial previews still receive their own snapshot buffer,
so asynchronous PNG encoding cannot see subsequent decoder writes; only the
undecoded tail is filled with opaque black.

The receive-memory changes alone left full-monitor AOT processing time
approximately unchanged on the tested x64 machine (about 103-105 ms for a
complete Robot 36 transmission); the later hot-path tuning above improves CPU
time separately.
The benchmark also measures repeated partial-image snapshots, whose timings
can vary with garbage collection:

```powershell
flutter test test\sstv_monitor_test.dart
dart run benchmark\sstv_monitor_benchmark.dart
```

## Encoder performance

The same native platforms also encode all 16 supported modes in C++, including
HF Fax. Image scaling, RGB/YUV conversion, VIS headers, scan-line timing, and
phase-continuous waveform generation run in one native call. Scan-line storage
is reused, output is sized once, and each pixel's frequency increment is
calculated once for its run of samples instead of once per sample.

SSE2/NEON evaluate pairs of sine samples using a double-precision polynomial
after range reduction. The native scalar path uses the platform sine function.
Differential tests compare every waveform sample against Dart, with an absolute
error bound of `1e-9`; PCM comparisons allow at most one 16-bit quantization step.
Encoder phase continuity, reset, all mode lengths, and decoded PCM images are
also tested. ARM64 NEON has not yet been benchmarked on hardware.

Transmission now calls `Encoder.encodePcm16` directly in the existing background
isolate. This avoids the full floating-point audio intermediate and a Dart
sample-conversion loop, while keeping the existing two-second silence prefix.
The float-returning encoder API remains available. Web/iOS use the Dart encoder.

On the Windows x64 development machine, median AOT results at 32 kHz were:

| Mode | Dart PCM16 | Native SIMD PCM16 | Speedup |
| --- | ---: | ---: | ---: |
| Robot 36 | 87.94 ms | 15.86 ms | 5.5x |
| PD 290 | 708.12 ms | 117.00 ms | 6.1x |

PD 290 PCM output occupies 17.80 MiB (including silence), versus 70.71 MiB for
the float waveform alone, before counting the Dart growable sample list.
Native PCM generation does not allocate that float waveform.

Use `--dart-define=HT_SSTV_ENCODER_DART=true` to select the original encoder
independently of receive DSP. `HT_SSTV_SCALAR=true` disables SIMD for both paths.

```powershell
flutter test test\sstv_encoder_test.dart test\sstv_native_test.dart
dart run benchmark\sstv_encode_benchmark.dart
```

The encoder benchmark includes a warm-up and reports the median of three runs.
It covers float and direct PCM output, native scalar, and native SIMD.

The encoder also fuses SIMD sine evaluation with PCM clipping, rounding, and
little-endian packing instead of writing sine results back to a temporary
double buffer. Float output is written directly too. Native encoder scratch
storage uses a malloc-backed arena rather than clearing buffers before
overwriting them; all payload bytes are written by the encoder, and the silence
prefix is still explicitly zeroed.

Back-to-back AOT runs measured about 25-27% less PCM encoding time than the
previous native implementation:

| Mode | Previous native PCM16 | Fused native PCM16 |
| --- | ---: | ---: |
| Robot 36 | 21.33 ms | 15.86 ms |
| PD 290 | 158.02 ms | 117.00 ms |

This reduces memory traffic, not the size of the returned audio buffer. Tests
also cover bipolar full-scale samples, odd-length SIMD tails, unaligned output
after a silence prefix, and PCM agreement within one quantization step.

### Output ownership and peak memory

Completed native audio is copied into Dart-owned typed data before the native
allocation is freed. Returning a finalizer-backed native view proved unsafe
when the encoding isolate exited: full-size Robot 36 output could crash the
application after Send. The copy keeps float/PCM results and their buffer views
valid across `compute`/`Isolate.run` and the subsequent audio-isolate handoff.
Failed encodes also free their native output immediately.

This temporarily requires both output buffers in memory. The timing figures
above predate this safety copy; rerun the benchmark for current measurements.
Tests cover retained views, subsequent encodes and resets, and a full-size
32 kHz Robot 36 encode with its silence prefix surviving worker exit and
transfer to the audio path. Web/iOS fallback behavior is unchanged.
PCM timings varied, so no additional PCM throughput improvement is claimed.

The benchmark's memory options encode only native PD 290, without first
allocating the Dart reference waveform. Run each option in a fresh process;
the measurements above used AOT:

```powershell
dart build cli --target benchmark\sstv_encode_benchmark.dart --output build\sstv_encode_benchmark
.\build\sstv_encode_benchmark\bundle\bin\sstv_encode_benchmark.exe --memory-pcm
.\build\sstv_encode_benchmark\bundle\bin\sstv_encode_benchmark.exe --memory-float
```

### Other opportunities investigated

Symmetric receive FIR tap folding was implemented and measured, including a
compile-time-specialized version. Both were slower on the tested x64 machine
(about 111 ms versus 103 ms for the existing SIMD receive pipeline), so the
original faster implementation was retained.

On the M1, duplicated NEON FIR coefficients and a lane-multiply variant were
also tested. Neither established a reliable complete-receiver gain, so the
existing FIR was retained. Vectorizing the FFT's first stage was slower, and
explicit FFT loop unrolling did not improve timings; neither change is enabled.

Periodic receive oscillator normalization was also tested. Long, low-amplitude
streams slightly exceeded the existing `1e-10` normalized-frequency error
tolerance, so per-sample normalization was retained rather than weakening the
accuracy requirement.

Anti-aliased input decimation remains a receive candidate, but needs noisy-signal
and sync-timing validation. Native scan-line filtering/color conversion is
already enabled on supported native platforms as described above.

## Transmitting

To transmit an image you can drag & drop a PNG, JPEG, BMP into the "Communication" tab or go in the communication tab and select "Image..." from the context menu on the bottom right to select an image. Once an image is selected, you will see a dialog box that will confirm what image will be trasmitted and allows you to select what protocol you want to use.

Note that is seems the radio has a transmit limit of 60 seconds and so, image formats that take longer than 60 seconds will fail to fully transmit. Not sure if this limit can be fixed or not so, the safe bet is to use Robot36.