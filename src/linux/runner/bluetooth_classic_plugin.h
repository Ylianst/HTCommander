// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
//
// Native Linux Bluetooth Classic (RFCOMM / Serial Port Profile) plugin.
//
// Implements the same MethodChannel / EventChannel contract as the macOS
// (IOBluetooth), Windows (WinRT) and Android (Kotlin) bridges, so the Dart-side
// BluetoothClassicMacOS wrapper and BluetoothClassicTransport work unchanged:
//   - MethodChannel   com.htcommander/bluetooth_classic
//   - EventChannel    com.htcommander/bluetooth_classic_data   (control channel)
//   - EventChannel    com.htcommander/bluetooth_classic_audio  (registered, inert)
//
// Uses BlueZ: libbluetooth RFCOMM sockets + SDP for the data connection and
// GDBus (org.bluez) for paired-device enumeration and adapter power state.

#ifndef RUNNER_BLUETOOTH_CLASSIC_PLUGIN_H_
#define RUNNER_BLUETOOTH_CLASSIC_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

// Registers the Bluetooth Classic plugin channels on the given registrar.
// Safe to call once; subsequent calls are ignored.
void bluetooth_classic_plugin_register_with_registrar(
    FlPluginRegistrar* registrar);

G_END_DECLS

#endif  // RUNNER_BLUETOOTH_CLASSIC_PLUGIN_H_
