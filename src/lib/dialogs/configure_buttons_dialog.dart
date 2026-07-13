/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Dialog to configure the radio's programmable (PF) buttons. On open it requests
the current button table (GET_PF) via the DataBroker, groups the entries by
physical button, and shows a dropdown per button/press-type so the operator can
choose which effect it performs. Saving writes the whole table back (SET_PF),
preserving the button/action of each slot and only changing the effect.
*/

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../radio/gaia_protocol.dart';
import '../services/data_broker_client.dart';

/// One editable button/action slot from the PF table.
class _PfSlot {
  final int buttonId;
  final int action;
  int effect;
  _PfSlot({required this.buttonId, required this.action, required this.effect});
}

/// Human-readable label for a PF action (press type).
String _actionLabel(int action) {
  switch (PFActionType.fromValue(action)) {
    case PFActionType.short:
    case PFActionType.shortSingle:
      return 'Short press';
    case PFActionType.long:
      return 'Long press';
    case PFActionType.veryLong:
      return 'Very long press';
    case PFActionType.veryVeryLong:
      return 'Very-very long press';
    case PFActionType.double:
      return 'Double press';
    case PFActionType.triple:
      return 'Triple press';
    case PFActionType.repeat:
      return 'Repeat';
    case PFActionType.lowToHigh:
      return 'Press down';
    case PFActionType.highToLow:
      return 'Release';
    case PFActionType.longRelease:
      return 'Long release';
    case PFActionType.veryLongRelease:
      return 'Very long release';
    case PFActionType.veryVeryLongRelease:
      return 'Very-very long release';
    case PFActionType.invalid:
      return 'Action $action';
  }
}

/// Human-readable label for a PF effect.
String _effectLabel(int effect) {
  const labels = <PFEffectType, String>{
    PFEffectType.disable: 'Disabled',
    PFEffectType.alarm: 'Alarm',
    PFEffectType.alarmAndMute: 'Alarm and Mute',
    PFEffectType.toggleOffline: 'Toggle Offline',
    PFEffectType.toggleRadioTx: 'Toggle Radio TX',
    PFEffectType.toggleTxPower: 'Toggle TX Power',
    PFEffectType.toggleFm: 'Toggle FM Radio',
    PFEffectType.prevChannel: 'Previous Channel',
    PFEffectType.nextChannel: 'Next Channel',
    PFEffectType.tCall: 'T-Call (1750 Hz)',
    PFEffectType.prevRegion: 'Previous Region',
    PFEffectType.nextRegion: 'Next Region',
    PFEffectType.toggleChScan: 'Toggle Channel Scan',
    PFEffectType.mainPtt: 'Main PTT',
    PFEffectType.subPtt: 'Sub PTT',
    PFEffectType.toggleMonitor: 'Toggle Monitor',
    PFEffectType.btPairing: 'Bluetooth Pairing',
    PFEffectType.toggleDoubleCh: 'Toggle Dual Channel',
    PFEffectType.toggleAbCh: 'Toggle A/B Channel',
    PFEffectType.sendLocation: 'Send Location',
    PFEffectType.oneClickLink: 'One-Click Link',
    PFEffectType.volDown: 'Volume Down',
    PFEffectType.volUp: 'Volume Up',
    PFEffectType.toggleMute: 'Toggle Mute',
  };
  final e = PFEffectType.fromValue(effect);
  // fromValue() falls back to disable(0) for unknown codes; show the raw code
  // instead of mislabeling it as "Disabled".
  if (e == PFEffectType.disable && effect != 0) return 'Unknown ($effect)';
  return labels[e] ?? e.name;
}

/// Shows the Configure Buttons dialog for [initialDeviceId] (the currently
/// selected radio).
Future<void> showConfigureButtonsDialog(
  BuildContext context, {
  int? initialDeviceId,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) =>
        _ConfigureButtonsDialog(initialDeviceId: initialDeviceId),
  );
}

class _ConfigureButtonsDialog extends StatefulWidget {
  final int? initialDeviceId;
  const _ConfigureButtonsDialog({this.initialDeviceId});

