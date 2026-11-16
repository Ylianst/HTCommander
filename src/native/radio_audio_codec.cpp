// Copyright 2026 Ylian Saint-Hilaire - Apache-2.0
// Shared, fixed-point port of src/lib/sbc. No platform codec dependencies.
#include "radio_audio_codec.h"
#include "radio_audio_codec_tables.h"

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <new>
#include <vector>

#if !defined(HT_AUDIO_DISABLE_SIMD)
#if defined(__SSE2__) || defined(_M_X64) || (defined(_M_IX86_FP) && _M_IX86_FP >= 2)
#include <emmintrin.h>
#define HT_AUDIO_SSE2
#elif defined(_M_ARM64) && defined(_MSC_VER) && !defined(__clang__)
#include <arm64_neon.h>
#define HT_AUDIO_NEON
#elif defined(__ARM_NEON) || defined(__ARM_NEON__) || defined(__aarch64__)
#include <arm_neon.h>
#define HT_AUDIO_NEON
#endif
#endif

namespace {
using namespace ht_sbc;
constexpr size_t kPacketLimit = 65536;

// Unsigned shifts preserve Dart's rounding for negative values without division.
int64_t asr(int64_t v, int n) {
  return v >= 0 ? static_cast<int64_t>(static_cast<uint64_t>(v) >> n) :
                 -1 - static_cast<int64_t>(~static_cast<uint64_t>(v) >> n);
}
int16_t sat(int64_t v) {
  return static_cast<int16_t>(std::max<int64_t>(-32768, std::min<int64_t>(32767, v)));
}
int16_t wrap(int64_t v) {
  const uint32_t u = static_cast<uint32_t>(static_cast<uint64_t>(v) & 65535u);
  return static_cast<int16_t>(u < 32768 ? static_cast<int32_t>(u) :
                             static_cast<int32_t>(u) - 65536);
}
int64_t rounded(int64_t v, int n) {
  return asr(v + (int64_t{1} << (n - 1)), n);
}
struct Frame {
  int frequency = 1, mode = 0, allocation = 0, blocks = 16, subbands = 8, bitpool = 18;
  int channels() const { return mode == 0 ? 1 : 2; }
  int size() const {
    return 4 + (4 * subbands * channels() + blocks * bitpool * (mode == 1 ? 2 : 1)
                + (mode == 3 ? subbands : 0) + 7) / 8;
  }
  bool valid() const {
    const int maxBits = 16 * subbands * blocks * channels() - 32 -
                        4 * subbands * channels() - (mode == 3 ? subbands : 0);
    return bitpool <= std::min(maxBits / (blocks * (mode == 1 ? 2 : 1)),
                              (mode >= 2 ? 32 : 16) * subbands);
  }
};
struct Reader {
  const uint8_t* p;
  size_t position = 4;
  uint32_t buffer = 0;
  int count = 0;
  uint32_t get(int n) {
    while (count < n) {
      buffer = (buffer << 8) | p[position++];
      count += 8;
    }
    count -= n;
    return (buffer >> count) & ((uint32_t{1} << n) - 1);
  }
};
struct Writer {
  uint8_t* p;
  size_t position = 4;
  uint32_t buffer = 0;
  int count = 0;
  void put(int64_t value, int n) {
    buffer = (buffer << n) |
             (static_cast<uint32_t>(value) & ((uint32_t{1} << n) - 1));
    count += n;
    while (count >= 8) {
      count -= 8;
      p[position++] = static_cast<uint8_t>(buffer >> count);
    }
  }
  void finish() {
    if (count != 0) p[position] = static_cast<uint8_t>(buffer << (8 - count));
  }
};
uint8_t crc(const Frame& f, const uint8_t* p) {
  const int n = f.channels() * f.subbands * 4 + (f.mode == 3 ? f.subbands : 0);
  uint8_t c = crc8Table[crc8Table[0x0f ^ p[1]] ^ p[2]];
  for (int i = 4; i < 4 + n / 8; ++i) c = crc8Table[c ^ p[i]];
  if (n % 8) c = static_cast<uint8_t>((c << 4) ^ crc8Table[(c >> 4) ^ (p[4 + n / 8] >> 4)]);
  return c;
}
int header(const uint8_t* p, size_t size, Frame& f) {
  if (size != 0 && p[0] != 0x9c && p[0] != 0xad) return HT_AUDIO_ERROR_SYNC;
  if (size < 4) return HT_AUDIO_ERROR_TRUNCATED;
  if (p[0] == 0xad) {
    f = Frame{};
    f.frequency = 0; f.blocks = 15; f.bitpool = 26;
  } else if (p[0] == 0x9c) {
    f.frequency = p[1] >> 6;
    f.blocks = (1 + ((p[1] >> 4) & 3)) * 4;
    f.mode = (p[1] >> 2) & 3;
    f.allocation = (p[1] >> 1) & 1;
    f.subbands = (1 + (p[1] & 1)) * 4;
    f.bitpool = p[2];
  } else return HT_AUDIO_ERROR_SYNC;
  if (!f.valid()) return HT_AUDIO_ERROR_HEADER;
  if (size < static_cast<size_t>(f.size())) return HT_AUDIO_ERROR_TRUNCATED;
  if (crc(f, p) != p[3]) return HT_AUDIO_ERROR_CRC;
  return HT_AUDIO_ERROR_NONE;
}

void allocate(const Frame& f, const int (*scf)[8], int (*bits)[8]) {
  const int* offsets = f.subbands == 4 ? loudnessOffset4[f.frequency] :
                                       loudnessOffset8[f.frequency];
  const int channels = f.mode >= 2 ? 2 : 1;
  int needs[2][8]{};
  int maxNeed = 0;
  for (int ch = 0; ch < channels; ++ch) {
    for (int sb = 0; sb < f.subbands; ++sb) {
      int n = scf[ch][sb];
      if (f.allocation == 0) {
        n = n != 0 ? n - offsets[sb] : -5;
        if (n > 0) n /= 2;
      }
      needs[ch][sb] = n;
      maxNeed = std::max(maxNeed, n);
    }
  }
  int count = 0, slice = maxNeed + 1;
  for (int bc = 0; bc < f.bitpool;) {
    const int bs = slice--;
    count = bc;
    for (int ch = 0; ch < channels; ++ch)
      for (int sb = 0; sb < f.subbands; ++sb) {
        const int n = needs[ch][sb];
        bc += (n >= bs && n < bs + 15 ? 1 : 0) + (n == bs ? 1 : 0);
      }
  }
  for (int ch = 0; ch < channels; ++ch)
    for (int sb = 0; sb < f.subbands; ++sb) {
      const int n = needs[ch][sb] - slice;
      bits[ch][sb] = n < 2 ? 0 : std::min(n, 16);
    }
  for (int sb = 0; sb < f.subbands && count < f.bitpool; ++sb)
    for (int ch = 0; ch < channels && count < f.bitpool; ++ch) {
      const int b = bits[ch][sb];
      const int n = b > 0 && b < 16 ? 1 :
                    (needs[ch][sb] == slice + 1 && f.bitpool > count + 1 ? 2 : 0);
      bits[ch][sb] += n;
      count += n;
    }
  for (int sb = 0; sb < f.subbands && count < f.bitpool; ++sb)
    for (int ch = 0; ch < channels && count < f.bitpool; ++ch)
      if (bits[ch][sb] < 16) { ++bits[ch][sb]; ++count; }
}
struct EncoderState {
  int index = 0;
  int16_t x[2][8][5]{};
  int64_t y[4]{};
};
struct DecoderState {
  int index = 0;
  int16_t v[2][8][10]{};
};

constexpr int64_t cosineBound() {
  int64_t bound = 0;
  for (int i = 0; i < 8; ++i) {
    int64_t magnitude = 0;
    for (int j = 0; j < 8; ++j) {
      const int value = enc_cosMatrix8[i][j];
      magnitude += value < 0 ? -value : value;
    }
    bound = magnitude > bound ? magnitude : bound;
  }
  return bound * 32768 + 4096;
}
static_assert(cosineBound() <= INT32_MAX,
              "Saturated cosine inputs and rounding must fit int32 accumulators");

void analyze8(EncoderState& s, const uint8_t* pcm, int16_t* output) {
  constexpr int order[8] = {7, 3, 6, 0, 5, 1, 4, 2};
  const int idx = s.index / 2, odd = s.index & 1;
  const int inIdx = idx != 0 ? 5 - idx : 0;
  int64_t temp[8]{}, y[8]{};
  for (int i = 0; i < 8; ++i) {
    const int pos = order[i] * 2;
    s.x[odd][i][inIdx] = wrap(pcm[pos] | (uint32_t{pcm[pos + 1]} << 8));
    for (int j = 0; j < 5; ++j)
      temp[i] += int64_t{s.x[odd][i][j]} * enc_window8[i][idx + j];
  }
  y[0] = temp[0] + s.y[0]; y[1] = temp[2] + temp[3];
  y[2] = temp[4] + temp[5]; y[3] = temp[6] + temp[7];
  y[4] = s.y[1]; y[5] = s.y[2]; y[6] = s.y[3]; y[7] = temp[1];
  std::fill(std::begin(s.y), std::end(s.y), int64_t{0});
  for (int j = 0; j < 5; ++j) {
    s.y[0] += int64_t{s.x[odd][0][j]} * enc_window8b[0][idx + j];
    for (int i = 1; i < 4; ++i)
      s.y[i] += int64_t{s.x[odd][2 * i][j]} * enc_window8b[2 * i][idx + j] -
                int64_t{s.x[odd][2 * i + 1][j]} * enc_window8b[2 * i + 1][idx + j];
  }
  alignas(16) int16_t y16[8];
  for (int i = 0; i < 8; ++i) y16[i] = sat(rounded(y[i], 15));
#if defined(HT_AUDIO_SSE2)
  const __m128i in = _mm_load_si128(reinterpret_cast<const __m128i*>(y16));
#elif defined(HT_AUDIO_NEON)
  const int16x8_t in = vld1q_s16(y16);
#endif
  for (int i = 0; i < 8; ++i) {
#if defined(HT_AUDIO_SSE2)
    const __m128i coefficients = _mm_loadu_si128(
        reinterpret_cast<const __m128i*>(enc_cosMatrix8[i]));
    __m128i products = _mm_madd_epi16(in, coefficients);
    products = _mm_add_epi32(products, _mm_srli_si128(products, 8));
    products = _mm_add_epi32(products, _mm_srli_si128(products, 4));
    const int32_t sum = _mm_cvtsi128_si32(products);
#elif defined(HT_AUDIO_NEON)
    const int16x8_t coefficients = vld1q_s16(enc_cosMatrix8[i]);
    int32x4_t products = vmull_s16(vget_low_s16(in), vget_low_s16(coefficients));
    products = vmlal_s16(products, vget_high_s16(in), vget_high_s16(coefficients));
    const int32x2_t pairs = vpadd_s32(vget_low_s32(products), vget_high_s32(products));
    const int32_t sum = vget_lane_s32(vpadd_s32(pairs, pairs), 0);
#else
    int32_t sum = 0;
    for (int j = 0; j < 8; ++j) sum += int32_t{y16[j]} * enc_cosMatrix8[i][j];
#endif
    output[i] = sat(rounded(sum, 13));
  }
  s.index = s.index < 9 ? s.index + 1 : 0;
}
void encodeFrame(EncoderState& state, const uint8_t* pcm, int allocation,
                 uint8_t (&out)[44]) {
  Frame f;
  f.allocation = allocation;
  int16_t samples[128]{};
  for (int block = 0; block < 16; ++block)
    analyze8(state, pcm + block * 16, samples + block * 8);
  int scf[2][8]{}, bits[2][8]{};
  for (int sb = 0; sb < 8; ++sb) {
    int maximum = 0;
    for (int block = 0; block < 16; ++block) {
      const int v = samples[block * 8 + sb];
      maximum |= v < 0 ? -v : v;
    }
    int factor = 0;
    for (int v = maximum; v > 1; v >>= 1) ++factor;
    scf[0][sb] = factor;
  }
  allocate(f, scf, bits);
  std::memset(out, 0, sizeof(out));
  out[0] = 0x9c; out[1] = static_cast<uint8_t>(0x71 | (allocation << 1)); out[2] = 18;
  Writer writer{out};
  for (int sb = 0; sb < 8; ++sb) writer.put(scf[0][sb], 4);
  for (int block = 0; block < 16; ++block)
    for (int sb = 0; sb < 8; ++sb) {
      const int n = bits[0][sb];
      if (!n) continue;
      const int range = (1 << n) - 1;
      const int64_t q = asr(asr(int64_t{samples[block * 8 + sb]} * range,
                                scf[0][sb] + 1) + range, 1);
      writer.put(q, n);
    }
  writer.finish();
  out[3] = crc(f, out);
}

void synthesize(DecoderState& state, int subbands, const int16_t* input,
                int scale, int16_t* output) {
  const int idx = state.index ? 10 - state.index : 0, odd = idx & 1;
  auto& o = state.v[odd];
  auto& p = state.v[1 - odd];
  const int shr = 12 + scale;
  int64_t a[4]{}, b[4]{};
  if (subbands == 4) {
    const int64_t s03 = asr(int64_t{input[0]} + input[3], 1);
    const int64_t d03 = asr(int64_t{input[0]} - input[3], 1);
    const int64_t s12 = asr(int64_t{input[1]} + input[2], 1);
    const int64_t d12 = asr(int64_t{input[1]} - input[2], 1);
    a[0] = (s03 - s12) * cos8[2];
    b[1] = -(s03 + s12) * 8192;
    a[1] = d03 * cos8[3] - d12 * cos8[1];
    b[0] = -d03 * cos8[1] - d12 * cos8[3];
  } else {
    const int64_t s07 = asr(int64_t{input[0]} + input[7], 1);
    const int64_t d07 = asr(int64_t{input[0]} - input[7], 1);
    const int64_t s16 = asr(int64_t{input[1]} + input[6], 1);
    const int64_t d16 = asr(int64_t{input[1]} - input[6], 1);
    const int64_t s25 = asr(int64_t{input[2]} + input[5], 1);
    const int64_t d25 = asr(int64_t{input[2]} - input[5], 1);
    const int64_t s34 = asr(int64_t{input[3]} + input[4], 1);
    const int64_t d34 = asr(int64_t{input[3]} - input[4], 1);
    a[0] = ((s07 + s34) - (s25 + s16)) * cos16[4];
    b[3] = (-(s07 + s34) - (s25 + s16)) * 8192;
    a[2] = (s07 - s34) * cos16[6] + (s25 - s16) * cos16[2];
    b[1] = (s34 - s07) * cos16[2] + (s25 - s16) * cos16[6];
    a[1] = d07 * cos16[5] - d16 * cos16[1] + d25 * cos16[7] + d34 * cos16[3];
    b[2] = -d07 * cos16[1] - d16 * cos16[3] - d25 * cos16[5] - d34 * cos16[7];
    a[3] = d07 * cos16[7] - d16 * cos16[5] + d25 * cos16[3] - d34 * cos16[1];
    b[0] = -d07 * cos16[3] + d16 * cos16[7] + d25 * cos16[1] + d34 * cos16[5];
  }
  for (int i = 0; i < subbands / 2; ++i) {
    a[i] = rounded(a[i], shr);
    b[i] = rounded(b[i], shr);
  }
  o[0][idx] = sat(a[0]); p[0][idx] = sat(-a[0]);
  for (int i = 1; i < subbands / 2; ++i) {
    o[i][idx] = sat(a[i]); o[subbands - i][idx] = sat(-a[i]);
  }
  o[subbands / 2][idx] = 0;
  for (int i = 1; i <= subbands / 2; ++i) {
    p[i][idx] = sat(b[i - 1]);
    p[subbands - i][idx] = sat(b[i - 1]);
  }
  for (int i = 0; i < subbands; ++i) {
    int64_t sum = 0;
    for (int j = 0; j < 10; ++j) {
      const int w = subbands == 4 ? dec_window4[i][state.index + j] :
                                    dec_window8[i][state.index + j];
      sum += int64_t{o[i][j]} * w;
    }
    if (output) output[i] = sat(rounded(sum, 13));
  }
  state.index = state.index < 9 ? state.index + 1 : 0;
}
void decodeFrame(DecoderState (&state)[2], const Frame& f, const uint8_t* data,
                 int16_t* output) {
  Reader reader{data};
  int joint = 0;
  if (f.mode == 3) {
    const uint32_t mask = reader.get(f.subbands);
    for (int i = 0; i < f.subbands - 1; ++i)
      joint |= static_cast<int>((mask >> (f.subbands - 1 - i)) & 1) << i;
  }
  int scf[2][8]{}, bits[2][8]{}, scale[2]{};
  int16_t samples[2][128]{};
  for (int ch = 0; ch < f.channels(); ++ch)
    for (int sb = 0; sb < f.subbands; ++sb)
      scf[ch][sb] = static_cast<int>(reader.get(4));
  allocate(f, scf, bits);
  if (f.mode == 1) allocate(f, scf + 1, bits + 1);
  for (int ch = 0; ch < f.channels(); ++ch) {
    int maximum = 0;
    for (int sb = 0; sb < f.subbands; ++sb)
      maximum = std::max(maximum, scf[ch][sb] + ((joint >> sb) & 1));
    scale[ch] = 14 - maximum;
  }
  if (f.mode == 3) scale[0] = scale[1] = std::min(scale[0], scale[1]);
  for (int block = 0; block < f.blocks; ++block)
    for (int ch = 0; ch < f.channels(); ++ch)
      for (int sb = 0; sb < f.subbands; ++sb) {
        const int n = bits[ch][sb];
        if (n == 0) continue;
        const int64_t value = (int64_t{reader.get(n)} * 2 + 1) * rangeScale[n - 1];
        samples[ch][block * f.subbands + sb] =
            wrap(asr(value - (int64_t{1} << 28), 28 - (scf[ch][sb] + 1 + scale[ch])));
      }
  for (int sb = 0; sb < f.subbands; ++sb) {
    if (((joint >> sb) & 1) == 0) continue;
    for (int block = 0; block < f.blocks; ++block) {
      const int idx = block * f.subbands + sb;
      const int a = samples[0][idx], b = samples[1][idx];
      samples[0][idx] = wrap(a + b); samples[1][idx] = wrap(a - b);
    }
  }
  for (int ch = 0; ch < f.channels(); ++ch)
    for (int block = 0; block < f.blocks; ++block)
      synthesize(state[ch], f.subbands, samples[ch] + block * f.subbands, scale[ch],
                  ch == 0 ? output + block * f.subbands : nullptr);
}
} // namespace

