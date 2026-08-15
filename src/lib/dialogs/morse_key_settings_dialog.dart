/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Configures a USB morse key for the Comms tab's Morse Key mode: the key type
(straight or paddle), which keyboard key(s) the USB adapter emits, the paddle
speed in words-per-minute, and how long to keep the FM transmitter keyed after
the last element (the transmit tail). A live indicator lights up as the mapped
physical key is pressed so the operator can confirm the wiring before going on
the air. Settings are stored on the DataBroker (device 0, `MorseKeySettings`).
*/

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../radio/morse_keyer.dart';
import '../services/data_broker_client.dart';
import 'dialog_utils.dart';

/// Human-readable label for a [MorseKeyBinding].
String morseKeyBindingLabel(MorseKeyBinding b) {
  switch (b) {
    case MorseKeyBinding.bracketLeft:
      return '[  (left bracket)';
    case MorseKeyBinding.bracketRight:
      return ']  (right bracket)';
    case MorseKeyBinding.controlLeft:
      return 'Left Ctrl';
    case MorseKeyBinding.controlRight:
      return 'Right Ctrl';
  }
}

/// The [LogicalKeyboardKey] a [MorseKeyBinding] corresponds to.
LogicalKeyboardKey morseBindingLogicalKey(MorseKeyBinding b) {
  switch (b) {
    case MorseKeyBinding.bracketLeft:
      return LogicalKeyboardKey.bracketLeft;
    case MorseKeyBinding.bracketRight:
      return LogicalKeyboardKey.bracketRight;
    case MorseKeyBinding.controlLeft:
      return LogicalKeyboardKey.controlLeft;
    case MorseKeyBinding.controlRight:
      return LogicalKeyboardKey.controlRight;
  }
}

/// Human-readable label for a paddle key pair.
String morseKeyPaddleGroupLabel(MorseKeyPaddleGroup g) {
  switch (g) {
    case MorseKeyPaddleGroup.brackets:
      return '[  and  ]  (brackets)';
    case MorseKeyPaddleGroup.control:
      return 'Left and Right Ctrl';
  }
}

/// Shows the Morse Key settings dialog.
Future<void> showMorseKeySettingsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const _MorseKeySettingsDialog(),
  );
}

class _MorseKeySettingsDialog extends StatefulWidget {
  const _MorseKeySettingsDialog();

  @override
  State<_MorseKeySettingsDialog> createState() =>
      _MorseKeySettingsDialogState();
}

class _MorseKeySettingsDialogState extends State<_MorseKeySettingsDialog> {
  final DataBrokerClient _broker = DataBrokerClient();
  final FocusNode _keyFocus = FocusNode();

  late MorseKeyType _keyType;
  late MorseKeyBinding _straightBinding;
  late MorseKeyPaddleGroup _paddleGroup;
  late bool _paddleReversed;
  late int _wpm;
  late int _tailMs;
  late int _toneHz;

  // Live indicator state.
  bool _primaryPressed = false;
  bool _secondaryPressed = false;

  @override
  void initState() {
    super.initState();
    final stored = _broker.getValue<Map<dynamic, dynamic>>(
      0,
      'MorseKeySettings',
    );
    final s = stored != null
        ? MorseKeySettings.fromJson(stored)
        : const MorseKeySettings();
    _keyType = s.keyType;
    _straightBinding = s.straightBinding;
    _paddleGroup = s.paddleGroup;
    _paddleReversed = s.paddleReversed;
    _wpm = s.wpm;
    _tailMs = s.tailMs;
    _toneHz = s.toneHz;
  }

  @override
  void dispose() {
    _keyFocus.dispose();
    _broker.dispose();
    super.dispose();
  }

  bool get _isPaddle => _keyType == MorseKeyType.paddle;

  /// The settings currently being edited, used to resolve the live dit/dah keys.
  MorseKeySettings get _current => MorseKeySettings(
        keyType: _keyType,
        straightBinding: _straightBinding,
        paddleGroup: _paddleGroup,
        paddleReversed: _paddleReversed,
        wpm: _wpm,
        tailMs: _tailMs,
        toneHz: _toneHz,
      );

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final bool isDown = event is KeyDownEvent;
    final bool isUp = event is KeyUpEvent;
    if (!isDown && !isUp) return KeyEventResult.ignored;

