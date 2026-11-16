// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
//
// The platform thread owns Flutter channels and notification delivery only.
// NativePcmOutput owns the shared device and its independent playback worker.
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <mmsystem.h>

#include <cstdint>
#include <cstdio>
#include <limits>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_call.h>
#include <flutter/method_channel.h>
#include <flutter/method_result.h>
#include <flutter/standard_method_codec.h>

#include "native_pcm_output.h"
#include "pcm_player_plugin.h"

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;

constexpr char kMethodChannelName[] = "com.htcommander/pcm_player";
constexpr char kEventChannelName[] = "com.htcommander/pcm_player_feed";
constexpr UINT kFeedMessage = WM_USER + 0x51;
constexpr wchar_t kWindowClassName[] = L"HTCommanderPcmPlayerWindow";

int GetIntArg(const EncodableMap* args, const char* key, int fallback) {
  if (!args) return fallback;
  const auto it = args->find(EncodableValue(std::string(key)));
  if (it == args->end()) return fallback;
  if (const auto* v = std::get_if<int32_t>(&it->second)) return *v;
  if (const auto* v = std::get_if<int64_t>(&it->second)) {
    if (*v >= (std::numeric_limits<int>::min)() &&
        *v <= (std::numeric_limits<int>::max)()) {
      return static_cast<int>(*v);
    }
  }
  return fallback;
}

std::string GetStringArg(const EncodableMap* args, const char* key) {
  if (!args) return "";
  const auto it = args->find(EncodableValue(std::string(key)));
  if (it == args->end()) return "";
  if (const auto* v = std::get_if<std::string>(&it->second)) return *v;
  return "";
}

// No worker captures the plugin or a sink. Notification messages carry no
// pointers and are coalesced while the platform thread is busy.
struct FeedNotification {
  std::mutex mutex;
  HWND window = nullptr;
  bool pending = false;
};

}  // namespace

struct PcmPlayerPlugin::Impl {
  explicit Impl(flutter::BinaryMessenger* messenger);
  ~Impl();

  std::shared_ptr<NativePcmOutput> output =
      std::make_shared<NativePcmOutput>();
  std::shared_ptr<FeedNotification> notification =
      std::make_shared<FeedNotification>();
  HWND hwnd = nullptr;
  int feed_threshold = 0;
  std::unique_ptr<flutter::EventSink<EncodableValue>> feed_sink;
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> method_channel;
  std::unique_ptr<flutter::EventChannel<EncodableValue>> event_channel;

  void HandleMethodCall(
      const flutter::MethodCall<EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<EncodableValue>> result);
  EncodableValue ListDevices();
  void EnsureWindow();
  static LRESULT CALLBACK WndProc(HWND, UINT, WPARAM, LPARAM);
};

PcmPlayerPlugin::Impl::Impl(flutter::BinaryMessenger* messenger) {
  EnsureWindow();
  const std::weak_ptr<FeedNotification> weak_notification = notification;
  output->SetFeedCallback([weak_notification](int64_t) {
    if (const auto state = weak_notification.lock()) {
      std::lock_guard<std::mutex> lock(state->mutex);
      if (state->window && !state->pending) {
        state->pending =
            PostMessageW(state->window, kFeedMessage, 0, 0) != FALSE;
      }
    }
  });

  method_channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, kMethodChannelName,
      &flutter::StandardMethodCodec::GetInstance());
  method_channel->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });

  event_channel = std::make_unique<flutter::EventChannel<EncodableValue>>(
      messenger, kEventChannelName,
      &flutter::StandardMethodCodec::GetInstance());
  auto handler =
      std::make_unique<flutter::StreamHandlerFunctions<EncodableValue>>(
          [this](const EncodableValue*,
                 std::unique_ptr<flutter::EventSink<EncodableValue>>&& events)
              -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
            feed_sink = std::move(events);
            return nullptr;
          },
          [this](const EncodableValue*)
              -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
            feed_sink = nullptr;
            return nullptr;
          });
  event_channel->SetStreamHandler(std::move(handler));
}

PcmPlayerPlugin::Impl::~Impl() {
  method_channel->SetMethodCallHandler(nullptr);
  event_channel->SetStreamHandler(nullptr);
  output->SetFeedCallback(nullptr);
  {
    std::lock_guard<std::mutex> lock(notification->mutex);
    notification->window = nullptr;
  }
  if (hwnd) {
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
    DestroyWindow(hwnd);
  }
  feed_sink.reset();
  output->Release();
}

