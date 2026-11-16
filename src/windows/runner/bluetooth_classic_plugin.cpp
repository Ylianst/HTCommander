// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
//
// Windows Bluetooth Classic (RFCOMM) plugin using WinRT
// Windows.Devices.Bluetooth.Rfcomm + Windows.Networking.Sockets.StreamSocket
//
// Implements the same MethodChannel / EventChannel contract as the macOS
// BluetoothClassicHandler (IOBluetooth / Swift), so the Dart wrapper
// BluetoothClassicMacOS works on Windows without any Dart-side changes.

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
// GetCurrentTime is a Win32 macro that conflicts with WinRT internals.
#ifdef GetCurrentTime
#undef GetCurrentTime
#endif

// C++/WinRT headers from the Windows SDK.
#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Devices.Bluetooth.Rfcomm.h>
#include <winrt/Windows.Devices.Enumeration.h>
#include <winrt/Windows.Devices.Radios.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Networking.Sockets.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/Windows.System.h>

// Standard library.
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <stdexcept>
#include <thread>
#include <vector>
#include <algorithm>
#include <cmath>

// Flutter Desktop C++ wrapper.
#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/event_stream_handler.h>
#include <flutter/method_call.h>
#include <flutter/method_channel.h>
#include <flutter/method_result.h>
#include <flutter/standard_method_codec.h>

#include "bluetooth_classic_plugin.h"
#include "native_pcm_output.h"
#include "radio_audio_playback.h"

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------
namespace {

// WinRT namespace aliases.
namespace bt     = winrt::Windows::Devices::Bluetooth;
namespace rfcomm = winrt::Windows::Devices::Bluetooth::Rfcomm;
namespace denum  = winrt::Windows::Devices::Enumeration;
namespace radios = winrt::Windows::Devices::Radios;
namespace socks  = winrt::Windows::Networking::Sockets;
namespace strs   = winrt::Windows::Storage::Streams;
namespace wf     = winrt::Windows::Foundation;

// Service UUIDs -----------------------------------------------------------

// SPP / GAIA control channel.
const winrt::guid kSppUuid{
    0x00001101, 0x0000, 0x1000,
    {0x80, 0x00, 0x00, 0x80, 0x5F, 0x9B, 0x34, 0xFB}};

// BS AOC vendor service — carries SBC audio on these radios (ch 2).
// See docs/radio-bluetooth.md.
const winrt::guid kBsAocUuid{
    0x39144315, 0x32FA, 0x40DB,
    {0x85, 0xED, 0xFB, 0xFE, 0xBA, 0x2D, 0x86, 0xE6}};

// Generic Audio fallback (0x1203).
const winrt::guid kGenericAudioUuid{
    0x00001203, 0x0000, 0x1000,
    {0x80, 0x00, 0x00, 0x80, 0x5F, 0x9B, 0x34, 0xFB}};

// Convert "AA:BB:CC:DD:EE:FF" (or with '-') to uint64_t.
uint64_t ParseMac(const std::string& addr) {
  std::string s;
  for (char c : addr) {
    if (c != ':' && c != '-') s += c;
  }
  return std::stoull(s, nullptr, 16);
}

// Convert uint64_t to "AA:BB:CC:DD:EE:FF".
std::string FormatMac(uint64_t addr) {
  char buf[18];
  snprintf(buf, sizeof(buf), "%02X:%02X:%02X:%02X:%02X:%02X",
           static_cast<int>((addr >> 40) & 0xFF),
           static_cast<int>((addr >> 32) & 0xFF),
           static_cast<int>((addr >> 24) & 0xFF),
           static_cast<int>((addr >> 16) & 0xFF),
           static_cast<int>((addr >> 8) & 0xFF),
           static_cast<int>(addr & 0xFF));
  return buf;
}

// WinRT hstring → UTF-8 std::string.
std::string HstrToStr(const winrt::hstring& hs) {
  if (hs.empty()) return "";
  auto wstr = std::wstring_view(hs);
  int n = WideCharToMultiByte(CP_UTF8, 0, wstr.data(),
                              static_cast<int>(wstr.size()),
                              nullptr, 0, nullptr, nullptr);
  if (n <= 0) return "";
  std::string s(n, '\0');
  WideCharToMultiByte(CP_UTF8, 0, wstr.data(),
                      static_cast<int>(wstr.size()),
                      &s[0], n, nullptr, nullptr);
  return s;
}

// ---------------------------------------------------------------------------
// Active RFCOMM connection state
// ---------------------------------------------------------------------------
using BtMethodResult = flutter::MethodResult<flutter::EncodableValue>;

struct PreparedAudioJob {
  int64_t id;
  std::vector<uint8_t> data;
  std::vector<int32_t> lengths;
  std::vector<int32_t> samples;
  int lead_ms;
  std::atomic<bool> cancelled{false};
  std::unique_ptr<BtMethodResult> result;
};

const std::vector<uint8_t> kEndAudio{
    0x7e, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0x7e};

struct RfcommConn {
  socks::StreamSocket socket{nullptr};
  strs::DataReader    reader{nullptr};
  strs::DataWriter    writer{nullptr};
  std::string         address;
  std::atomic<bool>   running{false};
  std::thread         read_thread;
  std::mutex          write_mutex;
  std::mutex          audio_mutex;
  std::condition_variable audio_wake;
  std::shared_ptr<PreparedAudioJob> audio_job;
  std::thread         audio_thread;
  std::shared_ptr<RadioAudioPlayback> playback;

