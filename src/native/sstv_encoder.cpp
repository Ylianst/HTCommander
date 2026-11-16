// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
// Mode timing and color conversion ported from lib/sstv/encoder.dart.
#include "sstv_dsp.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <initializer_list>

#if defined(__SSE2__) || defined(_M_X64)
#include <emmintrin.h>
#define HT_SSTV_VECTOR
#define HT_SSTV_ENCODER_SSE2
using V2 = __m128d;
static V2 load(const double* p) { return _mm_loadu_pd(p); }
static void store(double* p, V2 v) { _mm_storeu_pd(p, v); }
static V2 splat(double x) { return _mm_set1_pd(x); }
static V2 add(V2 a, V2 b) { return _mm_add_pd(a, b); }
static V2 sub(V2 a, V2 b) { return _mm_sub_pd(a, b); }
static V2 mul(V2 a, V2 b) { return _mm_mul_pd(a, b); }
static V2 reflect(V2 x, double limit, double center) {
  const V2 mask = limit > 0 ? _mm_cmpgt_pd(x, splat(limit))
                            : _mm_cmplt_pd(x, splat(limit));
  return _mm_or_pd(_mm_and_pd(mask, sub(splat(center), x)),
                    _mm_andnot_pd(mask, x));
}
#elif defined(__aarch64__) || defined(_M_ARM64)
#include <arm_neon.h>
#define HT_SSTV_VECTOR
#define HT_SSTV_ENCODER_NEON
using V2 = float64x2_t;
static V2 load(const double* p) { return vld1q_f64(p); }
static void store(double* p, V2 v) { vst1q_f64(p, v); }
static V2 splat(double x) { return vdupq_n_f64(x); }
static V2 add(V2 a, V2 b) { return vaddq_f64(a, b); }
static V2 sub(V2 a, V2 b) { return vsubq_f64(a, b); }
static V2 mul(V2 a, V2 b) { return vmulq_f64(a, b); }
static V2 reflect(V2 x, double limit, double center) {
  const uint64x2_t mask = limit > 0 ? vcgtq_f64(x, splat(limit))
                                   : vcltq_f64(x, splat(limit));
  return vbslq_f64(mask, sub(splat(center), x), x);
}
#endif

namespace {
constexpr double pi = 3.14159265358979323846;
constexpr double two_pi = 2 * pi;

struct Segment {
  double seconds;
  double frequency;
  int channel = -1;
};

enum class Color { rgb, yuv, paired_yuv, gray };

struct Mode {
  int code, width = 320, height = 256, step = 1, count = 0;
  Color color = Color::rgb;
  std::array<Segment, 12> segments{};