void PcmPlayerPlugin::Impl::HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const std::string& method = call.method_name();
  const auto* args = call.arguments()
                         ? std::get_if<EncodableMap>(call.arguments())
                         : nullptr;

  if (method == "setLogLevel" || method == "start") {
    result->Success();
  } else if (method == "setup") {
    const int rate = GetIntArg(args, "sampleRate", 32000);
    const int channels = GetIntArg(args, "channels", 1);
    if (output->Setup(rate, channels, GetStringArg(args, "deviceId"))) {
      result->Success(EncodableValue(true));
    } else {
      result->Error("setup_failed",
                    "Unable to open PCM output; see native output log.");
    }
  } else if (method == "listDevices") {
    result->Success(ListDevices());
  } else if (method == "setFeedThreshold") {
    feed_threshold = GetIntArg(args, "threshold", 0);
    result->Success();
  } else if (method == "feed") {
    const std::vector<uint8_t>* bytes = nullptr;
    if (args) {
      const auto it = args->find(EncodableValue(std::string("buffer")));
      if (it != args->end()) {
        bytes = std::get_if<std::vector<uint8_t>>(&it->second);
      }
    }
    if (!bytes) {
      OutputDebugStringA("[NativePcmOutput] Missing PCM byte buffer\n");
      std::fputs("[NativePcmOutput] Missing PCM byte buffer\n", stderr);
      result->Error("invalid_arguments", "feed requires a PCM byte buffer.");
    } else if (output->Feed(bytes->data(), bytes->size())) {
      result->Success(EncodableValue(true));
    } else {
      result->Error("feed_failed",
                    "PCM feed rejected (closed, invalid, overflow, or device "
                    "failure); see native output log/counters.");
    }
  } else if (method == "release") {
    output->Release();
    result->Success();
  } else {
    result->NotImplemented();
  }
}

EncodableValue PcmPlayerPlugin::Impl::ListDevices() {
  const UINT count = waveOutGetNumDevs();
  flutter::EncodableList devices;
  for (UINT i = 0; i < count; ++i) {
    WAVEOUTCAPSW caps = {};
    if (waveOutGetDevCapsW(i, &caps, sizeof(caps)) == MMSYSERR_NOERROR) {
      const int length = WideCharToMultiByte(
          CP_UTF8, 0, caps.szPname, -1, nullptr, 0, nullptr, nullptr);
      std::string name;
      if (length > 0) {
        name.resize(static_cast<size_t>(length));
        WideCharToMultiByte(CP_UTF8, 0, caps.szPname, -1, name.data(),
                            length, nullptr, nullptr);
        name.pop_back();
      }
      EncodableMap entry;
      entry[EncodableValue("id")] = EncodableValue(std::to_string(i));
      entry[EncodableValue("label")] = EncodableValue(name);
      devices.emplace_back(entry);
    }
  }
  return EncodableValue(devices);
}

void PcmPlayerPlugin::Impl::EnsureWindow() {
  const HINSTANCE instance = GetModuleHandleW(nullptr);
  WNDCLASSEXW window_class = {};
  window_class.cbSize = sizeof(window_class);
  window_class.lpfnWndProc = &Impl::WndProc;
  window_class.hInstance = instance;
  window_class.lpszClassName = kWindowClassName;
  RegisterClassExW(&window_class);
  hwnd = CreateWindowExW(0, kWindowClassName, L"", 0, 0, 0, 0, 0,
                          HWND_MESSAGE, nullptr, instance, this);
  {
    std::lock_guard<std::mutex> lock(notification->mutex);
    notification->window = hwnd;
  }
  if (!hwnd) {
    OutputDebugStringA("[NativePcmOutput] Cannot create feed notification window\n");
    std::fputs("[NativePcmOutput] Cannot create feed notification window\n", stderr);
  }
}

LRESULT CALLBACK PcmPlayerPlugin::Impl::WndProc(
    HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_NCCREATE) {
    const auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
    SetWindowLongPtrW(window, GWLP_USERDATA,
                      reinterpret_cast<LONG_PTR>(create->lpCreateParams));
  } else if (message == kFeedMessage) {
    auto* self = reinterpret_cast<Impl*>(
        GetWindowLongPtrW(window, GWLP_USERDATA));
    if (self) {
      {
        std::lock_guard<std::mutex> lock(self->notification->mutex);
        self->notification->pending = false;
      }
      // Read the current queue, not a stale completion from before reconfigure.
      if (self->feed_sink) {
        self->feed_sink->Success(
            EncodableValue(self->output->buffered_frames()));
      }
    }
    return 0;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

PcmPlayerPlugin::PcmPlayerPlugin(flutter::BinaryMessenger* messenger)
    : impl_(std::make_unique<Impl>(messenger)) {}

PcmPlayerPlugin::~PcmPlayerPlugin() = default;

std::shared_ptr<NativePcmOutput> PcmPlayerPlugin::output() const {
  return impl_->output;
}
