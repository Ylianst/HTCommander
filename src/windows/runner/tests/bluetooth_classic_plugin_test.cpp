// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
// Link the runner's Bluetooth, PCM output, playback and codec objects with the
// Flutter wrapper/import libraries, windowsapp.lib, winmm.lib, user32.lib and
// avrt.lib. Put windows\flutter\ephemeral on PATH for flutter_windows.dll.
// Uses a fake Flutter messenger; no RFCOMM connection or audio device is opened.
#include "..\bluetooth_classic_plugin.h"
#include "..\native_pcm_output.h"

#include <flutter/binary_messenger.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>

#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <future>
#include <map>
#include <thread>

#define CHECK(condition)                                                  \
  do {                                                                    \
    if (!(condition)) {                                                   \
      std::fprintf(stderr, "FAILED line %d: %s\n", __LINE__, #condition);   \
      std::abort();                                                       \
    }                                                                     \
  } while (false)

namespace {
using EV = flutter::EncodableValue;
constexpr char kChannel[] = "com.htcommander/bluetooth_classic";

class Messenger : public flutter::BinaryMessenger {
 public:
  std::map<std::string, flutter::BinaryMessageHandler> handlers;

  void Send(const std::string&, const uint8_t*, size_t,
            flutter::BinaryReply = nullptr) const override {}

  void SetMessageHandler(const std::string& channel,
                         flutter::BinaryMessageHandler handler) override {
    if (handler) {
      handlers[channel] = std::move(handler);
    } else {
      handlers.erase(channel);
    }
  }

  void Call(const std::string& method, flutter::BinaryReply reply) {
    const auto bytes = flutter::StandardMethodCodec::GetInstance()
                           .EncodeMethodCall(flutter::MethodCall<EV>(method, nullptr));
    // Keep the invoked handler alive while teardown unregisters its channel.
    const auto handler = handlers.at(kChannel);
    handler(bytes->data(), bytes->size(), std::move(reply));
  }
};
}  // namespace

int main() {
  using namespace std::chrono_literals;
  Messenger messenger;
  auto output = std::make_shared<NativePcmOutput>();
  auto plugin = std::make_unique<BluetoothClassicPlugin>(&messenger, output);

  // StandardMethodCodec decodes null arguments as a null pointer, not a map.
  for (const auto* method : {"send", "sendAudio", "connect", "sendPreparedAudio"}) {
    bool rejected = false;
    messenger.Call(method, [&](const uint8_t* data, size_t length) {
      flutter::MethodResultFunctions<EV> result(
          [](const EV*) { std::abort(); },
          [&](const std::string& code, const std::string&, const EV*) {
            CHECK(code == "INVALID_ARGS");
            rejected = true;
          },
          [] { std::abort(); });
      CHECK(flutter::StandardMethodCodec::GetInstance()
                .DecodeAndProcessResponseEnvelope(data, length, &result));
    });
    CHECK(rejected);
  }

  // An availability reply is deliberately held in flight. Destruction must
  // join even this non-connection worker before invalidating its messenger.
  std::promise<void> entered;
  auto started = entered.get_future();
  std::promise<void> release;
  auto gate = release.get_future().share();
  std::atomic<bool> replied{false};
  std::atomic<bool> destroyed{false};
  messenger.Call("isAvailable", [&](const uint8_t*, size_t) {
    entered.set_value();
    gate.wait();
    CHECK(!destroyed.load());
    replied.store(true);
  });
  CHECK(started.wait_for(10s) == std::future_status::ready);
  std::thread unblock([&] {
    std::this_thread::sleep_for(50ms);
    CHECK(!destroyed.load());
    release.set_value();
  });
  plugin.reset();
  destroyed.store(true);
  CHECK(replied.load());
  unblock.join();
  CHECK(messenger.handlers.empty());
  std::puts("bluetooth_classic_plugin_test: passed");
}
