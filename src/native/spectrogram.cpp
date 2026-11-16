// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
#include "spectrogram.h"
#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>
#include <new>
#include <stdexcept>
#include <vector>

namespace {
struct Spectrogram {
  int size, step, first, height, fixed = 0;
  size_t start = 0, head = 0;
  int64_t processed = 0, roll_offset = 0;
  std::vector<double> samples, window, re, im, cosine, sine;
  std::vector<int32_t> reverse;
  std::vector<std::vector<double>> columns;

  Spectrogram(int n, int hop, int lo, int hi, const double* w)
      : size(n), step(hop), first(lo), height(hi - lo),
        window(w, w + n), re(n), im(n), cosine(n / 2), sine(n / 2),
        reverse(n) {
    const double pi = std::acos(-1.0);
    for (int i = 0; i < n / 2; ++i) {
      const double angle = 2.0 * pi * i / n;
      cosine[i] = std::cos(angle);
      sine[i] = std::sin(angle);
    }
    for (int i = 0; i < n; ++i) {
      int value = i, reversed = 0;
      for (int bit = n; bit > 1; bit >>= 1) {
        reversed = (reversed << 1) | (value & 1);
        value >>= 1;
      }
      reverse[i] = reversed;
    }
  }

  int pending() const {
    return static_cast<int>((static_cast<int64_t>(samples.size() - start) -
        size) / step);
  }
  size_t next() const {
    if (columns.empty()) return 0;
    const auto width = static_cast<int64_t>(columns.size());
    const auto index = (processed + roll_offset) % width;
    return static_cast<size_t>(index < 0 ? index + width : index);
  }
  void reserve_samples(int count) {
    if (start && samples.size() + count > samples.capacity()) {
      const size_t retained = samples.size() - start;
      std::memmove(samples.data(), samples.data() + start,
                   retained * sizeof(double));
      samples.resize(retained);
      start = 0;
    }
  }
};
}

void* ht_spectrogram_create(int32_t size, int32_t step, int32_t first,
                           int32_t last, const double* window) {
  if (size < 2 || (size & (size - 1)) || step < 1 || step > size ||
      first < 0 || last < first || last > size / 2 || !window) return nullptr;
  try { return new Spectrogram(size, step, first, last, window); }
  catch (const std::bad_alloc&) { return nullptr; }
  catch (const std::length_error&) { return nullptr; }
}

void ht_spectrogram_destroy(void* context) {
  delete static_cast<Spectrogram*>(context);
}

int32_t ht_spectrogram_add(void* context, const double* samples, int32_t count) {
  if (!context || count < 0 || (!samples && count)) return -1;
  auto& s = *static_cast<Spectrogram*>(context);
  try {
    s.reserve_samples(count);
    if (count) s.samples.insert(s.samples.end(), samples, samples + count);
    return 0;
  } catch (const std::bad_alloc&) { return -2; }
  catch (const std::length_error&) { return -2; }
}

int32_t ht_spectrogram_pcm(void* context, const uint8_t* samples, int32_t count) {
  if (!context || count < 0 || (!samples && count)) return -1;
  auto& s = *static_cast<Spectrogram*>(context);
  try {
    s.reserve_samples(count);
    const auto offset = s.samples.size();
    s.samples.resize(offset + count);
    for (int i = 0; i < count; ++i) {
      const int raw = samples[2 * i] | (samples[2 * i + 1] << 8);
      s.samples[offset + i] = raw >= 32768 ? raw - 65536 : raw;
    }
    return 0;
  } catch (const std::bad_alloc&) { return -2; }
  catch (const std::length_error&) { return -2; }
}

int32_t ht_spectrogram_process(void* context) {
  if (!context) return -1;
  auto& s = *static_cast<Spectrogram*>(context);
  const int count = s.pending();
  if (count < 1) return 0;
  try {
    const int skipped = s.fixed > 0 ? std::max(0, count - int(s.columns.size())) : 0;
    if (skipped) s.head = (s.head + skipped) % s.columns.size();
    for (int f = skipped; f < count; ++f) {
      const double* input = s.samples.data() + s.start + size_t(f) * s.step;
      for (int i = 0; i < s.size; ++i) {
        s.re[i] = input[i] * s.window[i];
        s.im[i] = 0.0;
      }
      ht_xara_fft(s.re.data(), s.im.data(), s.cosine.data(), s.sine.data(),
                  s.reverse.data(), s.size, 0, 1);
      if (s.fixed <= 0) s.columns.emplace_back(s.height);
      auto& column = s.columns[s.fixed > 0 ? s.head : s.columns.size() - 1];
      if (s.fixed > 0) s.head = (s.head + 1) % s.columns.size();
      for (int i = 0; i < s.height; ++i) {
        const int bin = s.first + i;
        column[i] = std::sqrt(s.re[bin] * s.re[bin] +
                             s.im[bin] * s.im[bin]) / s.size;
      }
    }
    s.processed += count;
    s.start += size_t(count) * s.step;
    return 0;
  } catch (const std::bad_alloc&) { return -2; }
  catch (const std::length_error&) { return -2; }
}

