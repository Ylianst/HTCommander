// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
// LDPC numerical order and iteration policy match lib/hamlib/dart_ldpc.dart.
#include "dart_dsp.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <limits>

#if defined(__SSE2__) || defined(_M_X64) || (defined(_M_IX86_FP) && _M_IX86_FP >= 2)
#include <emmintrin.h>
#define HT_DART_SSE2
#elif defined(_M_ARM64) && defined(_MSC_VER) && !defined(__clang__)
#include <arm64_neon.h>
#define HT_DART_NEON
#elif defined(__aarch64__)
#include <arm_neon.h>
#define HT_DART_NEON
#endif

namespace {
void invalid(const char* function) {
  std::fprintf(stderr, "%s: invalid native arguments\n", function);
}
bool valid_graph(const uint16_t* starts, const uint16_t* columns, int k, int n) {
  if (!starts || !columns || n != 648 ||
      (k != 324 && k != 432 && k != 486 && k != 540) || starts[0] != 0)
    return false;
  const int m = n - k;
  for (int c = 0; c < m; ++c)
    if (starts[c] > starts[c + 1]) return false;
  for (int e = 0; e < starts[m]; ++e)
    if (columns[e] >= n) return false;
  return true;
}
}

int32_t ht_dart_simd_width() {
#if defined(HT_DART_SSE2) || defined(HT_DART_NEON)
  return 2;
#else
  return 1;
#endif
}

void ht_dart_multiply_conjugate(
    double* re, double* im, const double* ref_re, const double* ref_im,
    int32_t n, int32_t simd) {
  if (!re || !im || !ref_re || !ref_im || n < 0 || n > 2048)
    return invalid(__func__);
  int i = 0;
#if defined(HT_DART_SSE2)
  if (simd) {
    for (; i + 1 < n; i += 2) {
      const __m128d r = _mm_loadu_pd(re + i), q = _mm_loadu_pd(im + i);
      const __m128d a = _mm_loadu_pd(ref_re + i), b = _mm_loadu_pd(ref_im + i);
      _mm_storeu_pd(re + i, _mm_add_pd(_mm_mul_pd(r, a), _mm_mul_pd(q, b)));
      _mm_storeu_pd(im + i, _mm_sub_pd(_mm_mul_pd(q, a), _mm_mul_pd(r, b)));
    }
  }
#elif defined(HT_DART_NEON)
  if (simd) {
    for (; i + 1 < n; i += 2) {
      const float64x2_t r = vld1q_f64(re + i), q = vld1q_f64(im + i);
      const float64x2_t a = vld1q_f64(ref_re + i), b = vld1q_f64(ref_im + i);
      vst1q_f64(re + i, vaddq_f64(vmulq_f64(r, a), vmulq_f64(q, b)));
      vst1q_f64(im + i, vsubq_f64(vmulq_f64(q, a), vmulq_f64(r, b)));
    }
  }
#endif
  for (; i < n; ++i) {
    const double r = re[i], q = im[i];
    re[i] = r * ref_re[i] + q * ref_im[i];
    im[i] = q * ref_re[i] - r * ref_im[i];
  }
}

double ht_dart_peak(const double* samples, int32_t count, int32_t simd) {
  if (count < 0 || count > 4096 || (!samples && count))
    return std::numeric_limits<double>::quiet_NaN();
  int i = 0;
  double peak = 0;
#if defined(HT_DART_SSE2)
  if (simd) {
    __m128d maximum = _mm_setzero_pd();
    for (; i + 1 < count; i += 2) {
      const __m128d value = _mm_andnot_pd(_mm_set1_pd(-0.0), _mm_loadu_pd(samples + i));
      maximum = _mm_max_pd(value, maximum);
    }
    peak = std::max(_mm_cvtsd_f64(maximum),
                   _mm_cvtsd_f64(_mm_unpackhi_pd(maximum, maximum)));
  }
#elif defined(HT_DART_NEON)
  if (simd) {
    float64x2_t maximum = vdupq_n_f64(0);
    for (; i + 1 < count; i += 2) {
      const float64x2_t value = vabsq_f64(vld1q_f64(samples + i));
      maximum = vbslq_f64(vcgtq_f64(value, maximum), value, maximum);
    }
    peak = std::max(vgetq_lane_f64(maximum, 0), vgetq_lane_f64(maximum, 1));
  }
#endif
  for (; i < count; ++i) {
    const double value = std::abs(samples[i]);
    if (value > peak) peak = value;
  }
  return peak;
}

