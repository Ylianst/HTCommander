// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
#include "packet_modem.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <limits>
#include <new>
#include <vector>

#if defined(__SSE2__) || defined(_M_X64)
#include <emmintrin.h>
#define HT_PACKET_SSE2
#elif defined(__aarch64__) || defined(_M_ARM64)
#include <arm_neon.h>
#define HT_PACKET_NEON
#endif

namespace {
constexpr double pi = 3.14159265358979323846;
constexpr int max_taps = 4096;

struct History {
  std::vector<float> data;
  int pos = 0;
  explicit History(int n) : data(n) {}
  void push(double x) {
    if (--pos < 0) pos = static_cast<int>(data.size()) - 1;
    data[pos] = static_cast<float>(x);
  }
  double at(int offset) const {
    int i = pos + offset;
    if (i >= static_cast<int>(data.size())) i -= static_cast<int>(data.size());
    return data[i];
  }
};

struct PrefilterHistory {
  std::vector<float> data;
  int size, pos = 0;
  // Retain three older samples for four consecutive FIR outputs, with three
  // mirrored entries so every four-lane load is contiguous across the wrap.
  explicit PrefilterHistory(int taps)
      : data(taps ? taps + 6 : 0), size(taps ? taps + 3 : 0) {}
  void push(double x) {
    if (++pos == size) pos = 0;
    data[pos] = static_cast<float>(x);
    if (pos < 3) data[size + pos] = data[pos];
  }
  double filter(const std::vector<float>& coeff) const {
    double sum = 0;
    int j = 0, taps = static_cast<int>(coeff.size());
    int tail = std::min(taps, pos + 1);
    for (int i = pos; i > pos - tail; --i)
      sum += static_cast<double>(coeff[j++]) * data[i];
    for (int i = size - 1; j < taps; --i)
      sum += static_cast<double>(coeff[j++]) * data[i];
    return sum;
  }
  std::array<double, 4> filter_four(const std::vector<float>& coeff) const {
    std::array<double, 4> result{};
    int j = 0, taps = static_cast<int>(coeff.size());
    int first = pos >= 3 ? pos - 3 : pos + size - 3;
    int tail = std::min(taps, first + 1);
    // Each lane accumulates one output in the original newest-to-oldest order.
#if defined(HT_PACKET_SSE2)
    __m128d a = _mm_setzero_pd(), b = _mm_setzero_pd();
    auto accumulate = [&](int begin, int count) {
      for (int i = begin; i > begin - count; --i) {
        __m128 x = _mm_loadu_ps(data.data() + i);
        __m128d h = _mm_set1_pd(coeff[j++]);
        a = _mm_add_pd(a, _mm_mul_pd(h, _mm_cvtps_pd(x)));
        b = _mm_add_pd(b, _mm_mul_pd(h, _mm_cvtps_pd(_mm_movehl_ps(x, x))));
      }
    };
    accumulate(first, tail);
    accumulate(size - 1, taps - tail);
    _mm_storeu_pd(result.data(), a);
    _mm_storeu_pd(result.data() + 2, b);
#elif defined(HT_PACKET_NEON)
    float64x2_t a = vdupq_n_f64(0), b = vdupq_n_f64(0);
    auto accumulate = [&](int begin, int count) {
      for (int i = begin; i > begin - count; --i) {
        float32x4_t x = vld1q_f32(data.data() + i);
        float64x2_t h = vdupq_n_f64(coeff[j++]);
        a = vaddq_f64(a, vmulq_f64(h, vcvt_f64_f32(vget_low_f32(x))));
        b = vaddq_f64(b, vmulq_f64(h, vcvt_f64_f32(vget_high_f32(x))));
      }
    };
    accumulate(first, tail);
    accumulate(size - 1, taps - tail);
    vst1q_f64(result.data(), a);
    vst1q_f64(result.data() + 2, b);
#else
    auto accumulate = [&](int begin, int count) {
      for (int i = begin; i > begin - count; --i) {
        double h = coeff[j++];
        for (int k = 0; k < 4; ++k)
          result[k] += h * data[i + k];
      }
    };
    accumulate(first, tail);
    accumulate(size - 1, taps - tail);
#endif
    return result;
  }
};

struct MixerHistory {
  using Output = std::array<double, 4>;
  using Block = std::array<Output, 4>;
  std::vector<float> data;
  int taps, size, pos = 0;
  MixerHistory(int n, int w) : data((n + 6) * w), taps(n), size(n + 3) {}
  template <int channels>
  void push(double i, double q, double si = 0, double sq = 0) {
    if (--pos < 0) pos = size - 1;
    float* p = data.data() + pos * channels;
    p[0] = static_cast<float>(i);
    p[1] = static_cast<float>(q);
    if constexpr (channels == 4) {
      p[2] = static_cast<float>(si);
      p[3] = static_cast<float>(sq);
    }
    if (pos < 3)
      std::copy_n(p, channels, data.data() + (size + pos) * channels);
  }
  template <int channels>
  Output filter_impl(const std::vector<float>& coeff) const {
    Output result{};
    int j = 0;
    int tail = std::min(taps, size - pos);
    // SIMD lanes are independent I/Q filters, not partial sums of one filter.
    // Changing the summation order can change AGC decisions near silence.
#if defined(HT_PACKET_SSE2)
    __m128d a = _mm_setzero_pd(), b = _mm_setzero_pd();
    auto accumulate = [&](int begin, int end) {
      for (int i = begin; i < end; ++i) {
        const float* p = data.data() + i * channels;
        __m128d h = _mm_set1_pd(coeff[j++]);
        __m128d x = _mm_cvtps_pd(_mm_castsi128_ps(
            _mm_loadl_epi64(reinterpret_cast<const __m128i*>(p))));
        a = _mm_add_pd(a, _mm_mul_pd(h, x));
        if (channels == 4) {
          x = _mm_cvtps_pd(_mm_castsi128_ps(
              _mm_loadl_epi64(reinterpret_cast<const __m128i*>(p + 2))));
          b = _mm_add_pd(b, _mm_mul_pd(h, x));
        }
      }
    };
    accumulate(pos, pos + tail);
    accumulate(0, taps - tail);
    _mm_storeu_pd(result.data(), a);
    _mm_storeu_pd(result.data() + 2, b);
#elif defined(HT_PACKET_NEON)
    float64x2_t a = vdupq_n_f64(0), b = vdupq_n_f64(0);
    auto accumulate = [&](int begin, int end) {
      for (int i = begin; i < end; ++i) {
        const float* p = data.data() + i * channels;
        float64x2_t h = vdupq_n_f64(coeff[j++]);
        a = vaddq_f64(a, vmulq_f64(h, vcvt_f64_f32(vld1_f32(p))));
        if (channels == 4)
          b = vaddq_f64(b, vmulq_f64(h, vcvt_f64_f32(vld1_f32(p + 2))));
      }
    };
    accumulate(pos, pos + tail);
    accumulate(0, taps - tail);
    vst1q_f64(result.data(), a);
    vst1q_f64(result.data() + 2, b);
#else
    auto accumulate = [&](int begin, int end) {
      for (int i = begin; i < end; ++i) {
        double h = coeff[j++];
        for (int k = 0; k < channels; ++k)
          result[k] += h * data[i * channels + k];
      }
    };
    accumulate(pos, pos + tail);
    accumulate(0, taps - tail);
#endif
    return result;
  }
  template <int channels>
  Block filter_four_impl(const std::vector<float>& coeff) const {
    Block result{};
    int j = 0, tail = std::min(taps, size - pos);
#if defined(HT_PACKET_SSE2)
    __m128d a[4] = {}, b[4] = {};
    auto accumulate = [&](int begin, int count) {
      for (int i = begin; i < begin + count; ++i) {
        __m128d h = _mm_set1_pd(coeff[j++]);
        for (int k = 0; k < 4; ++k) {
          const float* p = data.data() + (i + 3 - k) * channels;
          __m128d x = _mm_cvtps_pd(_mm_castsi128_ps(
              _mm_loadl_epi64(reinterpret_cast<const __m128i*>(p))));
          a[k] = _mm_add_pd(a[k], _mm_mul_pd(h, x));
          if (channels == 4) {
            x = _mm_cvtps_pd(_mm_castsi128_ps(
                _mm_loadl_epi64(reinterpret_cast<const __m128i*>(p + 2))));
            b[k] = _mm_add_pd(b[k], _mm_mul_pd(h, x));
          }
        }
      }
    };
    accumulate(pos, tail);
    accumulate(0, taps - tail);
    for (int k = 0; k < 4; ++k) {
      _mm_storeu_pd(result[k].data(), a[k]);
      _mm_storeu_pd(result[k].data() + 2, b[k]);
    }
#elif defined(HT_PACKET_NEON)
    float64x2_t a[4] = {}, b[4] = {};
    auto accumulate = [&](int begin, int count) {
      for (int i = begin; i < begin + count; ++i) {
        float64x2_t h = vdupq_n_f64(coeff[j++]);
        for (int k = 0; k < 4; ++k) {
          const float* p = data.data() + (i + 3 - k) * channels;
          a[k] = vaddq_f64(a[k], vmulq_f64(h, vcvt_f64_f32(vld1_f32(p))));
          if (channels == 4)
            b[k] = vaddq_f64(b[k], vmulq_f64(h, vcvt_f64_f32(vld1_f32(p + 2))));
        }
      }
    };
    accumulate(pos, tail);
    accumulate(0, taps - tail);
    for (int k = 0; k < 4; ++k) {
      vst1q_f64(result[k].data(), a[k]);
      vst1q_f64(result[k].data() + 2, b[k]);
    }
#else
    auto accumulate = [&](int begin, int count) {
      for (int i = begin; i < begin + count; ++i) {
        double h = coeff[j++];
        for (int k = 0; k < 4; ++k)
          for (int c = 0; c < channels; ++c)
            result[k][c] += h * data[(i + 3 - k) * channels + c];
      }
    };
    accumulate(pos, tail);
    accumulate(0, taps - tail);
#endif
    return result;
  }
};

struct Slicer {
  int32_t clock = 0;
  int previous = 0, good = 0, bad = 0, good_hist = 0, bad_hist = 0;
  uint32_t score = 0;
  float gain = 0;
  bool detected = false;
};

struct PhaseDecision {
  int before, after;
  double fraction;
};

int popcount(uint32_t x) {
  x -= (x >> 1) & 0x55555555u;
  x = (x & 0x33333333u) + ((x >> 2) & 0x33333333u);
  x = (x + (x >> 4)) & 0x0f0f0f0fu;
  return static_cast<int>((x * 0x01010101u) >> 24);
}

int32_t signed32(uint32_t x) {
  return static_cast<int32_t>(x < 0x80000000u
      ? static_cast<int64_t>(x) : static_cast<int64_t>(x) - 0x100000000LL);
}

int64_t event_capacity(const ht_packet_rx_config& c, int samples) {
  // Nudges toward zero cannot shorten the positive half of a PLL cycle.
  int64_t crossings = 1 + (static_cast<int64_t>(samples) * c.pll_step) / 0x80000000LL;
  return crossings * (c.mode >= 2 ? 4 : 2 * c.slicers);
}

double agc(double x, double fast, double slow, double& peak, double& valley) {
  double a = x >= peak ? fast : slow;
  peak = x * a + peak * (1 - a);
  a = x <= valley ? fast : slow;
  valley = x * a + valley * (1 - a);
  x = std::min(x, peak);
  x = std::max(x, valley);
  return peak > valley ? (x - 0.5 * (peak + valley)) / (peak - valley) : 0;
}

struct Receiver {
  ht_packet_rx_config c;
  std::vector<float> pre, lp, osc;
  PrefilterHistory input;
  History delay;
  MixerHistory mixer;
  std::vector<Slicer> slicer;
  uint32_t mark_phase = 0, space_phase = 0, center_phase = 0;
  double mpeak = 0, mvalley = 0, speak = 0, svalley = 0, prev_phase = 0;

