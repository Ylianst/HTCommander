// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
#ifndef RUNNER_PCM_PLAYER_BOUNDS_H_
#define RUNNER_PCM_PLAYER_BOUNDS_H_

#include <cstdint>
#include <limits>

namespace pcm_bounds {

inline bool ValidFormat(int rate, int channels) {
  return rate > 0 && rate <= 384000 && channels > 0 && channels <= 32;
}

inline int BufferedFrames(int64_t queued, uint64_t latency_us, int rate) {
  const int maximum = (std::numeric_limits<int>::max)();
  if (queued >= maximum) return maximum;
  if (queued < 0) queued = 0;
  // PulseAudio returns UINT64_MAX on failure, not a valid latency.
  if (latency_us == (std::numeric_limits<uint64_t>::max)() || rate <= 0) {
    return static_cast<int>(queued);
  }
  const uint64_t room = static_cast<uint64_t>(maximum - queued);
  if (latency_us > room * 1000000 / static_cast<uint64_t>(rate)) {
    return maximum;
  }
  return static_cast<int>(queued +
      latency_us * static_cast<uint64_t>(rate) / 1000000);
}

}  // namespace pcm_bounds

#endif  // RUNNER_PCM_PLAYER_BOUNDS_H_