int32_t ht_dart_to_pcm(const double* samples, int32_t count, double scale,
                        int16_t* out, int32_t simd) {
  if (count < 0 || count > 4096 || (count && (!samples || !out)) ||
      !std::isfinite(scale)) return -1;
  int i = 0;
#if defined(HT_DART_SSE2)
  if (simd) {
    for (; i + 1 < count; i += 2) {
      __m128d value = _mm_mul_pd(_mm_loadu_pd(samples + i), _mm_set1_pd(scale));
      const __m128d magnitude = _mm_andnot_pd(_mm_set1_pd(-0.0), value);
      if (_mm_movemask_pd(_mm_cmple_pd(magnitude,
              _mm_set1_pd(std::numeric_limits<double>::max()))) != 3) return -1;
      value = _mm_min_pd(_mm_max_pd(value, _mm_set1_pd(-32767)), _mm_set1_pd(32767));
      __m128i rounded = _mm_cvttpd_epi32(value);
      const __m128d fraction = _mm_sub_pd(value, _mm_cvtepi32_pd(rounded));
      const __m128i positive = _mm_shuffle_epi32(
          _mm_castpd_si128(_mm_cmpge_pd(fraction, _mm_set1_pd(0.5))), _MM_SHUFFLE(2, 0, 2, 0));
      const __m128i negative = _mm_shuffle_epi32(
          _mm_castpd_si128(_mm_cmple_pd(fraction, _mm_set1_pd(-0.5))), _MM_SHUFFLE(2, 0, 2, 0));
      // Adding 0.5 before truncation would incorrectly round the double
      // immediately below 0.5 to 1. Compare exact fractional parts instead.
      rounded = _mm_sub_epi32(_mm_add_epi32(rounded, negative), positive);
      out[i] = static_cast<int16_t>(_mm_cvtsi128_si32(rounded));
      out[i + 1] = static_cast<int16_t>(_mm_cvtsi128_si32(_mm_srli_si128(rounded, 4)));
    }
  }
#elif defined(HT_DART_NEON)
  if (simd) {
    for (; i + 1 < count; i += 2) {
      float64x2_t value = vmulq_f64(vld1q_f64(samples + i), vdupq_n_f64(scale));
      const uint64x2_t finite = vcleq_f64(vabsq_f64(value),
          vdupq_n_f64(std::numeric_limits<double>::max()));
      if (vgetq_lane_u64(finite, 0) == 0 || vgetq_lane_u64(finite, 1) == 0) return -1;
      value = vminq_f64(vmaxq_f64(value, vdupq_n_f64(-32767)), vdupq_n_f64(32767));
      int64x2_t rounded = vcvtq_s64_f64(value);
      const float64x2_t fraction = vsubq_f64(value, vcvtq_f64_s64(rounded));
      const int64x2_t positive = vreinterpretq_s64_u64(vcgeq_f64(fraction, vdupq_n_f64(0.5)));
      const int64x2_t negative = vreinterpretq_s64_u64(vcleq_f64(fraction, vdupq_n_f64(-0.5)));
      rounded = vsubq_s64(vaddq_s64(rounded, negative), positive);
      out[i] = static_cast<int16_t>(vgetq_lane_s64(rounded, 0));
      out[i + 1] = static_cast<int16_t>(vgetq_lane_s64(rounded, 1));
    }
  }
#endif
  for (; i < count; ++i) {
    const double value = samples[i] * scale;
    if (!std::isfinite(value)) return -1;
    out[i] = static_cast<int16_t>(std::round(std::clamp(value, -32767.0, 32767.0)));
  }
  return 0;
}

