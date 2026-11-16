// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
#pragma once
#include <stdint.h>
#if defined(_WIN32)
#define HT_RS_API __declspec(dllexport)
#else
#define HT_RS_API __attribute__((visibility("default")))
#endif
#ifdef __cplusplus
extern "C" {
#endif
// Tables are copied. Mode 0: ascending radiosonde coefficients; 1: FX.25.
HT_RS_API void* ht_rs_create(int32_t mode, int32_t roots, int32_t fcr,
    int32_t prim, int32_t inverse_prim, const uint8_t* exp,
    const uint8_t* log, const uint8_t* generator);
HT_RS_API void ht_rs_destroy(void* plan);
// 510 bytes: codeword [0,255), erasure locations [255,510).
HT_RS_API uint8_t* ht_rs_buffer(void* plan);
// Encode writes parity in place. Decode returns corrections or -1; invalid
// arguments return -2. Buffers retain partial corrections even on -1.
HT_RS_API int32_t ht_rs_process(void* plan, int32_t encode, int32_t erasures);
#ifdef __cplusplus
}
#endif
