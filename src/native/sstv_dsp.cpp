// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
// Streaming DSP ported from lib/sstv/{demodulator,phasor,
// complex_convolution,frequency_modulation,simple_moving_sum}.dart.
#include "sstv_dsp.h"

#include <cmath>
#include <cstdio>
#include <new>
#include <stdexcept>
#include <vector>

#if defined(__SSE2__) || defined(_M_X64)
#include <emmintrin.h>
#define HT_SSTV_SSE2
#elif defined(__aarch64__) || defined(_M_ARM64)
#include <arm_neon.h>
#define HT_SSTV_NEON
#endif

namespace {
constexpr double pi = 3.14159265358979323846;
void invalid(const char* function, HtSstvSync* result) {
  std::fprintf(stderr, "%s: invalid native arguments\n", function);
  if (result) {
    *result = {};
    result->detected = -1;
  }
}
}

struct HtSstvDemodulator {
  std::vector<double> taps, history, tree, delay;
  int position = 0, leaf, delay_position = 0, pulse_count = 0;
  const int tap_count, sync_count, min5, max5, max9, max20;
  const bool simd;
  const double delta_real, delta_imag, scale;
  double oscillator_real = 1, oscillator_imag = 0, previous_phase = 0;
  bool trigger = false;
  HtSstvSync sync{};

  HtSstvDemodulator(int rate, const double* coefficients, int count,
                    int sync_samples, int minimum5, int maximum5,
                    int maximum9, int maximum20, bool use_simd)
      : taps(coefficients, coefficients + count),
        history(4 * count), tree(2 * sync_samples), delay(sync_samples),
        leaf(sync_samples), tap_count(count), sync_count(sync_samples),
        min5(minimum5), max5(maximum5), max9(maximum9), max20(maximum20),
        simd(use_simd), delta_real(std::cos(-2 * pi * 1900 / rate)),
        delta_imag(std::sin(-2 * pi * 1900 / rate)),
        scale(rate / (800 * pi)) {
#if defined(HT_SSTV_SSE2)
    if (simd) {
      // Prepare both complex lanes once instead of broadcasting every sample.
      taps.resize(2 * count);
      for (int i = count - 1; i >= 0; --i) {
        taps[2 * i] = taps[2 * i + 1] = taps[i];
      }
    }
#endif
  }

  void filter(double real, double imag, double& out_real, double& out_imag) {
    const int count = tap_count;
    history[2 * position] = history[2 * (position + count)] = real;
    history[2 * position + 1] = history[2 * (position + count) + 1] = imag;
    if (++position == count) position = 0;
    // Mirroring the ring makes the oldest-to-newest dot product contiguous.
    const double* input = history.data() + 2 * position;
#if defined(HT_SSTV_SSE2)
    if (simd) {
      __m128d a = _mm_setzero_pd(), b = a, c = a, d = a;
      int i = 0;
      // Independent accumulators avoid a serial add dependency for every tap.
      for (; i + 3 < count; i += 4) {
        a = _mm_add_pd(a, _mm_mul_pd(_mm_loadu_pd(taps.data() + 2 * i),
                                    _mm_loadu_pd(input + 2 * i)));
        b = _mm_add_pd(b, _mm_mul_pd(_mm_loadu_pd(taps.data() + 2 * i + 2),
                                    _mm_loadu_pd(input + 2 * i + 2)));
        c = _mm_add_pd(c, _mm_mul_pd(_mm_loadu_pd(taps.data() + 2 * i + 4),
                                    _mm_loadu_pd(input + 2 * i + 4)));
        d = _mm_add_pd(d, _mm_mul_pd(_mm_loadu_pd(taps.data() + 2 * i + 6),
                                    _mm_loadu_pd(input + 2 * i + 6)));
      }
      __m128d sum = _mm_add_pd(_mm_add_pd(a, b), _mm_add_pd(c, d));
      for (; i < count; ++i) {
        sum = _mm_add_pd(sum, _mm_mul_pd(_mm_loadu_pd(taps.data() + 2 * i),
                                        _mm_loadu_pd(input + 2 * i)));
      }
      double values[2];
      _mm_storeu_pd(values, sum);
      out_real = values[0];
      out_imag = values[1];
      return;
    }
#elif defined(HT_SSTV_NEON)
    if (simd) {
      float64x2_t a = vdupq_n_f64(0), b = a, c = a, d = a;
      int i = 0;
      for (; i + 3 < count; i += 4) {
        a = vaddq_f64(a, vmulq_f64(vdupq_n_f64(taps[i]),
                                  vld1q_f64(input + 2 * i)));
        b = vaddq_f64(b, vmulq_f64(vdupq_n_f64(taps[i + 1]),
                                  vld1q_f64(input + 2 * i + 2)));
        c = vaddq_f64(c, vmulq_f64(vdupq_n_f64(taps[i + 2]),
                                  vld1q_f64(input + 2 * i + 4)));
        d = vaddq_f64(d, vmulq_f64(vdupq_n_f64(taps[i + 3]),
                                  vld1q_f64(input + 2 * i + 6)));
      }
      float64x2_t sum = vaddq_f64(vaddq_f64(a, b), vaddq_f64(c, d));
      for (; i < count; ++i) {
        sum = vaddq_f64(sum, vmulq_f64(vdupq_n_f64(taps[i]),
                                       vld1q_f64(input + 2 * i)));
      }
      out_real = vgetq_lane_f64(sum, 0);
      out_imag = vgetq_lane_f64(sum, 1);
      return;
    }
#endif
    out_real = out_imag = 0;
    for (int i = 0; i < count; ++i) {
      out_real += taps[i] * input[2 * i];
      out_imag += taps[i] * input[2 * i + 1];
    }
  }

