/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Tunes the radio's keypad frequency (VFO) mode, the mode the radio enters when
`*` is held. Tuning dispatches `VfoTune` (`{freqHz, am, wide}`)
and leaving the mode dispatches `VfoExit`
to the Radio handler, which writes the VFO memory slot and selects it as
channel A. Frequencies are only accepted inside the bands the radio reports
(`FreqRanges`) for the selected modulation. Frequency mode uses equal RX/TX
frequencies without tones. The user's saved frequencies are persisted on device 0
under `VfoFrequencies`.
*/

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../models/radio_models.dart' as ui;
import '../radio/radio_models.dart';
import '../services/data_broker_client.dart';
import 'dialog_utils.dart';

/// Tuning step sizes offered by the step buttons, in Hz.
const List<int> _stepOptionsHz = [5000, 6250, 10000, 12500, 25000, 100000];

/// DataBroker key (device 0) under which saved frequencies are persisted.
const String _savedStorageKey = 'VfoFrequencies';

/// One user-saved frequency mode entry.
class _SavedFreq {
  String name;
  final int freqHz;
  final bool am;
  final bool wide;

  _SavedFreq({
    required this.name,
    required this.freqHz,
    required this.am,
    required this.wide,
  });

  Map<String, Object?> toJson() => {
    'name': name,
    'freqHz': freqHz,
    'am': am,
    'wide': wide,
  };

  static _SavedFreq? fromJson(Object? json) {
    if (json is! Map) return null;
    final freq = (json['freqHz'] as num?)?.toInt();
    if (freq == null || freq <= 0) return null;
    return _SavedFreq(
      name: json['name'] as String? ?? '',
      freqHz: freq,
      am: json['am'] as bool? ?? false,
      wide: json['wide'] as bool? ?? false,
    );
  }
}

/// Shows the frequency (VFO) mode dialog for radio [deviceId].
Future<void> showVfoFrequencyDialog(
  BuildContext context, {
  required int deviceId,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _VfoFrequencyDialog(deviceId: deviceId),
  );
}

class _VfoFrequencyDialog extends StatefulWidget {
  final int deviceId;
  const _VfoFrequencyDialog({required this.deviceId});

  @override
  State<_VfoFrequencyDialog> createState() => _VfoFrequencyDialogState();
}

class _VfoFrequencyDialogState extends State<_VfoFrequencyDialog> {
  final DataBrokerClient _broker = DataBrokerClient();
  final TextEditingController _freqController = TextEditingController();

  List<RadioFreqBand> _bands = const [];
  Map<int, ui.RadioChannelInfo> _vfoChannels = {};
  List<ui.RadioChannelInfo> _channels = const [];
  int _channelA = -1;
  bool _am = false;
  bool _wide = false;
  int _stepHz = 12500;

  List<_SavedFreq> _saved = [];

  @override
  void initState() {
    super.initState();
    _loadState();
    _loadSaved();
    _initFields();
    _freqController.addListener(() => setState(() {}));
    _broker.subscribeMultiple(
      deviceId: widget.deviceId,
      names: ['Settings', 'VfoChannels', 'FreqRanges', 'Channels'],
      callback: _onBrokerEvent,
    );
  }

  @override
  void dispose() {
    _broker.dispose();
    _freqController.dispose();
    super.dispose();
  }

  void _onBrokerEvent(int deviceId, String name, Object? data) {
    if (!mounted || deviceId != widget.deviceId) return;
    setState(_loadState);
  }

  void _loadState() {
    _bands = parseFreqBands(
      _broker.getValueDynamic(widget.deviceId, 'FreqRanges'),
    );
    _vfoChannels = ui.parseVfoChannels(
      _broker.getValueDynamic(widget.deviceId, 'VfoChannels'),
    );
    _channels =
        _broker.getJsonListValue<ui.RadioChannelInfo>(
          widget.deviceId,
          'Channels',
          (json) => ui.RadioChannelInfo.fromJson(json),
        ) ??
        const [];
    final settings = _broker.getValueDynamic(widget.deviceId, 'Settings');
    _channelA = settings is Map ? (settings['channelA'] as int? ?? -1) : -1;
  }