void ht_dart_from_pcm(const int16_t* samples, int32_t count, double* out, int32_t simd) {
  if (count < 0 || count > 4096 || (count && (!samples || !out)))
    return invalid(__func__);
  int i = 0;
#if defined(HT_DART_SSE2)
  if (simd) {
    for (; i + 3 < count; i += 4) {
      const __m128i packed = _mm_loadl_epi64(reinterpret_cast<const __m128i*>(samples + i));
      const __m128i sign = _mm_cmpgt_epi16(_mm_setzero_si128(), packed);
      const __m128i wide = _mm_unpacklo_epi16(packed, sign);
      _mm_storeu_pd(out + i, _mm_div_pd(_mm_cvtepi32_pd(wide), _mm_set1_pd(32767)));
      _mm_storeu_pd(out + i + 2, _mm_div_pd(
          _mm_cvtepi32_pd(_mm_srli_si128(wide, 8)), _mm_set1_pd(32767)));
    }
  }
#elif defined(HT_DART_NEON)
  if (simd) {
    for (; i + 3 < count; i += 4) {
      const int32x4_t wide = vmovl_s16(vld1_s16(samples + i));
      const float64x2_t lo = vcvtq_f64_s64(vmovl_s32(vget_low_s32(wide)));
      const float64x2_t hi = vcvtq_f64_s64(vmovl_s32(vget_high_s32(wide)));
      vst1q_f64(out + i, vdivq_f64(lo, vdupq_n_f64(32767)));
      vst1q_f64(out + i + 2, vdivq_f64(hi, vdupq_n_f64(32767)));
    }
  }
#endif
  for (; i < count; ++i) out[i] = samples[i] / 32767.0;
}

void ht_dart_ldpc_encode(const uint16_t* starts, const uint16_t* columns,
                         int32_t k, int32_t n, const uint8_t* info,
                         uint8_t* out) {
  if (!info || !out || !valid_graph(starts, columns, k, n))
    return invalid(__func__);
  std::copy_n(info, k, out);
  int parity = 0;
  for (int c = 0; c < n - k; ++c) {
    for (int e = starts[c]; e < starts[c + 1]; ++e) {
      if (columns[e] < k) parity ^= info[columns[e]];
    }
    out[k + c] = static_cast<uint8_t>(parity);
  }
}

int32_t ht_dart_ldpc_decode(
    const uint16_t* starts, const uint16_t* columns,
    const uint16_t* var_starts, const uint16_t* var_edges,
    int32_t k, int32_t n, int32_t iterations, const double* llr,
    double* work, uint8_t* out) {
  if (!var_starts || !var_edges || !llr || !work || !out || iterations < 1 ||
      !valid_graph(starts, columns, k, n) || var_starts[0] != 0) return -1;
  const int m = n - k, edges = starts[m];
  if (var_starts[n] != edges) return -1;
  for (int v = 0; v < n; ++v)
    if (var_starts[v] > var_starts[v + 1]) return -1;
  for (int i = 0; i < edges; ++i)
    if (var_edges[i] >= edges) return -1;
  // Each phase can overwrite its input after taking the row minimum / column
  // sum: every edge belongs to exactly one check and one variable.
  double* q = work;
  uint8_t* hard = out;
  for (int e = 0; e < edges; ++e) q[e] = llr[columns[e]];
  for (int iter = 0; iter < iterations; ++iter) {
    for (int c = 0; c < m; ++c) {
      const int begin = starts[c], end = starts[c + 1];
      int sign = 0, min_index = begin;
      double minimum = std::numeric_limits<double>::infinity();
      double second = minimum;
      for (int e = begin; e < end; ++e) {
        const double value = q[e], a = std::abs(value);
        if (value < 0) sign ^= 1;
        if (a < minimum) {
          second = minimum;
          minimum = a;
          min_index = e;
        } else if (a < second) {
          second = a;
        }
      }
      for (int e = begin; e < end; ++e) {
        const int negative = sign ^ (q[e] < 0 ? 1 : 0);
        q[e] = (negative ? -1.0 : 1.0) *
            (e == min_index ? second : minimum) * 0.75;
      }
    }
    for (int v = 0; v < n; ++v) {
      double total = llr[v];
      for (int i = var_starts[v]; i < var_starts[v + 1]; ++i) {
        total += q[var_edges[i]];
      }
      hard[v] = total < 0 ? 1 : 0;
      for (int i = var_starts[v]; i < var_starts[v + 1]; ++i) {
        const int e = var_edges[i];
        q[e] = total - q[e];
      }
    }
    bool valid = true;
    for (int c = 0; c < m && valid; ++c) {
      int syndrome = 0;
      for (int e = starts[c]; e < starts[c + 1]; ++e) {
        syndrome ^= hard[columns[e]];
      }
      valid = syndrome == 0;
    }
    if (valid) break;
  }
  int corrections = 0;
  for (int v = 0; v < n; ++v) {
    if ((llr[v] < 0 ? 1 : 0) != hard[v]) ++corrections;
  }
  return corrections;
}

