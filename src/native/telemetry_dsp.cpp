// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
#include "telemetry_dsp.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <exception>
#include <memory>
#include <numeric>
#include <vector>

#if defined(__SSE2__) || defined(_M_X64) || (defined(_M_IX86_FP) && _M_IX86_FP >= 2)
#include <emmintrin.h>
#define HT_TELEMETRY_SSE2
#elif defined(_M_ARM64) && defined(_MSC_VER) && !defined(__clang__)
#include <arm64_neon.h>
#define HT_TELEMETRY_NEON
#elif defined(__aarch64__)
#include <arm_neon.h>
#define HT_TELEMETRY_NEON
#endif

namespace {
#if defined(HT_TELEMETRY_SSE2)
using V2 = __m128d;
inline V2 load(const double* p) { return _mm_loadu_pd(p); }
inline void store(double* p, V2 v) { _mm_storeu_pd(p, v); }
inline V2 splat(double v) { return _mm_set1_pd(v); }
inline V2 add(V2 a, V2 b) { return _mm_add_pd(a, b); }
inline V2 sub(V2 a, V2 b) { return _mm_sub_pd(a, b); }
inline V2 mul(V2 a, V2 b) { return _mm_mul_pd(a, b); }
#elif defined(HT_TELEMETRY_NEON)
using V2 = float64x2_t;
inline V2 load(const double* p) { return vld1q_f64(p); }
inline void store(double* p, V2 v) { vst1q_f64(p, v); }
inline V2 splat(double v) { return vdupq_n_f64(v); }
inline V2 add(V2 a, V2 b) { return vaddq_f64(a, b); }
inline V2 sub(V2 a, V2 b) { return vsubq_f64(a, b); }
inline V2 mul(V2 a, V2 b) { return vmulq_f64(a, b); }
#endif

constexpr double pi = 3.14159265358979323846;
using Frame = std::vector<uint8_t>;
struct Result {
  std::vector<Frame> frames;
};

struct Recording {
  std::vector<int16_t> pcm;
  std::vector<double> prefix;
  double stddev = 1;
  bool prepared = false;

