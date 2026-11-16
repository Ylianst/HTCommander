// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
#pragma once

#include <cstddef>
#include <cstdint>
#include <functional>
#include <memory>
#include <string>

// Shared signed 16-bit PCM sink. All device operations, including completion
// handling, run on a persistent worker; no platform message pump is required.
// Public calls are thread-safe. Feed only copies/enqueues bounded data; it never
// waits for the worker/driver. Setup and Release wait for device reconfiguration.
class NativePcmOutput {
 public:
  struct Stats {
    int64_t queued_frames;
    uint64_t underruns;  // Queue drained after playing audio (includes stream end).
    uint64_t overflows;  // Rejected feeds exceeding the 800 ms queue limit.
    uint64_t errors;     // Validation/device errors, excluding bounded overflow.
    int64_t buffered_ms;
    int64_t peak_buffered_ms;
    uint64_t catchups;
    uint64_t discarded_frames;  // Includes any played prefix of reset buffers.
  };

  NativePcmOutput();
  ~NativePcmOutput();
  NativePcmOutput(const NativePcmOutput&) = delete;
  NativePcmOutput& operator=(const NativePcmOutput&) = delete;

  bool Setup(int rate, int channels, const std::string& device_id);
  // True means admitted to the bounded queue. Later driver submission failures
  // are logged and counted by error_count(), not hidden as successful playback.
  bool Feed(const uint8_t* data, size_t length);
  // Atomically requires ready 32000 Hz mono and enqueues in that generation.
  // Radio-only backlogs above 200 ms reset to the newest (at most 60 ms) PCM.
  // Mixed/non-radio queues retain the ordinary 800 ms admission limit.
  // count is the number of int16_t samples, not bytes.
  bool FeedRadio(const int16_t* pcm, size_t count);
  void Release();
  int64_t buffered_frames() const;
  bool IsRadioFormat() const;
  uint64_t overflow_count() const;
  uint64_t underrun_count() const;
  uint64_t error_count() const;

  // Observational notification on the output worker, not a playback scheduler.
  // Keep callbacks short. Replacing/clearing waits for any old callback to finish.
  // Never destroy the output from its own callback.
  void SetFeedCallback(std::function<void(int64_t)> callback);
  Stats stats() const;

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
