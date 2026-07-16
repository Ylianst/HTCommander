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

import '../l10n/app_localizations.dart';
import 'dialog_utils.dart';
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
String _actionLabel(AppLocalizations l10n, int action) {
  switch (PFActionType.fromValue(action)) {
    case PFActionType.short:
    case PFActionType.shortSingle:
      return l10n.pfActionShort;
    case PFActionType.long:
      return l10n.pfActionLong;
    case PFActionType.veryLong:
      return l10n.pfActionVeryLong;
    case PFActionType.veryVeryLong:
      return l10n.pfActionVeryVeryLong;
    case PFActionType.double:
      return l10n.pfActionDouble;
    case PFActionType.triple:
      return l10n.pfActionTriple;
    case PFActionType.repeat:
      return l10n.pfActionRepeat;
    case PFActionType.lowToHigh:
      return l10n.pfActionPressDown;
    case PFActionType.highToLow:
      return l10n.pfActionRelease;
    case PFActionType.longRelease:
      return l10n.pfActionLongRelease;
    case PFActionType.veryLongRelease:
      return l10n.pfActionVeryLongRelease;
    case PFActionType.veryVeryLongRelease:
      return l10n.pfActionVeryVeryLongRelease;
    case PFActionType.invalid:
      return l10n.pfActionUnknown(action);
  }
}

/// Human-readable label for a PF effect.
String _effectLabel(AppLocalizations l10n, int effect) {
  final labels = <PFEffectType, String>{
    PFEffectType.disable: l10n.pfEffectDisabled,
    PFEffectType.alarm: l10n.pfEffectAlarm,
    PFEffectType.alarmAndMute: l10n.pfEffectAlarmAndMute,
    PFEffectType.toggleOffline: l10n.pfEffectToggleOffline,
    PFEffectType.toggleRadioTx: l10n.pfEffectToggleRadioTx,
    PFEffectType.toggleTxPower: l10n.pfEffectToggleTxPower,
    PFEffectType.toggleFm: l10n.pfEffectToggleFm,
    PFEffectType.prevChannel: l10n.pfEffectPrevChannel,
    PFEffectType.nextChannel: l10n.pfEffectNextChannel,
    PFEffectType.tCall: l10n.pfEffectTCall,
    PFEffectType.prevRegion: l10n.pfEffectPrevRegion,
    PFEffectType.nextRegion: l10n.pfEffectNextRegion,
    PFEffectType.toggleChScan: l10n.pfEffectToggleChScan,
    PFEffectType.mainPtt: l10n.pfEffectMainPtt,
    PFEffectType.subPtt: l10n.pfEffectSubPtt,
    PFEffectType.toggleMonitor: l10n.pfEffectToggleMonitor,
    PFEffectType.btPairing: l10n.pfEffectBtPairing,
    PFEffectType.toggleDoubleCh: l10n.pfEffectToggleDoubleCh,
    PFEffectType.toggleAbCh: l10n.pfEffectToggleAbCh,
    PFEffectType.sendLocation: l10n.pfEffectSendLocation,
    PFEffectType.oneClickLink: l10n.pfEffectOneClickLink,
    PFEffectType.volDown: l10n.pfEffectVolDown,
    PFEffectType.volUp: l10n.pfEffectVolUp,
    PFEffectType.toggleMute: l10n.pfEffectToggleMute,
  };
  final e = PFEffectType.fromValue(effect);
  // fromValue() falls back to disable(0) for unknown codes; show the raw code
  // instead of mislabeling it as "Disabled".
  if (e == PFEffectType.disable && effect != 0) {
    return l10n.pfEffectUnknown(effect);
  }
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
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.pfConfigTitle),
      content: SizedBox(width: 460, child: _buildContent()),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: DialogStyles.secondaryButtonStyle(context),
          child: Text(l10n.commonCancel),
        ),
        ElevatedButton(
          onPressed: (_slots == null || _slots!.isEmpty) ? null : _save,
          style: DialogStyles.primaryButtonStyle(context),
          child: Text(l10n.pfSaveToRadio),
        ),
      ],
    );
  }

  Widget _buildContent() {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    if (_deviceId <= 0) {
      return Text(l10n.pfNoRadio);
    }
    final slots = _slots;
    if (slots == null) {
      return const SizedBox(
        height: 80,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (slots.isEmpty) {
      return Text(l10n.pfNoButtons);
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
          Text(
            AppLocalizations.of(context).pfIntro,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
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
              AppLocalizations.of(context).pfButtonLabel(buttonId + 1),
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
    final l10n = AppLocalizations.of(context);
    // If the current effect isn't a known option, include it so it can be shown
    // and preserved rather than silently reset.
    final options = List<int>.from(_effectOptions);
    if (!options.contains(slot.effect)) options.add(slot.effect);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(_actionLabel(l10n, slot.action)),
          ),
          Expanded(
            child: DropdownButton<int>(
              isExpanded: true,
              value: slot.effect,
              items: options
                  .map(
                    (code) => DropdownMenuItem<int>(
                      value: code,
                      child: Text(_effectLabel(l10n, code)),
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