    final settings = _current;
    bool handled = false;
    if (key == morseBindingLogicalKey(settings.primaryBinding)) {
      setState(() => _primaryPressed = isDown);
      handled = true;
    }
    if (_isPaddle && key == morseBindingLogicalKey(settings.secondaryBinding)) {
      setState(() => _secondaryPressed = isDown);
      handled = true;
    }
    return handled ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  void _onSave() {
    _broker.dispatch(
      deviceId: 0,
      name: 'MorseKeySettings',
      data: _current.toJson(),
      store: true,
    );
    Navigator.of(context).pop();
  }

  // Input decoration matching the main Settings dialog dropdowns.
  InputDecoration _inputDecoration({String? labelText}) {
    return DialogStyles.inputDecoration(context, labelText: labelText);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Focus(
          focusNode: _keyFocus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Morse Key Settings',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                _buildForm(scheme),
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
      ),
    );
  }

  Widget _buildForm(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Key type
        DropdownButtonFormField<MorseKeyType>(
          initialValue: _keyType,
          decoration: _inputDecoration(labelText: 'Key type'),
          items: const [
            DropdownMenuItem(
              value: MorseKeyType.straight,
              child: Text('Straight key'),
            ),
            DropdownMenuItem(
              value: MorseKeyType.paddle,
              child: Text('Paddle key (iambic)'),
            ),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _keyType = v);
          },
        ),
        const SizedBox(height: 12),
        // Key mapping
        if (_isPaddle) ...[
          DropdownButtonFormField<MorseKeyPaddleGroup>(
            initialValue: _paddleGroup,
            decoration: _inputDecoration(labelText: 'Paddle keys'),
            items: [
              for (final g in MorseKeyPaddleGroup.values)
                DropdownMenuItem(
                  value: g,
                  child: Text(morseKeyPaddleGroupLabel(g)),
                ),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _paddleGroup = v);
            },
          ),
          const SizedBox(height: 4),
          CheckboxListTile(
            value: _paddleReversed,
            onChanged: (v) => setState(() => _paddleReversed = v ?? false),
            title: const Text('Reverse paddles (right lever sends dits)'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
          Text(
            'Standard: the left paddle sends dits (thumb) and the right paddle '
            'sends dahs (index finger). Reverse this for a left-handed layout.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ] else
          DropdownButtonFormField<MorseKeyBinding>(
            initialValue: _straightBinding,
            decoration: _inputDecoration(labelText: 'Key input'),
            items: [
              for (final b in MorseKeyBinding.values)
                DropdownMenuItem(value: b, child: Text(morseKeyBindingLabel(b))),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _straightBinding = v);
            },
          ),
        const SizedBox(height: 16),
        // Live key indicator
        _buildIndicator(scheme),
        const SizedBox(height: 16),
        // Speed (paddle only)
        if (_isPaddle) ...[
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
          const SizedBox(height: 8),
        ],
        // Transmit tail
        Row(
          children: [
            const SizedBox(width: 4),
            Text('Transmit tail: $_tailMs ms'),
          ],
        ),
        Slider(
          value: _tailMs.toDouble(),
          min: 200,
          max: 3000,
          divisions: 28,
          label: '$_tailMs ms',
          onChanged: (v) => setState(() => _tailMs = (v / 100).round() * 100),
        ),
        Text(
          'How long to keep the transmitter keyed after your last element '
          'before dropping it. Set it a little above your inter-word gap.',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildIndicator(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Press your key to test — the light turns green when it is down.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _indicatorDot(
                label: _isPaddle ? 'Dit' : 'Key',
                pressed: _primaryPressed,
              ),
              if (_isPaddle)
                _indicatorDot(label: 'Dah', pressed: _secondaryPressed),
            ],
          ),
        ],
      ),
    );
  }

  Widget _indicatorDot({required String label, required bool pressed}) {
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 60),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: pressed ? Colors.green : Colors.grey.shade500,
            boxShadow: pressed
                ? [
                    BoxShadow(
                      color: Colors.green.withValues(alpha: 0.6),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
