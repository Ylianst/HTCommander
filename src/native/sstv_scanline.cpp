// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
#include "sstv_scanline.h"
#include <algorithm>
#include <cmath>
#include <cstdint>

#if defined(__SSE2__) || defined(_M_X64)
#include <emmintrin.h>
#define HT_SSTV_SCANLINE_SSE2
#elif defined(__aarch64__) || defined(_M_ARM64)
#include <arm_neon.h>
#define HT_SSTV_SCANLINE_NEON
#endif

namespace {
// A convex EMA of inputs this small, followed by the finite offset/level
// transform, cannot approach double overflow, even allowing rounding error.
bool bounded_line(const double* input, int count, double alpha, double offset) {
  constexpr double bound = 1e100;
  if (!(alpha >= 0 && alpha <= 1 && std::abs(offset) <= bound)) return false;
  int i = 0;
#if defined(HT_SSTV_SCANLINE_SSE2)
  const __m128d sign = _mm_set1_pd(-0.0);
  const __m128d limit = _mm_set1_pd(bound);
  for (; i + 1 < count; i += 2) {
    const __m128d magnitude = _mm_andnot_pd(sign, _mm_loadu_pd(input + i));
    // Unordered (NaN) comparisons fail too.
    if (_mm_movemask_pd(_mm_cmple_pd(magnitude, limit)) != 3) return false;
  }
#elif defined(HT_SSTV_SCANLINE_NEON)
  const float64x2_t limit = vdupq_n_f64(bound);
  uint64x2_t valid = vdupq_n_u64(UINT64_MAX);
  for (; i + 3 < count; i += 4) {
    const uint64x2_t a = vcleq_f64(vabsq_f64(vld1q_f64(input + i)), limit);
    const uint64x2_t b = vcleq_f64(vabsq_f64(vld1q_f64(input + i + 2)), limit);
    valid = vandq_u64(valid, vandq_u64(a, b));
  }
  if (i + 1 < count) {
    valid = vandq_u64(valid,
        vcleq_f64(vabsq_f64(vld1q_f64(input + i)), limit));
    i += 2;
  }
  if ((vgetq_lane_u64(valid, 0) & vgetq_lane_u64(valid, 1)) != UINT64_MAX) {
    return false;
  }
#endif
  for (; i < count; ++i) {
    if (!(std::abs(input[i]) <= bound)) return false;
  }
  return true;
}

template <bool checked>
bool filter_line(const double* input, double* scratch, int count,
                 double alpha, double complement, double offset) {
  // Explicit scalar SIMD keeps the recurrence in registers under /fp:strict.
  // Separate multiply/add operations preserve Dart's rounding, without FMA.
#if defined(HT_SSTV_SCANLINE_SSE2)
  const __m128d a = _mm_set_sd(alpha), b = _mm_set_sd(complement);
  const __m128d correction = _mm_set_sd(offset);
  const __m128d one = _mm_set_sd(1.0), half = _mm_set_sd(0.5);
  __m128d previous = _mm_setzero_pd();
  for (int i = 0; i < count; ++i) {
    if (checked && !std::isfinite(input[i])) return false;
    previous = _mm_add_sd(_mm_mul_sd(previous, b),
                          _mm_mul_sd(a, _mm_load_sd(input + i)));
    if (checked && !std::isfinite(_mm_cvtsd_f64(previous))) return false;
    _mm_store_sd(scratch + i, previous);
  }
  previous = _mm_setzero_pd();
  for (int i = count - 1; i >= 0; --i) {
    previous = _mm_add_sd(_mm_mul_sd(previous, b),
                          _mm_mul_sd(a, _mm_load_sd(scratch + i)));
    const __m128d level = _mm_mul_sd(half,
        _mm_add_sd(_mm_sub_sd(previous, correction), one));
    if (checked && (!std::isfinite(_mm_cvtsd_f64(previous)) ||
                    !std::isfinite(_mm_cvtsd_f64(level)))) return false;
    _mm_store_sd(scratch + i, level);
  }
#elif defined(HT_SSTV_SCANLINE_NEON)
  const float64x1_t a = vdup_n_f64(alpha), b = vdup_n_f64(complement);
  const float64x1_t correction = vdup_n_f64(offset);
  const float64x1_t one = vdup_n_f64(1.0), half = vdup_n_f64(0.5);
  float64x1_t previous = vdup_n_f64(0);
  for (int i = 0; i < count; ++i) {
    if (checked && !std::isfinite(input[i])) return false;
    previous = vadd_f64(vmul_f64(previous, b), vmul_f64(a, vld1_f64(input + i)));
    if (checked && !std::isfinite(vget_lane_f64(previous, 0))) return false;
    vst1_f64(scratch + i, previous);
  }
  previous = vdup_n_f64(0);
  for (int i = count - 1; i >= 0; --i) {
    previous = vadd_f64(vmul_f64(previous, b), vmul_f64(a, vld1_f64(scratch + i)));
    const float64x1_t level = vmul_f64(half,
        vadd_f64(vsub_f64(previous, correction), one));
    if (checked && (!std::isfinite(vget_lane_f64(previous, 0)) ||
                    !std::isfinite(vget_lane_f64(level, 0)))) return false;
    vst1_f64(scratch + i, level);
  }
#else
  double previous = 0;
  for (int i = 0; i < count; ++i) {
    if (checked && !std::isfinite(input[i])) return false;
    scratch[i] = previous = previous * complement + alpha * input[i];
    if (checked && !std::isfinite(previous)) return false;
  }
  previous = 0;
  for (int i = count - 1; i >= 0; --i) {
    previous = previous * complement + alpha * scratch[i];
    scratch[i] = 0.5 * (previous - offset + 1.0);
    if (checked && (!std::isfinite(previous) ||
                    !std::isfinite(scratch[i]))) return false;
  }
#endif
  return true;
}

int byte(double value) {
  // Match sstvRound (ties to even), independently of the host rounding mode.
  value *= 255;
  if (value <= 0) return 0;
  if (value >= 255) return 255;
#if defined(HT_SSTV_SCANLINE_NEON)
  return static_cast<int>(vget_lane_s64(vcvtn_s64_f64(vdup_n_f64(value)), 0));
#else
  const double floor = std::floor(value);
  const double fraction = value - floor;
  const int base = static_cast<int>(floor);
  return base + (fraction > 0.5 || (fraction == 0.5 && (base & 1)));
#endif
}
int clamp(int x) { return std::min(255, std::max(0, x)); }
// Dart's signed >> rounds toward negative infinity, unlike integer division.
int shift8(int x) { return x >= 0 ? x / 256 : -((-x + 255) / 256); }
uint32_t rgb(int r, int g, int b) {
  return 0xff000000u | (r << 16) | (g << 8) | b;
}
uint32_t yuv(int y, int u, int v) {
  y -= 16; u -= 128; v -= 128;
  return rgb(clamp(shift8(298*y + 409*v + 128)),
             clamp(shift8(298*y - 100*u - 208*v + 128)),
             clamp(shift8(298*y + 516*u + 128)));
}
}

