/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Generic raw-command test dialog. Lets the user pick any radio basic command,
type an optional HEX payload, send it to the connected radio and watch the raw
response frames stream back. The dialog stays open after Send so commands can be
tweaked and re-sent repeatedly.
*/

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../radio/gaia_protocol.dart';
import '../radio/utils.dart';
import '../services/data_broker_client.dart';
import 'dialog_utils.dart';

/// Shows the raw radio command dialog for the given connected [deviceId].
Future<void> showRawCommandDialog(BuildContext context, int deviceId) {
  return showDialog<void>(
    context: context,
    builder: (context) => _RawCommandDialog(deviceId: deviceId),
  );
}

class _RawCommandDialog extends StatefulWidget {
  final int deviceId;

  const _RawCommandDialog({required this.deviceId});

  @override
  State<_RawCommandDialog> createState() => _RawCommandDialogState();
}

class _RawCommandDialogState extends State<_RawCommandDialog> {
  final DataBrokerClient _broker = DataBrokerClient();
  final TextEditingController _payloadController = TextEditingController();
  final TextEditingController _responseController = TextEditingController();
  final ScrollController _responseScroll = ScrollController();

  // All selectable basic commands (skips the placeholder `unknown` entry).
  late final List<RadioBasicCommand> _commands = RadioBasicCommand.values
      .where((c) => c != RadioBasicCommand.unknown)
      .toList();

  RadioBasicCommand _selectedCommand = RadioBasicCommand.getDevInfo;

  @override
  void initState() {
    super.initState();
    // Watch every raw response frame the radio produces so the user can see the
    // reply to the command they just sent (and any async notifications).
    _broker.subscribe(
      deviceId: widget.deviceId,
      name: 'RawCommandRx',
      callback: _onRawCommandRx,
    );
  }

  @override
  void dispose() {
    _broker.dispose();
    _payloadController.dispose();
    _responseController.dispose();
    _responseScroll.dispose();
    super.dispose();
  }

  String _timestamp() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}.'
        '${now.millisecond.toString().padLeft(3, '0')}';
  }

  void _appendLog(String line) {
    if (!mounted) return;
    final existing = _responseController.text;
    _responseController.text = existing.isEmpty ? line : '$existing\n$line';
    // Keep the newest line visible.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_responseScroll.hasClients) {
        _responseScroll.jumpTo(_responseScroll.position.maxScrollExtent);
      }
    });
  }

  void _onRawCommandRx(int deviceId, String name, Object? data) {
    if (deviceId != widget.deviceId) return;
    if (data is! Uint8List || data.length < 4) return;

    final parsed = GaiaProtocol.parseResponse(data);
    // Only show responses to the command currently selected in the dropdown so
    // the log isn't flooded with unrelated background/notification traffic.
    if (parsed.command != _selectedCommand) return;

    final status = data.length > 4 ? data[4] : -1;
    final payload = data.length > 5
        ? RadioUtils.bytesToHexRange(data, 5, data.length - 5)
        : '';

    final buffer = StringBuffer();
    buffer.write('[${_timestamp()}] RX ${parsed.command.name}');
    if (status >= 0) buffer.write('  status=${_statusName(status)}');
    if (payload.isNotEmpty) buffer.write('  data=$payload');
    buffer.write('\n            raw=${RadioUtils.bytesToHex(data)}');
    _appendLog(buffer.toString());
  }

  String _statusName(int status) {
    const names = {
      0: 'success',
      1: 'notSupported',
      2: 'notAuthenticated',
      3: 'insufficientResources',
      4: 'authenticating',
      5: 'invalidParameter',
      6: 'incorrectState',
      7: 'inProgress',
    };
    return '$status(${names[status] ?? 'unknown'})';
  }

  void _onSend() {
    // Parse the optional HEX payload (spaces are allowed for readability).
    final rawText = _payloadController.text.replaceAll(RegExp(r'\s+'), '');
    Uint8List payload = Uint8List(0);
    if (rawText.isNotEmpty) {
      final parsed = RadioUtils.hexStringToByteArray(rawText);
      if (parsed == null) {
        _appendLog(
          '[${_timestamp()}] ERROR: Invalid HEX payload '
          '(must be an even number of hex digits).',
        );
        return;
      }
      payload = parsed;
    }

    // Build the raw GATT command frame the radio layer expects:
    // [group_hi, group_lo, cmd_hi, cmd_lo, payload...].
    final frame = Uint8List(4 + payload.length);
    frame[0] = 0x00;
    frame[1] = RadioCommandGroup.basic.value & 0xFF;
    frame[2] = 0x00;
    frame[3] = _selectedCommand.value & 0xFF;
    frame.setRange(4, 4 + payload.length, payload);

    _broker.dispatch(
      deviceId: widget.deviceId,
      name: 'SendRawCommand',
      data: frame,
      store: false,
    );

    _appendLog(
      '[${_timestamp()}] TX ${_selectedCommand.name} '
      '(${_selectedCommand.value})  raw=${RadioUtils.bytesToHex(frame)}',
    );
  }

  void _onClearLog() {
    _responseController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return HTDialog(
      title: 'Raw Radio Command',
      maxWidth: 640,
      maxHeight: 560,
      content: Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Command', style: DialogStyles.labelStyle),
          const SizedBox(height: 4),
          DropdownButtonFormField<RadioBasicCommand>(
            initialValue: _selectedCommand,
            isExpanded: true,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            items: _commands
                .map(
                  (c) => DropdownMenuItem<RadioBasicCommand>(
                    value: c,
                    child: Text(
                      '${c.name}  '
                      '(${c.value} / 0x${c.value.toRadixString(16).padLeft(2, '0').toUpperCase()})',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _selectedCommand = value);
            },
          ),
          const SizedBox(height: 12),
          const Text('HEX Payload (optional)', style: DialogStyles.labelStyle),
          const SizedBox(height: 4),
          TextField(
            controller: _payloadController,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F ]')),
            ],
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'e.g. 01 A0 FF',
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            onSubmitted: (_) => _onSend(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Response', style: DialogStyles.labelStyle),
              const Spacer(),
              TextButton(
                onPressed: _onClearLog,
                style: DialogStyles.secondaryButtonStyle(context),
                child: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey.shade500),
              ),
              child: TextField(
                controller: _responseController,
                scrollController: _responseScroll,
                readOnly: true,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(8),
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: DialogStyles.secondaryButtonStyle(context),
          child: const Text('Close'),
        ),
        ElevatedButton(
          onPressed: _onSend,
          style: DialogStyles.primaryButtonStyle(context),
          child: const Text('Send'),
        ),
      ],
    );
  }
}
