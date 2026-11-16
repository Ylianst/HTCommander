# Native Reed-Solomon ECC

The radiosonde and FX.25 codecs use block-level native ECC on Windows, Linux,
macOS and Android. Web and iOS retain the Dart implementation. Pass
`useNative: false` to the radiosonde `ReedSolomon`, `Rs41Decoder` or `Lms6Decoder`
constructor, or to FX.25 `ReedSolomon.encode`, `ReedSolomon.decode` and
`Fx25Encode.encodeRs`, to force the reference implementation.

The native asset is `package:htcommander/reed_solomon`. The build hook imports
`reed_solomon.dart` and calls `await buildReedSolomon(input, output)` after the supported-platform
guard. The helper builds `native/reed_solomon.cpp` as C++17 and tracks its header.
No new package dependencies are required.

## Compatibility and lifetime

Both original algorithms are retained, rather than translating codewords into
a superficially similar RS variant:

* RS41: ascending coefficients, parity first, GF polynomial `0x11d`, alpha 2,
  first root 0, primitive-root power 1, 24 roots.
* LMS6: the same layout, polynomial `0x187`, alpha 2, first root 112,
  primitive-root power 11, 32 roots (CCSDS parameters).
* FX.25: descending coefficients, parity last, polynomial `0x11d`, first root
  1, primitive-root power 1, 16/32/64 roots.

FX.25 erasure locations use the existing zero-based codeword indexing. In
particular, the historical reference's **polynomial-form `u` in initialization
of multiple erasures** is preserved, not silently replaced with a conventional
RS decoder. Consequently theoretical multi-erasure capacity is not promised;
native and Dart return the same status and bytes, including historical failures
or miscorrections. Fixing those semantics is a separate change.

Both decoders copy corrections back even when decoding returns `-1`. FX.25 does
not acquire an extra post-correction syndrome check; radiosonde retains its
check. Beyond capacity an RS decoder may miscorrect, so callers must retain
their existing frame CRC checks.

Invalid lengths, byte values, erasure counts and locations throw; native ABI
status `-2` means invalid arguments, whereas `-1` is exclusively a valid
uncorrectable outcome. Missing symbols, allocation failures and other native
errors are explicit exceptions, never silently reported as uncorrectable or
retried in Dart. Unsupported platforms/configurations use Dart by design.

Each plan owns field/generator tables, block storage and reusable scratch
arrays. Native calls process whole blocks. Plans are cached on each sonde codec
or FX.25 control block and freed by native finalizers. FX.25 parameter/table
changes invalidate cached plans. Optional sonde `dispose()` and FX.25
`ReedSolomon.dispose(rs)` eagerly free storage; later calls may recreate it.
Native plan instances are synchronous and not safe for concurrent native calls.
Byte arrays/subviews are copied respecting their Dart offsets.
FX.25 overlapping message/parity views retain the order-dependent Dart encode
path (the alias check is conservative for equal-sized backing buffers).

Sonde plans additionally cache a 64 KiB multiplication table. Fixed-root
syndrome rows interleave independent Horner chains, avoiding per-symbol
logarithms/modulo and serial lookup latency; clean blocks do not clear decoder
scratch. Chien/Forney evaluation uses the same cached multiplication rows.
This changes arithmetic scheduling/storage only, not correction semantics.

## Validation and benchmark

Run from `src` after integrating the build helper:

```powershell
flutter test test\reed_solomon_test.dart test\native_reed_solomon_test.dart test\rs41_test.dart test\lms6_test.dart
dart run benchmark\reed_solomon_benchmark.dart 1000
```

The focused tests compare encoded bytes, correction counts and entire mutated
blocks for clean, maximum-error and over-capacity inputs, ordinary Lists,
typed subviews and randomized error/erasure combinations across all five
supported configurations. Native tests skip unsupported platforms; explicit
reference tests and validation still run. The benchmark warms both paths,
reports median microseconds per block including upload/copyback/cache overhead,
checks corrected codewords, and measures clean/max-error decoding and single
erasures in addition to encoding.

Windows x64 AOT measurements (median of five 1,000-block runs, including
upload/copyback) measured RS41 clean/max-error decoding at **3.54/10.67 us**
versus **17.44/54.68 us** in Dart, and LMS6 at **6.29/18.14 us** versus
**23.02/77.13 us**. FX.25 decoding improved approximately **1.3-1.8x** across
16/32/64-root cases. These are local results, not platform-independent
guarantees. Build the benchmark with `dart build cli` to bundle native assets;
`dart compile exe` alone does not provide a deployable native-asset bundle.
