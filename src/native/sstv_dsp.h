// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
#ifndef HT_SSTV_DSP_H
#define HT_SSTV_DSP_H

#include <stdint.h>

#if defined(_WIN32)
#define HT_SSTV_EXPORT __declspec(dllexport)
#else
#define HT_SSTV_EXPORT __attribute__((visibility("default"), used))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct HtSstvDemodulator HtSstvDemodulator;
typedef struct {
  int32_t detected;
  int32_t width;
  int32_t offset;
  double frequency_offset;
} HtSstvSync;

HT_SSTV_EXPORT int32_t ht_sstv_simd_width(void);
// Copies taps; returns null on allocation failure. No Dart pointers are retained.
HT_SSTV_EXPORT HtSstvDemodulator* ht_sstv_create(
    int32_t sample_rate, const double* taps, int32_t tap_count,
    int32_t sync_count, int32_t min5, int32_t max5, int32_t max9,
    int32_t max20, int32_t simd);
HT_SSTV_EXPORT void ht_sstv_destroy(HtSstvDemodulator* state);
// Demodulates in place, retaining oscillator/filter/sync state across blocks.
// channel_select: 0 mono, 1 left, 2 right, 3 sum, 4 complex I/Q.
HT_SSTV_EXPORT void ht_sstv_process(
    HtSstvDemodulator* state, double* samples, int32_t length,
    int32_t channel_select, HtSstvSync* result);
// Mono little-endian PCM16 input; output has capacity length / 2 doubles.
HT_SSTV_EXPORT void ht_sstv_process_pcm16(
    HtSstvDemodulator* state, const uint8_t* pcm, int32_t length,
    double* output, HtSstvSync* result);

// Encoder modes use their VIS code; -1 selects HF Fax. Returns -1 if invalid.
HT_SSTV_EXPORT int64_t ht_sstv_encoded_length(int32_t sample_rate, int32_t code);
// output has capacity samples (doubles, or little-endian PCM16 when pcm != 0).
// phase is in/out; no pointers are retained. Returns 0 on success, -1 for
// invalid arguments/capacity, -2 for an internal output-length mismatch.
HT_SSTV_EXPORT int32_t ht_sstv_encode(
    const int32_t* pixels, int64_t pixel_count, int32_t width, int32_t height,
    int32_t sample_rate, int32_t code, double* phase, void* output,
    int64_t capacity, int32_t pcm, int32_t simd);

#ifdef __cplusplus
}
#endif
#endif
