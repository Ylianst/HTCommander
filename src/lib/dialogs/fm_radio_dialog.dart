/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Controls the radio's built-in FM broadcast receiver. Shows the currently tuned
frequency, transport controls (seek/tune/off), a volume slider and a list of
user-saved preferred stations. Tuning and seek commands are dispatched to the
Radio handler through the DataBroker (`FmRadioSetMode`, `FmRadioSetFrequency`,
`FmRadioSeekUp`, `FmRadioSeekDown`) and live status is received back through the
`FmRadioStatus` event. Preferred stations are persisted on device 0 under the
`FmRadioStations` key so they survive across sessions.
*/

import 'dart:convert';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/radio_models.dart';
import '../services/data_broker_client.dart';
import 'dialog_utils.dart';

/// One user-saved FM broadcast station.
class _FmStation {
  String name;
  final int freqHz;
  _FmStation({required this.name, required this.freqHz});

  Map<String, Object?> toJson() => {'name': name, 'freqHz': freqHz};

  static _FmStation? fromJson(Object? json) {
    if (json is! Map) return null;
    final freq = (json['freqHz'] as num?)?.toInt();
    if (freq == null) return null;
    return _FmStation(name: json['name'] as String? ?? '', freqHz: freq);
  }
}

/// Lowest tunable FM broadcast frequency (Hz) used when stepping the tuner.
const int _fmMinFreqHz = 87000000;

/// Highest tunable FM broadcast frequency (Hz) used when stepping the tuner.
const int _fmMaxFreqHz = 108000000;

/// FM broadcast channel spacing (Hz) used by the tune up/down buttons.
const int _fmStepHz = 100000;

/// DataBroker key (device 0) under which preferred stations are persisted.
const String _stationsStorageKey = 'FmRadioStations';

/// Shows the FM Radio control dialog for [deviceId] (the connected radio).
Future<void> showFmRadioDialog(
  BuildContext context, {
  required int deviceId,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _FmRadioDialog(deviceId: deviceId),
  );
}

class _FmRadioDialog extends StatefulWidget {
  final int deviceId;
  const _FmRadioDialog({required this.deviceId});

  @override
  State<_FmRadioDialog> createState() => _FmRadioDialogState();
}

class _FmRadioDialogState extends State<_FmRadioDialog> {
  final DataBrokerClient _broker = DataBrokerClient();

  RadioFmRadioStatus _status = RadioFmRadioStatus();
  int _volume = 8;
  List<_FmStation> _stations = [];

  @override
  void initState() {
    super.initState();

    // Load the current FM status + volume from the cache, then subscribe for
    // live updates.
    final cached = _broker.getJsonValue<RadioFmRadioStatus>(
      widget.deviceId,
      'FmRadioStatus',
      (json) => RadioFmRadioStatus.fromJson(json),
    );
    if (cached != null) _status = cached;
    final cachedVol = _broker.getValue<int>(widget.deviceId, 'Volume');
    if (cachedVol != null) _volume = cachedVol;

    _loadStations();

    _broker.subscribe(
      deviceId: widget.deviceId,
      name: 'FmRadioStatus',
      callback: _onFmRadioStatus,
    );
    _broker.subscribe(
      deviceId: widget.deviceId,
      name: 'Volume',
      callback: _onVolume,
    );

    // Pull the receiver's current state + volume. The FM receiver is NOT turned
    // on automatically; the user enables it with the Power button.
    _broker.dispatch(
      deviceId: widget.deviceId,
      name: 'QueryFmRadioStatus',
      data: null,
      store: false,
    );
    _broker.dispatch(
      deviceId: widget.deviceId,
      name: 'GetVolume',
      data: null,
      store: false,
    );
  }

  @override
  void dispose() {
    _broker.unsubscribe(widget.deviceId, 'FmRadioStatus');
    _broker.unsubscribe(widget.deviceId, 'Volume');
    _broker.dispose();
    super.dispose();
  }

  void _onFmRadioStatus(int deviceId, String name, Object? data) {
    if (!mounted || deviceId != widget.deviceId) return;
    if (data is Map<String, dynamic>) {
      setState(() => _status = RadioFmRadioStatus.fromJson(data));
    }
  }

  void _onVolume(int deviceId, String name, Object? data) {
    if (!mounted || deviceId != widget.deviceId) return;
    if (data is int) setState(() => _volume = data.clamp(0, 15));
  }

  // ---------------------------------------------------------------------------
  // Preferred stations persistence
  // ---------------------------------------------------------------------------

