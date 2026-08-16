/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Low-level radio settings bit-field panels used as the Audio / Power / Transmit
/ Display / Advanced tabs of the hardware Radio Settings dialog. These fields
were previously only available in the experimental Radio Settings dialog on the
Debug tab.

All five tabs edit a single [RadioSettings] buffer, so they share one
[RadioBitfieldSettingsController]. Only the individual bit-fields edited here
are written back; every other byte of the radio's settings block is preserved
verbatim (the edits are overlaid on top of the current settings buffer).
*/

// `Radio` from radio.dart collides with Material's Radio button widget, which
// these panels do not use; hide it so the radio model type is unambiguous.
import 'dart:typed_data';

import 'package:flutter/material.dart' hide Radio;

import '../radio/radio.dart';
import '../services/bluetooth_service.dart';
import '../services/data_broker_client.dart';

/// The bit-field tabs offered by the hardware Radio Settings dialog.
enum RadioBitfieldTab { audio, power, transmit, display, advanced }

/// Shared state + persistence for the low-level radio bit-field settings that
/// are spread across the Audio/Power/Transmit/Display/Advanced tabs. A single
/// controller instance is shared by every panel so they edit one settings
/// buffer and write it back to the radio once.
class RadioBitfieldSettingsController extends ChangeNotifier {
  final DataBrokerClient _broker = DataBrokerClient();
  final BluetoothService _bluetooth = BluetoothService();

  final int deviceId;

  RadioBitfieldSettingsController(this.deviceId) {
    _loadFromRadio();
  }

  bool _loaded = false;
  bool get loaded => _loaded;

  // ---- Audio ----
  int squelchLevel = 0; // 0-15
  int micGain = 0; // 0-7
  int btMicGain = 0; // 0-7
  int localSpeaker = 0; // 0-3
  bool disTone = false;

  // ---- Power ----
  bool autoPowerOn = false;
  int autoPowerOff = 0; // 0-7
  bool powerSavingMode = false;
  bool pairingAtPowerOn = false;

  // ---- Transmit ----
  int txTimeLimit = 0; // 0-31
  int vfo1TxPower = 0; // 0-3
  int vfo2TxPower = 0; // 0-3
  bool pttLock = false;
  bool tailElim = false;

  // ---- Display ----
  int screenTimeout = 0; // 0-31
  bool imperialUnit = false;
  int timeOffset = 0; // 0-63
  int vfoX = 0; // 0-3

  // ---- Advanced ----
  bool scan = false;
  int doubleChannel = 0; // 0-3
  bool autoRelayEn = false;
  int positioningSystem = 0; // 0-15
  bool useFreqRange2 = false;
  bool disDigitalMute = false;
  bool signalingEccEn = false;
  bool leadingSyncBitEn = false;
  bool chDataLock = false;
  int wxMode = 0; // 0=off, 1=monitor, 2=alert

  Radio? get _radio => _bluetooth.radioInstance(deviceId);

  /// Applies [fn] to a field then notifies listening panels to rebuild.
  void update(VoidCallback fn) {
    fn();
    notifyListeners();
  }

  void _loadFromRadio() {
    final radio = _radio;
    final s = radio?.settings;
    if (radio == null || s == null) {
      _loaded = false;
      notifyListeners();
      return;
    }

    squelchLevel = s.squelchLevel;
    micGain = s.micGain;
    btMicGain = s.btMicGain;
    localSpeaker = s.localSpeaker;
    disTone = s.disTone;

    autoPowerOn = s.autoPowerOn;
    autoPowerOff = s.autoPowerOff;
    powerSavingMode = s.powerSavingMode;
    pairingAtPowerOn = s.pairingAtPowerOn;

    txTimeLimit = s.txTimeLimit;
    vfo1TxPower = s.vfolTxPowerX;
    vfo2TxPower = s.vfo2TxPowerX;
    pttLock = s.pttLock;
    tailElim = s.tailElim;

    screenTimeout = s.screenTimeout;
    imperialUnit = s.imperialUnit;
    timeOffset = s.timeOffset;
    vfoX = s.vfoX;

    scan = s.scan;
    doubleChannel = s.doubleChannel;
    autoRelayEn = s.autoRelayEn;
    positioningSystem = s.positioningSystem;
    useFreqRange2 = s.useFreqRange2;
    disDigitalMute = s.disDigitalMute;
    signalingEccEn = s.signalingEccEn;
    leadingSyncBitEn = s.leadingSyncBitEn;
    chDataLock = s.chDataLock;
    wxMode = s.wxMode;

    _loaded = true;
    notifyListeners();
  }

