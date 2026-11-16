// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
#pragma once
#include <stdint.h>

#if defined(_WIN32)
#define HT_CW_API __declspec(dllexport)
#else
#define HT_CW_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif
// Coefficients are copied. At most 4096 probes and 256 windows per call.
HT_CW_API void* ht_cw_create(
    const double* coefficients, int32_t probes, int32_t window, int32_t hop);
HT_CW_API void ht_cw_destroy(void* state);
// Reuses storage. Returned input remains valid until next prepare/destroy.
HT_CW_API double* ht_cw_prepare(void* state, int32_t windows);
// 0 = success, -1 = invalid state/arguments, -2 = non-finite input.
// Not a leaf call: work scales with window size, probes and window count.
HT_CW_API int32_t ht_cw_process(void* state, int32_t windows);
// Triples: frame energy, maximum probe power, peak probe index (-1 if no peak).
// Borrowed until next prepare/process/destroy.
HT_CW_API const double* ht_cw_metrics(const void* state);
#ifdef __cplusplus
}
#endif