  void _loadStations() {
    final raw = _broker.getValue<String>(0, _stationsStorageKey);
    _stations = [];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            final s = _FmStation.fromJson(item);
            if (s != null) _stations.add(s);
          }
        }
      } catch (_) {
        // Ignore malformed stored data.
      }
    }
  }

  void _saveStations() {
    _broker.dispatch(
      deviceId: 0,
      name: _stationsStorageKey,
      data: jsonEncode(_stations.map((s) => s.toJson()).toList()),
      store: true,
    );
  }

  // ---------------------------------------------------------------------------
  // FM control actions
  // ---------------------------------------------------------------------------

  int get _currentFreqHz =>
      _status.freqHz > 0 ? _status.freqHz : _fmMinFreqHz;

  /// Toggles the FM broadcast receiver on/off (the Power button).
  void _togglePower() {
    final turnOn = !_status.isOn;
    _broker.dispatch(
      deviceId: widget.deviceId,
      name: 'FmRadioSetMode',
      data: turnOn,
      store: false,
    );
    if (turnOn) {
      _broker.dispatch(
        deviceId: widget.deviceId,
        name: 'QueryFmRadioStatus',
        data: null,
        store: false,
      );
    }
  }

  void _tuneTo(int freqHz) {
    // Ensure the receiver is on before tuning (e.g. when a preferred station is
    // tapped while the receiver is off).
    if (!_status.isOn) {
      _broker.dispatch(
        deviceId: widget.deviceId,
        name: 'FmRadioSetMode',
        data: true,
        store: false,
      );
    }
    _broker.dispatch(
      deviceId: widget.deviceId,
      name: 'FmRadioSetFrequency',
      data: freqHz,
      store: false,
    );
  }

  void _stepFrequency(int deltaHz) {
    final next = (_currentFreqHz + deltaHz).clamp(_fmMinFreqHz, _fmMaxFreqHz);
    _tuneTo(next);
  }

  void _seek(bool up) {
    _broker.dispatch(
      deviceId: widget.deviceId,
      name: up ? 'FmRadioSeekUp' : 'FmRadioSeekDown',
      data: null,
      store: false,
    );
  }

  void _stop() {
    _broker.dispatch(
      deviceId: widget.deviceId,
      name: 'FmRadioSetMode',
      data: false,
      store: false,
    );
  }

  void _setVolume(int level) {
    setState(() => _volume = level);
    _broker.dispatch(
      deviceId: widget.deviceId,
      name: 'SetVolumeLevel',
      data: level,
      store: false,
    );
  }

  // ---------------------------------------------------------------------------
  // Preferred station actions
  // ---------------------------------------------------------------------------

  Future<void> _addCurrentStation() async {
    final freqHz = _status.freqHz;
    if (freqHz <= 0) return;
    final defaultName = _formatFrequency(freqHz);
    final name = await _promptStationName(defaultName);
    if (name == null || !mounted) return;
    setState(() {
      _stations.add(
        _FmStation(name: name.isEmpty ? defaultName : name, freqHz: freqHz),
      );
    });
    _saveStations();
  }

  Future<void> _renameStation(_FmStation station) async {
    final name = await _promptStationName(station.name);
    if (name == null || !mounted) return;
    setState(() {
      station.name = name.isEmpty ? _formatFrequency(station.freqHz) : name;
    });
    _saveStations();
  }

  Future<void> _deleteStation(_FmStation station) async {
    final l10n = AppLocalizations.of(context);
    final displayName =
        station.name.isEmpty ? _formatFrequency(station.freqHz) : station.name;
    final confirmed = await DialogHelper.showConfirmDialog(
      context,
      title: l10n.fmRadioDeleteTitle,
      message: l10n.fmRadioDeleteMessage(displayName),
      okText: l10n.commonDelete,
    );
    if (!confirmed || !mounted) return;
    setState(() => _stations.remove(station));
    _saveStations();
  }

  Future<String?> _promptStationName(String initial) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        final scheme = Theme.of(context).colorScheme;
        return AlertDialog(
          backgroundColor: scheme.surface,
          title: Text(l10n.fmRadioRenameTitle),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l10n.fmRadioStationNameLabel,
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: scheme.surfaceContainerHighest,
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

  String _formatFrequency(int freqHz) =>
      (freqHz / 1000000).toStringAsFixed(1);

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return HTDialog(
      title: l10n.fmRadioTitle,
      maxWidth: 460,
      maxHeight: 640,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildFrequencyDisplay(context),
          const SizedBox(height: 12),
          _buildTransportControls(context),
          const SizedBox(height: 12),
          _buildVolumeRow(context),
          const SizedBox(height: 8),
          _buildStationsHeader(context),
          const SizedBox(height: 4),
          Expanded(child: _buildStationsList(context)),
        ],
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: DialogStyles.primaryButtonStyle(context),
          child: Text(l10n.commonClose),
        ),
      ],
    );
  }

  Widget _buildFrequencyDisplay(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final freqText = !_status.isOn
        ? l10n.fmRadioOff
        : (_status.freqHz > 0
            ? l10n.fmRadioMhz(_formatFrequency(_status.freqHz))
            : '--');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        freqText,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 40,
          fontWeight: FontWeight.bold,
          color: _status.isOn ? scheme.primary : scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildTransportControls(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final on = _status.isOn;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          tooltip: l10n.fmRadioPowerTooltip,
          icon: const Icon(Icons.power_settings_new),
          iconSize: 30,
          visualDensity: VisualDensity.compact,
          color: on ? Colors.green : scheme.onSurfaceVariant,
          onPressed: _togglePower,
        ),
        IconButton(
          tooltip: l10n.fmRadioSeekDownTooltip,
          icon: const Icon(Icons.skip_previous),
          iconSize: 30,
          visualDensity: VisualDensity.compact,
          onPressed: on ? () => _seek(false) : null,
        ),
        IconButton(
          tooltip: l10n.fmRadioStepDownTooltip,
          icon: const Icon(Icons.fast_rewind),
          iconSize: 30,
          visualDensity: VisualDensity.compact,
          onPressed: on ? () => _stepFrequency(-_fmStepHz) : null,
        ),
        IconButton(
          tooltip: l10n.fmRadioStopTooltip,
          icon: const Icon(Icons.stop),
          iconSize: 30,
          visualDensity: VisualDensity.compact,
          onPressed: on ? _stop : null,
        ),
        IconButton(
          tooltip: l10n.fmRadioStepUpTooltip,
          icon: const Icon(Icons.fast_forward),
          iconSize: 30,
          visualDensity: VisualDensity.compact,
          onPressed: on ? () => _stepFrequency(_fmStepHz) : null,
        ),
        IconButton(
          tooltip: l10n.fmRadioSeekUpTooltip,
          icon: const Icon(Icons.skip_next),
          iconSize: 30,
          visualDensity: VisualDensity.compact,
          onPressed: on ? () => _seek(true) : null,
        ),
      ],
    );
  }

  Widget _buildVolumeRow(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.volume_up, color: scheme.onSurfaceVariant),
        Expanded(
          child: Slider(
            value: _volume.toDouble().clamp(0, 15),
            min: 0,
            max: 15,
            divisions: 15,
            label: '$_volume',
            onChanged: (value) => _setVolume(value.round()),
          ),
        ),
      ],
    );
  }

  Widget _buildStationsHeader(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            l10n.fmRadioStationsHeader,
            style: DialogStyles.labelStyle.copyWith(color: scheme.onSurface),
          ),
        ),
        IconButton(
          tooltip: l10n.fmRadioAddStationTooltip,
          icon: const Icon(Icons.add_circle, color: Colors.blue),
          onPressed:
              _status.isOn && _status.freqHz > 0 ? _addCurrentStation : null,
        ),
      ],
    );
  }

  Widget _buildStationsList(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Material(
        color: scheme.surface,
        child: _stations.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    l10n.fmRadioNoStations,
                    textAlign: TextAlign.center,
                    style: DialogStyles.bodyStyle.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            : ListView.builder(
                itemCount: _stations.length,
                itemBuilder: (context, index) {
                  final station = _stations[index];
                  final displayName = station.name.isEmpty
                      ? _formatFrequency(station.freqHz)
                      : station.name;
                  final isTuned = _status.isOn &&
                      (_status.freqHz - station.freqHz).abs() < 1000;
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
                      displayName,
                      style: DialogStyles.bodyStyle,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      l10n.fmRadioMhz(_formatFrequency(station.freqHz)),
                      style: DialogStyles.bodyStyle.copyWith(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    onTap: () => _tuneTo(station.freqHz),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: l10n.commonRename,
                          icon: const Icon(Icons.edit, size: 20),
                          onPressed: () => _renameStation(station),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: l10n.commonDelete,
                          icon: const Icon(
                            Icons.delete,
                            size: 20,
                            color: Colors.red,
                          ),
                          onPressed: () => _deleteStation(station),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
