// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
#ifndef HT_SSTV_SCANLINE_H
#define HT_SSTV_SCANLINE_H
#include "sstv_dsp.h"
#ifdef __cplusplus
extern "C" {
#endif
// config: kind (0 RGB, 1 YUV, 2 PD, 3 Robot36 even, 4 Robot36 odd,
// 5 gray), width, count, four channel starts, four channel lengths.
// Input/scratch have count elements; pixels has width (or 2*width for PD/36).
// Starts are relative to the filtered input. No pointers are retained.
HT_SSTV_EXPORT int32_t ht_sstv_scanline(
    const double* input, double* scratch, int32_t* pixels,
    const int32_t* config, double alpha, double frequency_offset);
#ifdef __cplusplus
}
#endif
#endif