  RfcommConn() = default;
  ~RfcommConn() {
    running.store(false);
    audio_wake.notify_all();
    try {
      if (socket) socket.Close();
    } catch (...) {}
    if (read_thread.joinable()) read_thread.detach();
    if (audio_thread.joinable()) {
      if (audio_thread.get_id() == std::this_thread::get_id()) {
        audio_thread.detach();
      } else {
        audio_thread.join();
      }
    }
  }
  RfcommConn(const RfcommConn&) = delete;
  RfcommConn& operator=(const RfcommConn&) = delete;
};

void StartAudioWriter(const std::shared_ptr<RfcommConn>& conn) {
  conn->audio_thread = std::thread([conn]() {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    for (;;) {
      std::shared_ptr<PreparedAudioJob> job;
      {
        std::unique_lock<std::mutex> lock(conn->audio_mutex);
        conn->audio_wake.wait(lock, [&]() {
          return conn->audio_job || !conn->running.load();
        });
        job = conn->audio_job;
        if (!job) break;
      }
      using Clock = std::chrono::steady_clock;
      const auto start = Clock::now();
      auto last_write = start;
      int64_t sent = 0;
      int64_t writes = 0;
      int64_t max_write_ms = 0;
      int64_t max_gap_ms = 0;
      int64_t max_behind_ms = 0;
      std::string error;
      std::unique_lock<std::mutex> write_lock(conn->write_mutex);
      auto write = [&](winrt::array_view<const uint8_t> bytes) {
        if (!conn->running.load()) {
          throw std::runtime_error("Bluetooth audio connection closed");
        }
        if (conn->playback && bytes.size() > 1 && bytes[0] == 0x7e &&
            bytes[1] == 0) conn->playback->SetTransmitting(true);
        conn->writer.WriteBytes(bytes);
        auto operation = conn->writer.StoreAsync();
        if (operation.wait_for(std::chrono::seconds(5)) ==
            wf::AsyncStatus::Started) {
          operation.Cancel();
          conn->socket.Close();
          throw std::runtime_error("Bluetooth audio write timed out");
        }
        if (operation.get() != bytes.size()) {
          conn->socket.Close();
          throw std::runtime_error("Incomplete Bluetooth audio write");
        }
        if (conn->playback && bytes.size() > 1 && bytes[0] == 0x7e &&
            bytes[1] == 1) conn->playback->SetTransmitting(false);
      };
      try {
        size_t offset = 0;
        for (size_t i = 0; i < job->lengths.size(); ++i) {
          const auto due = start + std::chrono::milliseconds(
              (sent + job->samples[i]) * 1000 / 32000 - job->lead_ms);
          {
            std::unique_lock<std::mutex> lock(conn->audio_mutex);
            conn->audio_wake.wait_until(lock, due, [&]() {
              return job->cancelled.load() || !conn->running.load();
            });
          }
          if (!conn->running.load()) {
            throw std::runtime_error("Bluetooth audio connection closed");
          }
          if (job->cancelled.load()) break;
          const auto before = Clock::now();
          max_gap_ms = (std::max)(max_gap_ms, static_cast<int64_t>(
              std::chrono::duration_cast<std::chrono::milliseconds>(
                  before - last_write).count()));
          write(winrt::array_view<const uint8_t>(
              job->data.data() + offset,
              job->data.data() + offset + job->lengths[i]));
          last_write = Clock::now();
          max_write_ms = (std::max)(max_write_ms, static_cast<int64_t>(
              std::chrono::duration_cast<std::chrono::milliseconds>(
                  last_write - before).count()));
          offset += job->lengths[i];
          sent += job->samples[i];
          ++writes;
          const auto elapsed =
              std::chrono::duration_cast<std::chrono::milliseconds>(
                  last_write - start).count();
          max_behind_ms = (std::max)(
              max_behind_ms, static_cast<int64_t>(elapsed) - sent * 1000 / 32000);
        }
      } catch (const winrt::hresult_error& e) {
        error = HstrToStr(e.message());
      } catch (const std::exception& e) {
        error = e.what();
      }
      // The same writer owns the stop marker, including on cancellation.
      if (conn->running.load() && error.empty()) {
        try {
          write(kEndAudio);
        } catch (const winrt::hresult_error& e) {
          error += " Stop: " + HstrToStr(e.message());
        } catch (const std::exception& e) {
          error += " Stop: " + std::string(e.what());
        }
      } else if (error.empty()) {
        error = "Bluetooth audio connection closed";
      }
      if (!error.empty()) {
        if (conn->playback) conn->playback->SetTransmitting(false);
        try { conn->socket.Close(); } catch (...) {}
      }
      write_lock.unlock();
      {
        std::lock_guard<std::mutex> lock(conn->audio_mutex);
        conn->audio_job.reset();
      }
      if (!error.empty()) {
        job->result->Error("AUDIO_TX_FAILED", error);
      } else {
        const auto elapsed =
            std::chrono::duration_cast<std::chrono::milliseconds>(
                Clock::now() - start).count();
        using EV = flutter::EncodableValue;
        job->result->Success(EV(flutter::EncodableMap{
            {EV("status"), EV(job->cancelled.load() ? "cancelled" : "submitted")},
            {EV("samplesSent"), EV(sent)}, {EV("writes"), EV(writes)},
            {EV("elapsedMs"), EV(static_cast<int64_t>(elapsed))},
            {EV("maxWriteMs"), EV(max_write_ms)},
            {EV("maxGapMs"), EV(max_gap_ms)},
            {EV("maxBehindMs"), EV(max_behind_ms)}}));
      }
    }
    winrt::uninit_apartment();
  });
}

// ---------------------------------------------------------------------------
// Thread-safe event stream handler that marshals events to the platform thread
//
// Flutter platform channel messages must be delivered on the platform (UI)
// thread. RFCOMM reads happen on background threads, so we cannot call
// EventSink::Success directly from there. The Flutter Windows platform thread
// runs a Win32 message loop (it has no WinRT DispatcherQueue), so we create a
// message-only window on that thread when the stream is listened to and post a
// drain message to it from background threads. The window procedure runs on the
// platform thread and delivers the queued events safely.
// ---------------------------------------------------------------------------
class BtStreamHandler
    : public flutter::StreamHandler<flutter::EncodableValue> {
 public:
  BtStreamHandler() = default;
  ~BtStreamHandler() override { DestroyMessageWindow(); }

  void Send(const flutter::EncodableValue& value) {
    HWND hwnd = nullptr;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      pending_events_.push_back(value);
      if (!sink_) return;
      hwnd = message_hwnd_;
    }

    if (hwnd) ::PostMessageW(hwnd, kDrainMessage, 0, 0);
  }

 protected:
  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  OnListenInternal(
      const flutter::EncodableValue*,
      std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&&
          events) override {
    // OnListen runs on the platform thread, so create the marshaling window
    // here to give it platform-thread affinity.
    EnsureMessageWindow();
    if (!message_hwnd_) {
      return std::make_unique<flutter::StreamHandlerError<flutter::EncodableValue>>(
          "EVENT_WINDOW_FAILED", "Could not create Bluetooth event window", nullptr);
    }
    {
      std::lock_guard<std::mutex> lock(mutex_);
      sink_ = std::move(events);
    }
    // Drain any events that accumulated before the listener was attached.
    DrainQueue();
    return nullptr;
  }

  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  OnCancelInternal(const flutter::EncodableValue*) override {
    std::lock_guard<std::mutex> lock(mutex_);
    sink_ = nullptr;
    pending_events_.clear();
    return nullptr;
  }

