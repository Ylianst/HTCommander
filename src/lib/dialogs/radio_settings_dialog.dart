/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

// `Radio` from radio.dart collides with Material's Radio button widget, which
// this dialog does not use; hide it so the radio model type is unambiguous.
import 'dart:typed_data';

import 'package:flutter/material.dart' hide Radio;

import '../radio/radio.dart';
import '../radio/radio_models.dart';
import '../services/bluetooth_service.dart';
import '../services/data_broker_client.dart';

/// Shows the experimental Radio Settings dialog for the connected radio
/// [deviceId]. This dialog exposes low-level [RadioSettings] fields that are
/// parsed by the app but not yet surfaced anywhere else, so their behaviour can
/// be tried out before deciding which ones deserve a permanent home in the UI.
///
/// Only the individual bit-fields edited here are written back; every other
/// byte of the radio's settings block is preserved verbatim (the edits are
/// overlaid on top of the current settings buffer).
Future<void> showRadioSettingsDialog(BuildContext context, int deviceId) {
  return showDialog<void>(
    context: context,
    builder: (context) => RadioSettingsDialog(deviceId: deviceId),
  );
}

class RadioSettingsDialog extends StatefulWidget {
  final int deviceId;

  const RadioSettingsDialog({super.key, required this.deviceId});

  @override
  State<RadioSettingsDialog> createState() => _RadioSettingsDialogState();
}

class _RadioSettingsDialogState extends State<RadioSettingsDialog> {
  final DataBrokerClient _broker = DataBrokerClient();
  final BluetoothService _bluetooth = BluetoothService();

  bool _loaded = false;
  String _radioName = '';

  // ---- Audio ----
  int _squelchLevel = 0; // 0-15
  int _micGain = 0; // 0-7
  int _btMicGain = 0; // 0-7
  int _localSpeaker = 0; // 0-3
  bool _disTone = false;

  // ---- Power ----
  bool _autoPowerOn = false;
  int _autoPowerOff = 0; // 0-7
  bool _powerSavingMode = false;
  bool _pairingAtPowerOn = false;

  // ---- Transmit ----
  int _txTimeLimit = 0; // 0-31
  int _vfo1TxPower = 0; // 0-3
  int _vfo2TxPower = 0; // 0-3
  bool _pttLock = false;
  bool _tailElim = false;

  // ---- Display ----
  int _screenTimeout = 0; // 0-31
  bool _imperialUnit = false;
  int _timeOffset = 0; // 0-63
  int _vfoX = 0; // 0-3

  // ---- Advanced ----
  bool _scan = false;
  int _doubleChannel = 0; // 0-3
  bool _autoRelayEn = false;
  int _positioningSystem = 0; // 0-15
  bool _useFreqRange2 = false;
  bool _disDigitalMute = false;
  bool _signalingEccEn = false;
  bool _leadingSyncBitEn = false;
  bool _chDataLock = false;

  @override
  void initState() {
    super.initState();
    _loadFromRadio();
  }

  @override
  void dispose() {
    _broker.dispose();
    super.dispose();
  }

  Radio? get _radio => _bluetooth.radioInstance(widget.deviceId);

  void _loadFromRadio() {
    final radio = _radio;
    final s = radio?.settings;
    if (radio == null || s == null) {
      setState(() => _loaded = false);
      return;
    }

    _radioName = radio.friendlyName.isNotEmpty
        ? radio.friendlyName
        : 'Radio ${widget.deviceId}';

    _squelchLevel = s.squelchLevel;
    _micGain = s.micGain;
    _btMicGain = s.btMicGain;
    _localSpeaker = s.localSpeaker;
    _disTone = s.disTone;

    _autoPowerOn = s.autoPowerOn;
    _autoPowerOff = s.autoPowerOff;
    _powerSavingMode = s.powerSavingMode;
    _pairingAtPowerOn = s.pairingAtPowerOn;

    _txTimeLimit = s.txTimeLimit;
    _vfo1TxPower = s.vfolTxPowerX;
    _vfo2TxPower = s.vfo2TxPowerX;
    _pttLock = s.pttLock;
    _tailElim = s.tailElim;

    _screenTimeout = s.screenTimeout;
    _imperialUnit = s.imperialUnit;
    _timeOffset = s.timeOffset;
    _vfoX = s.vfoX;

    _scan = s.scan;
    _doubleChannel = s.doubleChannel;
    _autoRelayEn = s.autoRelayEn;
    _positioningSystem = s.positioningSystem;
    _useFreqRange2 = s.useFreqRange2;
    _disDigitalMute = s.disDigitalMute;
    _signalingEccEn = s.signalingEccEn;
    _leadingSyncBitEn = s.leadingSyncBitEn;
    _chDataLock = s.chDataLock;

    setState(() => _loaded = true);
  }