  void prepare() {
    if (prepared) return;
    const size_t n = pcm.size();
    double mean = 0;
    for (const auto v : pcm) mean += v;
    if (n) mean /= n;
    prefix.resize(n + 1);
    prefix[0] = 0;
    double sum_sq = 0;
    for (size_t i = 0; i < n; ++i) {
      const double v = pcm[i] - mean;
      prefix[i + 1] = prefix[i] + v;
      sum_sq += v * v;
    }
    stddev = sum_sq > 0 ? std::sqrt(sum_sq / n) : 1;
    prepared = true;
  }
};

int rounded(double x) { return static_cast<int>(std::round(x)); }

struct Run { int start, end; double level; };

void append_run(std::vector<Run>& runs, int start, int end, double level) {
  if (!runs.empty() && runs.back().level == level) runs.back().end = end;
  else runs.push_back({start, end, level});
}

void correlate(const std::vector<double>& prefix, const std::vector<Run>& runs,
               int begin, int end, double norm, double* output) {
  int off = begin;
#if defined(HT_TELEMETRY_SSE2) || defined(HT_TELEMETRY_NEON)
  const V2 scale = splat(norm);
  for (; off + 3 < end; off += 4) {
    V2 a = splat(0), b = splat(0);
    // Lanes are adjacent scan offsets, not taps: every score retains the
    // scalar accumulation order, including ties used during peak selection.
    for (const auto& r : runs) {
      const V2 level = splat(r.level);
      const double* first = prefix.data() + off + r.start;
      const double* last = prefix.data() + off + r.end;
      a = add(a, mul(level, sub(load(last), load(first))));
      b = add(b, mul(level, sub(load(last + 2), load(first + 2))));
    }
    store(output + off - begin, mul(a, scale));
    store(output + off - begin + 2, mul(b, scale));
  }
#endif
  for (; off < end; ++off) {
    double acc = 0;
    for (const auto& r : runs)
      acc += r.level * (prefix[off + r.end] - prefix[off + r.start]);
    output[off - begin] = acc * norm;
  }
}

void matched_sonde(Result& result, const int16_t* pcm, int n, int rate,
                   int mode, int chip_rate, int symbols,
                   const double* header, int hlen, Recording* recording = nullptr) {
  const double sps = static_cast<double>(rate) / chip_rate;
  if (n < std::ceil(symbols * sps)) return;
  std::vector<double> local_prefix;
  double stddev;
  if (recording) {
    recording->prepare();
    stddev = recording->stddev;
  } else {
    double mean = 0;
    for (int i = 0; i < n; ++i) mean += pcm[i];
    mean /= n;
    local_prefix.resize(n + 1);
    double sum_sq = 0;
    for (int i = 0; i < n; ++i) {
      const double v = pcm[i] - mean;
      local_prefix[i + 1] = local_prefix[i] + v;
      sum_sq += v * v;
    }
    stddev = sum_sq > 0 ? std::sqrt(sum_sq / n) : 1;
  }
  const auto& prefix = recording ? recording->prefix : local_prefix;
  const int last = n - static_cast<int>(std::ceil(hlen * sps)) - 1;
  if (last <= 0) return;
  const double norm = 1.0 / (hlen * sps * stddev);
  std::vector<Run> runs;
  for (int j = 0; j < hlen; ++j) {
    append_run(runs, rounded(j * sps), rounded((j + 1) * sps), header[j]);
  }
  const double threshold = mode == 1 ? 0.4 : 0.35;
  const int gap = rounded(symbols * sps * 0.5);
  const int window = std::min(rounded(sps * 2), last - 1);
  struct Peak { int offset; double score; };
  std::vector<Peak> peaks;
  constexpr int block_size = 4096;
  std::vector<double> scores(std::min(last, block_size + 2 * window));
  // Overlapping score blocks preserve local-max and plateau decisions without
  // retaining an audio-sized score array or updating a deque for every sample.
  for (int begin = 1; begin < last - 1; begin += block_size) {
    const int end = std::min(last - 1, begin + block_size);
    const int lo = std::max(0, begin - window);
    const int hi = std::min(last, end + window);
    correlate(prefix, runs, lo, hi, norm, scores.data());
    for (int center = begin; center < end; ++center) {
      const double score = scores[center - lo];
      const double a = std::abs(score);
      if (a < threshold) continue;
      bool maximum = true;
      for (int k = std::max(0, center - window);
           k <= std::min(last - 1, center + window); ++k) {
        if (std::abs(scores[k - lo]) > a) { maximum = false; break; }
      }
      if (!maximum) continue;
      if (!peaks.empty() && center - peaks.back().offset < gap) {
        if (a > std::abs(peaks.back().score)) peaks.back() = {center, score};
      } else {
        peaks.push_back({center, score});
      }
    }
  }
  double refined = sps;
  std::vector<int> diffs;
  const double target = symbols * sps;
  for (size_t i = 1; i < peaks.size(); ++i) {
    const int d = peaks[i].offset - peaks[i - 1].offset;
    if (d > target * 0.8 && d < target * 1.2) diffs.push_back(d);
  }
  if (!diffs.empty()) {
    std::sort(diffs.begin(), diffs.end());
    refined = static_cast<double>(diffs[diffs.size() / 2]) / symbols;
  }
  for (const auto& candidate : peaks) {
    const int peak = candidate.offset;
    const int pol = candidate.score >= 0 ? 1 : -1;
    const bool manchester = mode == 0 || mode == 2;
    const int bit_count = manchester ? symbols / 2 : symbols;
    Frame bits(bit_count);
    bool valid = true;
    for (int j = 0; j < bit_count; ++j) {
      const int s = rounded(peak + (manchester ? 2 * j : j) * refined);
      const int e = rounded(peak + (manchester ? 2 * j + 2 : j + 1) * refined);
      if (s < 0 || e > n || e <= s) { valid = false; break; }
      double v = prefix[e] - prefix[s];
      if (manchester) {
        const int m = rounded(peak + (2 * j + 1) * refined);
        if (m <= s || e <= m) { valid = false; break; }
        v = (prefix[e] - prefix[m]) / (e - m) -
            (prefix[m] - prefix[s]) / (m - s);
      }
      bits[j] = pol * v >= 0 ? 1 : 0;
    }
    if (!valid) continue;
    if (mode == 1 || mode == 2) {
      Frame bytes(bit_count / 8);
      int prev = 0;
      for (int j = 0; j < bit_count; ++j) {
        int b = bits[j];
        if (mode == 2) { b = bits[j] == prev ? 1 : 0; prev = bits[j]; }
        bytes[j / 8] |= b << (mode == 1 ? j % 8 : 7 - j % 8);
      }
      result.frames.push_back(std::move(bytes));
    } else {
      result.frames.push_back(std::move(bits));
    }
  }
}

void imet(Result& result, const int16_t* pcm, int n, int rate) {
  const double bitlen = rate / 1200.0;
  const int win = static_cast<int>(std::floor(2 * bitlen + 0.5));
  if (n < win * 4) return;
  // Both integer-Hz tones repeat after rate/gcd(rate, 1200, 2200) samples.
  const int period = std::min(n, rate / std::gcd(rate, 200));
  std::vector<double> c1(period), s1(period), c2(period), s2(period);
  for (int i = 0; i < period; ++i) {
    const double a = 2 * pi * (2200.0 * i / rate - std::floor(2200.0 * i / rate));
    const double b = 2 * pi * (1200.0 * i / rate - std::floor(1200.0 * i / rate));
    c1[i] = std::cos(a); s1[i] = std::sin(a);
    c2[i] = std::cos(b); s2[i] = std::sin(b);
  }
  double f1i = 0, f1q = 0, f2i = 0, f2q = 0;
  Frame bits;
  int prev = 0, prev_pos = win, incoming = 0, outgoing = 0;
  for (int i = 0; i < n; ++i) {
    const int a = incoming;
    if (++incoming == period) incoming = 0;
    const double x = pcm[i] / 32768.0;
    f1i += x * c1[a]; f1q -= x * s1[a];
    f2i += x * c2[a]; f2q -= x * s2[a];
    if (i >= win) {
      const int b = outgoing;
      if (++outgoing == period) outgoing = 0;
      const double old = pcm[i - win] / 32768.0;
      f1i -= old * c1[b]; f1q += old * s1[b];
      f2i -= old * c2[b]; f2q += old * s2[b];
    }
    const int bit = f2i * f2i + f2q * f2q >= f1i * f1i + f1q * f1q ? 1 : 0;
    if (i == win) prev = bit;
    if (i > win && bit != prev) {
      bits.insert(bits.end(), rounded((i - prev_pos) / bitlen), prev);
      prev = bit; prev_pos = i;
    }
  }
  bits.insert(bits.end(), std::min(12, rounded((n - 1 - prev_pos) / bitlen)), prev);
  Frame bytes;
  for (size_t p = 0; p + 9 < bits.size();) {
    if (bits[p] != 0 || bits[p + 9] != 1) { ++p; continue; }
    int byte = 0;
    for (int k = 0; k < 8; ++k) byte |= bits[p + 1 + k] << k;
    bytes.push_back(byte);
    p += 10;
  }
  if (!bytes.empty()) result.frames.push_back(std::move(bytes));
}

void boxcar(std::vector<double>& x, int length, int count) {
  std::vector<double> ring(length);
  double acc = 0;
  int position = 0;
  for (int i = 0; i < count; ++i) {
    const double v = x[i];
    acc += v;
    if (i >= length) acc -= ring[position];
    ring[position] = v;
    if (++position == length) position = 0;
    x[i] = acc / std::min(static_cast<int>(i + 1), length);
  }
}

double estimate_carrier(const int16_t* pcm, int n, int rate,
                        double carrier, double mean) {
  double best_mag = -1, fc = carrier;
  constexpr int lanes = 8;
  constexpr int segment = 1024;
  for (int base = 0; base <= 500; base += lanes) {
    std::array<double, lanes> w, cw, sw, coefficient, si{}, sq{};
    for (int lane = 0; lane < lanes; ++lane) {
      w[lane] = 2 * pi * (carrier - 250 + base + lane) / rate;
      cw[lane] = std::cos(w[lane]); sw[lane] = std::sin(w[lane]);
      coefficient[lane] = 2 * cw[lane];
    }
    // Reset the recurrence every segment to bound roundoff near DC/Nyquist,
    // then phase-align each segment's DFT before summing the full recording.
    for (int begin = 0; begin < n;) {
      const int end = begin + std::min(segment, n - begin);
      std::array<double, lanes> previous{}, older{};
      for (int i = begin; i < end; ++i) {
        const double x = pcm[i] - mean;
        for (int lane = 0; lane < lanes; ++lane) {
          const double next = x + coefficient[lane] * previous[lane] - older[lane];
          older[lane] = previous[lane]; previous[lane] = next;
        }
      }
      for (int lane = 0; lane < lanes; ++lane) {
        const double real = previous[lane] - cw[lane] * older[lane];
        const double imag = sw[lane] * older[lane];
        const double phase = w[lane] * (end - 1);
        const double c = std::cos(phase), s = std::sin(phase);
        si[lane] += real * c + imag * s;
        sq[lane] += real * s - imag * c;
      }
      begin = end;
    }
    for (int lane = 0; lane < lanes && base + lane <= 500; ++lane) {
      const double mag = si[lane] * si[lane] + sq[lane] * sq[lane];
      if (mag > best_mag) { best_mag = mag; fc = carrier - 250 + base + lane; }
    }
  }
  return fc;
}

void coherent(Result& result, const int16_t* pcm, int n, int rate, double carrier) {
  double mean = 0;
  for (int i = 0; i < n; ++i) mean += pcm[i];
  mean /= n;
  const double fc = estimate_carrier(pcm, n, rate, carrier, mean);
  std::vector<double> ib(n + 1), qb(n);
  const double w = 2 * pi * fc / rate;
  for (int i = 0; i < n; ++i) {
    const double x = pcm[i] - mean;
    ib[i] = x * std::cos(w * i);
    qb[i] = -x * std::sin(w * i);
  }
  const int lp = static_cast<int>(std::min(
      static_cast<double>(n), std::max(3.0, std::round(rate / (2 * fc)))));
  boxcar(ib, lp, n); boxcar(qb, lp, n);
  double di = 0, dq = 0;
  for (int i = 0; i < n; ++i) { di += ib[i]; dq += qb[i]; }
  const double mag = std::sqrt(di * di + dq * dq);
  if (mag == 0) return;
  di /= mag; dq /= mag;
  // Replace I baseband with phase prefix sums; no phase or DC-blocked array.
  double phase_sum = 0;
  for (int i = 0; i < n; ++i) {
    const double phase = std::atan2(qb[i] * di - ib[i] * dq, ib[i] * di + qb[i] * dq);
    ib[i] = phase_sum;
    phase_sum += phase;
  }
  ib[n] = phase_sum;
  std::vector<double>().swap(qb);
  const auto& prefix = ib;
  const double hb = rate / 800.0;
  const int tmpl_len = rounded(48 * hb);
  const int count = n - tmpl_len;
  if (count <= 0) return;
  const char* sync = "111111111111111000101111";
  std::vector<Run> runs;
  for (int i = 0; i < tmpl_len; ++i) {
    const int half = static_cast<int>(std::floor(i / hb));
    const double level = ((sync[half >> 1] == '1') == ((half & 1) == 0)) ? 1 : -1;
    append_run(runs, i, i + 1, level);
  }
  std::vector<double> corr(count);
  correlate(prefix, runs, 0, count, 1, corr.data());
  double max_abs = 0;
  for (const double value : corr) max_abs = std::max(max_abs, std::abs(value));
  const int guard = tmpl_len / 2;
  auto average = [&](double lo, double hi) {
    const int a = std::max(0, rounded(lo)), b = std::min(n, rounded(hi));
    return b <= a ? 0.0 : (prefix[b] - prefix[a]) / (b - a);
  };
  for (int i = 0; i < count;) {
    if (std::abs(corr[i]) < max_abs * 0.5) { ++i; continue; }
    int best = i;
    for (int j = i; j < count && j < i + guard; ++j)
      if (std::abs(corr[j]) > std::abs(corr[best])) best = j;
    for (int pol : {1, -1}) {
      Frame bits(144);
      for (int k = 0; k < 144; ++k) {
        const double a = average(best + 2 * k * hb, best + (2 * k + 1) * hb);
        const double b = average(best + (2 * k + 1) * hb, best + (2 * k + 2) * hb);
        bits[k] = (pol > 0 ? a > b : a < b) ? 1 : 0;
      }
      bool valid_sync = true;
      for (int k = 0; k < 15; ++k)
        if (bits[k] != 1) valid_sync = false;
      int frame_sync = 0;
      for (int k = 15; k < 24; ++k) frame_sync = (frame_sync << 1) | bits[k];
      if (!valid_sync || (frame_sync != 0x02f && frame_sync != 0x0d0)) continue;
      bits.resize(bits[24] == 1 ? 144 : 112);
      result.frames.push_back(std::move(bits));
    }
    i = best + guard;
  }
}

void fm_sarsat(Result& result, const int16_t* pcm, int n, int rate) {
  const int nb = rounded(rate / 400.0), size = 2 * nb;
  if (nb < 4 || n < nb * 40) return;
  int pos = 0, guard = 0;
  while (pos < n - nb * 40 && guard++ < 64) {
    std::vector<double> y(size);
    double sum = 0, pairs = 0, mx = 10e3, mn = -10e3;
    double threshold1 = mx / 100, threshold0 = mn / 100;
    int k = 0, num_bit = 0, sync = 0, depart = 0, length = 144, ticks = 0, state = -1;
    std::vector<int> bits(150, -1);
    while (num_bit < length && pos < n) {
      if (++k == size) k = 0;
      const double value = pcm[pos++], delta = value - y[k];
      pairs += delta * y[k < nb ? k + nb : k - nb];
      sum += delta;
      y[k] = value;
      // Each delayed pair covers both halves exactly once:
      // sum((a-mean)*(b-mean)) = sum(a*b) - sum(y)^2/(4*nb).
      const double y1 = pairs - sum * sum / (4 * nb);
      if (y1 > mx) { mx = y1; threshold1 = mx / 100; }
      if (y1 < mn) { mn = y1; threshold0 = mn / 100; }
      if (sync == 0) {
        if (depart == 0) {
          if (y1 > threshold1) depart = 1;
          ticks = 0;
        } else {
          ++ticks;
          if (y1 < threshold0) {
            const int nb15 = ticks / nb;
            if (nb15 >= 12 && nb15 <= 18) {
              sync = 1; ticks = 0;
              std::fill(bits.begin(), bits.begin() + 15, 1);
              num_bit = 15; state = 0;
            } else {
              ticks = 0; depart = 0; sync = 0; state = -1; num_bit = 0;
            }
          }
        }
      } else {
        ++ticks;
        if (bits[24] == 0) length = 112;
        if (y1 > threshold1) {
          if (state == 0) {
            state = 1; ticks -= nb / 2;
            while (ticks > 0 && num_bit < length) {
              bits[num_bit] = bits[num_bit - 1] == 1 ? 0 : 1;
              ++num_bit; ticks -= nb;
            }
            ticks = 0;
          }
        } else if (y1 < threshold0 && state == 1) {
          state = 0; ticks -= nb / 2;
          while (ticks > 0 && num_bit < 149) {
            bits[num_bit] = bits[num_bit - 1]; ++num_bit; ticks -= nb;
          }
          ticks = 0;
        }
      }
    }
    if (num_bit < length) break;
    Frame frame(length);
    for (int j = 0; j < length; ++j) frame[j] = bits[j] == 1 ? 1 : 0;
    result.frames.push_back(std::move(frame));
  }
}
}  // namespace

