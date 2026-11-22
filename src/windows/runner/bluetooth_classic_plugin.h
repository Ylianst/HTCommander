#pragma once
// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0

#include <memory>

// Forward declarations only — no WinRT or Flutter headers needed here.
namespace flutter {
class BinaryMessenger;
}
class NativePcmOutput;

/// Native Windows Bluetooth Classic (RFCOMM) plugin.
///
/// Mirrors the macOS BluetoothClassicHandler (IOBluetooth / Swift) so that the
/// Dart-side BluetoothClassicMacOS wrapper works unchanged on Windows.
///
/// Registers three channels:
///   - MethodChannel   com.htcommander/bluetooth_classic
///   - EventChannel    com.htcommander/bluetooth_classic_data
///   - EventChannel    com.htcommander/bluetooth_classic_audio
/// Background operations (including retired connection readers and replies)
/// are cancelled/joined before channels or their messenger can be destroyed.
class BluetoothClassicPlugin {
 public:
  BluetoothClassicPlugin(flutter::BinaryMessenger* messenger,
                         std::shared_ptr<NativePcmOutput> output);
  ~BluetoothClassicPlugin();

  BluetoothClassicPlugin(const BluetoothClassicPlugin&) = delete;
  BluetoothClassicPlugin& operator=(const BluetoothClassicPlugin&) = delete;

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
