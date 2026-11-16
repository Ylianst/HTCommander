// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
#ifndef HT_GSM_SIMD_H
#define HT_GSM_SIMD_H

#include <stdint.h>

#if defined(__SSE2__) || defined(_M_X64)
#include <emmintrin.h>
#define HT_GSM_SIMD_WIDTH 8
#elif defined(__aarch64__) || defined(_M_ARM64)
#include <arm_neon.h>
#define HT_GSM_SIMD_WIDTH 8
#else
#define HT_GSM_SIMD_WIDTH 1
#endif

// GSM dynamically scales LTP/LPC inputs so even the sum of absolute products
// fits int32_t. Vector reduction therefore preserves the scalar integer result.
static inline int32_t ht_gsm_dot(const int16_t* a, const int16_t* b, int n) {
  int i = 0;
  int32_t result = 0;
#if defined(__SSE2__) || defined(_M_X64)
  __m128i sum = _mm_setzero_si128();
  for (; i + 8 <= n; i += 8) {
    const __m128i x = _mm_loadu_si128((const __m128i*)(a + i));
    const __m128i y = _mm_loadu_si128((const __m128i*)(b + i));
    sum = _mm_add_epi32(sum, _mm_madd_epi16(x, y));
  }
  sum = _mm_add_epi32(sum, _mm_srli_si128(sum, 8));
  sum = _mm_add_epi32(sum, _mm_srli_si128(sum, 4));
  result = _mm_cvtsi128_si32(sum);
#elif defined(__aarch64__) || defined(_M_ARM64)
  int32x4_t sum = vdupq_n_s32(0);
  for (; i + 8 <= n; i += 8) {
    const int16x8_t x = vld1q_s16(a + i);
    const int16x8_t y = vld1q_s16(b + i);
    sum = vmlal_s16(sum, vget_low_s16(x), vget_low_s16(y));
    sum = vmlal_s16(sum, vget_high_s16(x), vget_high_s16(y));
  }
  result = vaddvq_s32(sum);
#endif
  for (; i < n; ++i) result += (int32_t)a[i] * b[i];
  return result;
}

#endif
