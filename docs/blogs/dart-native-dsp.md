# Native DART software-modem DSP

DART uses native numerical kernels by default on Windows, Linux, macOS, and
Android. Web and iOS retain the portable Dart implementation. The on-air format,
header, CRCs, interleaving, scrambling, mode selection, pilots, and ARQ are
unchanged. This accelerates the existing DART modem, not the unrelated packet,
XARA, or SSTV protocols.

## What runs natively

- **LDPC encoding and decoding:** the same DART parity-check graph and scaled
  min-sum algorithm, including summation order, 50-iteration limit, and correction
  accounting. As before, iteration exhaustion returns the final hard decision;
  the frame CRC determines acceptance. These codes use a custom accumulator
  parity structure, so replacing them with an unmodified IEEE 802.11n decoder
  would not be wire-compatible. Check and variable updates alternate in one
  message buffer; sparse graph offsets and indices fit in 16 bits.
- **FFT/IFFT:** reuses the existing XARA SSE2/NEON native FFT, with DART's inverse
  normalization. OFDM maps into reusable split real/imaginary arrays directly,
  returning objects only for active carriers instead of constructing
  FFT-sized `Complex` arrays. No additional FFT library is needed.
- **DFT spreading:** native double-precision transforms using cached twiddles.
  Forward and inverse transforms share the same tables via conjugation.
- **Preamble correlation:** bounded overlap-save FFT blocks replace the default
  sample-by-sample dot-product scan. Rolling energy normalizes each position;
  the existing lobe verification and earliest-strong-lobe selection remain in
  Dart. All-zero blocks skip the transforms. Unusual preamble lengths use bounded
  direct native correlation, or the Dart reference outside native limits.
  Spectral products use SSE2/NEON.
- **Mode F:** native tone-energy detection with cached sine/cosine tables, and
  batched continuous-phase synthesis using those same tables. Two-lane SIMD
  accelerates tone dot products. Soft demodulation is batched, with the payload
  SNR computed from the same energies instead of rescanning the audio.
- **PCM:** native SIMD peak scanning, normalization to int16, and int16-to-double
  conversion. Rounding matches Dart's ties-away-from-zero behavior, including
  doubles immediately below a half-integer; clipping remains +/-32767.

Framing and receiver control remain in Dart. FFT and oscillator roundoff can
differ from the reference; tests require PCM differences of at most one int16
unit and cross-decode frames in both directions.

## CPU and allocation behavior

The native LDPC plan caches its graph, channel buffer, messages, and hard
decisions per code rate. It now needs approximately **18-19 KiB of message
storage**, versus 36-37 KiB in the first native version and the per-block Dart
reference allocation. Both native message and graph storage are halved; across
all four initialized rates this saves about **116 KiB** including alignment,
with channel/hard-decision storage unchanged. FFT/DFT work buffers are also
reused. The default correlator's double buffers occupy about 38 KiB,
independent of input-stream length, plus a shared native FFT plan. Mode F avoids
per-sample trigonometry and per-symbol tone-energy/amplitude list allocation.
Bit-stream processing also avoids temporary PN arrays, redundant interleaver
copies, and per-block LDPC input allocations.

This trades lazy, long-lived workspaces for less allocation churn; it is not a
claim that total process RSS is lower. Payload/PCM results and some intermediate
symbol objects still allocate. Native allocations have finalizers and are
accounted as external memory. Short bounded kernels pin typed data for leaf
calls; iterative LDPC decoding copies only its 648 LLRs to reusable storage and
runs non-leaf so it does not hold up GC. PCM and FSK batches cover at most 4096
sample positions per leaf call.

Example warm bundled-AOT results on the Windows development machine, comparing
the preserved first native executable against this second pass with 256-byte
payloads (median milliseconds over five batches; illustrative, not CI thresholds):

| Work | Previous native | Optimized native |
|---|---:|---:|
| Mode 2 encode | 1.334 | 0.550 |
| Mode 2 decode | 3.024 | 2.459 |
| Mode 5 encode | 0.768 | 0.324 |
| Mode 5 decode | 2.216 | 1.746 |
| Mode F encode | 4.157 | 0.957 |
| Mode F decode | 13.220 | 11.130 |
| One-second silence scan, Mode 2 configuration | 0.307 | 0.350 |
| Noisy LDPC block, rate 1/2 | 0.203 | 0.200 |

The new Mode F soft-decode-plus-SNR microbenchmark took 0.169 ms with SIMD versus
0.283 ms with the new scalar kernels (2048 coded bits). Native LDPC speed and
silence scans are largely unchanged; the LDPC improvement here is memory use.

Other platforms and physical-radio CPU/memory consumption have not been
measured here.

## Verification and reference selection

From `src`:

```text
flutter test test/dart_native_test.dart test/modem_tx_encoder_test.dart
dart run benchmark/dart_native_benchmark.dart
dart run test/dart_modem_tool.dart loopback --sbc
```

For an AOT benchmark, use `dart build cli` with
`--target=benchmark/dart_native_benchmark.dart` and an `--output` directory, then
run the executable under that directory's `bundle/bin`. This bundles the code
assets; a bare `dart compile exe` does not. The benchmark reports the median of
five timed batches after warm-up.

`DartModem(useNative: false)` selects the reference for that modem, including its
preamble, OFDM, FSK, and LDPC operations. The lower-level components expose the
same switch. Set `HT_DART_REFERENCE=true` in the environment, or supply the
equivalent Dart define, to disable native DART kernels process-wide. The reused
FFT also honors XARA's existing `HT_XARA_DART` and `HT_XARA_SCALAR` switches.
Disabling XARA native kernels leaves DART's other native kernels enabled.
`HT_DART_SCALAR=true` (environment or Dart define) disables DART's new SIMD
intrinsics while retaining native kernels and the independent XARA FFT setting.

The focused tests cover all seven modes, empty and multi-block payloads, noisy
and iteration-exhausted LDPC blocks, FIFO preamble detection and search offsets,
direct-correlation fallbacks, custom OFDM parameters without payload pilots,
and odd-length/truncated Mode F input. The existing SBC loopback tool also
produces the same outcomes with native kernels and the reference.
Additional cases cover exact PCM rounding/clipping and every int16 input value,
retained OFDM results and weak-carrier equalization, batched SNR with incomplete
audio, SIMD/direct correlation parity, and original reference PCM wire fixtures
on Windows. SIMD, scalar-native, and forced-reference runs are checked separately.

The build entry point calls [the DART hook](../../src/hook/dart_modem.dart);
the kernels are in [dart_dsp.cpp](../../src/native/dart_dsp.cpp), and the portable
facade is [native_dart_dsp.dart](../../src/lib/hamlib/native_dart_dsp.dart).