  void sequence(std::initializer_list<Segment> values) {
    count = static_cast<int>(values.size());
    std::copy(values.begin(), values.end(), segments.begin());
  }
};

bool configure(int code, Mode& m) {
  m.code = code;
  if (code == 8) {
    m.height = 240; m.step = 2; m.color = Color::paired_yuv;
    m.sequence({{.009,1200}, {.003,1500}, {.088,0,0},
                {.0045,1500}, {.0015,1500}, {.044,0,3},
                {.009,1200}, {.003,1500}, {.088,0,1},
                {.0045,2300}, {.0015,1500}, {.044,0,2}});
  } else if (code == 12) {
    m.height = 240; m.color = Color::yuv;
    m.sequence({{.009,1200}, {.003,1500}, {.138,0,0},
                {.0045,1500}, {.0015,1500}, {.069,0,2},
                {.0045,1500}, {.0015,1500}, {.069,0,1}});
  } else if (code == 44 || code == 40) {
    const double t = code == 44 ? .146432 : .073216;
    m.sequence({{.004862,1200}, {.000572,1500}, {t,0,1},
                {.000572,1500}, {t,0,2}, {.000572,1500}, {t,0,0}});
  } else if (code == 60 || code == 56 || code == 76) {
    const double t = code == 60 ? .138240 : (code == 56 ? .088064 : .3456);
    m.sequence({{.0015,1500}, {t,0,1}, {.0015,1500}, {t,0,2},
                {.009,1200}, {.0015,1500}, {t,0,0}});
  } else if (code == 55) {
    m.sequence({{.0055225,1200}, {.0005,1500},
                {.235,0,0}, {.235,0,1}, {.235,0,2}});
  } else if (code == -1) {
    m.width = 640; m.height = 1200; m.color = Color::gray;
    m.sequence({{.5,0,0}});
  } else {
    double t;
    m.step = 2; m.color = Color::paired_yuv;
    switch (code) {
      case 93: t = .09152; break;
      case 99: t = .17024; break;
      case 95: m.width = 640; m.height = 496; t = .1216; break;
      case 98: m.width = 512; m.height = 400; t = .195584; break;
      case 96: m.width = 640; m.height = 496; t = .18304; break;
      case 97: m.width = 640; m.height = 496; t = .24448; break;
      case 94: m.width = 800; m.height = 616; t = .2288; break;
      default: return false;
    }
    m.sequence({{.02,1200}, {.00208,1500}, {t,0,0},
                {t,0,3}, {t,0,2}, {t,0,1}});
  }
  return true;
}

int64_t rounded(double value) {
  const double low = std::floor(value), fraction = value - low;
  const int64_t n = static_cast<int64_t>(low);
  return n + (fraction > .5 || (fraction == .5 && (n & 1)));
}

int64_t length(const Mode& m, int rate) {
  int64_t line = 0;
  for (int i = 0; i < m.count; ++i) line += rounded(m.segments[i].seconds * rate);
  const int64_t header = m.code < 0 ? 0 :
      2 * rounded(.3 * rate) + rounded(.01 * rate) + 10 * rounded(.03 * rate);
  return header + line * (m.height / m.step);
}

#if defined(HT_SSTV_VECTOR)
V2 sine(V2 phase) {
  // Reflect [0, 2*pi] into [-pi/2, pi/2]. The degree-19 Taylor
  // remainder is below 3e-16 here; no coarse sine lookup table is used.
  V2 x = sub(phase, splat(pi));
  x = reflect(x, pi / 2, pi);
  x = reflect(x, -pi / 2, -pi);
  const V2 z = mul(x, x);
  V2 p = splat(-1.0 / 121645100408832000.0);
  p = add(splat(1.0 / 355687428096000.0), mul(z, p));
  p = add(splat(-1.0 / 1307674368000.0), mul(z, p));
  p = add(splat(1.0 / 6227020800.0), mul(z, p));
  p = add(splat(-1.0 / 39916800.0), mul(z, p));
  p = add(splat(1.0 / 362880.0), mul(z, p));
  p = add(splat(-1.0 / 5040.0), mul(z, p));
  p = add(splat(1.0 / 120.0), mul(z, p));
  p = add(splat(-1.0 / 6.0), mul(z, p));
  return sub(splat(0), add(x, mul(mul(x, z), p)));
}

void pcmPair(V2 value, uint8_t* output) {
  // A signed half-step followed by truncation matches Dart's rounding.
  uint32_t packed;
#if defined(HT_SSTV_ENCODER_SSE2)
  value = _mm_mul_pd(_mm_max_pd(splat(-1), _mm_min_pd(splat(1), value)),
                      splat(32767));
  const V2 offset = _mm_or_pd(splat(.5), _mm_and_pd(value, splat(-0.0)));
  const __m128i integers = _mm_cvttpd_epi32(_mm_add_pd(value, offset));
  packed = static_cast<uint32_t>(_mm_cvtsi128_si32(
      _mm_packs_epi32(integers, _mm_setzero_si128())));
#elif defined(HT_SSTV_ENCODER_NEON)
  value = vmulq_f64(vmaxq_f64(splat(-1), vminq_f64(splat(1), value)),
                    splat(32767));
  const uint64x2_t sign = vandq_u64(vreinterpretq_u64_f64(value),
                                   vdupq_n_u64(uint64_t{1} << 63));
  const V2 offset = vreinterpretq_f64_u64(
      vorrq_u64(vreinterpretq_u64_f64(splat(.5)), sign));
  const int64x2_t integers = vcvtq_s64_f64(vaddq_f64(value, offset));
  packed = static_cast<uint16_t>(vgetq_lane_s64(integers, 0)) |
      (static_cast<uint32_t>(static_cast<uint16_t>(
          vgetq_lane_s64(integers, 1))) << 16);
#endif
  output[0] = static_cast<uint8_t>(packed);
  output[1] = static_cast<uint8_t>(packed >> 8);
  output[2] = static_cast<uint8_t>(packed >> 16);
  output[3] = static_cast<uint8_t>(packed >> 24);
}
#endif

class Writer {
  void* output;
  const int rate;
  const bool pcm, simd;
  double pending[512];
  int used = 0;
  int64_t position = 0;

  void flush() {
    int i = 0;
#if defined(HT_SSTV_VECTOR)
    if (simd) {
      if (pcm) {
        auto* bytes = static_cast<uint8_t*>(output) + 2 * position;
        for (; i + 1 < used; i += 2) {
          pcmPair(sine(load(pending + i)), bytes + 2 * i);
        }
      } else {
        auto* samples = static_cast<double*>(output) + position;
        for (; i + 1 < used; i += 2) {
          store(samples + i, sine(load(pending + i)));
        }
      }
    }
#endif
    if (pcm) {
      auto* bytes = static_cast<uint8_t*>(output);
      for (; i < used; ++i) {
        const double value = std::clamp(std::sin(pending[i]), -1.0, 1.0) * 32767;
        const int sample = static_cast<int>(value < 0 ? value - .5 : value + .5);
        const uint16_t bits = static_cast<uint16_t>(sample);
        bytes[2 * (position + i)] = static_cast<uint8_t>(bits);
        bytes[2 * (position + i) + 1] = static_cast<uint8_t>(bits >> 8);
      }
    } else {
      auto* samples = static_cast<double*>(output);
      for (; i < used; ++i) samples[position + i] = std::sin(pending[i]);
    }
    position += used;
    used = 0;
  }

