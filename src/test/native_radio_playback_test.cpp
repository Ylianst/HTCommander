// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
// Standalone test: link radio_audio_playback.cpp and radio_audio_codec.cpp.
#include "../windows/runner/radio_audio_playback.h"

#include <cmath>
#include <cstdlib>
#include <iostream>
#include <thread>

namespace {
void Check(bool ok, const char* message) {
  if (!ok) {
    std::cerr << message << "\n";
    std::exit(1);
  }
}

std::vector<uint8_t> Packet(int command, const std::vector<uint8_t>& payload) {
  std::vector<uint8_t> bytes{0x7e, static_cast<uint8_t>(command)};
  for (const auto value : payload) {
    if (value == 0x7d || value == 0x7e) {
      bytes.push_back(0x7d);
      bytes.push_back(value ^ 0x20);
    } else {
      bytes.push_back(value);
    }
  }
  bytes.push_back(0x7e);
  return bytes;
}

std::vector<std::vector<uint8_t>> MakePackets() {
  std::unique_ptr<HtAudioCodec, decltype(&ht_audio_destroy)> codec(
      ht_audio_create(), ht_audio_destroy);
  std::vector<int16_t> pcm(128 * 6 * 5);
  for (size_t i = 0; i < pcm.size(); ++i) {
    pcm[i] = static_cast<int16_t>(10000 * std::sin(i * 0.13));
  }
  HtAudioTxResult tx{};
  Check(ht_audio_encode(codec.get(), reinterpret_cast<const uint8_t*>(pcm.data()),
                        static_cast<int32_t>(pcm.size() * 2), 0, &tx) == 0,
        "encode failed");
  std::vector<std::vector<uint8_t>> packets;
  size_t start = 0;
  for (int32_t i = 1; i < tx.data_length; ++i) {
    if (tx.data[i] != 0x7e) continue;
    packets.emplace_back(tx.data + start, tx.data + i + 1);
    packets.back()[1] = 3;
    start = static_cast<size_t>(++i);
  }
  Check(packets.size() == 5, "expected five RX packets");
  return packets;
}

std::vector<int16_t> Decode(const std::vector<std::vector<uint8_t>>& packets) {
  std::unique_ptr<HtAudioCodec, decltype(&ht_audio_destroy)> codec(
      ht_audio_create(), ht_audio_destroy);
  std::vector<int16_t> pcm;
  for (const auto& packet : packets) {
    HtAudioRxResult rx{};
    Check(ht_audio_receive(codec.get(), packet.data(),
                           static_cast<int32_t>(packet.size()), 1u << 3, &rx) == 1,
          "reference decode failed");
    Check(rx.error == 0, "reference SBC error");
    pcm.insert(pcm.end(), rx.pcm, rx.pcm + rx.pcm_samples);
  }
  return pcm;
}
}  // namespace

int main() {
  const auto packets = MakePackets();
  const auto expected = Decode(packets);
  std::vector<int16_t> played;
  std::vector<std::string> errors;
  RadioAudioPlayback playback(
      [&](const int16_t* pcm, size_t count) {
        played.insert(played.end(), pcm, pcm + count);
        return true;
      },
      [&](const std::string& error) { errors.push_back(error); });
  RadioAudioPlayback::Controls controls;
  controls.enabled = true;
  playback.Configure(controls);
  playback.Receive(packets[0].data(), packets[0].size());
  playback.Receive(packets[1].data(), packets[1].size());
  Check(played.empty(), "RX must hold at least 60ms before playback");
  // No UI event loop or Dart acknowledgement is involved in this producer.
  std::thread producer([&] {
    for (size_t i = 2; i < packets.size(); ++i) {
      for (const auto byte : packets[i]) playback.Receive(&byte, 1);
    }
  });
  producer.join();
  Check(played == expected, "native speaker PCM differs from codec PCM");
  Check(errors.empty(), "unexpected native playback error");

  auto reset = [&] {
    controls.enabled = false;
    playback.Configure(controls);
    controls.enabled = true;
    playback.Configure(controls);
    played.clear();
  };
  const auto end = Packet(1, {});
  reset();
  playback.Receive(packets[0].data(), packets[0].size());
  Check(played.empty(), "short run should await pre-roll or end");
  playback.Receive(end.data(), end.size());
  Check(played == Decode({packets[0]}), "end marker lost a short burst");

  reset();
  controls.muted = true;
  playback.Configure(controls);
  playback.Receive(packets[0].data(), packets[0].size());
  controls.muted = false;
  controls.volume = 0.5;
  playback.Configure(controls);
  for (size_t i = 1; i < packets.size(); ++i) {
    playback.Receive(packets[i].data(), packets[i].size());
  }
  Check(played.size() == expected.size() - 768, "muted PCM leaked or lost unmuted tail");
  for (size_t i = 0; i < played.size(); ++i) {
    Check(played[i] == std::lround(expected[i + 768] * 0.5),
          "volume scaling or muted decoder history differs");
  }

  reset();
  controls.audible = false;
  playback.Configure(controls);
  for (const auto& packet : packets) playback.Receive(packet.data(), packet.size());
  playback.Receive(end.data(), end.size());
  Check(played.empty(), "non-selected radio reached speaker");
  controls.audible = true;
  controls.volume = 1.0;
  playback.Configure(controls);

  reset();
  auto echo = packets[0];
  echo[1] = 9;
  playback.Receive(echo.data(), echo.size());
  Check(played.empty(), "TX echo reached speaker");
  playback.SetTransmitting(true);
  playback.Receive(packets[1].data(), packets[1].size());
  Check(played.empty(), "RX interrupted active TX echo run");
  playback.SetTransmitting(false);
  std::vector<uint8_t> coalesced(end);
  coalesced.insert(coalesced.end(), packets[2].begin(), packets[2].end());
  coalesced.insert(coalesced.end(), end.begin(), end.end());
  playback.Receive(coalesced.data(), coalesced.size());
  Check(played.size() == 768, "coalesced end marker did not restore RX decode mask");
  const auto echo_then_rx = Decode({packets[0], packets[2]});
  Check(played == std::vector<int16_t>(echo_then_rx.begin() + 768, echo_then_rx.end()),
        "ignored RX changed synthesis history");

  reset();
  playback.Receive(packets[0].data(), packets[0].size());
  echo = packets[1];
  echo[1] = 9;
  playback.Receive(echo.data(), echo.size());
  playback.Receive(packets[2].data(), packets[2].size());
  playback.Receive(end.data(), end.size());
  Check(played == echo_then_rx, "ignored TX echo changed receive synthesis history");

  RadioAudioPlayback rejected(
      [](const int16_t*, size_t) { return false; },
      [&](const std::string& error) { errors.push_back(error); });
  rejected.SetTransmitting(false);
  rejected.Configure(controls);
  for (const auto& packet : packets) rejected.Receive(packet.data(), packet.size());
  Check(rejected.stats().dropped_samples == static_cast<int64_t>(expected.size()),
        "speaker rejection was not counted");
  Check(!errors.empty(), "speaker rejection was not reported");
  const auto malformed = Packet(3, {0});
  rejected.Receive(malformed.data(), malformed.size());
  Check(rejected.stats().decode_errors == 1, "bad SBC was not diagnosed");
  std::cout << "Native radio playback tests passed\n";
}