struct HtAudioCodec {
  EncoderState encoder{};
  DecoderState decoder[2]{};
  std::array<uint8_t, kPacketLimit> packet{};
  size_t packetSize = 0;
  bool started = false, escaped = false, discarding = false;
  std::vector<uint8_t> tx;
  std::vector<int32_t> lengths, samples;
  std::vector<int16_t> pcm;
  std::vector<uint32_t> formats;
};

namespace {
void initRx(HtAudioRxResult& r) {
  r = HtAudioRxResult{};
  r.command = -1;
}
void processPacket(HtAudioCodec& c, uint32_t mask, HtAudioRxResult& r) {
  r.command = c.packet[0];
  r.payload_bytes = static_cast<int32_t>(c.packetSize - 1);
  if ((r.command != 0 && r.command != 3 && r.command != 9) ||
      (mask & (uint32_t{1} << r.command)) == 0) return;
  size_t pos = 1;
  static constexpr int frequencies[4] = {16000, 32000, 44100, 48000};
  while (pos < c.packetSize) {
    Frame f;
    r.error = header(c.packet.data() + pos, c.packetSize - pos, f);
    if (r.error) {
      r.rejected_bytes = static_cast<int32_t>(c.packetSize - pos);
      break;
    }
    const int count = f.blocks * f.subbands;
    const size_t start = c.pcm.size();
    const size_t end = start + static_cast<size_t>(count);
    if (end > c.pcm.capacity()) {
      // Zero-bitpool SBC produces at most sixteen samples per packet byte.
      const size_t capacity = std::min(kPacketLimit * 16, c.pcm.capacity() * 2);
      c.pcm.reserve(std::max(end, capacity));
    }
    c.pcm.resize(end);
    decodeFrame(c.decoder, f, c.packet.data() + pos, c.pcm.data() + start);
    ++r.decoded_frames;
    r.audio_us += int64_t{count} * 1000000 / frequencies[f.frequency];
    const uint32_t code = static_cast<uint32_t>((f.frequency << 16) | (f.mode << 8) | f.bitpool);
    if (std::find(c.formats.begin(), c.formats.end(), code) == c.formats.end())
      c.formats.push_back(code);
    pos += static_cast<size_t>(f.size());
  }
  r.pcm_samples = static_cast<int32_t>(c.pcm.size());
  r.pcm = c.pcm.data();
  r.format_count = static_cast<int32_t>(c.formats.size());
  r.formats = c.formats.data();
}
} // namespace

