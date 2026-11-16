// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
#ifndef HT_DART_DSP_H
#define HT_DART_DSP_H
#include <stdint.h>
#if defined(_WIN32)
#define HT_DART_EXPORT __declspec(dllexport)
#else
#define HT_DART_EXPORT __attribute__((visibility("default"), used))
#endif
#ifdef __cplusplus
extern "C" {
#endif

// All storage belongs to the caller. LDPC workspace has edges doubles;
// the output buffer holds n hard-decision bytes (first k are information).
// Decode returns the correction count, including on iteration exhaustion;
// as in the reference implementation, the frame CRC decides acceptance.
HT_DART_EXPORT void ht_dart_ldpc_encode(
    const uint16_t* starts, const uint16_t* columns, int32_t k, int32_t n,
    const uint8_t* info, uint8_t* out);
HT_DART_EXPORT int32_t ht_dart_ldpc_decode(
    const uint16_t* starts, const uint16_t* columns,
    const uint16_t* var_starts, const uint16_t* var_edges,
    int32_t k, int32_t n, int32_t iterations, const double* llr,
    double* work, uint8_t* out);
HT_DART_EXPORT int32_t ht_dart_simd_width(void);
// In-place re/im *= conjugate(reference), n <= 2048, disjoint arrays.
HT_DART_EXPORT void ht_dart_multiply_conjugate(
    double* re, double* im, const double* ref_re, const double* ref_im,
    int32_t n, int32_t simd);
// Bounded PCM kernels: count <= 4096. Conversion rounds ties away from zero
// and clamps to +/-32767. Returns -1 for non-finite scaled samples.
HT_DART_EXPORT double ht_dart_peak(const double* samples, int32_t count, int32_t simd);
HT_DART_EXPORT int32_t ht_dart_to_pcm(
    const double* samples, int32_t count, double scale, int16_t* out, int32_t simd);
HT_DART_EXPORT void ht_dart_from_pcm(
    const int16_t* samples, int32_t count, double* out, int32_t simd);

// Bounded leaf kernels: DFT size <= 128; correlation reference <= 2048,
// count <= 64; FSK samples per symbol <= 2048; TX output <= 4096 samples.
HT_DART_EXPORT void ht_dart_dft(
    const double* input, const double* cosine, const double* sine,
    int32_t n, double norm, int32_t inverse, double* out);
HT_DART_EXPORT void ht_dart_correlate(
    const double* samples, const double* reference, int32_t length,
    double energy, int32_t start, int32_t count, double* out);
// Normalize an unnormalized inverse FFT correlation block. n <= 2048,
// count <= n-length+1; the sample window contains count+length-1 samples.
HT_DART_EXPORT void ht_dart_corr_normalize(
    const double* samples, int32_t length, double energy,
    const double* correlation, int32_t n, int32_t count, double* out);
HT_DART_EXPORT void ht_dart_fsk_energy(
    const double* samples, int32_t count, const double* cosine,
    const double* sine, int32_t stride, double* out, int32_t simd);
// At most 4096 sample positions per call, including truncated/absent symbols.
// quality holds cumulative [sum of tone-energy ratios, complete-symbol count].
HT_DART_EXPORT void ht_dart_fsk_soft(
    const double* samples, int32_t count, const double* cosine,
    const double* sine, int32_t stride, double* out, int32_t symbols,
    double* quality, int32_t measure_snr, int32_t simd);
HT_DART_EXPORT double ht_dart_fsk_modulate(
    const uint8_t* bits, int32_t count, int32_t sps, const double* steps,
    const double* cosine, const double* sine, double phase, double* out);
#ifdef __cplusplus
}
#endif
#endif
