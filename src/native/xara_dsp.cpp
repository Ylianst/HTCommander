// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
// Ported from lib/hamlib/xara/{complex,fm_rx_frontend,resample,turbo_decoder}.dart.
// XARA: Copyright (c) 2026 x0rro and the XARA authors, MIT License.
#include "xara_dsp.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <limits>
#include <new>
#include <stdexcept>
#include <vector>

#if defined(__SSE2__) || defined(_M_X64) || (defined(_M_IX86_FP) && _M_IX86_FP >= 2)
#include <emmintrin.h>
#define HT_XARA_SSE2
#elif defined(_M_ARM64) && defined(_MSC_VER) && !defined(__clang__)
#include <arm64_neon.h>
#define HT_XARA_NEON
#elif defined(__aarch64__)
#include <arm_neon.h>
#define HT_XARA_NEON
#endif

namespace {
#if defined(HT_XARA_SSE2)
using V2 = __m128d;
inline V2 load(const double* p) { return _mm_loadu_pd(p); }
inline void store(double* p, V2 v) { _mm_storeu_pd(p, v); }
inline V2 pair(double a, double b) { return _mm_set_pd(b, a); }
inline V2 splat(double v) { return _mm_set1_pd(v); }
inline V2 add(V2 a, V2 b) { return _mm_add_pd(a, b); }
inline V2 sub(V2 a, V2 b) { return _mm_sub_pd(a, b); }
inline V2 mul(V2 a, V2 b) { return _mm_mul_pd(a, b); }
inline V2 load_float2(const float* p) {
  return _mm_cvtps_pd(_mm_castsi128_ps(_mm_loadl_epi64(reinterpret_cast<const __m128i*>(p))));
}
inline double sum(V2 v) {
  return _mm_cvtsd_f64(v) + _mm_cvtsd_f64(_mm_unpackhi_pd(v, v));
}
#elif defined(HT_XARA_NEON)
using V2 = float64x2_t;
inline V2 load(const double* p) { return vld1q_f64(p); }
inline void store(double* p, V2 v) { vst1q_f64(p, v); }
inline V2 pair(double a, double b) {
  const double values[2] = {a, b};
  return load(values);
}
inline V2 splat(double v) { return vdupq_n_f64(v); }
inline V2 add(V2 a, V2 b) { return vaddq_f64(a, b); }
inline V2 sub(V2 a, V2 b) { return vsubq_f64(a, b); }
inline V2 mul(V2 a, V2 b) { return vmulq_f64(a, b); }
inline V2 load_float2(const float* p) { return vcvt_f64_f32(vld1_f32(p)); }
inline double sum(V2 v) { return vgetq_lane_f64(v, 0) + vgetq_lane_f64(v, 1); }
#endif

constexpr int window = 1024;
constexpr int segments = 4;
constexpr double neg = -1e9;
using States = std::array<double, 8>;
const States term = {0, neg, neg, neg, neg, neg, neg, neg};

struct Trellis {
  int next[16]{}, gis[16]{}, edge_s[16]{}, edge_g[16]{};
  Trellis() {
    for (int s = 0; s < 8; ++s) {
      for (int u = 0; u < 2; ++u) {
        const int r0 = (s >> 2) & 1, r1 = (s >> 1) & 1, r2 = s & 1;
        const int a = u ^ r0 ^ r1;
        const int n = (r1 << 2) | (r2 << 1) | a;
        next[2 * s + u] = n;
        gis[2 * s + u] = (u << 1) | (a ^ r2 ^ r0);
        edge_s[2 * n + (s >> 2)] = s;
        edge_g[2 * n + (s >> 2)] = gis[2 * s + u];
      }
    }
  }
};

const Trellis trellis;

double spectrum_hypot(double x, double y) {
  const double a = std::abs(x), b = std::abs(y);
  if (std::isinf(a) || std::isinf(b)) return std::numeric_limits<double>::infinity();
  if (std::isnan(a) || std::isnan(b)) return std::numeric_limits<double>::quiet_NaN();
  const double hi = a > b ? a : b, lo = a > b ? b : a;
  if (hi == 0.0) return 0.0;
  if (hi > 1e150 || lo < 1e-150) {
    const double r = lo / hi;
    return hi * std::sqrt(1.0 + r * r);
  }
  return std::sqrt(hi * hi + lo * lo);
}

void alpha(const double* x, const double* p, int n, States& a, double* cells) {
  for (int t = 0; t < n; ++t) {
    std::copy(a.begin(), a.end(), cells + 8 * t);
    const double g0 = 0.5 * (x[t] + p[t]), g1 = 0.5 * (x[t] - p[t]);
    const double g[] = {g0, g1, -g1, -g0};
    States nb;
    for (int d = 0; d < 8; ++d) {
      const double va = a[trellis.edge_s[2 * d]] + g[trellis.edge_g[2 * d]];
      const double vb = a[trellis.edge_s[2 * d + 1]] + g[trellis.edge_g[2 * d + 1]];
      nb[d] = va > vb ? va : vb;
    }
    for (int d = 0; d < 8; ++d) a[d] = nb[d] - nb[0];
  }
}

void beta(double scale, const double* x, const double* p, int n, States& b,
          const double* cells, double* out, int out_len) {
  for (int t = n - 1; t >= 0; --t) {
    const double g0 = 0.5 * (x[t] + p[t]), g1 = 0.5 * (x[t] - p[t]);
    const double g[] = {g0, g1, -g1, -g0};
    double bs[16];
    for (int s = 0; s < 16; ++s) bs[s] = b[trellis.next[s]] + g[trellis.gis[s]];
    if (t < out_len) {
      double m0 = -std::numeric_limits<double>::infinity(), m1 = m0;
      for (int s = 0; s < 8; ++s) {
        const double v0 = cells[8 * t + s] + bs[2 * s];
        const double v1 = cells[8 * t + s] + bs[2 * s + 1];
        if (v0 > m0) m0 = v0;
        if (v1 > m1) m1 = v1;
      }
      out[t] = scale * ((m0 - m1) - x[t]);
    }
    States nb;
    for (int s = 0; s < 8; ++s) nb[s] = bs[2 * s] > bs[2 * s + 1] ? bs[2 * s] : bs[2 * s + 1];
    for (int s = 0; s < 8; ++s) b[s] = nb[s] - nb[0];
  }
}

bool crc_ok(const uint8_t* bits, const uint8_t* white, int white_len, int nbytes) {
  if (nbytes < 3) return false;
  uint16_t crc = 0xffff;
  int received = 0;
  for (int i = 0; i < nbytes; ++i) {
    int v = 0;
    for (int j = 0; j < 8; ++j) {
      const int idx = 8 * i + j;
      v = (v << 1) | ((bits[idx] ^ (idx < white_len ? white[idx] : 0)) & 1);
    }
    if (i >= nbytes - 2) {
      received = (received << 8) | v;
    } else {
      crc ^= static_cast<uint16_t>(v << 8);
      for (int j = 0; j < 8; ++j) {
        crc = static_cast<uint16_t>((crc & 0x8000) ? (crc << 1) ^ 0x1021 : crc << 1);
      }
    }
  }
  return received == (crc ^ 0xffff);
}
}  // namespace

