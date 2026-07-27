/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Configures the transmit speed (words per minute) used when sending a text
message in the Comms tab's "Morse" mode. The value is persisted on the
DataBroker (device 0, `MorseSpeedWpm`) and read by the CommsHandler when it
generates the Morse tone from typed text.
*/

import 'package:flutter/material.dart';

import '../services/data_broker_client.dart';
import 'dialog_utils.dart';

/// Default Morse transmit speed in words per minute.
const int kMorseSpeedDefaultWpm = 15;

/// Shows the Morse (text) speed settings dialog.
Future<void> showMorseSpeedDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const _MorseSpeedDialog(),
  );
}

class _MorseSpeedDialog extends StatefulWidget {
  const _MorseSpeedDialog();

  @override
  State<_MorseSpeedDialog> createState() => _MorseSpeedDialogState();
}

class _MorseSpeedDialogState extends State<_MorseSpeedDialog> {
  final DataBrokerClient _broker = DataBrokerClient();
  late int _wpm;

  @override
  void initState() {
    super.initState();
    _wpm = (_broker.getValue<int>(0, 'MorseSpeedWpm', kMorseSpeedDefaultWpm) ??
            kMorseSpeedDefaultWpm)
        .clamp(5, 40);
  }

  @override
  void dispose() {
    _broker.dispose();
    super.dispose();
  }

  void _onSave() {
    _broker.dispatch(
      deviceId: 0,
      name: 'MorseSpeedWpm',
      data: _wpm,
      store: true,
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Morse Settings',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              Row(
                children: [
                  const SizedBox(width: 4),
                  Text('Speed: $_wpm WPM'),
                ],
              ),
              Slider(
                value: _wpm.toDouble(),
                min: 5,
                max: 40,
                divisions: 35,
                label: '$_wpm WPM',
                onChanged: (v) => setState(() => _wpm = v.round()),
              ),
              Text(
                'Text messages sent in Morse mode are transmitted at this speed '
                '(words per minute).',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: DialogStyles.secondaryButtonStyle(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _onSave,
                    style: DialogStyles.primaryButtonStyle(context),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