void ht_dart_dft(const double* input, const double* cosine,
                 const double* sine, int32_t n, double norm,
                 int32_t inverse, double* out) {
  if (!input || !cosine || !sine || !out || n < 1 || n > 128)
    return invalid(__func__);
  for (int k = 0; k < n; ++k) {
    double re = 0, im = 0;
    for (int i = 0; i < n; ++i) {
      const double c = cosine[k * n + i];
      const double s = inverse ? -sine[k * n + i] : sine[k * n + i];
      re += input[2 * i] * c - input[2 * i + 1] * s;
      im += input[2 * i] * s + input[2 * i + 1] * c;
    }
    out[2 * k] = re * norm;
    out[2 * k + 1] = im * norm;
  }
}

void ht_dart_correlate(const double* samples, const double* reference,
                       int32_t length, double energy, int32_t start,
                       int32_t count, double* out) {
  if (!samples || !reference || !out || length < 1 || length > 2048 ||
      count < 0 || count > 64 || start < 0 ||
      int64_t(start) + count + length > INT32_MAX) return invalid(__func__);
  for (int p = 0; p < count; ++p) {
    double corr = 0, rx_energy = 0;
    for (int i = 0; i < length; ++i) {
      const double s = samples[start + p + i];
      corr += s * reference[i];
      rx_energy += s * s;
    }
    const double denom = std::sqrt(rx_energy * energy);
    out[p] = denom < 1e-10 ? 0 : std::abs(corr) / denom;
  }
}

void ht_dart_corr_normalize(
    const double* samples, int32_t length, double energy,
    const double* correlation, int32_t n, int32_t count, double* out) {
  if (!samples || !correlation || !out || n < 1 || n > 2048 ||
      length < 1 || length > n || count < 0 || count > n - length + 1)
    return invalid(__func__);
  double rx_energy = 0;
  for (int i = 0; i < length; ++i) rx_energy += samples[i] * samples[i];
  for (int p = 0; p < count; ++p) {
    // Recompute near silence: cancellation in the rolling energy must not
    // turn FFT roundoff into a spurious correlation peak.
    if (rx_energy < 1e-12) {
      rx_energy = 0;
      for (int i = 0; i < length; ++i) {
        rx_energy += samples[p + i] * samples[p + i];
      }
    }
    const double denom = std::sqrt(rx_energy * energy);
    out[p] = denom < 1e-10 ? 0 : std::abs(correlation[p] / n) / denom;
    if (p + 1 < count) {
      rx_energy -= samples[p] * samples[p];
      rx_energy += samples[p + length] * samples[p + length];
    }
  }
}