int32_t ht_xara_simd_width() {
#if defined(HT_XARA_SSE2) || defined(HT_XARA_NEON)
  return 2;
#else
  return 1;
#endif
}

void ht_xara_fft(double* re, double* im, const double* cosine, const double* sine,
                 const int32_t* reverse, int32_t n, int32_t inverse, int32_t simd) {
  for (int i = 0; i < n; ++i) {
    const int j = reverse[i];
    if (j > i) {
      std::swap(re[i], re[j]);
      std::swap(im[i], im[j]);
    }
  }
  const double sign = inverse ? 1.0 : -1.0;
  for (int size = 2; size <= n; size *= 2) {
    const int half = size / 2, step = n / size;
    for (int start = 0; start < n; start += size) {
      int k = 0;
#if defined(HT_XARA_SSE2) || defined(HT_XARA_NEON)
      if (simd) {
        for (; k + 1 < half; k += 2) {
          const V2 wr = pair(cosine[k * step], cosine[(k + 1) * step]);
          const V2 wi = mul(splat(sign), pair(sine[k * step], sine[(k + 1) * step]));
          const int a = start + k, b = a + half;
          const V2 br = load(re + b), bi = load(im + b);
          const V2 xr = sub(mul(br, wr), mul(bi, wi));
          const V2 xi = add(mul(br, wi), mul(bi, wr));
          const V2 ar = load(re + a), ai = load(im + a);
          store(re + b, sub(ar, xr));
          store(im + b, sub(ai, xi));
          store(re + a, add(ar, xr));
          store(im + a, add(ai, xi));
        }
      }
#endif
      for (; k < half; ++k) {
        const double wr = cosine[k * step], wi = sign * sine[k * step];
        const int a = start + k, b = a + half;
        const double xr = re[b] * wr - im[b] * wi;
        const double xi = re[b] * wi + im[b] * wr;
        re[b] = re[a] - xr;
        im[b] = im[a] - xi;
        re[a] += xr;
        im[a] += xi;
      }
    }
    if (size == n) break;
  }
}