  Receiver(const ht_packet_rx_config& config, const float* p, const float* l,
      const float* o, const float* g)
      : c(config), pre(p, p + c.pre_taps), lp(l, l + c.lp_taps),
        osc(o, o + (c.mode < 2 || c.use_lo ? 256 : 0)),
        input(c.pre_taps), delay(c.delay_taps),
        mixer(c.lp_taps, c.mode == 0 ? 4 : 2), slicer(c.slicers) {
    for (int j = 0; j < c.slicers; ++j) slicer[j].gain = g[j];
  }

  void dcd(Slicer& s, int slice, uint32_t*& out) {
    s.good_hist = ((s.good_hist << 1) | s.good) & 255;
    s.bad_hist = ((s.bad_hist << 1) | s.bad) & 255;
    s.good = s.bad = 0;
    s.score = (s.score << 1) |
        (popcount(s.good_hist) - popcount(s.bad_hist) >= 2 ? 1u : 0u);
    int score = popcount(s.score);
    bool detected = score >= 30 ? true : score <= 6 ? false : s.detected;
    if (detected != s.detected) {
      s.detected = detected;
      *out++ = 4096u | (slice << 8) | (detected ? 1u : 0u);
    }
  }

  template <int mode>
  void pll(int slice, int symbol, double demod, double amplitude,
      const PhaseDecision* phase, uint32_t*& out) {
    Slicer& s = slicer[slice];
    int32_t before = s.clock;
    s.clock = signed32(static_cast<uint32_t>(s.clock) + c.pll_step);
    constexpr bool psk = mode >= 2;
    if (s.clock < 0 && (psk ? before >= 0 : before > 0)) {
      if constexpr (psk) {
        for (int b = (mode == 2 ? 1 : 2); b >= 0; --b) {
          double soft = ((phase->before >> b) & 1) * (1 - phase->fraction) +
              ((phase->after >> b) & 1) * phase->fraction;
          int quality = static_cast<int>(std::round(100.0 * 2.0 * std::abs(soft - 0.5)));
          *out++ = ((symbol >> b) & 1) | (quality << 1);
        }
      } else {
        int q = static_cast<int>(std::min(100.0,
            std::abs(demod) * 100.0 / amplitude));
        *out++ = symbol | (q << 1) | (slice << 8);
      }
      dcd(s, slice, out);
    }
    if (symbol != s.previous) {
      if (s.clock > -536870912 && s.clock < 536870912) s.good = 1;
      else s.bad = 1;
      double phase = s.clock * (s.detected ? c.locked_inertia : c.searching_inertia);
      s.clock = static_cast<int32_t>(psk ? std::floor(phase) : std::trunc(phase));
    }
    s.previous = symbol;
  }