  /// True while the radio's channel A is a keypad VFO slot.
  bool get _active =>
      _vfoChannels.containsKey(_channelA) ||
      isVfoChannelId(_channelA, _channels.length);

  ui.RadioChannelInfo? get _vfoChannel =>
      _active ? _vfoChannels[_channelA] : null;

  /// Seeds the editor from the VFO slot, else from the current channel A.
  void _initFields() {
    ui.RadioChannelInfo? source = _vfoChannel;
    if (source == null && _channelA >= 0) {
      for (final c in _channels) {
        if (c.channelId == _channelA) source = c;
      }
    }
    if (source != null && source.rxFreq > 0) {
      _am = source.rxMod == ui.RadioModulationType.am;
      _wide = source.bandwidth == ui.RadioBandwidthType.wide;
      _freqController.text = _formatMhz(source.rxFreq);
    }
  }

  RadioModulationType get _mod =>
      _am ? RadioModulationType.am : RadioModulationType.fm;

  /// The entered frequency in Hz, or null when it does not parse.
  int? get _enteredHz {
    final mhz = double.tryParse(
      _freqController.text.trim().replaceAll(',', '.'),
    );
    if (mhz == null || mhz <= 0) return null;
    return (mhz * 1000000).round();
  }

  bool _allowed(int? hz) => hz != null && isFreqAllowed(_bands, hz, _mod);

