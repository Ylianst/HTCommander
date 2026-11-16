// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
#pragma once
#include <stdint.h>

#if defined(_WIN32)
#define HT_TELEMETRY_API __declspec(dllexport)
#else
#define HT_TELEMETRY_API __attribute__((visibility("default")))
#endif

extern "C" {
// Reusable recording storage. Resize invalidates prior views and cached sums.
HT_TELEMETRY_API void* ht_telemetry_create();
HT_TELEMETRY_API int16_t* ht_telemetry_resize(void* recording, int32_t count);
HT_TELEMETRY_API void ht_telemetry_destroy(void* recording);
HT_TELEMETRY_API void* ht_telemetry_recording_sonde(
    void* recording, int32_t rate, int32_t mode, int32_t chip_rate,
    int32_t frame_symbols, const double* header, int32_t header_count);
HT_TELEMETRY_API void* ht_telemetry_recording_sarsat(
    void* recording, int32_t rate, double carrier);
// Modes: 0 Manchester bits, 1 NRZ LSB bytes, 2 differential Manchester
// MSB bytes, 3 NRZ bits, 4 iMet bytes. Headers contain +/-1 chips.
HT_TELEMETRY_API void* ht_telemetry_sonde(
    const int16_t* pcm, int32_t count, int32_t rate, int32_t mode,
    int32_t chip_rate, int32_t frame_symbols, const double* header,
    int32_t header_count);
HT_TELEMETRY_API void* ht_telemetry_sarsat(
    const int16_t* pcm, int32_t count, int32_t rate, double carrier);
HT_TELEMETRY_API int32_t ht_telemetry_count(const void* result);
HT_TELEMETRY_API int32_t ht_telemetry_length(const void* result, int32_t frame);
HT_TELEMETRY_API const uint8_t* ht_telemetry_data(const void* result, int32_t frame);
HT_TELEMETRY_API void ht_telemetry_free(void* result);
}