  template <int mode>
  void mix(double x) {
    if constexpr (mode == 0) {
      mixer.push<4>(x * osc[(mark_phase >> 24) & 255],
          x * osc[((mark_phase >> 24) - 64) & 255],
          x * osc[(space_phase >> 24) & 255],
          x * osc[((space_phase >> 24) - 64) & 255]);
      mark_phase += c.mark_step;
      space_phase += c.space_step;
    } else if constexpr (mode == 1) {
      mixer.push<2>(x * osc[(center_phase >> 24) & 255],
          x * osc[((center_phase >> 24) - 64) & 255]);
      center_phase += c.center_step;
    } else if (c.use_lo) {
      mixer.push<2>(x * osc[((center_phase >> 24) + 64) & 255],
          x * osc[(center_phase >> 24) & 255]);
      center_phase += c.center_step;
    } else {
      delay.push(x);
      mixer.push<2>(x * delay.at(c.c_offs), x * delay.at(c.s_offs));
    }
  }

  template <int mode>
  void afsk(const MixerHistory::Output& filtered, uint32_t*& out) {
    if constexpr (mode == 0) {
      double mi = filtered[0], mq = filtered[1], si = filtered[2], sq = filtered[3];
      double m = std::sqrt(mi * mi + mq * mq);
      double s = std::sqrt(si * si + sq * sq);
      double mn = agc(m, c.fast_attack, c.slow_decay, mpeak, mvalley);
      double sn = agc(s, c.fast_attack, c.slow_decay, speak, svalley);
      for (int k = 0; k < c.slicers; ++k) {
        double value = mn - sn, amp = 1;
        if (c.slicers > 1) {
          value = m - s * slicer[k].gain;
          amp = 0.5 * (mpeak - mvalley + (speak - svalley) * slicer[k].gain);
          if (amp < 0.0000001) amp = 1;
        }
        pll<mode>(k, value > 0 ? 1 : 0, value, amp, nullptr, out);
      }
    } else {
      double phase = std::atan2(filtered[1], filtered[0]);
      double rate = phase - prev_phase;
      if (rate > pi) rate -= 2 * pi;
      else if (rate < -pi) rate += 2 * pi;
      prev_phase = phase;
      for (int k = 0; k < c.slicers; ++k) {
        double value = rate * c.normalize;
        if (c.slicers > 1) value += -0.5 + k * (1.0 / (c.slicers - 1));
        pll<mode>(k, value > 0 ? 1 : 0, value, 1, nullptr, out);
      }
    }
  }