void ht_dart_fsk_energy(const double* samples, int32_t count,
                        const double* cosine, const double* sine,
                        int32_t stride, double* out, int32_t simd) {
  if (!cosine || !sine || !out || stride < 1 || stride > 2048 ||
      count < 0 || count > stride || (!samples && count))
    return invalid(__func__);
  for (int t = 0; t < 4; ++t) {
    double re = 0, im = 0;
#if defined(HT_DART_SSE2)
    if (simd) {
      __m128d sum_re = _mm_setzero_pd(), sum_im = _mm_setzero_pd();
      int i = 0;
      for (; i + 1 < count; i += 2) {
        const __m128d x = _mm_loadu_pd(samples + i);
        sum_re = _mm_add_pd(sum_re, _mm_mul_pd(x, _mm_loadu_pd(cosine + t * stride + i)));
        sum_im = _mm_add_pd(sum_im, _mm_mul_pd(x, _mm_loadu_pd(sine + t * stride + i)));
      }
      re = _mm_cvtsd_f64(sum_re) + _mm_cvtsd_f64(_mm_unpackhi_pd(sum_re, sum_re));
      im = _mm_cvtsd_f64(sum_im) + _mm_cvtsd_f64(_mm_unpackhi_pd(sum_im, sum_im));
      if (i < count) {
        re += samples[i] * cosine[t * stride + i];
        im += samples[i] * sine[t * stride + i];
      }
    } else
#elif defined(HT_DART_NEON)
    if (simd) {
      float64x2_t sum_re = vdupq_n_f64(0), sum_im = vdupq_n_f64(0);
      int i = 0;
      for (; i + 1 < count; i += 2) {
        const float64x2_t x = vld1q_f64(samples + i);
        sum_re = vaddq_f64(sum_re, vmulq_f64(x, vld1q_f64(cosine + t * stride + i)));
        sum_im = vaddq_f64(sum_im, vmulq_f64(x, vld1q_f64(sine + t * stride + i)));
      }
      re = vgetq_lane_f64(sum_re, 0) + vgetq_lane_f64(sum_re, 1);
      im = vgetq_lane_f64(sum_im, 0) + vgetq_lane_f64(sum_im, 1);
      if (i < count) {
        re += samples[i] * cosine[t * stride + i];
        im += samples[i] * sine[t * stride + i];
      }
    } else
#endif
    {
      for (int i = 0; i < count; ++i) {
        re += samples[i] * cosine[t * stride + i];
        im += samples[i] * sine[t * stride + i];
      }
    }
    out[t] = re * re + im * im;
  }
}

void ht_dart_fsk_soft(
    const double* samples, int32_t count, const double* cosine,
    const double* sine, int32_t stride, double* out, int32_t symbols,
    double* quality, int32_t measure_snr, int32_t simd) {
  if (!samples || !cosine || !sine || !out || (measure_snr && !quality) ||
      stride < 1 || stride > 2048 || symbols < 1 ||
      int64_t(symbols) * stride > 4096 || count < 0 ||
      count > int64_t(symbols) * stride) return invalid(__func__);
  for (int s = 0; s < symbols; ++s) {
    const int offset = std::min(s * stride, count);
    const int length = std::min(stride, count - offset);
    double energy[4], amplitude[4], maximum = 1e-12;
    ht_dart_fsk_energy(samples + offset, length, cosine, sine, stride, energy, simd);
    for (int t = 0; t < 4; ++t) {
      amplitude[t] = std::sqrt(energy[t]);
      if (amplitude[t] > maximum) maximum = amplitude[t];
    }
    for (double& a : amplitude) a /= maximum;
    out[2 * s] = 4.0 * (std::max(amplitude[0], amplitude[1]) -
                        std::max(amplitude[2], amplitude[3]));
    out[2 * s + 1] = 4.0 * (std::max(amplitude[0], amplitude[2]) -
                            std::max(amplitude[1], amplitude[3]));
    if (measure_snr && s * stride + stride <= count) {
      std::sort(energy, energy + 4);
      if (energy[2] > 1e-12) {
        quality[0] += energy[3] / energy[2];
        quality[1] += 1;
      }
    }
  }
}

double ht_dart_fsk_modulate(
    const uint8_t* bits, int32_t count, int32_t sps, const double* steps,
    const double* cosine, const double* sine, double phase, double* out) {
  constexpr double tau = 6.28318530717958647692;
  if (!bits || !steps || !cosine || !sine || !out ||
      count < 0 || sps < 1 || int64_t(sps) * 4 > INT32_MAX ||
      ((int64_t(count) + 1) / 2) * sps > INT32_MAX ||
      !std::isfinite(phase)) return std::numeric_limits<double>::quiet_NaN();
  for (int i = 0; i < count; ++i)
    if (bits[i] > 1) return std::numeric_limits<double>::quiet_NaN();
  for (int i = 0; i < count; i += 2) {
    const int symbol = (bits[i] << 1) | (i + 1 < count ? bits[i + 1] : 0);
    const double re = std::cos(phase), im = std::sin(phase);
    const double* c = cosine + symbol * sps;
    const double* s = sine + symbol * sps;
    double* dest = out + (i / 2) * sps;
    for (int j = 0; j < sps; ++j) dest[j] = re * c[j] - im * s[j];
    phase = std::fmod(phase + steps[symbol] * sps, tau);
  }
  return phase;
}
