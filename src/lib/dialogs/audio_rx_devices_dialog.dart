/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

//
// audio_rx_devices_dialog.dart - Manage the list of Audio Receive Devices: a
// computer sound-card input HTCommander decodes data off (receive-only). Each
// device is persisted on Data Broker device 0 ('AudioReceiveDevices') and run by
// the AudioRxManager. This file provides the list dialog and the add/edit editor.
//

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:record/record.dart' show InputDevice;

import '../audio_rx/audio_rx_device.dart';
import '../services/data_broker_client.dart';
import '../services/microphone_capture.dart';

/// Selectable input-gain multipliers for an Audio Receive Device.
const List<double> _gainOptions = <double>[1.0, 2.0, 4.0, 8.0, 16.0];

/// Peak (0..1) at or above which the input is treated as clipping (too loud),
/// lighting the level meter's red zone.
const double _clipThreshold = 0.98;

/// Shows the Audio Receive Devices manager (list + add/edit/remove).
Future<void> showAudioRxDevicesDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext ctx) => const _AudioRxDevicesDialog(),
  );
}

class _AudioRxDevicesDialog extends StatefulWidget {
  const _AudioRxDevicesDialog();

  @override
  State<_AudioRxDevicesDialog> createState() => _AudioRxDevicesDialogState();
}

class _AudioRxDevicesDialogState extends State<_AudioRxDevicesDialog> {
  final DataBrokerClient _broker = DataBrokerClient();
  List<AudioRxDevice> _devices = <AudioRxDevice>[];

  @override
  void initState() {
    super.initState();
    _devices = _read();
  }

  @override
  void dispose() {
    _broker.dispose();
    super.dispose();
  }

  List<AudioRxDevice> _read() {
    final Object? raw = _broker.getValueDynamic(0, audioRxDevicesKey);
    final List<AudioRxDevice> out = <AudioRxDevice>[];
    if (raw is List) {
      for (final Object? e in raw) {
        if (e is Map) out.add(AudioRxDevice.fromMap(e));
      }
    }
    return out;
  }

  void _save() {
    _broker.dispatch(
      deviceId: 0,
      name: audioRxDevicesKey,
      data: _devices.map((AudioRxDevice d) => d.toMap()).toList(),
      store: true,
    );
  }

  int _nextDeviceId() {
    int max = audioRxDeviceIdBase - 1;
    for (final AudioRxDevice d in _devices) {
      if (d.deviceId > max) max = d.deviceId;
    }
    return max + 1;
  }

  /// Input ports already used by other devices (and the Audio tab input), which
  /// the editor must not let a device reuse. [exclude] is the device being
  /// edited, whose own port is allowed.
  Set<String> _takenPorts({AudioRxDevice? exclude}) {
    final Set<String> ports = <String>{};
    for (final AudioRxDevice d in _devices) {
      if (identical(d, exclude)) continue;
      if (d.inputDeviceId.isNotEmpty) ports.add(d.inputDeviceId.toLowerCase());
    }
    final String audioTabInput =
        _broker.getValue<String>(0, 'InputAudioDevice', '') ?? '';
    if (audioTabInput.isNotEmpty) ports.add(audioTabInput.toLowerCase());
    return ports;
  }

  Future<void> _add() async {
    final AudioRxDevice? result = await showDialog<AudioRxDevice>(
      context: context,
      builder: (BuildContext ctx) => _AudioRxDeviceEditor(
        deviceId: _nextDeviceId(),
        takenPorts: _takenPorts(),
      ),
    );
    if (result == null) return;
    setState(() => _devices = <AudioRxDevice>[..._devices, result]);
    _save();
  }

  Future<void> _edit(int index) async {
    final AudioRxDevice existing = _devices[index];
    final AudioRxDevice? result = await showDialog<AudioRxDevice>(
      context: context,
      builder: (BuildContext ctx) => _AudioRxDeviceEditor(
        deviceId: existing.deviceId,
        existing: existing,
        takenPorts: _takenPorts(exclude: existing),
      ),
    );
    if (result == null) return;
    setState(() {
      final List<AudioRxDevice> next = <AudioRxDevice>[..._devices];
      next[index] = result;
      _devices = next;
    });
    _save();
  }

  void _remove(int index) {
    setState(() {
      final List<AudioRxDevice> next = <AudioRxDevice>[..._devices];
      next.removeAt(index);
      _devices = next;
    });
    _save();
  }