extern "C" {
uint32_t ht_audio_abi_version(void) { return 1; }
HtAudioCodec* ht_audio_create(void) {
  try {
    auto* c = new HtAudioCodec;
    try {
      c->pcm.reserve(6 * 128);
      c->formats.reserve(4);
    } catch (...) { delete c; throw; }
    return c;
  } catch (...) { return nullptr; }
}
void ht_audio_destroy(HtAudioCodec* c) { delete c; }
void ht_audio_reset(HtAudioCodec* c, uint32_t flags) {
  if (!c) return;
  if (flags & HT_AUDIO_RESET_ENCODER) c->encoder = EncoderState{};
  if (flags & HT_AUDIO_RESET_DECODER) {
    c->decoder[0] = DecoderState{}; c->decoder[1] = DecoderState{};
  }
  if (flags & HT_AUDIO_RESET_PARSER) {
    c->packetSize = 0; c->started = c->escaped = c->discarding = false;
  }
  c->tx.clear(); c->lengths.clear(); c->samples.clear();
  c->pcm.clear(); c->formats.clear();
}
int32_t ht_audio_encode(HtAudioCodec* c, const uint8_t* pcm, int32_t length,
                        int32_t allocation, HtAudioTxResult* result) {
  if (result) *result = HtAudioTxResult{};
  if (!c || !result || length < 0 || (!pcm && length != 0) ||
      (allocation != 0 && allocation != 1)) return -1;
  try {
    const size_t frames = static_cast<size_t>(length) / 256;
    const size_t packets = (frames + 5) / 6, batches = (packets + 3) / 4;
    c->tx.clear(); c->lengths.clear(); c->samples.clear();
    c->tx.reserve(frames * 88 + packets * 3);
    c->lengths.reserve(batches); c->samples.reserve(batches);
    size_t frame = 0;
    while (frame < frames) {
      const size_t batchStart = c->tx.size(), firstFrame = frame;
      for (int packet = 0; packet < 4 && frame < frames; ++packet) {
        c->tx.push_back(0x7e); c->tx.push_back(0);
        for (int i = 0; i < 6 && frame < frames; ++i, ++frame) {
          uint8_t encoded[44];
          encodeFrame(c->encoder, pcm + frame * 256, allocation, encoded);
          for (const uint8_t b : encoded) {
            if (b == 0x7d || b == 0x7e) {
              c->tx.push_back(0x7d); c->tx.push_back(b ^ 0x20);
            } else c->tx.push_back(b);
          }
        }
        c->tx.push_back(0x7e);
      }
      c->lengths.push_back(static_cast<int32_t>(c->tx.size() - batchStart));
      c->samples.push_back(static_cast<int32_t>((frame - firstFrame) * 128));
    }
    result->pcm_consumed = static_cast<int32_t>(frames * 256);
    result->data_length = static_cast<int32_t>(c->tx.size());
    result->batch_count = static_cast<int32_t>(c->lengths.size());
    result->data = c->tx.data(); result->lengths = c->lengths.data();
    result->samples = c->samples.data();
    return 0;
  } catch (const std::bad_alloc&) { return -2; }
    catch (...) { return -3; }
}
int32_t ht_audio_receive(HtAudioCodec* c, const uint8_t* bytes, int32_t length,
                         uint32_t decode_mask, HtAudioRxResult* result) {
  if (result) initRx(*result);
  if (!c || !result || length < 0 || (!bytes && length != 0)) return -1;
  try {
    c->pcm.clear(); c->formats.clear();
    for (int32_t i = 0; i < length; ++i) {
      const uint8_t b = bytes[i];
      result->consumed = i + 1;
      if (b == 0x7e) {
        const bool badEscape = c->escaped;
        c->escaped = false;
        if (c->discarding) {
          c->discarding = false; c->started = true; c->packetSize = 0;
          continue;
        }
        if (c->started && (c->packetSize != 0 || badEscape)) {
          if (badEscape) {
            result->error = HT_AUDIO_ERROR_ESCAPE;
            if (c->packetSize) {
              result->payload_bytes = static_cast<int32_t>(c->packetSize - 1);
              result->rejected_bytes = result->payload_bytes;
            }
          } else processPacket(*c, decode_mask, *result);
          c->packetSize = 0;
          // A closing flag can also start the next packet.
          c->started = true;
          return 1;
        }
        c->started = true;
        continue;
      }
      if (!c->started || c->discarding) continue;
      if (!c->escaped && b == 0x7d) { c->escaped = true; continue; }
      const uint8_t value = c->escaped ? b ^ 0x20 : b;
      c->escaped = false;
      if (c->packetSize == kPacketLimit) {
        result->payload_bytes = static_cast<int32_t>(c->packetSize - 1);
        result->rejected_bytes = result->payload_bytes + 1;
        result->error = HT_AUDIO_ERROR_OVERFLOW;
        c->packetSize = 0; c->discarding = true;
        return 1;
      }
      c->packet[c->packetSize++] = value;
    }
    return 0;
  } catch (const std::bad_alloc&) { return -2; }
    catch (...) { return -3; }
}
} // extern "C"
