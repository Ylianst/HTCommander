// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
//
// Windows PCM playback plugin using the Win32 waveOut (winmm) API.
//
// flutter_pcm_sound only supports Android / iOS / macOS, so this native plugin
// provides the equivalent streaming PCM sink on Windows for the radio audio
// path. It plays 16-bit signed PCM fed in chunks and reports the remaining
// buffered frame count back to Dart so the caller can bound latency.
//
// Threading: all waveOut device calls and the EventChannel sink are touched
// only on the platform thread. The waveOut completion callback runs on a
// system MM thread and is restricted (by the Win32 docs) to PostMessage, so it
// simply posts a message to a message-only window owned by this plugin; the
// window procedure then does the real work back on the platform thread.

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <mmsystem.h>

#include <cstdint>
#include <cstring>
#include <memory>
#include <set>
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

#include "pcm_player_plugin.h"

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;

constexpr char kMethodChannelName[] = "com.htcommander/pcm_player";
constexpr char kEventChannelName[] = "com.htcommander/pcm_player_feed";
constexpr UINT kBufferDoneMessage = WM_USER + 0x51;
constexpr wchar_t kWindowClassName[] = L"HTCommanderPcmPlayerWindow";

// Reads an int value from an EncodableMap, returning |fallback| if missing.
int GetIntArg(const EncodableMap* args, const char* key, int fallback) {
  if (!args) return fallback;
  auto it = args->find(EncodableValue(std::string(key)));
  if (it == args->end()) return fallback;
  if (const auto* v = std::get_if<int32_t>(&it->second)) return *v;
  if (const auto* v = std::get_if<int64_t>(&it->second)) {
    return static_cast<int>(*v);
  }
  return fallback;
}

}  // namespace

// ---------------------------------------------------------------------------
// Pimpl
// ---------------------------------------------------------------------------
struct PcmPlayerPlugin::Impl {
  explicit Impl(flutter::BinaryMessenger* messenger);
  ~Impl();

  // ---- platform-thread-only state ----
  HWAVEOUT hwo = nullptr;
  int sample_rate = 32000;
  int channels = 1;
  int64_t buffered_frames = 0;  // frames still queued in the device
  int feed_threshold = 0;
  HWND hwnd = nullptr;
  std::set<WAVEHDR*> outstanding;
  std::unique_ptr<flutter::EventSink<EncodableValue>> feed_sink;

  std::unique_ptr<flutter::MethodChannel<EncodableValue>> method_channel;
  std::unique_ptr<flutter::EventChannel<EncodableValue>> event_channel;

  void HandleMethodCall(
      const flutter::MethodCall<EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<EncodableValue>> result);

  bool Setup(int rate, int chans);
  bool Feed(const std::vector<uint8_t>& data);
  void Release();

  void EnsureWindow();
  void DestroyWindowSafe();
  void OnBufferDone(WAVEHDR* hdr);

  static void CALLBACK WaveOutProc(HWAVEOUT, UINT msg, DWORD_PTR instance,
                                   DWORD_PTR param1, DWORD_PTR param2);
  static LRESULT CALLBACK WndProc(HWND, UINT, WPARAM, LPARAM);
};

PcmPlayerPlugin::Impl::Impl(flutter::BinaryMessenger* messenger) {
  method_channel =
      std::make_unique<flutter::MethodChannel<EncodableValue>>(
          messenger, kMethodChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  method_channel->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });

  event_channel =
      std::make_unique<flutter::EventChannel<EncodableValue>>(
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
  Release();
  DestroyWindowSafe();
}

void PcmPlayerPlugin::Impl::HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const std::string& method = call.method_name();
  const auto* args = std::get_if<EncodableMap>(call.arguments());

  if (method == "setLogLevel" || method == "start") {
    result->Success();
    return;
  }
  if (method == "setup") {
    const int rate = GetIntArg(args, "sampleRate", 32000);
    const int chans = GetIntArg(args, "channels", 1);
    result->Success(EncodableValue(Setup(rate, chans)));
    return;
  }
  if (method == "setFeedThreshold") {
    feed_threshold = GetIntArg(args, "threshold", 0);
    result->Success();
    return;
  }
  if (method == "feed") {
    if (args) {
      auto it = args->find(EncodableValue(std::string("buffer")));
      if (it != args->end()) {
        if (const auto* bytes =
                std::get_if<std::vector<uint8_t>>(&it->second)) {
          result->Success(EncodableValue(Feed(*bytes)));
          return;
        }
      }
    }
    result->Success(EncodableValue(false));
    return;
  }
  if (method == "release") {
    Release();
    result->Success();
    return;
  }
  result->NotImplemented();
}

bool PcmPlayerPlugin::Impl::Setup(int rate, int chans) {
  Release();
  sample_rate = rate > 0 ? rate : 32000;
  channels = chans > 0 ? chans : 1;

  WAVEFORMATEX fmt = {};
  fmt.wFormatTag = WAVE_FORMAT_PCM;
  fmt.nChannels = static_cast<WORD>(channels);
  fmt.nSamplesPerSec = static_cast<DWORD>(sample_rate);
  fmt.wBitsPerSample = 16;
  fmt.nBlockAlign = static_cast<WORD>(channels * 2);
  fmt.nAvgBytesPerSec = fmt.nSamplesPerSec * fmt.nBlockAlign;
  fmt.cbSize = 0;

  EnsureWindow();

  HWAVEOUT handle = nullptr;
  const MMRESULT r = waveOutOpen(
      &handle, WAVE_MAPPER, &fmt,
      reinterpret_cast<DWORD_PTR>(&PcmPlayerPlugin::Impl::WaveOutProc),
      reinterpret_cast<DWORD_PTR>(this), CALLBACK_FUNCTION);
  if (r != MMSYSERR_NOERROR) {
    hwo = nullptr;
    return false;
  }
  hwo = handle;
  buffered_frames = 0;
  return true;
}

