// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
#ifndef HT_RADIO_AUDIO_CODEC_H
#define HT_RADIO_AUDIO_CODEC_H

#include <stdint.h>

#if defined(_WIN32)
#define HT_AUDIO_EXPORT __declspec(dllexport)
#else
#define HT_AUDIO_EXPORT __attribute__((visibility("default"), used))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct HtAudioCodec HtAudioCodec;

enum {
  HT_AUDIO_RESET_DECODER = 1,
  HT_AUDIO_RESET_PARSER = 2,
  HT_AUDIO_RESET_ENCODER = 4,
  HT_AUDIO_ERROR_NONE = 0,
  HT_AUDIO_ERROR_SYNC = 1,
  HT_AUDIO_ERROR_HEADER = 2,
  HT_AUDIO_ERROR_TRUNCATED = 3,
  HT_AUDIO_ERROR_CRC = 4,
  HT_AUDIO_ERROR_OVERFLOW = 5,
  HT_AUDIO_ERROR_ESCAPE = 6
};

// Output storage belongs to the context and remains valid until its next
// encode/reset/destroy call. Input is little-endian 32 kHz/16-bit/mono PCM.
typedef struct {
  int32_t pcm_consumed;
  int32_t data_length;
  int32_t batch_count;
  int32_t reserved;
  const uint8_t* data;
  const int32_t* lengths;
  const int32_t* samples;
} HtAudioTxResult;

// One unescaped Bluetooth packet, optionally SBC-decoded according to the
// command bit in decode_mask. A valid PCM prefix survives a trailing bad frame.
// Storage remains valid until the next decode/reset/destroy call.
typedef struct {
  int32_t consumed;
  int32_t command;
  int32_t payload_bytes;
  int32_t pcm_samples;
  int32_t decoded_frames;
  int32_t rejected_bytes;
  int32_t error;
  int32_t format_count;
  int64_t audio_us;
  const int16_t* pcm;
  const uint32_t* formats;  // frequency_index << 16 | mode_index << 8 | bitpool
} HtAudioRxResult;

HT_AUDIO_EXPORT uint32_t ht_audio_abi_version(void);
HT_AUDIO_EXPORT HtAudioCodec* ht_audio_create(void);
HT_AUDIO_EXPORT void ht_audio_destroy(HtAudioCodec* codec);
HT_AUDIO_EXPORT void ht_audio_reset(HtAudioCodec* codec, uint32_t flags);

// 0 = success, -1 = invalid arguments, -2 = allocation failure, -3 = codec
// failure. Encodes all complete 256-byte SBC inputs; no partial PCM is retained.
// Groups <=300-byte SBC payloads into escaped 0x7e/command-0 packets, up to four
// packets per batch. allocation is 0=loudness, 1=SNR.
HT_AUDIO_EXPORT int32_t ht_audio_encode(
    HtAudioCodec* codec, const uint8_t* pcm, int32_t length,
    int32_t allocation, HtAudioTxResult* result);

// 1 = packet/diagnostic event, 0 = incomplete (all input consumed), negative =
// API/allocation failure as above. Caller advances by result.consumed and calls
// again with the remaining input. Partial packets/escapes survive calls. Parser
// storage is bounded to 64 KiB; overflow is reported, not silently discarded.
HT_AUDIO_EXPORT int32_t ht_audio_receive(
    HtAudioCodec* codec, const uint8_t* bytes, int32_t length,
    uint32_t decode_mask, HtAudioRxResult* result);

#ifdef __cplusplus
}
#endif
#endif