 private:
  static constexpr UINT kDrainMessage = WM_USER + 0x42;

  std::mutex mutex_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink_;
  std::vector<flutter::EncodableValue> pending_events_;
  HWND message_hwnd_ = nullptr;

  void DrainQueue() {
    // Platform-thread-only sink access; never block the Bluetooth reader while
    // delivering a backlog to Flutter.
    std::vector<flutter::EncodableValue> events;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      if (!sink_) return;
      events.swap(pending_events_);
    }
    for (const auto& ev : events) {
      if (!sink_) break;
      try {
        sink_->Success(ev);
      } catch (...) {
        // Ignore errors; sink might be invalidated.
      }
    }
  }

  // Must be called on the platform thread (from OnListen).
  void EnsureMessageWindow() {
    if (message_hwnd_) return;
    static const wchar_t* kClassName = L"HTCommanderBtClassicMsgWindow";
    HINSTANCE instance = ::GetModuleHandleW(nullptr);

    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = &BtStreamHandler::WndProc;
    wc.hInstance = instance;
    wc.lpszClassName = kClassName;
    // Ignore failure if the class is already registered by another handler.
    ::RegisterClassExW(&wc);

    message_hwnd_ = ::CreateWindowExW(
        0, kClassName, L"", 0, 0, 0, 0, 0,
        HWND_MESSAGE, nullptr, instance, this);
  }

  void DestroyMessageWindow() {
    if (message_hwnd_) {
      ::DestroyWindow(message_hwnd_);
      message_hwnd_ = nullptr;
    }
  }

  static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wparam,
                                  LPARAM lparam) {
    if (msg == WM_NCCREATE) {
      auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
      ::SetWindowLongPtrW(hwnd, GWLP_USERDATA,
                          reinterpret_cast<LONG_PTR>(create->lpCreateParams));
      return ::DefWindowProcW(hwnd, msg, wparam, lparam);
    }
    if (msg == kDrainMessage) {
      auto* self = reinterpret_cast<BtStreamHandler*>(
          ::GetWindowLongPtrW(hwnd, GWLP_USERDATA));
      if (self) {
        self->DrainQueue();
      }
      return 0;
    }
    return ::DefWindowProcW(hwnd, msg, wparam, lparam);
  }
};

}  // namespace

// ---------------------------------------------------------------------------
// Pimpl struct
// ---------------------------------------------------------------------------
struct BluetoothClassicPlugin::Impl {
  // Flutter channels.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      method_channel;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>>
      data_event_channel;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>>
      audio_event_channel;

  // Raw (non-owning) pointers to stream handlers — ownership transferred to
  // the event channels via SetStreamHandler.
  BtStreamHandler* data_handler  = nullptr;
  BtStreamHandler* audio_handler = nullptr;

  // Active connections.
  std::mutex conn_mutex;
  std::map<std::string, std::shared_ptr<RfcommConn>> connections;
  std::map<std::string, std::shared_ptr<RfcommConn>> audio_connections;
  std::map<std::string, std::shared_ptr<RadioAudioPlayback>> playback_states;
  std::shared_ptr<NativePcmOutput> output;

  // Set to true during destruction to suppress further event dispatches.
  std::atomic<bool> shutdown{false};

