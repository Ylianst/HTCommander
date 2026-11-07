/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Tunes the radio's keypad frequency (VFO) mode, the mode the radio enters when
`*` is held. Tuning dispatches `VfoTune` (`{freqHz, am, wide}`) and leaving the
mode dispatches `VfoExit` to the Radio handler, which writes the VFO memory
slot and selects it as channel A. Frequencies are only accepted inside the
bands the radio reports (`FreqRanges`) for the selected modulation.
*/

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../models/radio_models.dart' as ui;
import '../radio/radio_models.dart';
import '../services/data_broker_client.dart';
import 'dialog_utils.dart';

/// Tuning step sizes offered by the step buttons, in Hz.
const List<int> _stepOptionsHz = [5000, 6250, 10000, 12500, 25000, 100000];

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

  @override
  void initState() {
    super.initState();
    _loadState();
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
    final khz = hz / 1000;
    return khz == khz.roundToDouble()
        ? '${khz.toStringAsFixed(0)} kHz'
        : '${khz.toStringAsFixed(2)} kHz';
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
      data: {'freqHz': freqHz, 'am': _am, 'wide': _wide},
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

  void _exit() {
    _broker.dispatch(
      deviceId: widget.deviceId,
      name: 'VfoExit',
      data: null,
      store: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hz = _enteredHz;
    final valid = _allowed(hz);
    final showError = _freqController.text.trim().isNotEmpty && !valid;
    final allowed = freqBandsFor(_bands, _mod).map(_bandText).join(', ');

    return HTDialog(
      title: l10n.vfoDialogTitle,
      maxWidth: 440,
      maxHeight: 560,
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDisplay(context),
            const SizedBox(height: 16),
            Row(
              children: [
                IconButton(
                  tooltip: l10n.vfoDialogStepDown,
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _allowed((hz ?? 0) - _stepHz)
                      ? () => _step(-1)
                      : null,
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
                  onPressed: _allowed((hz ?? 0) + _stepHz)
                      ? () => _step(1)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              showError
                  ? l10n.vfoDialogOutOfRange
                  : l10n.vfoDialogAllowed(allowed),
              style: DialogStyles.bodyStyle.copyWith(
                fontSize: 12,
                color: showError
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            _labeledRow(
              l10n.vfoDialogModulation,
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('FM')),
                  ButtonSegment(value: true, label: Text('AM')),
                ],
                selected: {_am},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _am = s.first),
              ),
            ),
            const SizedBox(height: 8),
            _labeledRow(
              l10n.vfoDialogBandwidth,
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: true, label: Text(l10n.cdBandwidthWide)),
                  ButtonSegment(
                    value: false,
                    label: Text(l10n.cdBandwidthNarrow),
                  ),
                ],
                selected: {_wide},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _wide = s.first),
              ),
            ),
            const SizedBox(height: 8),
            _labeledRow(
              l10n.vfoDialogStep,
              DropdownButton<int>(
                value: _stepHz,
                items: [
                  for (final s in _stepOptionsHz)
                    DropdownMenuItem(value: s, child: Text(_formatStep(s))),
                ],
                onChanged: (v) => setState(() => _stepHz = v ?? _stepHz),
              ),
            ),
          ],
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: valid ? () => _tune() : null,
          style: DialogStyles.primaryButtonStyle(context),
          child: Text(l10n.vfoDialogTune),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: DialogStyles.secondaryButtonStyle(context),
          child: Text(l10n.commonClose),
        ),
      ],
    );
  }

  /// A label and its control, wrapping onto two lines on narrow screens.
  Widget _labeledRow(String label, Widget control) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 4,
      children: [
        Text(label, style: DialogStyles.labelStyle),
        control,
      ],
    );
  }

  Widget _buildDisplay(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final ch = _vfoChannel;
    final tuned = ch != null && ch.rxFreq > 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              tuned
                  ? '${ch.frequencyDisplay} MHz'
                  : (_active ? l10n.riVfo : l10n.vfoDialogChannelMode),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: _active ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (tuned)
            Text(
              ch.vfoCaption(l10n.riVfo),
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          if (_active) ...[
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: _exit,
              icon: const Icon(Icons.logout, size: 18),
              label: Text(l10n.vfoDialogExit),
            ),
          ],
        ],
      ),
    );
  }
}
