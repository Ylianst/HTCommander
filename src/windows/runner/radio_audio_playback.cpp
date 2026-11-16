// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
#include "radio_audio_playback.h"

#include <algorithm>
#include <cmath>
#include <limits>
#include <stdexcept>
#include <utility>

RadioAudioPlayback::RadioAudioPlayback(Feed feed, Report report)
    : codec_(ht_audio_create(), ht_audio_destroy),
      feed_(std::move(feed)), report_(std::move(report)) {
  if (!codec_) throw std::runtime_error("Native RX codec allocation failed");
  preroll_.reserve(32000 * 60 / 1000 + 768);
}

void RadioAudioPlayback::Configure(const Controls& controls) {
  if (!std::isfinite(controls.volume) || controls.volume < 0) {
    throw std::invalid_argument("Invalid native playback volume");
  }
  std::lock_guard<std::mutex> lock(mutex_);
  if (controls.enabled != controls_.enabled) {
    ht_audio_reset(codec_.get(), HT_AUDIO_RESET_DECODER | HT_AUDIO_RESET_PARSER);
    in_run_ = false;
  }
  if (controls.enabled != controls_.enabled ||
      controls.audible != controls_.audible ||
      controls.muted != controls_.muted) {
    preroll_.clear();
    preroll_flushed_ = false;
  }
  controls_ = controls;
}

void RadioAudioPlayback::SetTransmitting(bool transmitting) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (transmitting && !transmitting_) {
    preroll_.clear();
    preroll_flushed_ = false;
    if (!transmit_run_) in_run_ = false;
  }
  transmitting_ = transmitting;
}

void RadioAudioPlayback::Receive(const uint8_t* data, size_t length) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (!controls_.enabled) return;
  while (length != 0) {
    uint32_t mask = 0;
    if (!(in_run_ && transmit_run_ && transmitting_)) {
      mask |= (1u << 0) | (1u << 3);
    }
    if (!(in_run_ && !transmit_run_)) mask |= 1u << 9;
    const int32_t chunk = static_cast<int32_t>(
        std::min(length, static_cast<size_t>(std::numeric_limits<int32_t>::max())));
    HtAudioRxResult packet{};
    const int status = ht_audio_receive(codec_.get(), data, chunk, mask, &packet);
    if (status < 0 || packet.consumed <= 0 || packet.consumed > chunk) {
      Error("Native RX codec API failure: " + std::to_string(status));
      ht_audio_reset(codec_.get(), HT_AUDIO_RESET_PARSER);
      return;
    }
    data += packet.consumed;
    length -= static_cast<size_t>(packet.consumed);
    if (status == 0) continue;
    if (packet.error != 0) {
      ++stats_.decode_errors;
      Error("Native RX rejected audio: error=" + std::to_string(packet.error) +
            ", bytes=" + std::to_string(packet.rejected_bytes));
    }
    switch (packet.command) {
      case 0:
      case 3:
        if (in_run_ && transmit_run_ && transmitting_) break;
        if (!in_run_ || transmit_run_) {
          in_run_ = true;
          transmit_run_ = false;
          preroll_.clear();
          preroll_flushed_ = false;
          feed_error_reported_ = false;
        }
        ++stats_.packets;
        stats_.decoded_samples += packet.pcm_samples;
        if (!controls_.audible || controls_.muted || packet.pcm_samples == 0) break;
        if (preroll_flushed_) {
          Play(packet.pcm, static_cast<size_t>(packet.pcm_samples));
        } else {
          preroll_.insert(preroll_.end(), packet.pcm,
                          packet.pcm + packet.pcm_samples);
          if (preroll_.size() >= 32000 * 60 / 1000) Flush();
        }
        break;
      case 1:
        if (in_run_ && !transmit_run_) Flush();
        in_run_ = false;
        break;
      case 9:
        if (!(in_run_ && !transmit_run_)) {
          in_run_ = true;
          transmit_run_ = true;
        }
        break;
      default:
        break;
    }
  }
}

void RadioAudioPlayback::Play(const int16_t* pcm, size_t count) {
  if (count == 0) return;
  if (controls_.volume < 0.999) {
    scaled_.resize(count);
    for (size_t i = 0; i < count; ++i) {
      scaled_[i] = static_cast<int16_t>(std::clamp(
          std::lround(pcm[i] * controls_.volume), -32768L, 32767L));
    }
    pcm = scaled_.data();
  }
  if (feed_(pcm, count)) {
    stats_.queued_samples += static_cast<int64_t>(count);
  } else {
    stats_.dropped_samples += static_cast<int64_t>(count);
    if (!feed_error_reported_) {
      Error("Native RX speaker feed rejected; check output device or queue overflow");
      feed_error_reported_ = true;
    }
  }
}

void RadioAudioPlayback::Flush() {
  if (controls_.enabled && controls_.audible && !controls_.muted) {
    Play(preroll_.data(), preroll_.size());
  }
  preroll_.clear();
  preroll_flushed_ = true;
}

RadioAudioPlayback::Stats RadioAudioPlayback::stats() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return stats_;
}

void RadioAudioPlayback::Error(const std::string& message) {
  stats_.last_error = message;
  report_(message);
}
