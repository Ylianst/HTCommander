# Vendored libgsm

Minimal integer GSM 06.10 encoder/decoder sources from
[libgsm 1.0.24](https://www.quut.com/gsm/gsm-1.0.24.tar.gz).

Archive SHA256:
`a3c40c6471928383f4abfcb2e8f24012a1f562be2f17b8d672145d5986681a92`.

The upstream permissive license is preserved in [COPYRIGHT](COPYRIGHT) and
embedded in the shared library through the exported `ht_gsm_license` function.
Only library sources needed for standard 33-byte toast frames are included;
WAV49, floating-point, FAST and LTP_CUT options are not enabled.

Local changes:

- `inc/private.h`: fixed-width integer types (including on LP64 platforms) and
  a per-stream SIMD flag.
- `src/long_term.c`: optional exact integer SIMD dot products for pitch search,
  and an exact-zero residual shortcut returning the same lag/gain parameters
  without searching. Reconstructed-history and filtering updates still run.
- `src/lpc.c`: optional exact integer SIMD autocorrelation, with zero
  correlations returned immediately for an exactly zero input frame.
- `src/preprocess.c`: zero output shortcut only when the complete PCM frame and
  all three preprocessing state values are exactly zero; filter tails still run.

The SIMD helper lives in [../gsm_simd.h](../gsm_simd.h): SSE2 on x64, NEON on
ARM64, scalar elsewhere. It uses unaligned loads, bounded vector loops and
scalar tails. The GSM input scaling bounds these accumulations to int32.

[../echolink_gsm.c](../echolink_gsm.c) owns each direction's independent state
and fixed packet buffers. Reset preserves SIMD selection and restores `nrp=40`.
Malformed frames retain the same partial decoder progress as the Dart codec.
