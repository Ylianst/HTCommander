// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
// Numerical kernels ported from the Dart XARA port.
// XARA: Copyright (c) 2026 x0rro and the XARA authors, MIT License.
#ifndef HT_XARA_DSP_H
#define HT_XARA_DSP_H

#include <stdint.h>

#if defined(_WIN32)
#define HT_XARA_EXPORT __declspec(dllexport)
#else
#define HT_XARA_EXPORT __attribute__((visibility("default"), used))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// All buffers belong to the caller. No pointer is retained across calls.
// Invalid arguments to void kernels emit a function-named stderr diagnostic.
// Pointer allocation extents cannot be inferred by this ABI: callers must
// supply the documented lengths; Dart wrappers validate typed-list extents.
// FFT n is a power of two, cosine/sine have n/2 entries, reverse has n
// entries in [0,n), and re/im have n entries each.
// SIMD uses only baseline SSE2 (x86-64) or NEON (ARM64); other targets use scalar.
HT_XARA_EXPORT int32_t ht_xara_simd_width(void);
HT_XARA_EXPORT void ht_xara_fft(
    double* re, double* im, const double* cosine, const double* sine,
    const int32_t* reverse, int32_t n, int32_t inverse, int32_t simd);

// Bounded leaf variant: n <= 2048. work has 2*n doubles and is only needed
// when re/im overlap; copy-back order matches the ordinary Dart FFI wrapper.
HT_XARA_EXPORT void ht_xara_fft_direct(
    double* re, double* im, const double* cosine, const double* sine,
    const int32_t* reverse, int32_t n, int32_t inverse, int32_t simd,
    double* work);

// x contains taps + (count - 1) * dec samples in chronological order.
// hr/hi are in reverse tap order. out contains count interleaved complex values.
HT_XARA_EXPORT void ht_xara_fir(
    const double* x, const double* hr, const double* hi, int32_t taps,
    int32_t dec, int32_t count, double* out, int32_t simd);

// Scan count adjacent STFT positions against one OFDM marker/data pattern.
// The circular buffer is bin-major: diff[bin * capacity + row].
// bins are interleaved complex scalar offsets, rows are relative to first.
// refs is interleaved complex.
// scratch has 4*count doubles; out has 2*count (markerChi, dataChi) values.
// marker_min=-infinity preserves all metrics; otherwise dataChi is zero for
// candidates that fail markerChi >= marker_min.
HT_XARA_EXPORT void ht_xara_correlate(
    const float* diff, int32_t capacity,
    const int32_t* rows, const int32_t* bins, const double* refs,
    int32_t markers, int32_t cells, int32_t first, int32_t count,
    double marker_min, double* scratch, double* out, int32_t simd);

HT_XARA_EXPORT void ht_xara_append_row(
    float* diff, int32_t capacity, int32_t width, int32_t index,
    const float* row);

// Bounded leaf kernel: n <= 128. Rounds FFT output to float32 before taking
// differential products, matching the reference STFT's storage precision.
HT_XARA_EXPORT void ht_xara_append_spectrum(
    float* diff, int32_t capacity, int32_t index,
    const double* re, const double* im, const float* previous,
    float* row, int32_t n, int32_t has_previous);

typedef struct {
  int32_t index;
  int32_t count;
  double fraction;
} HtXaraResampled;

// table has (phases+1)*2*half entries; index >= half-1; fraction/part are
// in [0,1), whole >= 0 and whole+part > 0.
// Returns 0 on success, -1 on insufficient capacity, -2 on invalid parameters.
HT_XARA_EXPORT int32_t ht_xara_resample(
    const double* x, int32_t length, const double* table, int32_t half,
    int32_t phases, int32_t index, double fraction, int32_t whole,
    double part, double* out, int32_t capacity, HtXaraResampled* result,
    int32_t simd);

// Returns iterations run, -1 on invalid input, -2 on allocation failure.
// The four input streams have k + 3 entries. bits has k entries.
// min_iters=0 disables early CRC termination; white is one byte per bit.
HT_XARA_EXPORT int32_t ht_xara_turbo(
    const double* ls, const double* lp1, const double* ls2, const double* lp2,
    const int32_t* perm, int32_t k, int32_t iters, double scale,
    int32_t min_iters, const uint8_t* white, int32_t white_length,
    int32_t nbytes, uint8_t* bits);

#ifdef __cplusplus
}
#endif
#endif
