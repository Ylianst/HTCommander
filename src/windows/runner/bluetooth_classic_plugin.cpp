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
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>
#include <algorithm>

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

// Known radio name patterns (same list as macOS / Dart side).
const wchar_t* kCompatibleNames[] = {
    L"UV-PRO", L"UV-50PRO", L"GA-5WB", L"VR-N75", L"VR-N76",
    L"VR-N7500", L"VR-N7600", L"DB50-B", L"WP-C1", L"HT-CH1",
    L"QUANSHENG", L"VR-N", L"SA-888S", L"HG-UV98", L"UV-98",
    L"HAM-AIO", L"VR-6600PRO", L"TH-UV88", L"3B01B", L"E1WPR",
    L"PNI-HP98WP",
};

bool IsCompatibleDevice(std::wstring_view name) {
  std::wstring upper(name);
  std::transform(upper.begin(), upper.end(), upper.begin(), ::towupper);
  for (auto* pattern : kCompatibleNames) {
    if (upper.find(pattern) != std::wstring::npos) return true;
  }
  return false;
}

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
struct RfcommConn {
  socks::StreamSocket socket{nullptr};
  strs::DataReader    reader{nullptr};
  strs::DataWriter    writer{nullptr};
  std::string         address;
  std::atomic<bool>   running{false};
  std::thread         read_thread;
  std::mutex          write_mutex;

  RfcommConn() = default;
  ~RfcommConn() {
    running.store(false);
    try {
      if (socket) socket.Close();
    } catch (...) {}
    if (read_thread.joinable()) read_thread.detach();
  }
  RfcommConn(const RfcommConn&) = delete;
  RfcommConn& operator=(const RfcommConn&) = delete;
};

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

    if (hwnd) {
      // Marshal the drain onto the platform thread via its message loop.
      ::PostMessageW(hwnd, kDrainMessage, 0, 0);
    } else {
      // No marshaling window yet; deliver inline (we are on the platform
      // thread during OnListen, which is the only time this happens).
      std::lock_guard<std::mutex> lock(mutex_);
      DrainQueue();
    }
  }

 protected:
  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  OnListenInternal(
      const flutter::EncodableValue*,
      std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&&
          events) override {
    std::lock_guard<std::mutex> lock(mutex_);
    sink_ = std::move(events);

    // OnListen runs on the platform thread, so create the marshaling window
    // here to give it platform-thread affinity.
    EnsureMessageWindow();

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
    // Must be called under mutex_ lock and on the platform thread.
    if (!sink_ || pending_events_.empty()) return;
    auto events = std::move(pending_events_);
    for (const auto& ev : events) {
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
        std::lock_guard<std::mutex> lock(self->mutex_);
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

  // Set to true during destruction to suppress further event dispatches.
  std::atomic<bool> shutdown{false};

  // -------------------------------------------------------------------------
  explicit Impl(flutter::BinaryMessenger* messenger);
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

  // Helper: enumerate all paired Classic BT devices.
  flutter::EncodableList GetPairedDeviceList(bool compatible_only);
};

// ---------------------------------------------------------------------------
// Impl constructor / destructor
// ---------------------------------------------------------------------------
BluetoothClassicPlugin::Impl::Impl(flutter::BinaryMessenger* messenger) {
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
  // Close all sockets — this unblocks any pending LoadAsync in the read loops.
  {
    std::lock_guard<std::mutex> lock(conn_mutex);
    for (auto& [addr, conn] : connections) {
      conn->running.store(false);
      try { conn->socket.Close(); } catch (...) {}
    }
    for (auto& [addr, conn] : audio_connections) {
      conn->running.store(false);
      try { conn->socket.Close(); } catch (...) {}
    }
    connections.clear();
    audio_connections.clear();
  }
  // Brief pause so read-loop threads can finish and stop referencing our
  // members before the event-channel destructors run.
  std::this_thread::sleep_for(std::chrono::milliseconds(100));
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
BluetoothClassicPlugin::Impl::GetPairedDeviceList(bool compatible_only) {
  flutter::EncodableList list;
  try {
    auto selector =
        bt::BluetoothDevice::GetDeviceSelectorFromPairingState(true);
    auto devices = denum::DeviceInformation::FindAllAsync(selector).get();

    for (const auto& di : devices) {
      try {
        auto btDev = bt::BluetoothDevice::FromIdAsync(di.Id()).get();
        if (!btDev) continue;

        std::wstring wname{btDev.Name()};
        if (compatible_only && !IsCompatibleDevice(wname)) continue;

        std::string name    = HstrToStr(btDev.Name());
        std::string address = FormatMac(btDev.BluetoothAddress());

        flutter::EncodableMap dev;
        dev[flutter::EncodableValue("name")]        = flutter::EncodableValue(name);
        dev[flutter::EncodableValue("address")]     = flutter::EncodableValue(address);
        dev[flutter::EncodableValue("isPaired")]    = flutter::EncodableValue(true);
        dev[flutter::EncodableValue("isConnected")] = flutter::EncodableValue(false);
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

      SendEvent(is_audio, "data", conn->address, &buf);
    } catch (...) {
      break;  // Socket closed or error.
    }
  }

  // If we exited unexpectedly (i.e., not because the caller set running=false),
  // send a disconnected event and remove from the map.
  bool was_running = conn->running.exchange(false);
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
    res->Success(flutter::EncodableValue(self->GetPairedDeviceList(true)));
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

      {
        std::lock_guard<std::mutex> lock(self->conn_mutex);
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
    try { conn->socket.Close(); } catch (...) {}
    if (conn->read_thread.joinable()) conn->read_thread.detach();
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

// ---------------------------------------------------------------------------
// BluetoothClassicPlugin outer class — just delegates to Impl
// ---------------------------------------------------------------------------
BluetoothClassicPlugin::BluetoothClassicPlugin(
    flutter::BinaryMessenger* messenger)
    : impl_(std::make_unique<Impl>(messenger)) {}

BluetoothClassicPlugin::~BluetoothClassicPlugin() = default;