  @override
  State<_ConfigureButtonsDialog> createState() =>
      _ConfigureButtonsDialogState();
}

class _ConfigureButtonsDialogState extends State<_ConfigureButtonsDialog> {
  final DataBrokerClient _broker = DataBrokerClient();

  int _deviceId = -1;
  List<_PfSlot>? _slots;

  /// Effect codes offered in the dropdown (all known effects).
  final List<int> _effectOptions =
      PFEffectType.values.map((e) => e.value).toList();

  @override
  void initState() {
    super.initState();
    _deviceId = widget.initialDeviceId ?? -1;
    if (_deviceId <= 0) return;

    _applyTable(_broker.getValueDynamic(_deviceId, 'PfTable'));
    _broker.subscribe(
      deviceId: _deviceId,
      name: 'PfTable',
      callback: _onPfTable,
    );
    // Request a fresh copy so the dialog reflects the radio's current state.
    _broker.dispatch(
      deviceId: _deviceId,
      name: 'QueryProgFunctions',
      data: null,
      store: false,
    );
  }

  @override
  void dispose() {
    _broker.dispose();
    super.dispose();
  }

  void _onPfTable(int deviceId, String name, Object? data) {
    if (!mounted) return;
    setState(() => _applyTable(data));
  }

  void _applyTable(Object? data) {
    if (data is! List) return;
    final slots = <_PfSlot>[];
    for (final item in data) {
      if (item is Map) {
        slots.add(
          _PfSlot(
            buttonId: (item['buttonId'] as num?)?.toInt() ?? 0,
            action: (item['actionValue'] as num?)?.toInt() ?? 0,
            effect: (item['effectValue'] as num?)?.toInt() ?? 0,
          ),
        );
      }
    }
    _slots = slots;
  }

  void _save() {
    final slots = _slots;
    if (slots == null || slots.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    // SET_PF expects ONE effect byte per slot (not key/effect pairs), in the
    // same slot order GET_PF returned. Verified against hardware: the radio
    // reads N effect bytes and assigns them to its N fixed button/action slots.
    final bytes = <int>[for (final s in slots) s.effect & 0xFF];
    _broker.dispatch(
      deviceId: _deviceId,
      name: 'SetProgFunctions',
      data: Uint8List.fromList(bytes),
      store: false,
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Configure Buttons'),
      content: SizedBox(width: 460, child: _buildContent()),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_slots == null || _slots!.isEmpty) ? null : _save,
          child: const Text('Save to Radio'),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_deviceId <= 0) {
      return const Text('No radio connected.');
    }
    final slots = _slots;
    if (slots == null) {
      return const SizedBox(
        height: 80,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (slots.isEmpty) {
      return const Text('This radio reported no programmable buttons.');
    }

    // Group slots by physical button, preserving order.
    final buttonIds = <int>[];
    for (final s in slots) {
      if (!buttonIds.contains(s.buttonId)) buttonIds.add(s.buttonId);
    }

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Choose what each programmable button does for every press type. '
            'Changes are written to the radio when you save.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          for (final buttonId in buttonIds) _buildButtonSection(buttonId, slots),
        ],
      ),
    );
  }

  Widget _buildButtonSection(int buttonId, List<_PfSlot> slots) {
    final buttonSlots = slots.where((s) => s.buttonId == buttonId).toList();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Button ${buttonId + 1}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            for (final slot in buttonSlots) _buildSlotRow(slot),
          ],
        ),
      ),
    );
  }

  Widget _buildSlotRow(_PfSlot slot) {
    // If the current effect isn't a known option, include it so it can be shown
    // and preserved rather than silently reset.
    final options = List<int>.from(_effectOptions);
    if (!options.contains(slot.effect)) options.add(slot.effect);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 140, child: Text(_actionLabel(slot.action))),
          Expanded(
            child: DropdownButton<int>(
              isExpanded: true,
              value: slot.effect,
              items: options
                  .map(
                    (code) => DropdownMenuItem<int>(
                      value: code,
                      child: Text(_effectLabel(code)),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => slot.effect = v);
              },
            ),
          ),
        ],
      ),
    );
  }
}