bool PcmPlayerPlugin::Impl::Feed(const std::vector<uint8_t>& data) {
  if (!hwo || data.empty()) return false;

  char* buf = new char[data.size()];
  std::memcpy(buf, data.data(), data.size());

  WAVEHDR* hdr = new WAVEHDR();
  std::memset(hdr, 0, sizeof(WAVEHDR));
  hdr->lpData = buf;
  hdr->dwBufferLength = static_cast<DWORD>(data.size());

  if (waveOutPrepareHeader(hwo, hdr, sizeof(WAVEHDR)) != MMSYSERR_NOERROR) {
    delete[] buf;
    delete hdr;
    return false;
  }
  if (waveOutWrite(hwo, hdr, sizeof(WAVEHDR)) != MMSYSERR_NOERROR) {
    waveOutUnprepareHeader(hwo, hdr, sizeof(WAVEHDR));
    delete[] buf;
    delete hdr;
    return false;
  }

  outstanding.insert(hdr);
  const int frame_bytes = channels * 2;
  buffered_frames +=
      static_cast<int64_t>(data.size()) / (frame_bytes > 0 ? frame_bytes : 2);
  return true;
}

void PcmPlayerPlugin::Impl::Release() {
  // Null the handle first so any late buffer-done messages bail out without
  // touching freed memory (everything here runs on the platform thread).
  HWAVEOUT handle = hwo;
  hwo = nullptr;
  if (handle) {
    waveOutReset(handle);  // marks all queued buffers done
    for (auto* hdr : outstanding) {
      waveOutUnprepareHeader(handle, hdr, sizeof(WAVEHDR));
      delete[] hdr->lpData;
      delete hdr;
    }
    outstanding.clear();
    waveOutClose(handle);
  }
  buffered_frames = 0;
}

void PcmPlayerPlugin::Impl::OnBufferDone(WAVEHDR* hdr) {
  // Ignore stale completions that arrive after Release() / unknown buffers.
  if (!hwo || !hdr || outstanding.find(hdr) == outstanding.end()) return;

  const int frame_bytes = channels * 2;
  const int64_t frames =
      hdr->dwBufferLength / (frame_bytes > 0 ? frame_bytes : 2);

  waveOutUnprepareHeader(hwo, hdr, sizeof(WAVEHDR));
  outstanding.erase(hdr);
  delete[] hdr->lpData;
  delete hdr;

  buffered_frames -= frames;
  if (buffered_frames < 0) buffered_frames = 0;

  if (feed_sink) {
    feed_sink->Success(EncodableValue(static_cast<int32_t>(buffered_frames)));
  }
}

void PcmPlayerPlugin::Impl::EnsureWindow() {
  if (hwnd) return;
  HINSTANCE instance = ::GetModuleHandleW(nullptr);

  WNDCLASSEXW wc = {};
  wc.cbSize = sizeof(wc);
  wc.lpfnWndProc = &PcmPlayerPlugin::Impl::WndProc;
  wc.hInstance = instance;
  wc.lpszClassName = kWindowClassName;
  ::RegisterClassExW(&wc);  // ignore "already registered"

  hwnd = ::CreateWindowExW(0, kWindowClassName, L"", 0, 0, 0, 0, 0,
                           HWND_MESSAGE, nullptr, instance, this);
}

void PcmPlayerPlugin::Impl::DestroyWindowSafe() {
  if (hwnd) {
    ::DestroyWindow(hwnd);
    hwnd = nullptr;
  }
}

void CALLBACK PcmPlayerPlugin::Impl::WaveOutProc(HWAVEOUT, UINT msg,
                                                 DWORD_PTR instance,
                                                 DWORD_PTR param1,
                                                 DWORD_PTR /*param2*/) {
  // Only PostMessage is permitted from a waveOut callback.
  if (msg != WOM_DONE) return;
  auto* self = reinterpret_cast<Impl*>(instance);
  if (self && self->hwnd) {
    ::PostMessageW(self->hwnd, kBufferDoneMessage, 0,
                   static_cast<LPARAM>(param1));
  }
}

LRESULT CALLBACK PcmPlayerPlugin::Impl::WndProc(HWND hwnd, UINT msg,
                                                WPARAM wparam, LPARAM lparam) {
  if (msg == WM_NCCREATE) {
    auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
    ::SetWindowLongPtrW(hwnd, GWLP_USERDATA,
                        reinterpret_cast<LONG_PTR>(create->lpCreateParams));
    return ::DefWindowProcW(hwnd, msg, wparam, lparam);
  }
  if (msg == kBufferDoneMessage) {
    auto* self =
        reinterpret_cast<Impl*>(::GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    if (self) self->OnBufferDone(reinterpret_cast<WAVEHDR*>(lparam));
    return 0;
  }
  return ::DefWindowProcW(hwnd, msg, wparam, lparam);
}

// ---------------------------------------------------------------------------
// Public wrapper
// ---------------------------------------------------------------------------
PcmPlayerPlugin::PcmPlayerPlugin(flutter::BinaryMessenger* messenger)
    : impl_(std::make_unique<Impl>(messenger)) {}

PcmPlayerPlugin::~PcmPlayerPlugin() = default;
