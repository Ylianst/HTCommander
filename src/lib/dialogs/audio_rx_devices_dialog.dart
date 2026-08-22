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

import 'package:flutter/material.dart';
import 'package:record/record.dart' show InputDevice;

import '../audio_rx/audio_rx_device.dart';
import '../services/data_broker_client.dart';
import '../services/microphone_capture.dart';

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
    final String usage = d.usage == AudioRxUsage.aprs ? 'APRS' : 'Comms';
    final String modem = d.usage == AudioRxUsage.aprs
        ? 'AFSK 1200'
        : _modemLabel(d.modem);
    final String port = d.inputDeviceLabel.isNotEmpty
        ? d.inputDeviceLabel
        : (d.inputDeviceId.isNotEmpty ? d.inputDeviceId : 'no input');
    final String pairing =
        d.isPaired ? ' • paired ${d.pairedRadioMac}' : '';
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

  List<InputDevice> _inputs = <InputDevice>[];
  bool _inputsLoaded = false;
  List<_RadioOption> _radios = <_RadioOption>[];

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
    _radios = _readRadios();
    _loadInputs();
  }

  @override
  void dispose() {
    _name.dispose();
    _broker.dispose();
    super.dispose();
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

  bool get _isPaired => _pairedMac.isNotEmpty;

  bool get _portValid =>
      _inputDeviceId.isNotEmpty &&
      !widget.takenPorts.contains(_inputDeviceId.toLowerCase());

  bool get _valid {
    if (!_portValid) return false;
    if (!_isPaired && _name.text.trim().isEmpty) return false;
    return true;
  }

  void _submit() {
    if (!_valid) return;
    Navigator.of(context).pop(AudioRxDevice(
      deviceId: widget.deviceId,
      name: _name.text.trim(),
      inputDeviceId: _inputDeviceId,
      inputDeviceLabel: _inputDeviceLabel,
      usage: _usage,
      modem: _modem,
      pairedRadioMac: _isPaired ? _pairedMac.toUpperCase() : '',
    ));
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
                ],
                selected: <AudioRxUsage>{_usage},
                onSelectionChanged: (Set<AudioRxUsage> s) =>
                    setState(() => _usage = s.first),
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
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                initialValue: _pairedMac.isEmpty ? '' : _pairedMac.toUpperCase(),
                decoration: const InputDecoration(labelText: 'Pair to radio'),
                items: <DropdownMenuItem<String>>[
                  const DropdownMenuItem<String>(
                    value: '',
                    child: Text('None (independent device)'),
                  ),
                  for (final _RadioOption r in _radios)
                    DropdownMenuItem<String>(
                      value: r.mac,
                      child: Text('${r.name} (${r.mac})'),
                    ),
                ],
                onChanged: (String? v) => setState(() => _pairedMac = v ?? ''),
              ),
              const SizedBox(height: 8),
              if (!_isPaired)
                TextField(
                  controller: _name,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'Shown as the received channel in Comms',
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Paired: decoded data is attributed to the radio and only '
                    'received while it is connected.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
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
