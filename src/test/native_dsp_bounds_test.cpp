// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
#include "../native/dart_dsp.h"
#include "../native/spectrogram.h"
#include "../native/sstv_dsp.h"
#include "../native/telemetry_dsp.h"
#include "../native/xara_dsp.h"
#include <cassert>
#include <cmath>
#include <cstdint>

extern "C" void ht_satellite_init(void*);
extern "C" void ht_satellite_observer(void*, double, double, double);

int main() {
  double re[4] = {1, 2, 3, 4}, im[4] = {};
  const double trig[2] = {1, 0};
  const int32_t invalid_reverse[4] = {0, 1, 2, 4};
  ht_xara_fft(re, im, trig, trig, invalid_reverse, 4, 0, 1);
  assert(re[0] == 1 && re[3] == 4);
  ht_xara_fft_direct(re, im, trig, trig, invalid_reverse, -1, 0, 1, nullptr);
  double work[8] = {};
  ht_xara_fft_direct(re, re, trig, trig, invalid_reverse, 4, 0, 1, work);
  assert(re[0] == 1 && re[3] == 4);
  ht_xara_fir(nullptr, nullptr, nullptr, 0, 0, 1, nullptr, 1);
  ht_xara_append_row(nullptr, 0, 0, 0, nullptr);
  ht_xara_append_spectrum(nullptr, 0, 0, nullptr, nullptr, nullptr,
                          nullptr, 0, 0);
  ht_xara_correlate(nullptr, 0, nullptr, nullptr, nullptr, 0, 0,
                    0, 0, 0, nullptr, nullptr, 1);

  double output[4] = {17, 17, 17, 17};
  const double kernel[8] = {};
  HtXaraResampled result{};
  assert(ht_xara_resample(re, 4, kernel, 2, 1, 0, 0, 1, 0,
                         output, 4, &result, 1) == -2);
  assert(ht_xara_resample(re, 4, kernel, 2, 1, 1, NAN, 1, 0,
                         output, 4, &result, 1) == -2);
  assert(ht_xara_resample(re, 4, kernel, 2, 1, 1, 0, 0, 0,
                         output, 4, &result, 1) == -2);
  assert(output[0] == 17);
  assert(ht_xara_resample(re, 4, kernel, 2, 1, 1, 0, 1, 0,
                         output, 4, &result, 1) == 0);
  assert(result.count == 1 && result.index == 2);

  assert(ht_sstv_create(8000, re, 0, 1, 1, 2, 3, 4, 1) == nullptr);
  assert(ht_sstv_create(8000, re, 1, 0, 1, 2, 3, 4, 1) == nullptr);
  HtSstvSync sync{};
  ht_sstv_process(nullptr, re, 4, 0, &sync);
  assert(sync.detected == -1);
  ht_sstv_process_pcm16(nullptr, nullptr, -1, nullptr, &sync);
  assert(sync.detected == -1);
  HtSstvDemodulator* demod = ht_sstv_create(8000, re, 1, 1, 1, 2, 3, 4, 1);
  assert(demod);
  ht_sstv_process(demod, re, 4, 5, &sync);
  assert(sync.detected == -1);
  ht_sstv_destroy(demod);
  double phase = 0;
  assert(ht_sstv_encode(nullptr, 1, 1, 1, 8000, 8, &phase,
                        output, 4, 0, 1) == -1);

  const uint8_t invalid_bits[2] = {2, 0};
  assert(std::isnan(ht_dart_fsk_modulate(invalid_bits, 2, 1, re,
                                       re, re, 0, output)));
  assert(ht_dart_ldpc_decode(nullptr, nullptr, nullptr, nullptr,
                             324, 648, 1, re, re, nullptr) == -1);
  assert(ht_dart_to_pcm(nullptr, 1, 1, nullptr, 1) == -1);
  output[0] = 17;
  ht_dart_correlate(re, re, 1, 1, -1, 1, output);
  assert(output[0] == 17);
  ht_dart_multiply_conjugate(nullptr, nullptr, nullptr, nullptr, 1, 1);
  ht_dart_from_pcm(nullptr, 1, nullptr, 1);
  ht_dart_ldpc_encode(nullptr, nullptr, 324, 648, nullptr, nullptr);
  ht_dart_dft(nullptr, nullptr, nullptr, 1, 1, 0, nullptr);
  ht_dart_corr_normalize(nullptr, 1, 1, nullptr, 1, 1, nullptr);
  ht_dart_fsk_energy(nullptr, 1, nullptr, nullptr, 1, nullptr, 1);
  ht_dart_fsk_soft(nullptr, 1, nullptr, nullptr, 1, nullptr, 1,
                    nullptr, 1, 1);

  const double header[1] = {1};
  const int16_t pcm[1] = {};
  assert(ht_telemetry_sonde(pcm, 1, 8000, 1, 1200, 9, header, 1) == nullptr);
  assert(ht_telemetry_sarsat(nullptr, 1, 8000, 1200) == nullptr);
  void* frames = ht_telemetry_sonde(nullptr, 0, 8000, 1, 1200, 8, header, 1);
  assert(frames && ht_telemetry_count(frames) == 0);
  assert(ht_telemetry_length(frames, -1) == -1);
  assert(ht_telemetry_length(frames, 0) == -1);
  assert(ht_telemetry_data(frames, 0) == nullptr);
  ht_telemetry_free(frames);
  assert(ht_telemetry_count(nullptr) == -1);
  assert(ht_spectrogram_width(nullptr) == -1);
  ht_spectrogram_clear(nullptr);
  ht_spectrogram_peak(nullptr, nullptr);
  ht_spectrogram_roll_reset(nullptr, 0);
  ht_satellite_init(nullptr);
  ht_satellite_observer(nullptr, 0, 0, 0);
  return 0;
}