  /// Builds the write buffer by starting from the radio's current settings
  /// (header stripped) and overlaying only the fields these tabs edit. Byte
  /// indices are the raw settings offsets minus 5, because [writeSettings]
  /// expects the message header to be stripped (raw byte N -> index N-5).
  Uint8List? _buildSettingsBuffer() {
    final s = _radio?.settings;
    if (s == null) return null;
    final data = s.toByteArrayWith();

    void setBits(int index, int mask, int value) {
      if (index < 0 || index >= data.length) return;
      data[index] = (data[index] & (~mask & 0xFF)) | (value & mask);
    }

    // Byte 6 (index 1): scan, double channel, squelch.
    setBits(1, 0x80, scan ? 0x80 : 0);
    setBits(1, 0x30, (doubleChannel & 0x03) << 4);
    setBits(1, 0x0F, squelchLevel & 0x0F);

    // Byte 7 (index 2): tail elim, auto relay, mic gain.
    setBits(2, 0x80, tailElim ? 0x80 : 0);
    setBits(2, 0x40, autoRelayEn ? 0x40 : 0);
    setBits(2, 0x20, autoPowerOn ? 0x20 : 0);
    setBits(2, 0x0E, (micGain & 0x07) << 1);

    // Byte 8 (index 3): TX time limit.
    setBits(3, 0x1F, txTimeLimit & 0x1F);

    // Byte 9 (index 4): local speaker, BT mic gain, disable tone, power saving.
    setBits(4, 0xC0, (localSpeaker & 0x03) << 6);
    setBits(4, 0x38, (btMicGain & 0x07) << 3);
    setBits(4, 0x02, disTone ? 0x02 : 0);
    setBits(4, 0x01, powerSavingMode ? 0x01 : 0);

    // Byte 10 (index 5): auto power off.
    setBits(5, 0xE0, (autoPowerOff & 0x07) << 5);

    // Byte 11 (index 6): positioning system, time offset (high 2 bits).
    setBits(6, 0x3C, (positioningSystem & 0x0F) << 2);
    setBits(6, 0x03, (timeOffset >> 4) & 0x03);

    // Byte 12 (index 7): time offset (low nibble), freq range 2, PTT lock,
    // leading sync bit, pairing at power on.
    setBits(7, 0xF0, (timeOffset & 0x0F) << 4);
    setBits(7, 0x08, useFreqRange2 ? 0x08 : 0);
    setBits(7, 0x04, pttLock ? 0x04 : 0);
    setBits(7, 0x02, leadingSyncBitEn ? 0x02 : 0);
    setBits(7, 0x01, pairingAtPowerOn ? 0x01 : 0);

    // Byte 13 (index 8): screen timeout, VFO x, imperial units.
    setBits(8, 0xF8, (screenTimeout & 0x1F) << 3);
    setBits(8, 0x06, (vfoX & 0x03) << 1);
    setBits(8, 0x01, imperialUnit ? 0x01 : 0);

    // Byte 15 (index 10): VFO1 TX power, weather mode (Off/Monitor/Alert).
    setBits(10, 0x03, vfo1TxPower & 0x03);
    setBits(10, 0xC0, (wxMode & 0x03) << 6);

    // Byte 16 (index 11): VFO2 TX power, digital mute, signaling ECC, ch lock.
    setBits(11, 0xC0, (vfo2TxPower & 0x03) << 6);
    setBits(11, 0x20, disDigitalMute ? 0x20 : 0);
    setBits(11, 0x10, signalingEccEn ? 0x10 : 0);
    setBits(11, 0x08, chDataLock ? 0x08 : 0);

    return data;
  }