  String _subtitle(AudioRxDevice d) {
    final String usage = _usageLabel(d.usage);
    final String modem = d.usage == AudioRxUsage.aprs
        ? 'AFSK 1200'
        : d.usage == AudioRxUsage.paired
            ? 'voice + data'
            : _modemLabel(d.modem);
    final String port = d.inputDeviceLabel.isNotEmpty
        ? d.inputDeviceLabel
        : (d.inputDeviceId.isNotEmpty ? d.inputDeviceId : 'no input');
    final String pairing =
        d.usage == AudioRxUsage.paired ? ' • ${d.pairedRadioMac}' : '';
    return '$port • $usage ($modem)$pairing';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Audio Receive Devices'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              'Decode data (AFSK 1200, PSK 2400 or DART) off a computer audio '
              'input. Receive-only.',
            ),
            const SizedBox(height: 12),
            if (_devices.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No audio receive devices yet.')),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _devices.length,
                  itemBuilder: (BuildContext ctx, int i) {
                    final AudioRxDevice d = _devices[i];
                    final String title = d.name.isNotEmpty
                        ? d.name
                        : (d.isPaired ? 'Paired device' : 'Audio device');
                    return ListTile(
                      dense: true,
                      title: Text(title),
                      subtitle: Text(_subtitle(d)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          IconButton(
                            icon: const Icon(Icons.edit),
                            tooltip: 'Edit',
                            onPressed: () => _edit(i),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Remove',
                            onPressed: () => _remove(i),
                          ),
                        ],
                      ),
                      onTap: () => _edit(i),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add device'),
                onPressed: _add,
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

String _modemLabel(AudioRxModem m) {
  switch (m) {
    case AudioRxModem.psk2400:
      return 'PSK 2400';
    case AudioRxModem.dart:
      return 'DART';
    case AudioRxModem.afsk1200:
      return 'AFSK 1200';
  }
}

String _usageLabel(AudioRxUsage u) {
  switch (u) {
    case AudioRxUsage.aprs:
      return 'APRS';
    case AudioRxUsage.comms:
      return 'Comms';
    case AudioRxUsage.paired:
      return 'Paired';
  }
}

class _AudioRxDeviceEditor extends StatefulWidget {
  final int deviceId;
  final AudioRxDevice? existing;
  final Set<String> takenPorts;

  const _AudioRxDeviceEditor({
    required this.deviceId,
    required this.takenPorts,
    this.existing,
  });

  @override
  State<_AudioRxDeviceEditor> createState() => _AudioRxDeviceEditorState();
}

class _AudioRxDeviceEditorState extends State<_AudioRxDeviceEditor> {
  final DataBrokerClient _broker = DataBrokerClient();
  late final TextEditingController _name;

  String _inputDeviceId = '';
  String _inputDeviceLabel = '';
  AudioRxUsage _usage = AudioRxUsage.aprs;
  AudioRxModem _modem = AudioRxModem.afsk1200;
  String _pairedMac = '';
  AudioRxChannel _audioChannel = AudioRxChannel.auto;
  double _audioGain = 1.0;

  List<InputDevice> _inputs = <InputDevice>[];
  bool _inputsLoaded = false;
  List<_RadioOption> _radios = <_RadioOption>[];

  // Live input-level meter shown to help pick the channel and gain. It opens a
  // temporary recorder on the selected port, so it runs only when that port is
  // connected and not already in use (a second recorder on one device crashes).
  final ValueNotifier<_LevelSample> _level =
      ValueNotifier<_LevelSample>(_LevelSample.zero);
  MicrophoneCapture? _levelMonitor;
  String _activeMonitorSig = '';
  Future<void> _monitorOp = Future<void>.value();
  Set<String> _activePorts = <String>{};
  bool _closingForSave = false;
  bool _stateDisposed = false;
  double _levelDisplay = 0;
  DateTime _clipUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastLevelEmit = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    final AudioRxDevice? e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _inputDeviceId = e?.inputDeviceId ?? '';
    _inputDeviceLabel = e?.inputDeviceLabel ?? '';
    _usage = e?.usage ?? AudioRxUsage.aprs;
    _modem = e?.modem ?? AudioRxModem.afsk1200;
    _pairedMac = e?.pairedRadioMac ?? '';
    _audioChannel = e?.audioChannel ?? AudioRxChannel.auto;
    _audioGain = e?.audioGain ?? 1.0;
    _activePorts = _readActivePorts();
    _broker.subscribe(
      deviceId: 0,
      name: audioRxActivePortsKey,
      callback: (_, _, _) {
        if (!mounted) return;
        setState(() => _activePorts = _readActivePorts());
        _queueMonitorSync();
      },
    );
    _radios = _readRadios();
    _loadInputs();
  }

  @override
  void dispose() {
    _stateDisposed = true;
    _queueMonitorSync(); // tears the recorder down on the serialized queue
    _name.dispose();
    _level.dispose();
    _broker.dispose();
    super.dispose();
  }

  Set<String> _readActivePorts() {
    final Object? raw = _broker.getValueDynamic(0, audioRxActivePortsKey);
    final Set<String> out = <String>{};
    if (raw is List) {
      for (final Object? e in raw) {
        final String s = (e ?? '').toString().toLowerCase();
        if (s.isNotEmpty) out.add(s);
      }
    }
    return out;
  }

  /// Whether a live level meter can safely run for the current selection: a
  /// connected input that is not already selected elsewhere or in use.
  bool get _canMonitor {
    if (_stateDisposed || _closingForSave) return false;
    if (!MicrophoneCapture.isSupported || !_inputsLoaded) return false;
    if (_inputDeviceId.isEmpty) return false;
    final String key = _inputDeviceId.toLowerCase();
    // Not connected: the port is not among the currently enumerated inputs.
    if (!_inputs.any((InputDevice d) => d.id == _inputDeviceId)) return false;
    // In use: taken by another device / the Audio tab, or already captured.
    if (widget.takenPorts.contains(key)) return false;
    if (_activePorts.contains(key)) return false;
    return true;
  }

  /// Enqueues a monitor reconcile on the serialized queue so two recorders are
  /// never open on the same device at once (which crashes the audio backend).
  void _queueMonitorSync() {
    _monitorOp =
        _monitorOp.then((_) => _applyMonitorState()).catchError((_) {});
  }

  Future<void> _applyMonitorState() async {
    if (_stateDisposed || _closingForSave || !_canMonitor) {
      final MicrophoneCapture? old = _levelMonitor;
      _levelMonitor = null;
      _activeMonitorSig = '';
      if (old != null) await old.dispose();
      if (!_stateDisposed) _level.value = _LevelSample.zero;
      return;
    }

    final String want = '$_inputDeviceId|${_audioChannel.name}';
    if (_levelMonitor != null && want == _activeMonitorSig) {
      _levelMonitor!.gain = _audioGain; // gain applies live; no restart needed
      return;
    }

    // Rebuild for a new port or channel: fully release the old recorder first.
    final MicrophoneCapture? old = _levelMonitor;
    _levelMonitor = null;
    _activeMonitorSig = '';
    if (old != null) await old.dispose();
    if (_stateDisposed || _closingForSave || !_canMonitor) return;

    final MicrophoneCapture cap = MicrophoneCapture(
      sampleRate: audioRxSampleRate,
      deviceId: _inputDeviceId,
      requestedChannels: 2,
      monoReduction: _monoReductionFor(_audioChannel),
      gain: _audioGain,
    );
    final bool ok = await cap.start(_onMonitorPcm);
    if (!ok || _stateDisposed || _closingForSave || !_canMonitor) {
      await cap.dispose();
      return;
    }
    _levelMonitor = cap;
    _activeMonitorSig = want;
  }

  void _onMonitorPcm(Uint8List pcm16) {
    if (_stateDisposed) return;
    final int n = pcm16.length ~/ 2;
    if (n == 0) return;
    final ByteData bd = ByteData.sublistView(pcm16, 0, n * 2);
    int peak = 0;
    for (int i = 0; i < n; i++) {
      final int s = bd.getInt16(i * 2, Endian.little);
      final int a = s < 0 ? -s : s;
      if (a > peak) peak = a;
    }
    final double p = (peak / 32768.0).clamp(0.0, 1.0);
    final DateTime now = DateTime.now();
    // Fast attack, slow decay so brief peaks are visible without flicker.
    _levelDisplay = p >= _levelDisplay ? p : (_levelDisplay * 0.8 + p * 0.2);
    if (p >= _clipThreshold) {
      _clipUntil = now.add(const Duration(milliseconds: 1200));
    }
    if (now.difference(_lastLevelEmit).inMilliseconds < 40) return;
    _lastLevelEmit = now;
    _level.value = _LevelSample(_levelDisplay, now.isBefore(_clipUntil));
  }

  static MonoReduction _monoReductionFor(AudioRxChannel c) {
    switch (c) {
      case AudioRxChannel.left:
        return MonoReduction.left;
      case AudioRxChannel.right:
        return MonoReduction.right;
      case AudioRxChannel.mix:
        return MonoReduction.mix;
      case AudioRxChannel.auto:
        return MonoReduction.auto;
    }
  }

  Future<void> _loadInputs() async {
    final List<InputDevice> list = await MicrophoneCapture.listInputDevices();
    if (!mounted) return;
    setState(() {
      _inputs = list;
      _inputsLoaded = true;
      // Keep the stored label current when the device is still present.
      for (final InputDevice d in list) {
        if (d.id == _inputDeviceId) _inputDeviceLabel = d.label;
      }
    });
    _queueMonitorSync();
  }

  List<_RadioOption> _readRadios() {
    final List<_RadioOption> out = <_RadioOption>[];
    final Object? raw = _broker.getValueDynamic(1, 'ConnectedRadios');
    if (raw is List) {
      for (final Object? e in raw) {
        if (e is! Map) continue;
        final String mac =
            (e['MacAddress'] ?? e['macAddress'] ?? '').toString();
        if (mac.isEmpty) continue;
        final String name =
            (e['FriendlyName'] ?? e['friendlyName'] ?? mac).toString();
        out.add(_RadioOption(mac: mac.toUpperCase(), name: name));
      }
    }
    // Preserve a previously-paired radio that is not currently connected.
    if (_pairedMac.isNotEmpty &&
        !out.any((_RadioOption r) => r.mac == _pairedMac.toUpperCase())) {
      out.add(_RadioOption(
          mac: _pairedMac.toUpperCase(), name: '${_pairedMac.toUpperCase()} (offline)'));
    }
    return out;
  }

  bool get _isPaired => _usage == AudioRxUsage.paired;

  bool get _portValid =>
      _inputDeviceId.isNotEmpty &&
      !widget.takenPorts.contains(_inputDeviceId.toLowerCase());

  bool get _valid {
    if (!_portValid) return false;
    if (_usage == AudioRxUsage.comms && _name.text.trim().isEmpty) return false;
    if (_usage == AudioRxUsage.paired && _pairedMac.isEmpty) return false;
    return true;
  }

  Future<void> _submit() async {
    if (!_valid) return;
    // Fully release the level-meter recorder before the manager reopens this
    // port, so two recorders never briefly share the same device.
    _closingForSave = true;
    _queueMonitorSync();
    await _monitorOp;
    if (!mounted) return;
    Navigator.of(context).pop(AudioRxDevice(
      deviceId: widget.deviceId,
      name: _name.text.trim(),
      inputDeviceId: _inputDeviceId,
      inputDeviceLabel: _inputDeviceLabel,
      usage: _usage,
      modem: _modem,
      pairedRadioMac: _isPaired ? _pairedMac.toUpperCase() : '',
      audioChannel: _audioChannel,
      audioGain: _audioGain,
    ));
  }

  static String _modeHelp(AudioRxUsage usage) {
    switch (usage) {
      case AudioRxUsage.aprs:
        return 'Frames are received on the APRS channel.';
      case AudioRxUsage.comms:
        return 'Frames are received on a channel named after this device.';
      case AudioRxUsage.paired:
        return "Frames are received on the paired radio's current channel, "
            'only while it is connected.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool portTaken = _inputDeviceId.isNotEmpty &&
        widget.takenPorts.contains(_inputDeviceId.toLowerCase());
    return AlertDialog(
      title: Text(widget.existing == null
          ? 'Add Audio Receive Device'
          : 'Edit Audio Receive Device'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildInputDropdown(portTaken),
              const SizedBox(height: 12),
              DropdownButtonFormField<AudioRxChannel>(
                initialValue: _audioChannel,
                decoration: const InputDecoration(
                  labelText: 'Audio channel',
                  helperText:
                      'Stereo cables often carry audio on one channel only',
                ),
                items: const <DropdownMenuItem<AudioRxChannel>>[
                  DropdownMenuItem<AudioRxChannel>(
                    value: AudioRxChannel.auto,
                    child: Text('Auto (loudest channel)'),
                  ),
                  DropdownMenuItem<AudioRxChannel>(
                    value: AudioRxChannel.left,
                    child: Text('Left'),
                  ),
                  DropdownMenuItem<AudioRxChannel>(
                    value: AudioRxChannel.right,
                    child: Text('Right'),
                  ),
                  DropdownMenuItem<AudioRxChannel>(
                    value: AudioRxChannel.mix,
                    child: Text('Mix (average both)'),
                  ),
                ],
                onChanged: (AudioRxChannel? v) {
                  setState(() => _audioChannel = v ?? AudioRxChannel.auto);
                  _queueMonitorSync();
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<double>(
                initialValue:
                    _gainOptions.contains(_audioGain) ? _audioGain : 1.0,
                decoration: const InputDecoration(
                  labelText: 'Input gain',
                  helperText: 'Boost a quiet line-in (analog level is cleaner)',
                ),
                items: <DropdownMenuItem<double>>[
                  for (final double g in _gainOptions)
                    DropdownMenuItem<double>(
                      value: g,
                      child: Text(g == 1.0
                          ? '0 dB (1×)'
                          : '+${(20 * (log(g) / ln10)).round()} dB (${g.toInt()}×)'),
                    ),
                ],
                onChanged: (double? v) {
                  setState(() => _audioGain = v ?? 1.0);
                  _queueMonitorSync();
                },
              ),
              if (_canMonitor) ...<Widget>[
                const SizedBox(height: 12),
                const Text(
                  'Input level',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 4),
                ValueListenableBuilder<_LevelSample>(
                  valueListenable: _level,
                  builder: (BuildContext ctx, _LevelSample s, _) =>
                      _LevelBar(sample: s),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Adjust gain and channel so loud audio stays out of the red.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
              const SizedBox(height: 12),
              SegmentedButton<AudioRxUsage>(
                segments: const <ButtonSegment<AudioRxUsage>>[
                  ButtonSegment<AudioRxUsage>(
                    value: AudioRxUsage.aprs,
                    label: Text('APRS'),
                  ),
                  ButtonSegment<AudioRxUsage>(
                    value: AudioRxUsage.comms,
                    label: Text('Comms'),
                  ),
                  ButtonSegment<AudioRxUsage>(
                    value: AudioRxUsage.paired,
                    label: Text('Paired'),
                  ),
                ],
                selected: <AudioRxUsage>{_usage},
                onSelectionChanged: (Set<AudioRxUsage> s) =>
                    setState(() => _usage = s.first),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _modeHelp(_usage),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              if (_usage == AudioRxUsage.comms) ...<Widget>[
                const SizedBox(height: 12),
                DropdownButtonFormField<AudioRxModem>(
                  initialValue: _modem,
                  decoration: const InputDecoration(labelText: 'Modem'),
                  items: const <DropdownMenuItem<AudioRxModem>>[
                    DropdownMenuItem<AudioRxModem>(
                      value: AudioRxModem.afsk1200,
                      child: Text('AFSK 1200'),
                    ),
                    DropdownMenuItem<AudioRxModem>(
                      value: AudioRxModem.psk2400,
                      child: Text('PSK 2400'),
                    ),
                    DropdownMenuItem<AudioRxModem>(
                      value: AudioRxModem.dart,
                      child: Text('DART'),
                    ),
                  ],
                  onChanged: (AudioRxModem? v) =>
                      setState(() => _modem = v ?? AudioRxModem.afsk1200),
                ),
              ],
              if (_usage == AudioRxUsage.comms) ...<Widget>[
                const SizedBox(height: 8),
                TextField(
                  controller: _name,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Channel name',
                    hintText: 'Shown as the received channel in Comms',
                  ),
                ),
              ],
              if (_usage == AudioRxUsage.paired) ...<Widget>[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue:
                      _pairedMac.isEmpty ? null : _pairedMac.toUpperCase(),
                  decoration: const InputDecoration(
                    labelText: 'Paired radio',
                    helperText:
                        "Frames use the radio's currently-tuned channel",
                  ),
                  hint: const Text('Select a radio'),
                  items: <DropdownMenuItem<String>>[
                    for (final _RadioOption r in _radios)
                      DropdownMenuItem<String>(
                        value: r.mac,
                        child: Text('${r.name} (${r.mac})'),
                      ),
                  ],
                  onChanged: (String? v) => setState(() => _pairedMac = v ?? ''),
                ),
                if (_radios.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'No radios available. Connect a radio to pair.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _valid ? _submit : null,
          child: const Text('OK'),
        ),
      ],
    );
  }

  Widget _buildInputDropdown(bool portTaken) {
    if (!_inputsLoaded) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: <Widget>[
            SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 8),
            Text('Finding audio inputs…'),
          ],
        ),
      );
    }

    // Build the item list; keep the current selection visible even if it is now
    // taken or missing so the user can see (and fix) it.
    final List<DropdownMenuItem<String>> items = <DropdownMenuItem<String>>[];
    final Set<String> seen = <String>{};
    for (final InputDevice d in _inputs) {
      final bool taken = widget.takenPorts.contains(d.id.toLowerCase()) &&
          d.id != _inputDeviceId;
      seen.add(d.id);
      items.add(DropdownMenuItem<String>(
        value: d.id,
        enabled: !taken,
        child: Text(
          taken ? '${d.label} (in use)' : d.label,
          overflow: TextOverflow.ellipsis,
        ),
      ));
    }
    if (_inputDeviceId.isNotEmpty && !seen.contains(_inputDeviceId)) {
      items.insert(
        0,
        DropdownMenuItem<String>(
          value: _inputDeviceId,
          child: Text(
            _inputDeviceLabel.isNotEmpty
                ? '$_inputDeviceLabel (unplugged)'
                : '$_inputDeviceId (unplugged)',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        DropdownButtonFormField<String>(
          initialValue: _inputDeviceId.isEmpty ? null : _inputDeviceId,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Audio input',
            errorText: portTaken ? 'This input is already in use' : null,
          ),
          hint: const Text('Select an input'),
          items: items,
          onChanged: (String? v) {
            setState(() {
              _inputDeviceId = v ?? '';
              for (final InputDevice d in _inputs) {
                if (d.id == _inputDeviceId) _inputDeviceLabel = d.label;
              }
            });
            _queueMonitorSync();
          },
        ),
        if (_inputs.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'No audio inputs found.',
              style: TextStyle(fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _RadioOption {
  final String mac;
  final String name;
  const _RadioOption({required this.mac, required this.name});
}

/// A single reading for the input-level meter: the (smoothed) peak level 0..1
/// and whether the input has recently clipped (peaked at/near full scale).
class _LevelSample {
  final double peak;
  final bool clipping;
  const _LevelSample(this.peak, this.clipping);
  static const _LevelSample zero = _LevelSample(0, false);
}

/// A horizontal input-level meter with green / amber / red zones. The fill rises
/// with the audio peak and turns red when the input is too loud, so the user can
/// set the device's channel and gain (or its own volume) to stay out of the red.
class _LevelBar extends StatelessWidget {
  const _LevelBar({required this.sample});

  final _LevelSample sample;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 12,
      width: double.infinity,
      child: CustomPaint(
        painter: _LevelBarPainter(
          peak: sample.peak,
          clipping: sample.clipping,
        ),
      ),
    );
  }
}

class _LevelBarPainter extends CustomPainter {
  _LevelBarPainter({required this.peak, required this.clipping});

  final double peak;
  final bool clipping;

  // Zone boundaries (fractions of full scale).
  static const double _amberStart = 0.75;
  static const double _redStart = 0.9;

  static const Color _green = Color(0xFF35C759);
  static const Color _amber = Color(0xFFF5A623);
  static const Color _red = Color(0xFFE53935);

  @override
  void paint(Canvas canvas, Size size) {
    final RRect track = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(3),
    );
    canvas.save();
    canvas.clipRRect(track);

    // Faint zone backgrounds so the red "too loud" region is always visible.
    void zone(double from, double to, Color c) {
      final Rect r = Rect.fromLTRB(
        from * size.width,
        0,
        to * size.width,
        size.height,
      );
      canvas.drawRect(r, Paint()..color = c.withValues(alpha: 0.18));
    }

    zone(0.0, _amberStart, _green);
    zone(_amberStart, _redStart, _amber);
    zone(_redStart, 1.0, _red);

    // Filled portion up to the current peak, colored by the zone it reaches.
    final double p = peak.clamp(0.0, 1.0);
    if (p > 0) {
      final Color fill =
          p >= _redStart ? _red : (p >= _amberStart ? _amber : _green);
      canvas.drawRect(
        Rect.fromLTRB(0, 0, p * size.width, size.height),
        Paint()..color = fill,
      );
    }

    // Emphasize the red zone edge while clipping so it clearly reads too loud.
    if (clipping) {
      canvas.drawRect(
        Rect.fromLTRB(_redStart * size.width, 0, size.width, size.height),
        Paint()..color = _red,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LevelBarPainter old) =>
      old.peak != peak || old.clipping != clipping;
}

