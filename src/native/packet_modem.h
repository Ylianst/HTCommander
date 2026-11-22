// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
#pragma once
#include <stdint.h>

#ifdef _WIN32
#define HT_PACKET_API __declspec(dllexport)
#else
#define HT_PACKET_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// mode: 0 = AFSK A, 1 = AFSK B, 2 = QPSK, 3 = 8PSK.
typedef struct {
  int32_t mode, slicers, pre_taps, lp_taps, delay_taps;
  int32_t use_lo, v26_b, b_offs, c_offs, s_offs;
  uint32_t pll_step, mark_step, space_step, center_step;
  double locked_inertia, searching_inertia, fast_attack, slow_decay;
  double normalize;
} ht_packet_rx_config;

typedef struct {
  int32_t mode, v26_b;
  uint32_t ticks_sample, ticks_symbol, mark_step, space_step;
} ht_packet_tx_config;

HT_PACKET_API void* ht_packet_rx_create(const ht_packet_rx_config* config,
    const float* pre, const float* lp, const float* oscillator,
    const float* gains);
HT_PACKET_API void ht_packet_rx_destroy(void* state);
// Events in chronological order: bit 0 = value, 1..7 = quality,
// 8..11 = slicer, 12 = DCD event (otherwise a raw demodulated bit).
// Negative result means invalid arguments; no state is consumed.
// pcm_bytes is the available byte length, including offset. Each sample uses
// two bytes; capacity is the number of uint32_t entries in events.
// Borrows PCM/event storage only for this call; no allocations or callbacks.
HT_PACKET_API int32_t ht_packet_rx_process_bounded(void* state, const uint8_t* pcm,
    intptr_t pcm_bytes, intptr_t offset, int32_t samples, uint32_t* events,
    int32_t capacity);
HT_PACKET_API int32_t ht_packet_tx(const ht_packet_tx_config* config,
    const int16_t* sine, const uint8_t* bits, int32_t count,
    uint8_t* pcm, int32_t capacity_samples, int32_t leading, int32_t trailing);

#ifdef __cplusplus
}
#endif