  /// Builds the write buffer by starting from the radio's current settings
  /// (header stripped) and overlaying only the fields this dialog edits. Byte
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
    setBits(1, 0x80, _scan ? 0x80 : 0);
    setBits(1, 0x30, (_doubleChannel & 0x03) << 4);
    setBits(1, 0x0F, _squelchLevel & 0x0F);

    // Byte 7 (index 2): tail elim, auto relay, mic gain.
    setBits(2, 0x80, _tailElim ? 0x80 : 0);
    setBits(2, 0x40, _autoRelayEn ? 0x40 : 0);
    setBits(2, 0x20, _autoPowerOn ? 0x20 : 0);
    setBits(2, 0x0E, (_micGain & 0x07) << 1);

    // Byte 8 (index 3): TX time limit.
    setBits(3, 0x1F, _txTimeLimit & 0x1F);

    // Byte 9 (index 4): local speaker, BT mic gain, disable tone, power saving.
    setBits(4, 0xC0, (_localSpeaker & 0x03) << 6);
    setBits(4, 0x38, (_btMicGain & 0x07) << 3);
    setBits(4, 0x02, _disTone ? 0x02 : 0);
    setBits(4, 0x01, _powerSavingMode ? 0x01 : 0);

    // Byte 10 (index 5): auto power off.
    setBits(5, 0xE0, (_autoPowerOff & 0x07) << 5);

    // Byte 11 (index 6): positioning system, time offset (high 2 bits).
    setBits(6, 0x3C, (_positioningSystem & 0x0F) << 2);
    setBits(6, 0x03, (_timeOffset >> 4) & 0x03);

    // Byte 12 (index 7): time offset (low nibble), freq range 2, PTT lock,
    // leading sync bit, pairing at power on.
    setBits(7, 0xF0, (_timeOffset & 0x0F) << 4);
    setBits(7, 0x08, _useFreqRange2 ? 0x08 : 0);
    setBits(7, 0x04, _pttLock ? 0x04 : 0);
    setBits(7, 0x02, _leadingSyncBitEn ? 0x02 : 0);
    setBits(7, 0x01, _pairingAtPowerOn ? 0x01 : 0);

    // Byte 13 (index 8): screen timeout, VFO x, imperial units.
    setBits(8, 0xF8, (_screenTimeout & 0x1F) << 3);
    setBits(8, 0x06, (_vfoX & 0x03) << 1);
    setBits(8, 0x01, _imperialUnit ? 0x01 : 0);

    // Byte 15 (index 10): VFO1 TX power.
    setBits(10, 0x03, _vfo1TxPower & 0x03);

    // Byte 16 (index 11): VFO2 TX power, digital mute, signaling ECC, ch lock.
    setBits(11, 0xC0, (_vfo2TxPower & 0x03) << 6);
    setBits(11, 0x20, _disDigitalMute ? 0x20 : 0);
    setBits(11, 0x10, _signalingEccEn ? 0x10 : 0);
    setBits(11, 0x08, _chDataLock ? 0x08 : 0);