void ht_xara_fft_direct(
    double* re, double* im, const double* cosine, const double* sine,
    const int32_t* reverse, int32_t n, int32_t inverse, int32_t simd,
    double* work) {
  const uintptr_t r = reinterpret_cast<uintptr_t>(re);
  const uintptr_t i = reinterpret_cast<uintptr_t>(im);
  const uintptr_t bytes = static_cast<uintptr_t>(n) * sizeof(double);
  if (r < i + bytes && i < r + bytes) {
    std::copy_n(re, n, work);
    std::copy_n(im, n, work + n);
    ht_xara_fft(work, work + n, cosine, sine, reverse, n, inverse, simd);
    std::copy_n(work, n, re);
    std::copy_n(work + n, n, im);
  } else {
    ht_xara_fft(re, im, cosine, sine, reverse, n, inverse, simd);
  }
}

void ht_xara_fir(const double* x, const double* hr, const double* hi, int32_t taps,
                 int32_t dec, int32_t count, double* out, int32_t simd) {
  for (int o = 0; o < count; ++o) {
    const double* v = x + o * dec;
    double ar = 0, ai = 0;
    int i = 0;
#if defined(HT_XARA_SSE2) || defined(HT_XARA_NEON)
    if (simd) {
      V2 vr = splat(0), vi = splat(0);
      for (; i + 1 < taps; i += 2) {
        const V2 sample = load(v + i);
        vr = add(vr, mul(sample, load(hr + i)));
        vi = add(vi, mul(sample, load(hi + i)));
      }
      ar = sum(vr);
      ai = sum(vi);
    }
#endif
    for (; i < taps; ++i) {
      ar += v[i] * hr[i];
      ai += v[i] * hi[i];
    }
    out[2 * o] = ar;
    out[2 * o + 1] = ai;
  }
}

void ht_xara_append_row(float* diff, int32_t capacity, int32_t width,
                        int32_t index, const float* row) {
  for (int k = 0; k < width; ++k) diff[k * capacity + index] = row[k];
}

void ht_xara_append_spectrum(
    float* diff, int32_t capacity, int32_t index,
    const double* re, const double* im, const float* previous,
    float* row, int32_t n, int32_t has_previous) {
  for (int k = 0; k < n; ++k) {
    const double ar = static_cast<float>(re[k]), ai = static_cast<float>(im[k]);
    double dr = 0.0, di = 0.0;
    if (has_previous) {
      const double br = previous[2 * k], bi = previous[2 * k + 1];
      const double pr = ar * br + ai * bi, pi = ai * br - ar * bi;
      const double norm = spectrum_hypot(pr, pi) + 1e-30;
      dr = pr / norm;
      di = pi / norm;
    }
    row[2 * k] = static_cast<float>(ar);
    row[2 * k + 1] = static_cast<float>(ai);
    diff[2 * k * capacity + index] = static_cast<float>(dr);
    diff[(2 * k + 1) * capacity + index] = static_cast<float>(di);
  }
}

