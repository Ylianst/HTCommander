// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
#include "../native/packet_modem.h"

#include <algorithm>
#include <array>
#include <cassert>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <limits>
#include <vector>

int main() {
  std::array<float, 256> oscillator{};
  for (int i = 0; i < 256; ++i)
    oscillator[i] = static_cast<float>(std::cos(i * 6.283185307179586 / 256));
  const float gains[9] = {0.5f, 0.7f, 1, 1.3f, 1.8f, 2, 2.5f, 3, 4};
  const uint32_t canary = 0xdeadbeef;
  for (int mode = 0; mode < 4; ++mode) {
    for (int taps : {1, 2, 3, 4, 7, 4096}) {
      ht_packet_rx_config c{};
      c.mode = mode;
      c.slicers = mode < 2 ? 9 : 1;
      c.pre_taps = c.lp_taps = c.delay_taps = taps;
      c.b_offs = c.c_offs = c.s_offs = taps - 1;
      c.use_lo = 1;
      c.pll_step = 0x10000000;
      c.mark_step = 0x09999999;
      c.space_step = 0x11999999;
      c.center_step = 0x0ccccccc;
      c.locked_inertia = 0.74;
      c.searching_inertia = 0.5;
      c.fast_attack = 0.1;
      c.slow_decay = 0.001;
      c.normalize = 1;
      std::vector<float> coefficients(taps, 1.0f / taps);
      void* state = ht_packet_rx_create(&c, coefficients.data(),
          coefficients.data(), oscillator.data(), gains);
      assert(state);
      const int samples = taps + 7;
      std::vector<uint8_t> pcm(samples * 2);
      for (size_t i = 0; i < pcm.size(); ++i)
        pcm[i] = static_cast<uint8_t>(i * 37);
      const int capacity = (1 + samples / 8) * (mode < 2 ? 18 : 4);
      std::vector<uint32_t> events(capacity + 2, canary);
      auto process = [&](intptr_t bytes, intptr_t offset, int count, int cap) {
        return ht_packet_rx_process_bounded(state, pcm.data(), bytes, offset,
            count, events.data() + 1, cap);
      };
      assert(process(pcm.size(), 0, samples + 1, capacity) == -1);
      assert(process(pcm.size(), pcm.size() - 1, 1, capacity) == -1);
      assert(process(pcm.size(), std::numeric_limits<intptr_t>::max(), 1,
          capacity) == -1);
      assert(process(-1, 0, 1, capacity) == -1);
      assert(process(pcm.size(), 0, samples, capacity - 1) == -1);
      assert(std::all_of(events.begin(), events.end(),
          [&](uint32_t value) { return value == canary; }));
      const int written = process(pcm.size(), 0, samples, capacity);
      assert(written >= 0 && written <= capacity);
      assert(events.front() == canary && events.back() == canary);
      ht_packet_rx_destroy(state);

      coefficients[0] = std::numeric_limits<float>::quiet_NaN();
      assert(!ht_packet_rx_create(&c, coefficients.data(),
          coefficients.data(), oscillator.data(), gains));
      coefficients[0] = std::numeric_limits<float>::max();
      assert(!ht_packet_rx_create(&c, coefficients.data(),
          coefficients.data(), oscillator.data(), gains));
    }
  }
  std::cout << "Native packet modem bounds tests passed\n";
}