  template <int mode>
  void psk(const MixerHistory::Output& filtered, uint32_t*& out) {
    double delta;
    if (c.use_lo) {
      double i = filtered[0], q = filtered[1];
      double a = i == 0 && q == 0 ? 0 : std::atan2(i, q);
      delay.push(a);
      delta = a - delay.at(c.b_offs);
      if (mode == 2 && c.v26_b) delta -= pi / 4;
    } else {
      double i = filtered[0], q = filtered[1];
      delta = i == 0 && q == 0 ? 0 : std::atan2(i, q);
      delta += mode == 2 ? (c.v26_b ? pi / 2 : 3 * pi / 4) : 3 * pi / 2;
    }
    constexpr int bits = mode == 2 ? 2 : 3, n = 1 << bits;
    double a = delta * n / (pi * 2);
    while (a >= n) a -= n;
    while (a < 0) a += n;
    int index = static_cast<int>(a);
    if (index == n) index = n - 1;
    double f = a - index;
    constexpr int gray4[] = {0, 1, 3, 2};
    constexpr int gray8[] = {1, 0, 2, 3, 7, 6, 4, 5};
    const int* gray = mode == 2 ? gray4 : gray8;
    PhaseDecision phase{gray[index], gray[(index + 1) & (n - 1)], f};
    // Adjacent Gray symbols differ in one bit. At exactly halfway the
    // reference interpolator slices that bit to one, whichever side it is on.
    int symbol = f < 0.5 ? phase.before : f > 0.5 ? phase.after :
        phase.before | phase.after;
    pll<mode>(0, symbol, 0, 1, &phase, out);
  }

