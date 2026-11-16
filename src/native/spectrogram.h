// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
#pragma once
#include "xara_dsp.h"

extern "C" {
HT_XARA_EXPORT void* ht_spectrogram_create(int32_t size, int32_t step,
    int32_t first, int32_t last, const double* window);
HT_XARA_EXPORT void ht_spectrogram_destroy(void* context);
HT_XARA_EXPORT int32_t ht_spectrogram_add(void* context, const double* samples,
    int32_t count);
HT_XARA_EXPORT int32_t ht_spectrogram_pcm(void* context, const uint8_t* samples,
    int32_t count);
HT_XARA_EXPORT int32_t ht_spectrogram_process(void* context);
HT_XARA_EXPORT int32_t ht_spectrogram_resize(void* context, int32_t columns);
HT_XARA_EXPORT int32_t ht_spectrogram_width(void* context);
HT_XARA_EXPORT int32_t ht_spectrogram_pending(void* context);
HT_XARA_EXPORT int32_t ht_spectrogram_next(void* context);
HT_XARA_EXPORT void ht_spectrogram_roll_reset(void* context, int32_t offset);
HT_XARA_EXPORT void ht_spectrogram_clear(void* context);
HT_XARA_EXPORT void ht_spectrogram_peak(void* context, double* result);
HT_XARA_EXPORT int32_t ht_spectrogram_render(void* context, uint8_t* rgba,
    const uint8_t* colors, double intensity, double db_scale, int32_t decibel,
    int32_t roll, int32_t count);
}