void* ht_telemetry_create() {
  try { return new Recording(); }
  catch (const std::exception&) { return nullptr; }
}

int16_t* ht_telemetry_resize(void* context, int32_t count) {
  if (!context || count < 0) return nullptr;
  auto& recording = *static_cast<Recording*>(context);
  try {
    recording.pcm.resize(count);
    recording.prepared = false;
    return recording.pcm.data();
  } catch (const std::exception&) { return nullptr; }
}

void ht_telemetry_destroy(void* context) { delete static_cast<Recording*>(context); }

void* ht_telemetry_recording_sonde(
    void* context, int32_t rate, int32_t mode, int32_t chip_rate,
    int32_t symbols, const double* header, int32_t hlen) {
  if (!context) return nullptr;
  try {
    auto& recording = *static_cast<Recording*>(context);
    auto result = std::make_unique<Result>();
    const auto* pcm = recording.pcm.data();
    const int n = static_cast<int>(recording.pcm.size());
    if (mode == 4) imet(*result, pcm, n, rate);
    else matched_sonde(*result, pcm, n, rate, mode, chip_rate, symbols,
                       header, hlen, &recording);
    return result.release();
  } catch (const std::exception&) { return nullptr; }
}

void* ht_telemetry_recording_sarsat(void* context, int32_t rate, double carrier) {
  if (!context) return nullptr;
  auto& recording = *static_cast<Recording*>(context);
  return ht_telemetry_sarsat(recording.pcm.data(),
                            static_cast<int32_t>(recording.pcm.size()), rate, carrier);
}