  template <int mode>
  void demod(const MixerHistory::Output& filtered, uint32_t*& out) {
    if constexpr (mode >= 2) psk<mode>(filtered, out);
    else afsk<mode>(filtered, out);
  }

  template <int mode>
  void process_sample(double x, uint32_t*& out) {
    mix<mode>(x);
    demod<mode>(mixer.filter_impl<mode == 0 ? 4 : 2>(lp), out);
  }

  template <int mode>
  void process_four(const std::array<double, 4>& samples, uint32_t*& out) {
    // Oscillators and input delays do not depend on symbol/AGC feedback.
    for (double x : samples) mix<mode>(x);
    for (const auto& filtered : mixer.filter_four_impl<mode == 0 ? 4 : 2>(lp))
      demod<mode>(filtered, out);
  }

  template <int mode>
  int process(const uint8_t* pcm, int samples, uint32_t* events) {
    uint32_t* out = events;
    int j = 0;
    auto sample_at = [&](int i) {
      const size_t pos = static_cast<size_t>(i) * 2;
      int sample = pcm[pos] | (pcm[pos + 1] << 8);
      if (sample >= 32768) sample -= 65536;
      return sample / 16384.0;
    };
    for (; j + 3 < samples; j += 4) {
      std::array<double, 4> block;
      if (c.pre_taps) {
        for (int k = 0; k < 4; ++k) input.push(sample_at(j + k));
        block = input.filter_four(pre);
      } else {
        for (int k = 0; k < 4; ++k) block[k] = sample_at(j + k);
      }
      process_four<mode>(block, out);
    }
    for (; j < samples; ++j) {
      double x = sample_at(j);
      if (c.pre_taps) {
        input.push(x);
        x = input.filter(pre);
      }
      process_sample<mode>(x, out);
    }
    return static_cast<int>(out - events);
  }
};
}  // namespace