void ht_xara_correlate(
    const float* diff, int32_t capacity,
    const int32_t* rows, const int32_t* bins, const double* refs,
    int32_t markers, int32_t cells, int32_t first, int32_t count,
    double marker_min, double* scratch, double* out, int32_t simd) {
  const bool gated = marker_min != -std::numeric_limits<double>::infinity();
  std::fill(scratch, scratch + 4 * count, 0.0);
  for (int c = 0; c < cells; ++c) {
    if (gated && c == markers) {
      bool any = false;
      for (int j = 0; j < count; ++j) {
        out[2 * j] = (scratch[j] * scratch[j] + scratch[count + j] * scratch[count + j]) / markers;
        out[2 * j + 1] = 0.0;
        if (out[2 * j] >= marker_min) any = true;
      }
      if (!any) return;
    }
    double* ar = scratch + (c < markers ? 0 : 2 * count);
    double* ai = ar + count;
    const double rr = refs[2 * c], ri = refs[2 * c + 1];
    const float* real = diff + bins[c] * capacity;
    const float* imag = real + capacity;
    int row = (first + rows[c]) % capacity;
    int j = 0;
#if defined(HT_XARA_SSE2) || defined(HT_XARA_NEON)
    if (simd) {
      const V2 vr = splat(rr), vi = splat(ri), two = splat(2.0);
      for (; j + 1 < count; j += 2) {
        const int row2 = row + 1 == capacity ? 0 : row + 1;
        if (gated && c >= markers &&
            !(out[2 * j] >= marker_min || out[2 * (j + 1)] >= marker_min)) {
          row = row2 + 1 == capacity ? 0 : row2 + 1;
          continue;
        }
        V2 dr = row2 == 0 ? pair(real[row], real[0]) : load_float2(real + row);
        V2 di = row2 == 0 ? pair(imag[row], imag[0]) : load_float2(imag + row);
        if (c >= markers) {
          const V2 sr = sub(mul(dr, dr), mul(di, di));
          const V2 si = mul(mul(two, dr), di);
          dr = sub(mul(sr, sr), mul(si, si));
          di = mul(mul(two, sr), si);
        }
        store(ar + j, add(load(ar + j), sub(mul(dr, vr), mul(di, vi))));
        store(ai + j, add(load(ai + j), add(mul(dr, vi), mul(di, vr))));
        row = row2 + 1 == capacity ? 0 : row2 + 1;
      }
    }
#endif
    for (; j < count; ++j) {
      if (gated && c >= markers && !(out[2 * j] >= marker_min)) {
        if (++row == capacity) row = 0;
        continue;
      }
      double dr = real[row], di = imag[row];
      if (c >= markers) {
        const double sr = dr * dr - di * di, si = 2 * dr * di;
        dr = sr * sr - si * si;
        di = 2 * sr * si;
      }
      ar[j] += dr * rr - di * ri;
      ai[j] += dr * ri + di * rr;
      if (++row == capacity) row = 0;
    }
  }
  for (int j = 0; j < count; ++j) {
    out[2 * j] = (scratch[j] * scratch[j] + scratch[count + j] * scratch[count + j]) / markers;
    const double br = scratch[2 * count + j], bi = scratch[3 * count + j];
    out[2 * j + 1] = cells == markers || (gated && !(out[2 * j] >= marker_min))
        ? 0.0 : (br * br + bi * bi) / (cells - markers);
  }
}