 public:
  double phase;

  Writer(void* out, int sample_rate, double initial_phase, bool pcm16, bool vector)
      : output(out), rate(sample_rate), pcm(pcm16),
        simd(vector && sample_rate >= 2300), phase(initial_phase) {}

  void tone(double frequency, int64_t count) {
    const double delta = 2 * pi * frequency / rate;
    for (int64_t i = 0; i < count; ++i) {
      pending[used++] = phase;
      phase += delta;
      if (phase > two_pi) phase -= two_pi;
      if (used == 512) flush();
    }
  }

  void pixels(const double* levels, int width, int64_t count) {
    for (int64_t i = 0; i < count;) {
      const int pixel = static_cast<int>(i * width / count);
      const int64_t end = ((pixel + 1) * count + width - 1) / width;
      const double frequency = 1500 + std::clamp(levels[pixel], 0.0, 1.0) * 800;
      tone(frequency, end - i);
      i = end;
    }
  }

  void header(int code) {
    tone(1900, rounded(.3 * rate));
    tone(1200, rounded(.01 * rate));
    tone(1900, rounded(.3 * rate));
    tone(1200, rounded(.03 * rate));
    int parity = 0;
    for (int i = 0; i < 7; ++i) parity ^= (code >> i) & 1;
    const int bits = (code & 127) | (parity << 7);
    for (int i = 0; i < 8; ++i) {
      tone((bits & (1 << i)) ? 1100 : 1300, rounded(.03 * rate));
    }
    tone(1200, rounded(.03 * rate));
  }

  int64_t finish() {
    flush();
    return position;
  }
};

void color(int32_t argb, Color mode, double* out) {
  const uint32_t bits = static_cast<uint32_t>(argb);
  const double r = ((bits >> 16) & 255) / 255.0;
  const double g = ((bits >> 8) & 255) / 255.0;
  const double b = (bits & 255) / 255.0;
  if (mode == Color::rgb) {
    out[0] = r; out[1] = g; out[2] = b;
  } else {
    out[0] = .299 * r + .587 * g + .114 * b;
    out[1] = -.169 * r - .331 * g + .500 * b + .5;
    out[2] = .500 * r - .419 * g - .081 * b + .5;
  }
}
}  // namespace

int64_t ht_sstv_encoded_length(int32_t rate, int32_t code) {
  Mode mode{};
  return rate > 0 && configure(code, mode) ? length(mode, rate) : -1;
}

int32_t ht_sstv_encode(
    const int32_t* pixels, int64_t pixel_count, int32_t width, int32_t height,
    int32_t rate, int32_t code, double* phase, void* output,
    int64_t capacity, int32_t pcm, int32_t simd) {
  Mode mode{};
  if (rate <= 0 || width <= 0 || height <= 0 ||
      static_cast<int64_t>(width) * height > pixel_count ||
      !configure(code, mode) || !std::isfinite(*phase) ||
      length(mode, rate) != capacity) return -1;
  Writer writer(output, rate, *phase, pcm != 0, simd != 0);
  if (code >= 0) writer.header(code);
  double levels[4][800];
  for (int line = 0; line < mode.height; line += mode.step) {
    const int y = static_cast<int>(static_cast<int64_t>(line) * height / mode.height);
    const int next_y = std::min(height - 1, static_cast<int>(
        static_cast<int64_t>(line + 1) * height / mode.height));
    for (int x = 0; x < mode.width; ++x) {
      const int src_x = static_cast<int>(static_cast<int64_t>(x) * width / mode.width);
      double a[3];
      color(pixels[static_cast<int64_t>(y) * width + src_x], mode.color, a);
      if (mode.color == Color::paired_yuv) {
        double b[3];
        color(pixels[static_cast<int64_t>(next_y) * width + src_x], mode.color, b);
        levels[0][x] = a[0]; levels[1][x] = b[0];
        levels[2][x] = (a[1] + b[1]) / 2;
        levels[3][x] = (a[2] + b[2]) / 2;
      } else {
        for (int c = 0; c < 3; ++c) levels[c][x] = a[c];
      }
    }
    for (int s = 0; s < mode.count; ++s) {
      const Segment& segment = mode.segments[s];
      const int64_t samples = rounded(segment.seconds * rate);
      if (segment.channel < 0) writer.tone(segment.frequency, samples);
      else writer.pixels(levels[segment.channel], mode.width, samples);
    }
  }
  if (writer.finish() != capacity) return -2;
  *phase = writer.phase;
  return 0;
}
