// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
#include "cw_dsp.h"

#include <algorithm>
#include <cmath>
#include <new>
#include <stdexcept>
#include <vector>

#if defined(__SSE2__) || defined(_M_X64) || (defined(_M_IX86_FP) && _M_IX86_FP >= 2)
#include <emmintrin.h>
#define HT_CW_SSE2
#elif defined(_M_ARM64) && defined(_MSC_VER) && !defined(__clang__)
#include <arm64_neon.h>
#define HT_CW_NEON
#elif defined(__aarch64__)
#include <arm_neon.h>
#define HT_CW_NEON
#endif

namespace {
struct Cw {
  std::vector<double> coefficients, input, metrics, s1, s2;
  int window, hop, prepared = 0;
  Cw(const double* c, int probes, int w, int h)
      : coefficients(c, c + probes), s1(probes), s2(probes), window(w), hop(h) {}
};

void analyze(Cw& state, const double* samples, double* result) {
  auto& s1 = state.s1;
  auto& s2 = state.s2;
  const auto& c = state.coefficients;
  const int probes = static_cast<int>(c.size());
  std::fill(s1.begin(), s1.end(), 0.0);
  std::fill(s2.begin(), s2.end(), 0.0);
  double energy = 0.0;
  for (int i = 0; i < state.window; ++i) {
    const double x = samples[i];
    energy += x * x;
    int p = 0;
    // Independent probes preserve the reference's recurrence and reduction order.
#if defined(HT_CW_SSE2)
    const auto vx = _mm_set1_pd(x);
    for (; p + 1 < probes; p += 2) {
      const auto a = _mm_loadu_pd(s1.data() + p);
      const auto b = _mm_loadu_pd(s2.data() + p);
      const auto next = _mm_sub_pd(
          _mm_add_pd(vx, _mm_mul_pd(_mm_loadu_pd(c.data() + p), a)), b);
      _mm_storeu_pd(s2.data() + p, a);
      _mm_storeu_pd(s1.data() + p, next);
    }
#elif defined(HT_CW_NEON)
    const auto vx = vdupq_n_f64(x);
    for (; p + 1 < probes; p += 2) {
      const auto a = vld1q_f64(s1.data() + p);
      const auto b = vld1q_f64(s2.data() + p);
      const auto next = vsubq_f64(
          vaddq_f64(vx, vmulq_f64(vld1q_f64(c.data() + p), a)), b);
      vst1q_f64(s2.data() + p, a);
      vst1q_f64(s1.data() + p, next);
    }
#endif
    for (; p < probes; ++p) {
      const double next = x + c[p] * s1[p] - s2[p];
      s2[p] = s1[p];
      s1[p] = next;
    }
  }
  double maximum = 0.0;
  int peak = -1;
  for (int p = 0; p < probes; ++p) {
    const double power =
        s1[p] * s1[p] + s2[p] * s2[p] - c[p] * s1[p] * s2[p];
    if (power > maximum) {
      maximum = power;
      peak = p;
    }
  }
  result[0] = energy;
  result[1] = maximum;
  result[2] = peak;
}
}  // namespace

void* ht_cw_create(const double* coefficients, int32_t probes,
                   int32_t window, int32_t hop) {
  if (!coefficients || probes < 1 || probes > 4096 ||
      window < 1 || window > 1048576 || hop < 1 || hop > window) return nullptr;
  for (int i = 0; i < probes; ++i) {
    if (!std::isfinite(coefficients[i])) return nullptr;
  }
  try {
    return new Cw(coefficients, probes, window, hop);
  } catch (const std::bad_alloc&) {
    return nullptr;
  } catch (const std::length_error&) {
    return nullptr;
  }
}

void ht_cw_destroy(void* state) { delete static_cast<Cw*>(state); }

double* ht_cw_prepare(void* state, int32_t windows) {
  if (!state) return nullptr;
  auto& cw = *static_cast<Cw*>(state);
  cw.prepared = 0;
  if (windows < 1 || windows > 256) return nullptr;
  try {
    const size_t count = cw.window + static_cast<size_t>(windows - 1) * cw.hop;
    cw.input.resize(count);
    cw.metrics.resize(static_cast<size_t>(windows) * 3);
    cw.prepared = windows;
    return cw.input.data();
  } catch (const std::bad_alloc&) {
    return nullptr;
  } catch (const std::length_error&) {
    return nullptr;
  }
}

int32_t ht_cw_process(void* state, int32_t windows) {
  if (!state) return -1;
  auto& cw = *static_cast<Cw*>(state);
  if (windows < 1 || windows != cw.prepared) return -1;
  for (const double x : cw.input) {
    if (!std::isfinite(x)) return -2;
  }
  for (int w = 0; w < windows; ++w) {
    analyze(cw, cw.input.data() + static_cast<size_t>(w) * cw.hop,
            cw.metrics.data() + w * 3);
  }
  return 0;
}

const double* ht_cw_metrics(const void* state) {
  if (!state) return nullptr;
  const auto& cw = *static_cast<const Cw*>(state);
  return cw.prepared > 0 ? cw.metrics.data() : nullptr;
}