int32_t ht_spectrogram_resize(void* context, int32_t columns) {
  if (!context) return -1;
  auto& s = *static_cast<Spectrogram*>(context);
  if (columns == s.fixed) return 0;
  try {
    const size_t keep = columns > 0
        ? std::min(size_t(columns), s.columns.size()) : s.columns.size();
    std::vector<std::vector<double>> retained;
    retained.reserve(columns > 0 ? size_t(columns) : keep);
    for (size_t i = keep; columns > 0 && i < size_t(columns); ++i)
      retained.emplace_back(s.height, 0.0);
    for (size_t i = 0; i < keep; ++i)
      retained.push_back(s.columns[(s.head + s.columns.size() - keep + i) %
                                   s.columns.size()]);
    s.columns.swap(retained);
    s.head = 0;
    s.fixed = columns;
    return 0;
  } catch (const std::bad_alloc&) { return -2; }
  catch (const std::length_error&) { return -2; }
}

int32_t ht_spectrogram_width(void* context) {
  return static_cast<int32_t>(static_cast<Spectrogram*>(context)->columns.size());
}
int32_t ht_spectrogram_pending(void* context) {
  return static_cast<Spectrogram*>(context)->pending();
}
int32_t ht_spectrogram_next(void* context) {
  return static_cast<int32_t>(static_cast<Spectrogram*>(context)->next());
}
void ht_spectrogram_roll_reset(void* context, int32_t offset) {
  auto& s = *static_cast<Spectrogram*>(context);
  s.roll_offset = -s.processed + offset;
}
void ht_spectrogram_clear(void* context) {
  auto& s = *static_cast<Spectrogram*>(context);
  if (s.fixed > 0) {
    for (auto& column : s.columns) std::fill(column.begin(), column.end(), 0.0);
  } else s.columns.clear();
  s.samples.clear();
  s.start = s.head = 0;
  s.processed = s.roll_offset = 0;
}
void ht_spectrogram_peak(void* context, double* result) {
  auto& s = *static_cast<Spectrogram*>(context);
  result[0] = result[1] = std::numeric_limits<double>::quiet_NaN();
  if (s.columns.empty()) return;
  const auto& column = s.columns[(s.head + s.columns.size() - 1) % s.columns.size()];
  int bin = 0;
  double magnitude = 0;
  for (int i = 0; i < s.height; ++i) {
    if (column[i] > magnitude) { magnitude = column[i]; bin = i; }
  }
  result[0] = s.first + bin;
  result[1] = magnitude;
}
int32_t ht_spectrogram_render(void* context, uint8_t* rgba,
    const uint8_t* colors, double intensity, double db_scale, int32_t decibel,
    int32_t roll, int32_t count) {
  if (!context || !rgba || !colors) return -1;
  auto& s = *static_cast<Spectrogram*>(context);
  const size_t width = s.columns.size();
  if (count < 0 || size_t(count) > width) return -1;
  if (!count || !s.height) return 0;
  if (!roll && size_t(count) < width) {
    for (int row = 0; row < s.height; ++row) {
      uint8_t* dst = rgba + size_t(row) * width * 4;
      std::memmove(dst, dst + size_t(count) * 4, (width - count) * 4);
    }
  }
  const double log_mul = 20.0 / std::log(10.0);
  for (size_t source = width - count; source < width; ++source) {
    const size_t col = roll ? (source + s.next()) % width : source;
    const auto& values = s.columns[(s.head + source) % width];
    for (int row = 0; row < s.height; ++row) {
      double value = values[row];
      if (decibel) value = log_mul * std::log(value * db_scale + 1.0);
      value *= intensity;
      if (value > 255.0) value = 255.0;
      if (value < 0.0) value = 0.0;
      if (!std::isfinite(value)) return -3;
      const int v = static_cast<int>(value);
      const size_t pixel = (size_t(s.height - 1 - row) * width + col) * 4;
      rgba[pixel] = colors[v];
      rgba[pixel + 1] = colors[256 + v];
      rgba[pixel + 2] = colors[512 + v];
      rgba[pixel + 3] = 255;
    }
  }
  return 0;
}
