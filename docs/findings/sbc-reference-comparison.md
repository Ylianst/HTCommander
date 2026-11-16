# SBC external-reference comparison

## Result

**Google libsbc is the selected bit-exact target.** The Dart encoder now
matches all 64,064 tested encoded frames, and the decoder matches all
16,219,136 tested PCM samples. The optimized native codec also matches Dart
exactly in its supported radio format.

The correction changes negative-sample scale-factor calculation in both
encoders to match Google. Decoder arithmetic was already exact and is unchanged.
BlueZ remains an independent diagnostic reference with different numerical
output; matching it is not the selected goal. These results are not a Bluetooth
SIG conformance certification or a proof over every possible input.

## References and reproduction

Tested locally on Windows x64 with MSVC 14.51.36231:

- [BlueZ SBC 2.2](https://www.kernel.org/pub/linux/bluetooth/sbc-2.2.tar.xz),
  generic C implementation, LGPL-2.1-or-later.
  Archive SHA256:
  `a1ada76ef35e5af9c2fbd063754dc9e37a8d989417c6eb1ecebb089b1383ae9e`.
- [Google libsbc](https://github.com/google/libsbc/tree/6e505650145c9973d08a0bdd5e5f5e1914305e40),
  revision `6e505650145c9973d08a0bdd5e5f5e1914305e40`, Apache-2.0.
  This is the implementation whose analysis filter structure is cited by our
  original port.

From the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\tool\compare_sbc.ps1
```

The [script](../../src/tool/compare_sbc.ps1) downloads pinned sources, checks
the archive hash/checkout revision, builds both DLLs, and runs the
[comparison tool](../../src/tool/sbc_reference_compare.dart). It requires
Visual Studio x64 C++ build tools, Dart with the application's dependencies
already restored, Git, curl, and tar.

Upstream codec sources are not edited. A
[build-only compatibility header](../../src/tool/sbc_reference_msvc.h)
supplies Windows type/endian declarations, removes GCC-only attributes, and
implements Google's leading-zero intrinsic using `_BitScanReverse`.
The [Google adapter](../../src/tool/sbc_google_reference.c) only owns contexts
and bridges interleaved PCM; filter, allocation, and quantization arithmetic
remain upstream. Both references are compiled with `/O2`, without assembly.

Sources and binaries stay under the already-ignored
[reference directory](../../reference). Detailed machine-readable results:

- [BlueZ comparison](../../reference/sbc-comparison/bluez-comparison.json)
- [Google comparison](../../reference/sbc-comparison/google-comparison.json)

Each report explicitly records `requiredBitExact`, `nativeParity`, and
`externalBitExact`. Google has `requiredBitExact: true`; BlueZ is diagnostic.
The Dart tool exits 1 for a native/Dart discrepancy, 2 for a Google numerical
difference, and 0 when Google and native parity pass. BlueZ differences are
still printed and recorded, but do not fail the selected Google target.
The PowerShell wrapper throws on either nonzero result.

The checked-in [Google golden vectors](../../src/test/sbc_vectors/google.json)
run offline through [focused tests](../../src/test/sbc_reference_test.dart).
They contain fixed PCM inputs and independent C-generated compressed bytes and
decoded samples for mono, stereo, joint stereo, both subband counts, both
allocation methods, and mSBC. To deliberately regenerate them:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\tool\compare_sbc.ps1 -UpdateGoldens
```

Golden data is generated only by Google, never by the production Dart encoder.
All seven golden profiles detect the original encoder bug when run against a
pre-correction source snapshot.

## Coverage

Each reference run covers 1,305 configurations:

- All four sampling rates and channel modes.
- Four/eight subbands; 4/8/12/16 blocks; loudness and SNR allocation.
- Sampled bitpools 2, 18, 40, 53, 64, 124, where accepted by our frame validator.
- One additional standard mSBC configuration.

Each configuration runs a continuous 32-frame sequence: four frames each of
silence, impulse, 997 Hz tone, multitone, low-level tone, deterministic
full-range noise, alternating full-scale samples, and trailing silence.
It then repeats after resetting/reusing Dart and native RX states, with fresh
reference contexts. This exercises filter history and reset behavior.
Native RX packets are also fragmented across calls.

Both PCM channels are compared between Dart and the external decoder.
The radio's native RX API outputs only the left channel, so native comparisons
use that channel. Native TX's actual fixed format is 32 kHz, mono, 16 blocks,
eight subbands, bitpool 18; both allocation methods are checked.

Dual-channel **decoding** uses real BlueZ-generated frames for every reference.
Dual-channel encoding is excluded: Dart's existing path is unsupported, and
Google's corresponding path repeats the shifted-channel scale-factor call.
The test does not use either as a dual-channel encoding oracle.

These are deterministic differential tests, not exhaustive bitpool/input
coverage, official conformance vectors, or real-radio recordings.

## Measured results

| Comparison | Result |
| --- | --- |
| Native TX vs Dart TX | 128/128 frames identical per reference run |
| Native RX vs Dart RX | 18,642,944 sample comparisons across both runs; zero differences |
| Dart decoder vs Google decoder | 16,219,136 sample comparisons; zero differences |
| Dart encoder vs Google encoder | 64,064/64,064 frames byte-identical |
| Dart encoder vs BlueZ encoder | 28,780/64,064 frames byte-identical |
| Dart vs BlueZ decoding of BlueZ frames | Maximum PCM difference 17,069; RMSE 267.587 |
| Dart vs BlueZ decoding of Dart frames | Maximum PCM difference 13,991 |

Decoder comparisons use the **same compressed input** for both decoders.
Encoding is compared separately by decoding both encoders' streams through the
same reference decoder, avoiding confusion between encoder and decoder errors.

### Radio-format results

For 32 kHz mono, 16 blocks, eight subbands, across the six bitpools and both
allocation methods:

- Google: 768/768 encoded frames byte-identical; decoder output always exact.
- Google-decoded differences between the two encoded streams: zero.
- BlueZ decoding of its own encoded stream versus Dart decoding that stream:
  maximum difference 8,859, aggregate RMSE 240.586.

For the loudness/bitpool-18 radio profile, BlueZ/Dart decoder differences on
the ordinary tone and multitone segments peak at 10 PCM units, but reach
7,492 on the full-range noise segment. At loudness/bitpool 40, full-scale input
produces a maximum decoder difference of 6,524. These large stress-input
differences must not be described as uniformly harmless rounding noise.

## Corrected encoder discrepancy

The Google reference's
[scale-factor calculation](https://github.com/google/libsbc/blob/6e505650145c9973d08a0bdd5e5f5e1914305e40/src/sbc.c)
uses one's complement for negative samples (`s < 0 ? ~s : s`).
Our [encoder](../../src/lib/sbc/sbc_encoder.dart) previously used absolute value.
At negative powers of two this changes the scale factor: for example, `-2`
contributes 1 in Google and 2 in Dart, yielding scale factors 0 and 1.
The joint-stereo scale-factor calculation had the same sign-handling difference.
Both Dart paths and the fixed-format native encoder now use one's complement.

Before the fix, captured wire data confirmed differing scale-factor nibbles. For the
32 kHz/mono/16x8/loudness/bitpool-18 case, the first Google mismatch occurs in
frame 10 (zero-based), with:

```text
Dart:   [14, 4, 2, 1, 1, 1, 1, 1]
Google: [14, 4, 2, 1, 1, 1, 0, 1]
```

That changed the CRC and could change allocation/quantization. Some different
frames still decoded identically when the affected subband got no bits.
This was a shared port/reference discrepancy, not an optimization-only
regression. Before correction, 13,122 encoded frames differed from Google,
and Google-decoded differences reached 43,624 PCM units in the stress matrix.
After correction, every encoded-byte and decoded-sample difference against
Google in that matrix is zero.

The optimized native path remains exact against Dart after the correction.
BlueZ's non-identical decoder output remains outside this selected target;
official conformance vectors would be needed before claiming universal SBC
correctness.

## Validation

- Both pinned reference DLLs build and both complete comparison reports persist.
- Targeted Dart analysis: no issues.
- `flutter test --no-pub test\sbc_reference_test.dart test\radio_audio_codec_test.dart`:
  all targeted tests pass.
- Google bit-exact comparison and native parity: **pass with zero tolerance**.
- BlueZ differences: retained in the diagnostic report, not relabeled exact.