  double average(double value) {
    tree[leaf] = value;
    for (int child = leaf, parent = leaf / 2; parent > 0;
         child = parent, parent /= 2) {
      tree[parent] = tree[child] + tree[child ^ 1];
    }
    if (++leaf == 2 * sync_count) leaf = sync_count;
    return tree[1] / sync_count;
  }
};

int32_t ht_sstv_simd_width() {
#if defined(HT_SSTV_SSE2) || defined(HT_SSTV_NEON)
  return 2;
#else
  return 1;
#endif
}

HtSstvDemodulator* ht_sstv_create(
    int32_t rate, const double* taps, int32_t count, int32_t sync_count,
    int32_t min5, int32_t max5, int32_t max9, int32_t max20, int32_t simd) {
  if (rate < 1 || !taps || count < 1 || count > INT32_MAX / 4 ||
      sync_count < 1 || sync_count > INT32_MAX / 2 ||
      min5 < 0 || max5 < min5 || max9 < max5 || max20 < max9 ||
      max20 == INT32_MAX) return nullptr;
  for (int i = 0; i < count; ++i)
    if (!std::isfinite(taps[i])) return nullptr;
  try {
    return new HtSstvDemodulator(rate, taps, count, sync_count,
                                 min5, max5, max9, max20, simd != 0);
  } catch (const std::bad_alloc&) {
    return nullptr;
  } catch (const std::length_error&) {
    return nullptr;
  }
}

void ht_sstv_destroy(HtSstvDemodulator* state) { delete state; }

template <typename Input>
static void process_samples(HtSstvDemodulator* s, double* samples, int32_t length,
                             int32_t channel, HtSstvSync* result, Input input) {
  s->sync.detected = 0;
  const int count = length / (channel > 0 ? 2 : 1);
  for (int i = 0; i < count; ++i) {
    double real, imag = 0;
    switch (channel) {
      case 1: real = input(2 * i); break;
      case 2: real = input(2 * i + 1); break;
      case 3: real = input(2 * i) + input(2 * i + 1); break;
      case 4: real = input(2 * i); imag = input(2 * i + 1); break;
      default: real = input(i); break;
    }
    const double next_real = s->oscillator_real * s->delta_real -
                             s->oscillator_imag * s->delta_imag;
    const double next_imag = s->oscillator_real * s->delta_imag +
                             s->oscillator_imag * s->delta_real;
    const double magnitude = std::sqrt(next_real * next_real + next_imag * next_imag);
    s->oscillator_real = next_real / magnitude;
    s->oscillator_imag = next_imag / magnitude;
    const double mixed_real = real * s->oscillator_real - imag * s->oscillator_imag;
    const double mixed_imag = real * s->oscillator_imag + imag * s->oscillator_real;
    s->filter(mixed_real, mixed_imag, real, imag);
    const double phase = std::atan2(imag, real);
    double delta = phase - s->previous_phase;
    if (delta < -pi) delta += 2 * pi;
    else if (delta > pi) delta -= 2 * pi;
    s->previous_phase = phase;
    samples[i] = s->scale * delta;
    const double value = s->average(samples[i]);
    const double delayed = s->delay[s->delay_position];
    s->delay[s->delay_position] = value;
    if (++s->delay_position == s->sync_count) s->delay_position = 0;
    if (s->trigger) {
      if (value < -1.5625) s->trigger = false;
    } else if (value > -1.375) {
      s->trigger = true;
    }
    if (!s->trigger) {
      if (s->pulse_count <= s->max20) ++s->pulse_count;
    } else if (s->pulse_count < s->min5 || s->pulse_count > s->max20 ||
               std::abs(delayed + 1.75) > 0.125) {
      s->pulse_count = 0;
    } else {
      s->sync.width = s->pulse_count < s->max5 ? 0 :
                       (s->pulse_count < s->max9 ? 1 : 2);
      s->sync.offset = i - (s->sync_count - 1) / 2;
      s->sync.frequency_offset = delayed + 1.75;
      s->sync.detected = 1;
      s->pulse_count = 0;
    }
  }
  *result = s->sync;
}

void ht_sstv_process(HtSstvDemodulator* state, double* samples, int32_t length,
                     int32_t channel, HtSstvSync* result) {
  if (!state || !result || length < 0 || (!samples && length) ||
      channel < 0 || channel > 4) return invalid(__func__, result);
  process_samples(state, samples, length, channel, result,
                   [samples](int i) { return samples[i]; });
}

void ht_sstv_process_pcm16(HtSstvDemodulator* state, const uint8_t* pcm,
                           int32_t length, double* output, HtSstvSync* result) {
  if (!state || !result || length < 0 || (!pcm && length) ||
      (!output && length / 2)) return invalid(__func__, result);
  process_samples(state, output, length / 2, 0, result, [pcm](int i) {
    const int raw = pcm[2 * i] | (pcm[2 * i + 1] << 8);
    return (raw >= 0x8000 ? raw - 0x10000 : raw) / 32768.0;
  });
}