int32_t ht_sstv_scanline(const double* input, double* scratch, int32_t* pixels,
                         const int32_t* c, double alpha, double offset) {
  if (!input || !scratch || !pixels || !c) return -1;
  const int kind = c[0], width = c[1], count = c[2];
  if (kind < 0 || kind > 5 ||
      width <= 0 || count <= 0 || !std::isfinite(alpha) ||
      !std::isfinite(offset)) return -1;
  const int channels = kind == 5 ? 1 : (kind == 2 ? 4 :
                        (kind == 3 || kind == 4 ? 2 : 3));
  for (int ch = 0; ch < channels; ++ch) {
    const int64_t last = c[3+ch] + int64_t(width-1)*c[7+ch]/width;
    if (c[3+ch] < 0 || c[7+ch] < 0 || last >= count) return -1;
  }
  const double complement = 1 - alpha;
  const bool filtered = bounded_line(input, count, alpha, offset)
      ? filter_line<false>(input, scratch, count, alpha, complement, offset)
      : filter_line<true>(input, scratch, count, alpha, complement, offset);
  if (!filtered) return -2;
  for (int x = 0; x < width; ++x) {
    auto sample = [&](int ch) {
      return scratch[c[3+ch] + int64_t(x)*c[7+ch]/width];
    };
    if (kind == 5) {
      const int gray = byte(std::sqrt(std::min(1.0, std::max(0.0, sample(0)))));
      pixels[x] = static_cast<int32_t>(rgb(gray, gray, gray));
      continue;
    }
    const int a = byte(sample(0));
    if (kind == 3) {
      pixels[x] = static_cast<int32_t>(rgb(a, 0, byte(sample(1))));
    } else if (kind == 4) {
      const uint32_t even = static_cast<uint32_t>(pixels[x]);
      const int u = byte(sample(1)), v = even & 255;
      pixels[x] = static_cast<int32_t>(yuv((even >> 16) & 255, u, v));
      pixels[x+width] = static_cast<int32_t>(yuv(a, u, v));
    } else {
      const int b = byte(sample(1)), d = byte(sample(2));
      pixels[x] = static_cast<int32_t>(kind == 0 ? rgb(a,b,d) : yuv(a,b,d));
      if (kind == 2) {
        pixels[x+width] = static_cast<int32_t>(yuv(byte(sample(3)),b,d));
      }
    }
  }
  return 0;
}
