// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
#ifndef HT_ECHOLINK_GSM_H
#define HT_ECHOLINK_GSM_H
#include <stdint.h>

#ifdef _WIN32
#define HT_GSM_API __declspec(dllexport)
#else
#define HT_GSM_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ht_gsm_codec ht_gsm_codec;

HT_GSM_API int32_t ht_gsm_simd_width(void);
HT_GSM_API int32_t ht_gsm_storage_bytes(void);
HT_GSM_API const char* ht_gsm_license(void);
HT_GSM_API ht_gsm_codec* ht_gsm_create(int32_t encoder, int32_t simd);
HT_GSM_API void ht_gsm_destroy(ht_gsm_codec* codec);
HT_GSM_API void ht_gsm_reset(ht_gsm_codec* codec);
// Fixed owned buffers: 640 PCM samples and 132 toast-frame bytes per packet.
HT_GSM_API int16_t* ht_gsm_pcm(ht_gsm_codec* codec);
HT_GSM_API uint8_t* ht_gsm_frames(ht_gsm_codec* codec);
// Returns 0 on success, -1 for a wrong-direction/null handle, or (decode only)
// the 1-based invalid frame index. Earlier valid frames advance decoder state.
HT_GSM_API int32_t ht_gsm_encode(ht_gsm_codec* codec);
HT_GSM_API int32_t ht_gsm_decode(ht_gsm_codec* codec);

#ifdef __cplusplus
}
#endif
#endif