extern "C" {
void* ht_packet_rx_create(const ht_packet_rx_config* c, const float* pre,
    const float* lp, const float* oscillator, const float* gains) {
  if (!c || !pre || !lp || !oscillator || !gains ||
      c->mode < 0 || c->mode > 3 || c->slicers < 1 || c->slicers > 9 ||
      (c->mode >= 2 && c->slicers != 1) ||
      c->pre_taps < 0 || c->pre_taps > max_taps ||
      c->lp_taps < 1 || c->lp_taps > max_taps ||
      c->delay_taps < 0 || c->delay_taps > max_taps ||
      c->pll_step == 0 || c->pll_step >= 0x80000000u ||
      !(c->locked_inertia >= 0 && c->locked_inertia <= 1) ||
      !(c->searching_inertia >= 0 && c->searching_inertia <= 1) ||
      !(c->fast_attack >= 0 && c->fast_attack <= 1) ||
      !(c->slow_decay >= 0 && c->slow_decay <= 1) ||
      !std::isfinite(c->normalize) ||
      (c->mode >= 2 && (c->delay_taps < 1 ||
          c->b_offs < 0 || c->b_offs >= c->delay_taps ||
          c->c_offs < 0 || c->c_offs >= c->delay_taps ||
          c->s_offs < 0 || c->s_offs >= c->delay_taps))) return nullptr;
  double input_bound = c->pre_taps ? 0 : 2;
  for (int i = 0; i < c->pre_taps; ++i) {
    if (!std::isfinite(pre[i])) return nullptr;
    input_bound += 2 * std::abs(static_cast<double>(pre[i]));
  }
  for (int i = 0; i < c->lp_taps; ++i)
    if (!std::isfinite(lp[i])) return nullptr;
  double oscillator_bound = 0;
  if (c->mode < 2 || c->use_lo) {
    for (int i = 0; i < 256; ++i) {
      if (!std::isfinite(oscillator[i])) return nullptr;
      oscillator_bound = std::max(oscillator_bound,
          std::abs(static_cast<double>(oscillator[i])));
    }
  }
  for (int i = 0; i < c->slicers; ++i)
    if (!std::isfinite(gains[i]) || gains[i] < 0) return nullptr;
  // Histories store floats. Reject configurations that can overflow them and
  // turn a PSK phase into a NaN-derived Gray-table index.
  const double mixer_bound = c->mode >= 2 && !c->use_lo
      ? input_bound * input_bound : input_bound * oscillator_bound;
  if (mixer_bound > std::numeric_limits<float>::max()) return nullptr;
  try {
    return new Receiver(*c, pre, lp, oscillator, gains);
  } catch (const std::bad_alloc&) {
    return nullptr;
  }
}

void ht_packet_rx_destroy(void* state) { delete static_cast<Receiver*>(state); }

int32_t ht_packet_rx_process_bounded(void* state, const uint8_t* pcm, intptr_t pcm_bytes,
    intptr_t offset, int32_t samples, uint32_t* events, int32_t capacity) {
  if (!state || !pcm || !events || pcm_bytes < 0 || offset < 0 ||
      offset > pcm_bytes || samples < 0 ||
      samples > (pcm_bytes - offset) / 2 || capacity < 0) return -1;
  auto& r = *static_cast<Receiver*>(state);
  if (event_capacity(r.c, samples) > capacity) return -1;
  switch (r.c.mode) {
    case 0: return r.process<0>(pcm + offset, samples, events);
    case 1: return r.process<1>(pcm + offset, samples, events);
    case 2: return r.process<2>(pcm + offset, samples, events);
    case 3: return r.process<3>(pcm + offset, samples, events);
    default: return -1;
  }
}

int32_t ht_packet_tx(const ht_packet_tx_config* c, const int16_t* sine,
    const uint8_t* bits, int32_t count, uint8_t* pcm,
    int32_t capacity, int32_t leading, int32_t trailing) {
  if (!c || !sine || !bits || !pcm || count < 0 || leading < 0 || trailing < 0 ||
      c->mode < 0 || c->mode > 3 || capacity < 0 || capacity > 0x3fffffff ||
      !c->ticks_sample ||
      c->ticks_symbol < c->ticks_sample) return -1;
  int bits_per_symbol = c->mode < 2 ? 1 : c->mode == 2 ? 2 : 3;
  int64_t symbols = count / bits_per_symbol;
  int64_t length = (symbols * c->ticks_symbol + c->ticks_sample - 1) /
      c->ticks_sample + leading + trailing;
  if (length > capacity) return -1;
  for (int j = 0; j < count; ++j) if (bits[j] > 1) return -1;
  std::fill(pcm, pcm + 2 * static_cast<size_t>(leading), uint8_t{0});
  std::fill(pcm + 2 * (static_cast<size_t>(length) - trailing),
      pcm + 2 * static_cast<size_t>(length), uint8_t{0});
  uint32_t phase = c->mode == 2 ? 0x20000000u : 0;
  uint64_t acc = 0;
  int output = leading;
  constexpr int gray4[] = {0, 1, 3, 2};
  constexpr int gray8[] = {1, 0, 2, 3, 6, 7, 5, 4};
  for (int64_t j = 0; j < symbols; ++j) {
    int dat = 0;
    for (int b = 0; b < bits_per_symbol; ++b)
      dat = (dat << 1) | bits[j * bits_per_symbol + b];
    if (c->mode == 2) {
      phase += static_cast<uint32_t>(gray4[dat]) * 0x40000000u;
      if (c->v26_b) phase += 0x20000000u;
    } else if (c->mode == 3) {
      phase += static_cast<uint32_t>(gray8[dat]) * 0x20000000u;
    }
    uint32_t step = c->mode >= 2 || dat ? c->mark_step : c->space_step;
    do {
      phase += step;
      uint16_t sample = static_cast<uint16_t>(sine[phase >> 24]);
      pcm[2 * output] = static_cast<uint8_t>(sample);
      pcm[2 * output + 1] = static_cast<uint8_t>(sample >> 8);
      ++output;
      acc += c->ticks_sample;
    } while (acc < c->ticks_symbol);
    acc -= c->ticks_symbol;
  }
  return static_cast<int32_t>(length);
}
}
