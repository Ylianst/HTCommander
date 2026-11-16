// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
#pragma once

#include <cstddef>
#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "../../native/radio_audio_codec.h"

// The Bluetooth reader is the producer; Dart only changes control state.
class RadioAudioPlayback {
 public:
  using Feed = std::function<bool(const int16_t*, size_t)>;
  using Report = std::function<void(const std::string&)>;

  struct Controls {
    bool enabled = false;
    bool audible = true;
    bool muted = false;
    double volume = 1.0;
  };

  struct Stats {
    int64_t packets = 0;
    int64_t decoded_samples = 0;
    int64_t queued_samples = 0;
    int64_t dropped_samples = 0;
    int64_t decode_errors = 0;
    std::string last_error;
  };

  RadioAudioPlayback(Feed feed, Report report);
  void Configure(const Controls& controls);
  void SetTransmitting(bool transmitting);
  void Receive(const uint8_t* data, size_t length);
  Stats stats() const;

 private:
  void Play(const int16_t* pcm, size_t count);
  void Flush();
  void Error(const std::string& message);

  mutable std::mutex mutex_;
  std::unique_ptr<HtAudioCodec, decltype(&ht_audio_destroy)> codec_;
  Feed feed_;
  Report report_;
  Controls controls_;
  Stats stats_;
  bool in_run_ = false;
  bool transmit_run_ = false;
  bool transmitting_ = false;
  bool preroll_flushed_ = false;
  bool feed_error_reported_ = false;
  std::vector<int16_t> preroll_;
  std::vector<int16_t> scaled_;
};