  String _formatMhz(int hz) {
    var s = (hz / 1000000).toStringAsFixed(5);
    while (s.endsWith('0') && s.length - s.indexOf('.') > 4) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  String _formatStep(int hz) {
    var s = (hz / 1000).toStringAsFixed(2);
    s = s.replaceFirst(RegExp(r'\.?0+$'), '');
    return '$s kHz';
  }

  String _bandText(RadioFreqBand b) {
    String mhz(int hz) {
      final v = hz / 1000000;
      return v == v.roundToDouble()
          ? v.toStringAsFixed(0)
          : v.toStringAsFixed(3);
    }

    return '${mhz(b.lowHz)}-${mhz(b.highHz)} MHz';
  }

  void _tune([int? hz]) {
    final freqHz = hz ?? _enteredHz;
    if (!_allowed(freqHz)) return;
    _broker.dispatch(
      deviceId: widget.deviceId,
      name: 'VfoTune',
      data: {
        'freqHz': freqHz,
        'am': _am,
        'wide': _wide,
      },
      store: false,
    );
  }

  void _step(int direction) {
    final base = _enteredHz ?? _vfoChannel?.rxFreq;
    if (base == null) return;
    final next = base + direction * _stepHz;
    if (!_allowed(next)) return;
    _freqController.text = _formatMhz(next);
    _tune(next);
  }

  /// Returns the radio to channel mode and closes the dialog.
  void _exit() {
    _broker.dispatch(
      deviceId: widget.deviceId,
      name: 'VfoExit',
      data: null,
      store: false,
    );
    Navigator.of(context).pop();
  }

  // ---------------------------------------------------------------------------
  // Saved frequencies
  // ---------------------------------------------------------------------------

  void _loadSaved() {
    final raw = _broker.getValue<String>(0, _savedStorageKey);
    _saved = [];
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final item in decoded) {
          final f = _SavedFreq.fromJson(item);
          if (f != null) _saved.add(f);
        }
      }
    } catch (_) {
      // Ignore malformed stored data.
    }
  }

  void _storeSaved() {
    _broker.dispatch(
      deviceId: 0,
      name: _savedStorageKey,
      data: jsonEncode(_saved.map((f) => f.toJson()).toList()),
      store: true,
    );
  }

  String _savedName(_SavedFreq f) =>
      f.name.isEmpty ? '${_formatMhz(f.freqHz)} MHz' : f.name;

  String _savedCaption(BuildContext context, _SavedFreq f) {
    final l10n = AppLocalizations.of(context);
    final bw = f.wide ? l10n.cdBandwidthWide : l10n.cdBandwidthNarrow;
    return '${_formatMhz(f.freqHz)} MHz · ${f.am ? 'AM' : 'FM'} · $bw';
  }

  /// Loads a saved entry into the editor and tunes the radio to it.
  void _selectSaved(_SavedFreq f) {
    setState(() {
      _am = f.am;
      _wide = f.wide;
      _freqController.text = _formatMhz(f.freqHz);
    });
    _tune(f.freqHz);
  }

  Future<void> _addSaved() async {
    final hz = _enteredHz;
    if (hz == null || !_allowed(hz)) return;
    final defaultName = '${_formatMhz(hz)} MHz';
    final name = await _promptName(defaultName);
    if (name == null || !mounted) return;
    setState(() {
      _saved.add(
        _SavedFreq(
          name: name.isEmpty ? defaultName : name,
          freqHz: hz,
          am: _am,
          wide: _wide,
        ),
      );
    });
    _storeSaved();
  }

  Future<void> _renameSaved(_SavedFreq f) async {
    final name = await _promptName(_savedName(f));
    if (name == null || !mounted) return;
    setState(() => f.name = name);
    _storeSaved();
  }

  Future<void> _deleteSaved(_SavedFreq f) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await DialogHelper.showConfirmDialog(
      context,
      title: l10n.vfoDialogDeleteTitle,
      message: l10n.vfoDialogDeleteMessage(_savedName(f)),
      okText: l10n.commonDelete,
    );
    if (!confirmed || !mounted) return;
    setState(() => _saved.remove(f));
    _storeSaved();
  }

  Future<String?> _promptName(String initial) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        final scheme = Theme.of(context).colorScheme;
        return AlertDialog(
          backgroundColor: scheme.surface,
          title: Text(l10n.vfoDialogNameTitle),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: DialogStyles.inputDecoration(
              context,
              labelText: l10n.vfoDialogNameLabel,
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: DialogStyles.secondaryButtonStyle(context),
              child: Text(l10n.commonCancel),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              style: DialogStyles.primaryButtonStyle(context),
              child: Text(l10n.commonOk),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return HTDialog(
      title: _active ? l10n.vfoDialogTitle : l10n.vfoDialogChannelMode,
      maxWidth: 460,
      maxHeight: 720,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: _buildBody(context)),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: _active ? _exit : null,
                style: DialogStyles.secondaryButtonStyle(context),
                icon: const Icon(Icons.logout, size: 18),
                label: Text(l10n.vfoDialogExit),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: DialogStyles.secondaryButtonStyle(context),
                child: Text(l10n.commonClose),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hz = _enteredHz;
    final valid = _allowed(hz);
    final showError = _freqController.text.trim().isNotEmpty && !valid;
    final allowed = freqBandsFor(_bands, _mod).map(_bandText).join(', ');
    final controls = <Widget>[
      Row(
        children: [
          IconButton(
            tooltip: l10n.vfoDialogStepDown,
            icon: const Icon(Icons.chevron_left),
            onPressed: _allowed((hz ?? 0) - _stepHz) ? () => _step(-1) : null,
          ),
          Expanded(
            child: TextField(
              controller: _freqController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18),
              decoration: DialogStyles.inputDecoration(
                context,
                labelText: l10n.vfoDialogFrequency,
                invalid: showError,
              ),
              onSubmitted: (_) => _tune(),
            ),
          ),
          IconButton(
            tooltip: l10n.vfoDialogStepUp,
            icon: const Icon(Icons.chevron_right),
            onPressed: _allowed((hz ?? 0) + _stepHz) ? () => _step(1) : null,
          ),
          const SizedBox(width: 4),
          ElevatedButton(
            onPressed: valid ? () => _tune() : null,
            style: DialogStyles.primaryButtonStyle(context),
            child: Text(l10n.vfoDialogTune),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Text(
        !showError
            ? l10n.vfoDialogAllowed(allowed)
            : l10n.vfoDialogOutOfRange,
        style: DialogStyles.bodyStyle.copyWith(
          fontSize: 12,
          color: showError
              ? Theme.of(context).colorScheme.error
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          _toggleButton(
            l10n.vfoDialogModulation,
            _am ? 'AM' : 'FM',
            () => setState(() => _am = !_am),
          ),
          const SizedBox(width: 8),
          _toggleButton(
            l10n.vfoDialogBandwidth,
            _wide ? l10n.vfoDialogWide : l10n.vfoDialogNarrow,
            () => setState(() => _wide = !_wide),
          ),
          const SizedBox(width: 8),
          _toggleButton(l10n.vfoDialogStep, _formatStep(_stepHz), () {
            final i = _stepOptionsHz.indexOf(_stepHz);
            setState(
              () => _stepHz = _stepOptionsHz[(i + 1) % _stepOptionsHz.length],
            );
          }),
        ],
      ),
      const SizedBox(height: 4),
      _buildSavedHeader(context, valid),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Give the saved list all remaining height; on very short screens
        // scroll everything instead.
        if (constraints.maxHeight >= 320) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...controls,
              Expanded(child: _buildSavedList(context, expand: true)),
            ],
          );
        }
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [...controls, _buildSavedList(context, expand: false)],
          ),
        );
      },
    );
  }

  /// A compact button that cycles a setting each time it is pressed.
  Widget _toggleButton(String tooltip, String label, VoidCallback onPressed) {
    return Expanded(
      child: Tooltip(
        message: tooltip,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 6),
          ),
          child: FittedBox(fit: BoxFit.scaleDown, child: Text(label)),
        ),
      ),
    );
  }

  Widget _buildSavedHeader(BuildContext context, bool canSave) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            l10n.vfoDialogSavedHeader,
            style: DialogStyles.labelStyle.copyWith(color: scheme.onSurface),
          ),
        ),
        IconButton(
          tooltip: l10n.vfoDialogSaveTooltip,
          icon: const Icon(Icons.add_circle, color: Colors.blue),
          onPressed: canSave ? _addSaved : null,
        ),
      ],
    );
  }

  Widget _buildSavedList(BuildContext context, {required bool expand}) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final ch = _vfoChannel;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Material(
        color: scheme.surface,
        child: _saved.isEmpty
            ? Align(
                alignment: Alignment.topCenter,
                heightFactor: expand ? null : 1,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    l10n.vfoDialogNoSaved,
                    textAlign: TextAlign.center,
                    style: DialogStyles.bodyStyle.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            : ListView.builder(
                shrinkWrap: !expand,
                physics: expand ? null : const NeverScrollableScrollPhysics(),
                itemCount: _saved.length,
                itemBuilder: (context, index) {
                  final f = _saved[index];
                  return _buildSavedTile(
                    context,
                    f,
                    ch != null &&
                        ch.rxFreq == f.freqHz &&
                        (ch.rxMod == ui.RadioModulationType.am) == f.am,
                  );
                },
              ),
      ),
    );
  }

  Widget _buildSavedTile(BuildContext context, _SavedFreq f, bool isTuned) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      selected: isTuned,
      selectedTileColor: scheme.primaryContainer,
      leading: Icon(
        Icons.radio,
        color: isTuned ? scheme.primary : scheme.onSurfaceVariant,
      ),
      title: Text(
        _savedName(f),
        style: DialogStyles.bodyStyle,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        _savedCaption(context, f),
        style: DialogStyles.bodyStyle.copyWith(
          fontSize: 11,
          color: scheme.onSurfaceVariant,
        ),
      ),
      onTap: () => _selectSaved(f),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: l10n.commonRename,
            icon: const Icon(Icons.edit, size: 20),
            onPressed: () => _renameSaved(f),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: l10n.commonDelete,
            icon: const Icon(Icons.delete, size: 20, color: Colors.red),
            onPressed: () => _deleteSaved(f),
          ),
        ],
      ),
    );
  }
}