  // -------------------------------------------------------------------------
  Impl(flutter::BinaryMessenger* messenger,
       std::shared_ptr<NativePcmOutput> pcm_output);
  ~Impl();

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Individual handlers — all dispatched to background MTA threads.
  void DoIsAvailable(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void DoGetPairedDevices(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void DoFindCompatibleDevices(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void DoGetDeviceNames(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void DoConnect(
      const std::string& address,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void DoDisconnect(
      const std::string& address,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void DoSend(
      const std::string& address,
      std::vector<uint8_t> data,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void DoConnectAudio(
      const std::string& address,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void DoDisconnectAudio(
      const std::string& address,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void DoSendAudio(
      const std::string& address,
      std::vector<uint8_t> data,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  // BLE pairing for devices that require an authenticated (PIN) bond before
  // exposing their GATT characteristics, e.g. MeshCore companion radios.
  void DoBlePair(
      const std::string& address,
      const std::string& pin,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void DoBleUnpair(
      const std::string& address,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Read loop — runs on a background thread per connection.
  void ReadLoop(std::shared_ptr<RfcommConn> conn, bool is_audio);

  // Thread-safe event dispatch.
  void SendEvent(bool is_audio,
                 const std::string& type,
                 const std::string& address,
                 const std::vector<uint8_t>* data = nullptr);

  // Helper: open an RFCOMM socket for a given service UUID.
  // Returns a fully-connected StreamSocket or throws on failure.
  socks::StreamSocket OpenRfcommSocket(
      uint64_t bt_address,
      std::initializer_list<winrt::guid> service_uuids);

  // Helper: enumerate all paired Classic BT devices. When emit_found is set,
  // each included device is also sent immediately as a "found" event on the
  // control event channel so the UI can list radios as they are identified.
  flutter::EncodableList GetPairedDeviceList(bool compatible_only,
                                             bool emit_found = false);
};

// ---------------------------------------------------------------------------
// Impl constructor / destructor
// ---------------------------------------------------------------------------
BluetoothClassicPlugin::Impl::Impl(flutter::BinaryMessenger* messenger,
    std::shared_ptr<NativePcmOutput> pcm_output) : output(std::move(pcm_output)) {
  using EV = flutter::EncodableValue;

  // Method channel.
  method_channel =
      std::make_unique<flutter::MethodChannel<EV>>(
          messenger,
          "com.htcommander/bluetooth_classic",
          &flutter::StandardMethodCodec::GetInstance());
  method_channel->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });

  // Data event channel.
  auto dh = std::make_unique<BtStreamHandler>();
  data_handler = dh.get();
  data_event_channel =
      std::make_unique<flutter::EventChannel<EV>>(
          messenger,
          "com.htcommander/bluetooth_classic_data",
          &flutter::StandardMethodCodec::GetInstance());
  data_event_channel->SetStreamHandler(std::move(dh));

  // Audio event channel.
  auto ah = std::make_unique<BtStreamHandler>();
  audio_handler = ah.get();
  audio_event_channel =
      std::make_unique<flutter::EventChannel<EV>>(
          messenger,
          "com.htcommander/bluetooth_classic_audio",
          &flutter::StandardMethodCodec::GetInstance());
  audio_event_channel->SetStreamHandler(std::move(ah));
}

BluetoothClassicPlugin::Impl::~Impl() {
  shutdown.store(true);
  std::vector<std::shared_ptr<RfcommConn>> closing_audio;
  std::vector<std::shared_ptr<RfcommConn>> closing_readers;
  // Close all sockets — this unblocks any pending LoadAsync in the read loops.
  {
    std::lock_guard<std::mutex> lock(conn_mutex);
    for (auto& [addr, conn] : connections) {
      conn->running.store(false);
      try { conn->socket.Close(); } catch (...) {}
      closing_readers.push_back(conn);
    }
    for (auto& [addr, conn] : audio_connections) {
      conn->running.store(false);
      conn->audio_wake.notify_all();
      try { conn->socket.Close(); } catch (...) {}
      closing_audio.push_back(conn);
      closing_readers.push_back(conn);
    }
    connections.clear();
    audio_connections.clear();
  }
  // Pending job replies must finish while the plugin messenger still exists.
  for (const auto& conn : closing_audio) {
    if (conn->audio_thread.joinable()) conn->audio_thread.join();
  }
  for (const auto& conn : closing_readers) {
    if (conn->read_thread.joinable()) conn->read_thread.join();
  }
}

// ---------------------------------------------------------------------------
// Method call dispatcher
// ---------------------------------------------------------------------------
void BluetoothClassicPlugin::Impl::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

  const auto& method = call.method_name();

  auto GetArg = [&](const char* key) -> const flutter::EncodableValue* {
    const auto* args =
        std::get_if<flutter::EncodableMap>(call.arguments());
    if (!args) return nullptr;
    auto it = args->find(flutter::EncodableValue(std::string(key)));
    return it != args->end() ? &it->second : nullptr;
  };

  if (method == "isAvailable") {
    DoIsAvailable(std::move(result));
  } else if (method == "getPairedDevices") {
    DoGetPairedDevices(std::move(result));
  } else if (method == "findCompatibleDevices") {
    DoFindCompatibleDevices(std::move(result));
  } else if (method == "getDeviceNames") {
    DoGetDeviceNames(std::move(result));
  } else if (method == "connect") {
    auto* addr = GetArg("address");
    if (!addr) { result->Error("INVALID_ARGS", "Missing address"); return; }
    DoConnect(std::get<std::string>(*addr), std::move(result));
  } else if (method == "disconnect") {
    auto* addr = GetArg("address");
    if (!addr) { result->Error("INVALID_ARGS", "Missing address"); return; }
    DoDisconnect(std::get<std::string>(*addr), std::move(result));
  } else if (method == "send") {
    auto* addr = GetArg("address");
    auto* data = GetArg("data");
    if (!addr || !data) {
      result->Error("INVALID_ARGS", "Missing address or data"); return;
    }
    DoSend(std::get<std::string>(*addr),
           std::get<std::vector<uint8_t>>(*data),
           std::move(result));
  } else if (method == "connectAudio") {
    auto* addr = GetArg("address");
    if (!addr) { result->Error("INVALID_ARGS", "Missing address"); return; }
    DoConnectAudio(std::get<std::string>(*addr), std::move(result));
  } else if (method == "disconnectAudio") {
    auto* addr = GetArg("address");
    if (!addr) { result->Error("INVALID_ARGS", "Missing address"); return; }
    DoDisconnectAudio(std::get<std::string>(*addr), std::move(result));
  } else if (method == "sendAudio") {
    auto* addr = GetArg("address");
    auto* data = GetArg("data");
    if (!addr || !data) {
      result->Error("INVALID_ARGS", "Missing address or data"); return;
    }
    DoSendAudio(std::get<std::string>(*addr),
                std::get<std::vector<uint8_t>>(*data),
                std::move(result));
  } else if (method == "configureNativeAudioPlayback" ||
             method == "getNativeAudioPlaybackStats") {
    auto* addr = GetArg("address");
    if (!addr || !std::holds_alternative<std::string>(*addr)) {
      result->Error("INVALID_ARGS", "Missing audio address");
      return;
    }
    const auto& address = std::get<std::string>(*addr);
    std::lock_guard<std::mutex> lock(conn_mutex);
    auto it = playback_states.find(address);
    if (method == "getNativeAudioPlaybackStats") {
      if (it == playback_states.end()) {
        result->Error("NOT_CONFIGURED", "Native playback is not configured");
        return;
      }
      const auto stats = it->second->stats();
      flutter::EncodableMap values;
      values[flutter::EncodableValue("packets")] = flutter::EncodableValue(stats.packets);
      values[flutter::EncodableValue("decodedSamples")] = flutter::EncodableValue(stats.decoded_samples);
      values[flutter::EncodableValue("queuedSamples")] = flutter::EncodableValue(stats.queued_samples);
      values[flutter::EncodableValue("droppedSamples")] = flutter::EncodableValue(stats.dropped_samples);
      values[flutter::EncodableValue("decodeErrors")] = flutter::EncodableValue(stats.decode_errors);
      values[flutter::EncodableValue("lastError")] = flutter::EncodableValue(stats.last_error);
      values[flutter::EncodableValue("bufferedFrames")] = flutter::EncodableValue(output->buffered_frames());
      values[flutter::EncodableValue("outputUnderruns")] = flutter::EncodableValue(
          static_cast<int64_t>(output->underrun_count()));
      values[flutter::EncodableValue("outputOverflows")] = flutter::EncodableValue(
          static_cast<int64_t>(output->overflow_count()));
      values[flutter::EncodableValue("outputErrors")] = flutter::EncodableValue(
          static_cast<int64_t>(output->error_count()));
      const auto output_stats = output->stats();
      values[flutter::EncodableValue("bufferedMs")] = flutter::EncodableValue(output_stats.buffered_ms);
      values[flutter::EncodableValue("peakBufferedMs")] = flutter::EncodableValue(output_stats.peak_buffered_ms);
      values[flutter::EncodableValue("outputCatchups")] = flutter::EncodableValue(
          static_cast<int64_t>(output_stats.catchups));
      values[flutter::EncodableValue("outputDiscardedFrames")] = flutter::EncodableValue(
          static_cast<int64_t>(output_stats.discarded_frames));
      result->Success(flutter::EncodableValue(values));
      return;
    }
    RadioAudioPlayback::Controls controls;
    auto boolean = [&](const char* key, bool& value) {
      const auto* arg = GetArg(key);
      if (!arg || !std::holds_alternative<bool>(*arg)) return false;
      value = std::get<bool>(*arg);
      return true;
    };
    const auto* volume = GetArg("volume");
    if (!boolean("enabled", controls.enabled) ||
        !boolean("audible", controls.audible) ||
        !boolean("muted", controls.muted) ||
        !volume || !std::holds_alternative<double>(*volume) ||
        !std::isfinite(std::get<double>(*volume)) ||
        std::get<double>(*volume) < 0) {
      result->Error("INVALID_ARGS", "Invalid native playback controls");
      return;
    }
    controls.volume = std::get<double>(*volume);
    try {
      if (it == playback_states.end()) {
        auto sink = output;
        auto state = std::make_shared<RadioAudioPlayback>(
            [sink](const int16_t* pcm, size_t count) {
              return sink->FeedRadio(pcm, count);
            },
            [](const std::string& error) {
              OutputDebugStringA(("[NativeRadioPlayback] " + error + "\n").c_str());
            });
        it = playback_states.emplace(address, std::move(state)).first;
      }
      it->second->Configure(controls);
    } catch (const std::exception& error) {
      result->Error("NATIVE_PLAYBACK_FAILED", error.what());
      return;
    }
    result->Success(flutter::EncodableValue(true));
  } else if (method == "sendPreparedAudio" ||
             method == "cancelPreparedAudio") {
    auto* addr = GetArg("address");
    auto integer = [](const flutter::EncodableValue* value,
                      int64_t* out) {
      if (!value) return false;
      if (const auto* n = std::get_if<int64_t>(value)) {
        *out = *n;
        return true;
      }
      if (const auto* n = std::get_if<int32_t>(value)) {
        *out = *n;
        return true;
      }
      return false;
    };
    int64_t id;
    if (!addr || !std::holds_alternative<std::string>(*addr) ||
        !integer(GetArg("jobId"), &id) || id <= 0) {
      result->Error("INVALID_ARGS", "Missing address or positive jobId");
      return;
    }
    std::shared_ptr<RfcommConn> conn;
    {
      std::lock_guard<std::mutex> lock(conn_mutex);
      auto it = audio_connections.find(std::get<std::string>(*addr));
      if (it != audio_connections.end()) conn = it->second;
    }
    if (method == "cancelPreparedAudio") {
      bool cancelled = false;
      if (conn) {
        std::lock_guard<std::mutex> lock(conn->audio_mutex);
        if (conn->audio_job && conn->audio_job->id == id) {
          conn->audio_job->cancelled.store(true);
          cancelled = true;
        }
        conn->audio_wake.notify_all();
      }
      result->Success(flutter::EncodableValue(cancelled));
      return;
    }
    auto* data_arg = GetArg("data");
    auto* lengths_arg = GetArg("lengths");
    auto* samples_arg = GetArg("samples");
    int64_t lead;
    if (!data_arg || !lengths_arg || !samples_arg ||
        !std::holds_alternative<std::vector<uint8_t>>(*data_arg) ||
        !std::holds_alternative<std::vector<int32_t>>(*lengths_arg) ||
        !std::holds_alternative<std::vector<int32_t>>(*samples_arg) ||
        !integer(GetArg("leadMs"), &lead) || lead < 0 || lead > 10000) {
      result->Error("INVALID_ARGS", "Invalid prepared audio payload");
      return;
    }
    const auto& data = std::get<std::vector<uint8_t>>(*data_arg);
    const auto& lengths = std::get<std::vector<int32_t>>(*lengths_arg);
    const auto& samples = std::get<std::vector<int32_t>>(*samples_arg);
    bool valid = !data.empty() && data.size() <= 16 * 1024 * 1024 &&
        !lengths.empty() && lengths.size() <= 200000 &&
        lengths.size() == samples.size();
    size_t total = 0;
    if (valid) {
      for (size_t i = 0; i < lengths.size(); ++i) {
        if (lengths[i] <= 0 || lengths[i] > 4096 ||
            samples[i] <= 0 || samples[i] > 3072 ||
            samples[i] % 128 != 0) {
          valid = false;
          break;
        }
        total += lengths[i];
      }
    }
    if (!valid || total != data.size()) {
      result->Error("INVALID_ARGS", "Invalid prepared audio batch sizes");
      return;
    }
    if (!conn || !conn->running.load()) {
      result->Error("NOT_CONNECTED", "Bluetooth audio is not connected");
      return;
    }
    {
      std::lock_guard<std::mutex> lock(conn->audio_mutex);
      if (!conn->running.load()) {
        result->Error("NOT_CONNECTED", "Bluetooth audio connection closed");
        return;
      }
      if (conn->audio_job) {
        result->Error("AUDIO_TX_BUSY", "A prepared audio job is active");
        return;
      }
      auto job = std::make_shared<PreparedAudioJob>();
      job->id = id;
      job->data = data;
      job->lengths = lengths;
      job->samples = samples;
      job->lead_ms = static_cast<int>(lead);
      job->result = std::move(result);
      conn->audio_job = std::move(job);
    }
    conn->audio_wake.notify_all();
  } else if (method == "blePair") {
    auto* addr = GetArg("address");
    auto* pin = GetArg("pin");
    if (!addr) { result->Error("INVALID_ARGS", "Missing address"); return; }
    std::string pin_str;
    if (pin) {
      if (const auto* s = std::get_if<std::string>(pin)) pin_str = *s;
    }
    DoBlePair(std::get<std::string>(*addr), pin_str, std::move(result));
  } else if (method == "bleUnpair") {
    auto* addr = GetArg("address");
    if (!addr) { result->Error("INVALID_ARGS", "Missing address"); return; }
    DoBleUnpair(std::get<std::string>(*addr), std::move(result));
  } else {
    result->NotImplemented();
  }
}

// ---------------------------------------------------------------------------
// SendEvent — thread-safe dispatch through an EventChannel sink
// ---------------------------------------------------------------------------
void BluetoothClassicPlugin::Impl::SendEvent(
    bool is_audio,
    const std::string& type,
    const std::string& address,
    const std::vector<uint8_t>* data) {

  if (shutdown.load()) return;

  flutter::EncodableMap event;
  event[flutter::EncodableValue("event")]   = flutter::EncodableValue(type);
  event[flutter::EncodableValue("address")] = flutter::EncodableValue(address);
  if (data) {
    event[flutter::EncodableValue("data")] = flutter::EncodableValue(*data);
  }
  auto ev = flutter::EncodableValue(std::move(event));
  if (is_audio) {
    if (audio_handler) audio_handler->Send(ev);
  } else {
    if (data_handler) data_handler->Send(ev);
  }
}

// ---------------------------------------------------------------------------
// OpenRfcommSocket helper
// Tries each UUID in order; returns the first successfully connected socket.
// ---------------------------------------------------------------------------
socks::StreamSocket
BluetoothClassicPlugin::Impl::OpenRfcommSocket(
    uint64_t bt_address,
    std::initializer_list<winrt::guid> service_uuids) {

  auto btDevice = bt::BluetoothDevice::FromBluetoothAddressAsync(bt_address)
                      .get();
  if (!btDevice) {
    throw winrt::hresult_error(E_FAIL, L"Device not found");
  }

  rfcomm::RfcommDeviceService service{nullptr};

  for (const auto& uuid : service_uuids) {
    try {
      auto res = btDevice.GetRfcommServicesForIdAsync(
                              rfcomm::RfcommServiceId::FromUuid(uuid),
                              bt::BluetoothCacheMode::Uncached)
                     .get();
      if (res.Error() == bt::BluetoothError::Success &&
          res.Services().Size() > 0) {
        service = res.Services().GetAt(0);
        break;
      }
    } catch (...) {}
  }

  if (!service) {
    // Last resort: first available RFCOMM service.
    auto res = btDevice.GetRfcommServicesAsync(bt::BluetoothCacheMode::Uncached)
                   .get();
    if (res.Error() != bt::BluetoothError::Success ||
        res.Services().Size() == 0) {
      throw winrt::hresult_error(E_FAIL, L"No RFCOMM services found");
    }
    service = res.Services().GetAt(0);
  }

  socks::StreamSocket sock;
  sock.ConnectAsync(
          service.ConnectionHostName(),
          service.ConnectionServiceName(),
          socks::SocketProtectionLevel::
              BluetoothEncryptionAllowNullAuthentication)
      .get();
  return sock;
}

// ---------------------------------------------------------------------------
// GetPairedDeviceList helper
// ---------------------------------------------------------------------------
flutter::EncodableList
BluetoothClassicPlugin::Impl::GetPairedDeviceList(bool compatible_only,
                                                  bool emit_found) {
  flutter::EncodableList list;
  try {
    auto selector =
        bt::BluetoothDevice::GetDeviceSelectorFromPairingState(true);
    auto devices = denum::DeviceInformation::FindAllAsync(selector).get();

    for (const auto& di : devices) {
      try {
        auto btDev = bt::BluetoothDevice::FromIdAsync(di.Id()).get();
        if (!btDev) continue;

        // Identify radios by their unique vendor SDP service UUID ("BS AOC")
        // rather than by name, which changes across rebrands / OS stacks.
        flutter::EncodableList service_uuids;
        try {
          auto res = btDev.GetRfcommServicesForIdAsync(
                              rfcomm::RfcommServiceId::FromUuid(kBsAocUuid),
                              bt::BluetoothCacheMode::Cached)
                         .get();
          if (res.Error() == bt::BluetoothError::Success &&
              res.Services().Size() > 0) {
            service_uuids.push_back(flutter::EncodableValue(
                std::string("39144315-32fa-40db-85ed-fbfeba2d86e6")));
          }
        } catch (...) {}

        if (compatible_only && service_uuids.empty()) continue;

        std::string name    = HstrToStr(btDev.Name());
        std::string address = FormatMac(btDev.BluetoothAddress());

        flutter::EncodableMap dev;
        dev[flutter::EncodableValue("name")]        = flutter::EncodableValue(name);
        dev[flutter::EncodableValue("address")]     = flutter::EncodableValue(address);
        dev[flutter::EncodableValue("isPaired")]    = flutter::EncodableValue(true);
        dev[flutter::EncodableValue("isConnected")] = flutter::EncodableValue(false);
        dev[flutter::EncodableValue("serviceUuids")] =
            flutter::EncodableValue(std::move(service_uuids));

        if (emit_found && !shutdown.load() && data_handler) {
          flutter::EncodableMap ev = dev;
          ev[flutter::EncodableValue("event")] =
              flutter::EncodableValue(std::string("found"));
          data_handler->Send(flutter::EncodableValue(std::move(ev)));
        }

        list.push_back(flutter::EncodableValue(std::move(dev)));
      } catch (...) {}
    }
  } catch (...) {}
  return list;
}

// ---------------------------------------------------------------------------
// Read loop — runs on a background thread
// ---------------------------------------------------------------------------
void BluetoothClassicPlugin::Impl::ReadLoop(
    std::shared_ptr<RfcommConn> conn, bool is_audio) {
  winrt::init_apartment(winrt::apartment_type::multi_threaded);

  while (conn->running.load()) {
    try {
      uint32_t bytes = conn->reader.LoadAsync(4096).get();
      if (bytes == 0) break;  // Remote end closed the connection.

      uint32_t available = conn->reader.UnconsumedBufferLength();
      std::vector<uint8_t> buf(available);
      conn->reader.ReadBytes(buf);

      if (is_audio && conn->playback) {
        conn->playback->Receive(buf.data(), buf.size());
      }
      SendEvent(is_audio, "data", conn->address, &buf);
    } catch (...) {
      break;  // Socket closed or error.
    }
  }

  // If we exited unexpectedly (i.e., not because the caller set running=false),
  // send a disconnected event and remove from the map.
  bool was_running = conn->running.exchange(false);
  conn->audio_wake.notify_all();
  if (was_running) {
    SendEvent(is_audio, "disconnected", conn->address);
    std::lock_guard<std::mutex> lock(conn_mutex);
    auto& map = is_audio ? audio_connections : connections;
    auto it = map.find(conn->address);
    if (it != map.end() && it->second.get() == conn.get()) {
      map.erase(it);
    }
  }

  winrt::uninit_apartment();
}

// ---------------------------------------------------------------------------
// Method implementations
// ---------------------------------------------------------------------------

void BluetoothClassicPlugin::Impl::DoIsAvailable(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  auto res = std::shared_ptr<
      flutter::MethodResult<flutter::EncodableValue>>(std::move(result));

  std::thread([res]() {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    try {
      auto adapter = bt::BluetoothAdapter::GetDefaultAsync().get();
      if (!adapter) {
        res->Success(flutter::EncodableValue(false));
        winrt::uninit_apartment();
        return;
      }
      auto radio = adapter.GetRadioAsync().get();
      bool on = radio &&
                radio.State() == radios::RadioState::On;
      res->Success(flutter::EncodableValue(on));
    } catch (...) {
      res->Success(flutter::EncodableValue(false));
    }
    winrt::uninit_apartment();
  }).detach();
}

void BluetoothClassicPlugin::Impl::DoGetPairedDevices(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  auto res = std::shared_ptr<
      flutter::MethodResult<flutter::EncodableValue>>(std::move(result));
  auto self = this;

  std::thread([res, self]() {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    res->Success(flutter::EncodableValue(self->GetPairedDeviceList(false)));
    winrt::uninit_apartment();
  }).detach();
}

void BluetoothClassicPlugin::Impl::DoFindCompatibleDevices(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  auto res = std::shared_ptr<
      flutter::MethodResult<flutter::EncodableValue>>(std::move(result));
  auto self = this;

  std::thread([res, self]() {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    res->Success(flutter::EncodableValue(self->GetPairedDeviceList(true, true)));
    winrt::uninit_apartment();
  }).detach();
}

void BluetoothClassicPlugin::Impl::DoGetDeviceNames(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  auto res = std::shared_ptr<
      flutter::MethodResult<flutter::EncodableValue>>(std::move(result));
  auto self = this;

  std::thread([res, self]() {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    auto list = self->GetPairedDeviceList(false);
    flutter::EncodableList names;
    for (const auto& item : list) {
      const auto& m = std::get<flutter::EncodableMap>(item);
      auto it = m.find(flutter::EncodableValue("name"));
      if (it != m.end()) names.push_back(it->second);
    }
    res->Success(flutter::EncodableValue(std::move(names)));
    winrt::uninit_apartment();
  }).detach();
}

void BluetoothClassicPlugin::Impl::DoConnect(
    const std::string& address,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  {
    std::lock_guard<std::mutex> lock(conn_mutex);
    if (connections.count(address)) {
      result->Success(flutter::EncodableValue(true));
      return;
    }
  }

  auto res = std::shared_ptr<
      flutter::MethodResult<flutter::EncodableValue>>(std::move(result));
  auto self = this;

  std::thread([self, address, res]() {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    try {
      uint64_t btAddr = ParseMac(address);
      auto sock = self->OpenRfcommSocket(btAddr, {kSppUuid});

      auto conn       = std::make_shared<RfcommConn>();
      conn->address   = address;
      conn->socket    = sock;
      conn->reader    = strs::DataReader(sock.InputStream());
      conn->reader.InputStreamOptions(strs::InputStreamOptions::Partial);
      conn->writer    = strs::DataWriter(sock.OutputStream());
      conn->running.store(true);

      {
        std::lock_guard<std::mutex> lock(self->conn_mutex);
        self->connections[address] = conn;
      }

      // Start read loop on its own thread.
      conn->read_thread = std::thread([self, conn]() {
        self->ReadLoop(conn, false);
      });

      self->SendEvent(false, "connected", address);
      res->Success(flutter::EncodableValue(true));
    } catch (...) {
      res->Success(flutter::EncodableValue(false));
    }
    winrt::uninit_apartment();
  }).detach();
}

void BluetoothClassicPlugin::Impl::DoDisconnect(
    const std::string& address,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  std::shared_ptr<RfcommConn> conn;
  {
    std::lock_guard<std::mutex> lock(conn_mutex);
    auto it = connections.find(address);
    if (it != connections.end()) {
      conn = it->second;
      connections.erase(it);
    }
  }
  if (conn) {
    conn->running.store(false);
    try { conn->socket.Close(); } catch (...) {}
    if (conn->read_thread.joinable()) conn->read_thread.detach();
    SendEvent(false, "disconnected", address);
  }
  result->Success(flutter::EncodableValue(true));
}

void BluetoothClassicPlugin::Impl::DoSend(
    const std::string& address,
    std::vector<uint8_t> data,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  std::shared_ptr<RfcommConn> conn;
  {
    std::lock_guard<std::mutex> lock(conn_mutex);
    auto it = connections.find(address);
    if (it != connections.end()) conn = it->second;
  }
  if (!conn || !conn->running.load()) {
    result->Success(flutter::EncodableValue(false));
    return;
  }

  auto res = std::shared_ptr<
      flutter::MethodResult<flutter::EncodableValue>>(std::move(result));

  std::thread([conn, data = std::move(data), res]() {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    try {
      std::lock_guard<std::mutex> write_lock(conn->write_mutex);
      conn->writer.WriteBytes(data);
      conn->writer.StoreAsync().get();
      res->Success(flutter::EncodableValue(true));
    } catch (...) {
      res->Success(flutter::EncodableValue(false));
    }
    winrt::uninit_apartment();
  }).detach();
}

void BluetoothClassicPlugin::Impl::DoConnectAudio(
    const std::string& address,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  {
    std::lock_guard<std::mutex> lock(conn_mutex);
    if (audio_connections.count(address)) {
      result->Success(flutter::EncodableValue(true));
      return;
    }
  }

  auto res = std::shared_ptr<
      flutter::MethodResult<flutter::EncodableValue>>(std::move(result));
  auto self = this;

  std::thread([self, address, res]() {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    try {
      uint64_t btAddr = ParseMac(address);
      // Try BS AOC vendor UUID first, fall back to Generic Audio.
      auto sock = self->OpenRfcommSocket(btAddr,
                                         {kBsAocUuid, kGenericAudioUuid});

      auto conn       = std::make_shared<RfcommConn>();
      conn->address   = address;
      conn->socket    = sock;
      conn->reader    = strs::DataReader(sock.InputStream());
      conn->reader.InputStreamOptions(strs::InputStreamOptions::Partial);
      conn->writer    = strs::DataWriter(sock.OutputStream());
      conn->running.store(true);

      StartAudioWriter(conn);
      {
        std::lock_guard<std::mutex> lock(self->conn_mutex);
        const auto playback = self->playback_states.find(address);
        if (playback != self->playback_states.end()) {
          conn->playback = playback->second;
        }
        self->audio_connections[address] = conn;
      }

      conn->read_thread = std::thread([self, conn]() {
        self->ReadLoop(conn, true);
      });

      self->SendEvent(true, "connected", address);
      res->Success(flutter::EncodableValue(true));
    } catch (...) {
      res->Success(flutter::EncodableValue(false));
    }
    winrt::uninit_apartment();
  }).detach();
}

void BluetoothClassicPlugin::Impl::DoDisconnectAudio(
    const std::string& address,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  std::shared_ptr<RfcommConn> conn;
  {
    std::lock_guard<std::mutex> lock(conn_mutex);
    auto it = audio_connections.find(address);
    if (it != audio_connections.end()) {
      conn = it->second;
      audio_connections.erase(it);
    }
  }
  if (conn) {
    conn->running.store(false);
    conn->audio_wake.notify_all();
    try { conn->socket.Close(); } catch (...) {}
    if (conn->read_thread.joinable()) conn->read_thread.join();
    SendEvent(true, "disconnected", address);
  }
  result->Success(flutter::EncodableValue(true));
}

void BluetoothClassicPlugin::Impl::DoSendAudio(
    const std::string& address,
    std::vector<uint8_t> data,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  std::shared_ptr<RfcommConn> conn;
  {
    std::lock_guard<std::mutex> lock(conn_mutex);
    auto it = audio_connections.find(address);
    if (it != audio_connections.end()) conn = it->second;
  }
  if (!conn || !conn->running.load()) {
    result->Success(flutter::EncodableValue(false));
    return;
  }

  {
    std::lock_guard<std::mutex> lock(conn->audio_mutex);
    if (conn->audio_job) {
      result->Error("AUDIO_TX_BUSY", "A prepared audio job owns the audio writer");
      return;
    }
  }
  auto res = std::shared_ptr<
      flutter::MethodResult<flutter::EncodableValue>>(std::move(result));

  std::thread([conn, data = std::move(data), res]() {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    try {
      std::lock_guard<std::mutex> write_lock(conn->write_mutex);
      {
        std::lock_guard<std::mutex> lock(conn->audio_mutex);
        if (conn->audio_job) {
          res->Error("AUDIO_TX_BUSY", "A prepared audio job owns the audio writer");
          winrt::uninit_apartment();
          return;
        }
      }
      if (conn->playback && data.size() > 1 && data[0] == 0x7e &&
          data[1] == 0) conn->playback->SetTransmitting(true);
      conn->writer.WriteBytes(data);
      conn->writer.StoreAsync().get();
      if (conn->playback && data.size() > 1 && data[0] == 0x7e &&
          data[1] == 1) conn->playback->SetTransmitting(false);
      res->Success(flutter::EncodableValue(true));
    } catch (...) {
      if (conn->playback) conn->playback->SetTransmitting(false);
      res->Success(flutter::EncodableValue(false));
    }
    winrt::uninit_apartment();
  }).detach();
}

// Pairs with a BLE device using a caller-supplied PIN. Returns a status string:
// "paired", "alreadyPaired", "notFound", "cannotPair", "authFailed",
// "failed:<DevicePairingResultStatus>" or "error".
void BluetoothClassicPlugin::Impl::DoBlePair(
    const std::string& address,
    const std::string& pin,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  auto res = std::shared_ptr<
      flutter::MethodResult<flutter::EncodableValue>>(std::move(result));

  std::thread([address, pin, res]() {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    std::string status = "error";
    try {
      auto device =
          bt::BluetoothLEDevice::FromBluetoothAddressAsync(ParseMac(address))
              .get();
      if (!device) {
        status = "notFound";
      } else {
        auto pairing = device.DeviceInformation().Pairing();
        if (pairing.IsPaired()) {
          status = "alreadyPaired";
        } else if (!pairing.CanPair()) {
          status = "cannotPair";
        } else {
          auto custom = pairing.Custom();
          const winrt::hstring hpin = winrt::to_hstring(pin);
          auto token = custom.PairingRequested(
              [hpin](const denum::DeviceInformationCustomPairing&,
                     const denum::DevicePairingRequestedEventArgs& args) {
                if (args.PairingKind() ==
                    denum::DevicePairingKinds::ProvidePin) {
                  args.Accept(hpin);
                } else {
                  args.Accept();
                }
              });
          const auto kinds = denum::DevicePairingKinds::ConfirmOnly |
                             denum::DevicePairingKinds::ProvidePin |
                             denum::DevicePairingKinds::ConfirmPinMatch |
                             denum::DevicePairingKinds::DisplayPin;
          auto pair_result =
              custom
                  .PairAsync(kinds, denum::DevicePairingProtectionLevel::
                                        EncryptionAndAuthentication)
                  .get();
          custom.PairingRequested(token);
          switch (pair_result.Status()) {
            case denum::DevicePairingResultStatus::Paired:
              status = "paired";
              break;
            case denum::DevicePairingResultStatus::AlreadyPaired:
              status = "alreadyPaired";
              break;
            case denum::DevicePairingResultStatus::AuthenticationFailure:
            case denum::DevicePairingResultStatus::AuthenticationTimeout:
            case denum::DevicePairingResultStatus::RejectedByHandler:
              status = "authFailed";
              break;
            default:
              status = "failed:" +
                       std::to_string(static_cast<int>(pair_result.Status()));
              break;
          }
        }
      }
    } catch (...) {
      status = "error";
    }
    res->Success(flutter::EncodableValue(status));
    winrt::uninit_apartment();
  }).detach();
}

void BluetoothClassicPlugin::Impl::DoBleUnpair(
    const std::string& address,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  auto res = std::shared_ptr<
      flutter::MethodResult<flutter::EncodableValue>>(std::move(result));

  std::thread([address, res]() {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    bool ok = false;
    try {
      auto device =
          bt::BluetoothLEDevice::FromBluetoothAddressAsync(ParseMac(address))
              .get();
      if (device) {
        auto r = device.DeviceInformation().Pairing().UnpairAsync().get();
        ok = r.Status() == denum::DeviceUnpairingResultStatus::Unpaired ||
             r.Status() == denum::DeviceUnpairingResultStatus::AlreadyUnpaired;
      }
    } catch (...) {}
    res->Success(flutter::EncodableValue(ok));
    winrt::uninit_apartment();
  }).detach();
}

// ---------------------------------------------------------------------------
// BluetoothClassicPlugin outer class — just delegates to Impl
// ---------------------------------------------------------------------------
BluetoothClassicPlugin::BluetoothClassicPlugin(
    flutter::BinaryMessenger* messenger, std::shared_ptr<NativePcmOutput> output)
    : impl_(std::make_unique<Impl>(messenger, std::move(output))) {}

BluetoothClassicPlugin::~BluetoothClassicPlugin() = default;