int32_t ht_xara_resample(
    const double* x, int32_t length, const double* table, int32_t half,
    int32_t phases, int32_t index, double fraction, int32_t whole,
    double part, double* out, int32_t capacity, HtXaraResampled* result, int32_t simd) {
  int count = 0;
  const int n = 2 * half;
  while (index + half < length) {
    if (count == capacity) return -1;
    const double pos = fraction * phases;
    const int p = std::min(static_cast<int>(pos), phases - 1);
    const double w = pos - p;
    const double* a = table + p * n;
    const double* b = a + n;
    const double* v = x + index + 1 - half;
    double acc = 0;
    int k = 0;
#if defined(HT_XARA_SSE2) || defined(HT_XARA_NEON)
    if (simd) {
      V2 total = splat(0);
      const V2 weight = splat(w);
      for (; k + 1 < n; k += 2) {
        const V2 c0 = load(a + k), c1 = load(b + k);
        total = add(total, mul(load(v + k), add(c0, mul(weight, sub(c1, c0)))));
      }
      acc = sum(total);
    }
#endif
    for (; k < n; ++k) acc += v[k] * (a[k] + w * (b[k] - a[k]));
    out[count++] = acc;
    index += whole;
    fraction += part;
    if (fraction >= 1.0) {
      fraction -= 1.0;
      ++index;
    }
  }
  result->index = index;
  result->fraction = fraction;
  result->count = count;
  return 0;
}

int32_t ht_xara_turbo(
    const double* ls, const double* lp1, const double* ls2, const double* lp2,
    const int32_t* perm, int32_t k, int32_t iters, double scale,
    int32_t min_iters, const uint8_t* white, int32_t white_length,
    int32_t nbytes, uint8_t* bits) {
  try {
    const int tlen = k + 3;
    const int nwin = (tlen + window - 1) / window;
    const int seg = ((nwin + segments - 1) / segments) * window;
    const int nseg = (tlen + seg - 1) / seg;
    std::vector<int> inv(k, -1);
    for (int i = 0; i < k; ++i) {
      if (perm[i] < 0 || perm[i] >= k || inv[perm[i]] != -1) return -1;
      inv[perm[i]] = i;
    }
    const double* systematic[] = {ls, ls2};
    const double* parity[] = {lp1, lp2};
    std::vector<double> ext[2] = {std::vector<double>(k), std::vector<double>(k)};
    std::vector<double> le21(k), x(seg), cells(8 * window);
    std::vector<States> pb[2][2], ap[2][2];
    for (int d = 0; d < 2; ++d) {
      for (int p = 0; p < 2; ++p) {
        pb[d][p].resize(nwin + 1);
        ap[d][p].resize(nseg + 1);
      }
    }
    std::fill(bits, bits + k, uint8_t{0});
    int ran = 0;
    for (int it = 1; it <= iters; ++it) {
      const int old = (it + 1) % 2, nw = it % 2;
      for (int d = 0; d < 2; ++d) {
        for (int i = 0; i < nseg; ++i) {
          const int s0 = i * seg, s1 = std::min((i + 1) * seg, tlen);
          for (int t = s0; t < s1; ++t) {
            x[t - s0] = t >= k ? systematic[d][t]
                : (d == 0 ? ls[t] + le21[t] : ls2[t] + ext[0][perm[t]]);
          }
          States a = i == 0 ? term : ap[d][old][i];
          for (int s = s0; s < s1; s += window) {
            const int e = std::min(s + window, s1);
            alpha(x.data() + s - s0, parity[d] + s, e - s, a, cells.data());
            States b = e == tlen ? term : pb[d][old][e / window];
            const int out_len = std::max(0, std::min(k, e) - s);
            beta(scale, x.data() + s - s0, parity[d] + s, e - s, b,
                 cells.data(), ext[d].data() + std::min(s, k), out_len);
            pb[d][nw][s / window] = b;
          }
          if (i + 1 < nseg) ap[d][nw][i + 1] = a;
        }
      }
      bool changed = false;
      for (int j = 0; j < k; ++j) {
        le21[j] = ext[1][inv[j]];
        const uint8_t bit = (ls[j] + ext[0][j]) + le21[j] < 0 ? 1 : 0;
        if (bit != bits[j]) changed = true;
        bits[j] = bit;
      }
      ran = it;
      if (min_iters > 0 && it >= min_iters && it < iters && !changed &&
          crc_ok(bits, white, white_length, nbytes)) break;
    }
    return ran;
  } catch (const std::bad_alloc&) {
    return -2;
  } catch (const std::length_error&) {
    return -2;
  }
}
