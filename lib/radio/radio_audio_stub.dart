/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

// Web stub for [RadioAudio]. The radio audio path (SBC over a second RFCOMM
// channel) is a Bluetooth Classic feature that is unavailable on the web, where
// only the BLE control channel is used. This stub exposes the same surface used
// by `BluetoothService` so web builds compile; it is inert.

import 'radio.dart';

/// Inert web implementation of the radio audio handler. Constructed on connect
/// like the desktop version but does nothing (audio is never enabled on web).
class RadioAudio {
  RadioAudio({
    required this.radio,
    required this.deviceId,
    required this.macAddress,
  });

  final Radio radio;
  final int deviceId;
  final String macAddress;

  Future<void> dispose() async {}
}