  /// Writes the overlaid bit-field edits back to the radio. No-op when the
  /// radio's settings have not loaded.
  void write() {
    final buffer = _buildSettingsBuffer();
    if (buffer == null) return;
    _broker.dispatch(
      deviceId: deviceId,
      name: 'WriteSettings',
      data: buffer,
      store: false,
    );
  }

  @override
  void dispose() {
    _broker.dispose();
    super.dispose();
  }
}

/// A single bit-field settings tab (Audio/Power/Transmit/Display/Advanced) that
/// reads and writes the shared [controller]. Editing rows update the controller
/// which rebuilds every panel bound to it.
class RadioBitfieldPanel extends StatelessWidget {
  final RadioBitfieldSettingsController controller;
  final RadioBitfieldTab tab;

  const RadioBitfieldPanel({
    super.key,
    required this.controller,
    required this.tab,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.loaded) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Radio settings are not available yet. Make sure a radio is '
                'connected and its settings have loaded.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        switch (tab) {
          case RadioBitfieldTab.audio:
            return _audioTab();
          case RadioBitfieldTab.power:
            return _powerTab();
          case RadioBitfieldTab.transmit:
            return _transmitTab();
          case RadioBitfieldTab.display:
            return _displayTab();
          case RadioBitfieldTab.advanced:
            return _advancedTab();
        }
      },
    );
  }

  Widget _tabBody(List<Widget> children) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: children,
    );
  }

  Widget _audioTab() {
    return _tabBody([
      _intRow('Squelch Level', controller.squelchLevel, 0, 15,
          (v) => controller.update(() => controller.squelchLevel = v)),
      _intRow('Mic Gain', controller.micGain, 0, 7,
          (v) => controller.update(() => controller.micGain = v),
          subtitle: 'Default is 3'),
      _intRow('Bluetooth Mic Gain', controller.btMicGain, 0, 7,
          (v) => controller.update(() => controller.btMicGain = v),
          subtitle: 'Default is 3'),
      _intRow('Local Speaker', controller.localSpeaker, 0, 3,
          (v) => controller.update(() => controller.localSpeaker = v)),
      _boolRow('Disable Tone (roger beep)', controller.disTone,
          (v) => controller.update(() => controller.disTone = v),
          subtitle: 'Default on'),
    ]);
  }

  Widget _powerTab() {
    return _tabBody([
      _boolRow('Auto Power On', controller.autoPowerOn,
          (v) => controller.update(() => controller.autoPowerOn = v),
          subtitle: 'Default on'),
      _intRow('Auto Power Off (timer)', controller.autoPowerOff, 0, 7,
          (v) => controller.update(() => controller.autoPowerOff = v),
          subtitle: 'Default is 0'),
      _boolRow('Power Saving Mode', controller.powerSavingMode,
          (v) => controller.update(() => controller.powerSavingMode = v),
          subtitle: 'Default off'),
      _boolRow('Pairing at Power On', controller.pairingAtPowerOn,
          (v) => controller.update(() => controller.pairingAtPowerOn = v),
          subtitle: 'Default off'),
    ]);
  }

  Widget _transmitTab() {
    return _tabBody([
      _intRow('TX Time Limit', controller.txTimeLimit, 0, 31,
          (v) => controller.update(() => controller.txTimeLimit = v),
          subtitle: 'Default is 7'),
      _intRow('VFO A TX Power', controller.vfo1TxPower, 0, 3,
          (v) => controller.update(() => controller.vfo1TxPower = v),
          subtitle: 'Default is 0'),
      _intRow('VFO B TX Power', controller.vfo2TxPower, 0, 3,
          (v) => controller.update(() => controller.vfo2TxPower = v),
          subtitle: 'Default is 0'),
      _boolRow('PTT Lock', controller.pttLock,
          (v) => controller.update(() => controller.pttLock = v),
          subtitle: 'Default off'),
      _boolRow('Squelch Tail Elimination', controller.tailElim,
          (v) => controller.update(() => controller.tailElim = v),
          subtitle: 'Default on'),
    ]);
  }

  Widget _displayTab() {
    return _tabBody([
      _intRow('Screen Timeout', controller.screenTimeout, 0, 31,
          (v) => controller.update(() => controller.screenTimeout = v),
          subtitle: 'Default is 20'),
      _boolRow('Imperial Units', controller.imperialUnit,
          (v) => controller.update(() => controller.imperialUnit = v)),
      _intRow('Time Offset', controller.timeOffset, 0, 63,
          (v) => controller.update(() => controller.timeOffset = v),
          subtitle: 'Default is 10'),
      _intRow('VFO X', controller.vfoX, 0, 3,
          (v) => controller.update(() => controller.vfoX = v),
          subtitle: 'Default is 0'),
    ]);
  }

  Widget _advancedTab() {
    return _tabBody([
      _boolRow('Auto Cross-band Repeat', controller.autoRelayEn,
          (v) => controller.update(() => controller.autoRelayEn = v),
          subtitle: 'Not recommended, keep off',
          warning: controller.autoRelayEn
              ? 'Warning: enabling this can lead to issues'
              : null),
      _choiceRow('Weather Mode', controller.wxMode, const {
        0: 'Off',
        1: 'Monitor',
        2: 'Alert',
      }, (v) => controller.update(() => controller.wxMode = v),
          subtitle: 'Default is Off'),
      _intRow('Positioning System', controller.positioningSystem, 0, 15,
          (v) => controller.update(() => controller.positioningSystem = v),
          subtitle: 'Default is 7'),
      _boolRow('Use Frequency Range 2', controller.useFreqRange2,
          (v) => controller.update(() => controller.useFreqRange2 = v),
          subtitle: 'Default off'),
      _boolRow('Disable Digital Mute', controller.disDigitalMute,
          (v) => controller.update(() => controller.disDigitalMute = v),
          subtitle: 'Default off'),
      _boolRow('Signaling ECC', controller.signalingEccEn,
          (v) => controller.update(() => controller.signalingEccEn = v),
          subtitle: 'Default off'),
      _boolRow('Leading Sync Bit', controller.leadingSyncBitEn,
          (v) => controller.update(() => controller.leadingSyncBitEn = v),
          subtitle: 'Default off'),
      _boolRow('Channel Data Lock', controller.chDataLock,
          (v) => controller.update(() => controller.chDataLock = v),
          subtitle: 'Default off'),
    ]);
  }

  // ---- Reusable rows ----

  /// Label plus optional smaller "default" subtitle and a red warning line.
  Widget _labelColumn(String label, String? subtitle, String? warning) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
        if (warning != null)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              warning,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.red,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  Widget _boolRow(
    String label,
    bool value,
    ValueChanged<bool> onChanged, {
    String? subtitle,
    String? warning,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: _labelColumn(label, subtitle, warning)),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _choiceRow(
    String label,
    int value,
    Map<int, String> options,
    ValueChanged<int> onChanged, {
    String? subtitle,
  }) {
    final selected = options.containsKey(value) ? value : options.keys.first;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: _labelColumn(label, subtitle, null)),
          DropdownButton<int>(
            value: selected,
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
            items: [
              for (final entry in options.entries)
                DropdownMenuItem<int>(
                  value: entry.key,
                  child: Text(entry.value),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _intRow(
    String label,
    int value,
    int min,
    int max,
    ValueChanged<int> onChanged, {
    String? subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 180, child: _labelColumn(label, subtitle, null)),
          Expanded(
            child: Slider(
              value: value.toDouble().clamp(min.toDouble(), max.toDouble()),
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: max - min,
              label: '$value',
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
          SizedBox(
            width: 28,
            child: Text('$value', textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}