void* ht_telemetry_sonde(const int16_t* pcm, int32_t n, int32_t rate,
                         int32_t mode, int32_t chip_rate, int32_t symbols,
                         const double* header, int32_t hlen) {
  try {
    auto result = std::make_unique<Result>();
    if (mode == 4) imet(*result, pcm, n, rate);
    else matched_sonde(*result, pcm, n, rate, mode, chip_rate, symbols, header, hlen);
    return result.release();
  } catch (const std::exception&) { return nullptr; }
}

void* ht_telemetry_sarsat(const int16_t* pcm, int32_t n, int32_t rate, double carrier) {
  try {
    auto result = std::make_unique<Result>();
    coherent(*result, pcm, n, rate, carrier);
    fm_sarsat(*result, pcm, n, rate);
    return result.release();
  } catch (const std::exception&) { return nullptr; }
}
int32_t ht_telemetry_count(const void* result) {
  return static_cast<int32_t>(static_cast<const Result*>(result)->frames.size());
}
int32_t ht_telemetry_length(const void* result, int32_t frame) {
  return static_cast<int32_t>(static_cast<const Result*>(result)->frames[frame].size());
}
const uint8_t* ht_telemetry_data(const void* result, int32_t frame) {
  return static_cast<const Result*>(result)->frames[frame].data();
}
void ht_telemetry_free(void* result) { delete static_cast<Result*>(result); }