    return data;
  }

  void _onApply() {
    final buffer = _buildSettingsBuffer();
    if (buffer == null) return;
    _broker.dispatch(
      deviceId: widget.deviceId,
      name: 'WriteSettings',
      data: buffer,
      store: false,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings written to radio')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: scheme.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 620),
        child: DefaultTabController(
          length: 5,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Radio Settings (Experimental)',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurface,
                      ),
                    ),
                    if (_loaded)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          _radioName,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (!_loaded)
                const Expanded(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Radio settings are not available yet. Make sure a '
                        'radio is connected and its settings have loaded.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                )
              else ...[
                const TabBar(
                  isScrollable: true,
                  tabs: [
                    Tab(text: 'Audio'),
                    Tab(text: 'Power'),
                    Tab(text: 'Transmit'),
                    Tab(text: 'Display'),
                    Tab(text: 'Advanced'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _audioTab(),
                      _powerTab(),
                      _transmitTab(),
                      _displayTab(),
                      _advancedTab(),
                    ],
                  ),
                ),
              ],
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _loaded ? _onApply : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Apply'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Tab builders ----

  Widget _tabBody(List<Widget> children) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: children,
    );
  }

  Widget _audioTab() {
    return _tabBody([
      _intRow('Squelch Level', _squelchLevel, 0, 15,
          (v) => setState(() => _squelchLevel = v)),
      _intRow('Mic Gain', _micGain, 0, 7,
          (v) => setState(() => _micGain = v)),
      _intRow('Bluetooth Mic Gain', _btMicGain, 0, 7,
          (v) => setState(() => _btMicGain = v)),
      _intRow('Local Speaker', _localSpeaker, 0, 3,
          (v) => setState(() => _localSpeaker = v)),
      _boolRow('Disable Tone (roger beep)', _disTone,
          (v) => setState(() => _disTone = v)),
    ]);
  }

  Widget _powerTab() {
    return _tabBody([
      _boolRow('Auto Power On', _autoPowerOn,
          (v) => setState(() => _autoPowerOn = v)),
      _intRow('Auto Power Off (timer)', _autoPowerOff, 0, 7,
          (v) => setState(() => _autoPowerOff = v)),
      _boolRow('Power Saving Mode', _powerSavingMode,
          (v) => setState(() => _powerSavingMode = v)),
      _boolRow('Pairing at Power On', _pairingAtPowerOn,
          (v) => setState(() => _pairingAtPowerOn = v)),
    ]);
  }

  Widget _transmitTab() {
    return _tabBody([
      _intRow('TX Time Limit', _txTimeLimit, 0, 31,
          (v) => setState(() => _txTimeLimit = v)),
      _intRow('VFO A TX Power', _vfo1TxPower, 0, 3,
          (v) => setState(() => _vfo1TxPower = v)),
      _intRow('VFO B TX Power', _vfo2TxPower, 0, 3,
          (v) => setState(() => _vfo2TxPower = v)),
      _boolRow('PTT Lock', _pttLock, (v) => setState(() => _pttLock = v)),
      _boolRow('Squelch Tail Elimination', _tailElim,
          (v) => setState(() => _tailElim = v)),
    ]);
  }

  Widget _displayTab() {
    return _tabBody([
      _intRow('Screen Timeout', _screenTimeout, 0, 31,
          (v) => setState(() => _screenTimeout = v)),
      _boolRow('Imperial Units', _imperialUnit,
          (v) => setState(() => _imperialUnit = v)),
      _intRow('Time Offset', _timeOffset, 0, 63,
          (v) => setState(() => _timeOffset = v)),
      _intRow('VFO X', _vfoX, 0, 3, (v) => setState(() => _vfoX = v)),
    ]);
  }

  Widget _advancedTab() {
    return _tabBody([
      _boolRow('Scan', _scan, (v) => setState(() => _scan = v)),
      _intRow('Double Channel (dual watch)', _doubleChannel, 0, 3,
          (v) => setState(() => _doubleChannel = v)),
      _boolRow('Auto Cross-band Repeat', _autoRelayEn,
          (v) => setState(() => _autoRelayEn = v)),
      _intRow('Positioning System', _positioningSystem, 0, 15,
          (v) => setState(() => _positioningSystem = v)),
      _boolRow('Use Frequency Range 2', _useFreqRange2,
          (v) => setState(() => _useFreqRange2 = v)),
      _boolRow('Disable Digital Mute', _disDigitalMute,
          (v) => setState(() => _disDigitalMute = v)),
      _boolRow('Signaling ECC', _signalingEccEn,
          (v) => setState(() => _signalingEccEn = v)),
      _boolRow('Leading Sync Bit', _leadingSyncBitEn,
          (v) => setState(() => _leadingSyncBitEn = v)),
      _boolRow('Channel Data Lock', _chDataLock,
          (v) => setState(() => _chDataLock = v)),
    ]);
  }

  // ---- Reusable rows ----

  Widget _boolRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _intRow(
    String label,
    int value,
    int min,
    int max,
    ValueChanged<int> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 180, child: Text(label)),
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
