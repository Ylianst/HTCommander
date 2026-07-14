/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from the C# `RadioInfoForm`. Displays live radio information grouped
into Device Information, Device Status, Device Settings, BSS Settings and
Position sections. All data is read from the DataBroker (per-device `Info`,
`HtStatus`, `Settings`, `BssSettings`, `Position`) and the connected radio
list (`ConnectedRadios` on device 1), and the dialog updates in real time as
the broker dispatches new values.
*/

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../models/radio_models.dart';
import '../services/data_broker_client.dart';
import 'dialog_utils.dart';

/// Shows the Radio Information dialog. [initialDeviceId] selects which radio is
/// shown first; when omitted the first connected radio is used.
Future<void> showRadioInfoDialog(BuildContext context, {int? initialDeviceId}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _RadioInfoDialog(initialDeviceId: initialDeviceId),
  );
}

class _RadioInfoDialog extends StatefulWidget {
  final int? initialDeviceId;
  const _RadioInfoDialog({this.initialDeviceId});

  @override
  State<_RadioInfoDialog> createState() => _RadioInfoDialogState();
}

class _RadioInfoDialogState extends State<_RadioInfoDialog> {
  final DataBrokerClient _broker = DataBrokerClient();

  /// The currently selected radio device id, or -1 when none is connected.
  int _deviceId = -1;

  List<ConnectedRadioInfo> _radios = const [];

  RadioDevInfo? _info;
  RadioHtStatus? _htStatus;
  RadioSettings? _settings;
  RadioBssSettings? _bssSettings;
  RadioPosition? _position;
  String _friendlyName = '';

  @override
  void initState() {
    super.initState();

    // Track the connected radio list so the selector stays in sync.
    _broker.subscribe(
      deviceId: 1,
      name: 'ConnectedRadios',
      callback: _onConnectedRadiosChanged,
    );

    _loadConnectedRadios();

    // Pick the initial device: the requested one if still connected, else the
    // first available radio.
    final requested = widget.initialDeviceId;
    if (requested != null && _radios.any((r) => r.deviceId == requested)) {
      _switchToDevice(requested);
    } else if (_radios.isNotEmpty) {
      _switchToDevice(_radios.first.deviceId);
    }
  }

  @override
  void dispose() {
    _broker.dispose();
    super.dispose();
  }

  void _loadConnectedRadios() {
    final radios =
        _broker.getJsonListValue<ConnectedRadioInfo>(
          1,
          'ConnectedRadios',
          (json) => ConnectedRadioInfo.fromJson(json),
        ) ??
        const [];
    // De-duplicate by device id - the broker list can contain repeated
    // entries, and the dropdown requires each value to be unique.
    final byId = <int, ConnectedRadioInfo>{};
    for (final radio in radios) {
      if (radio.deviceId > 0) {
        byId.putIfAbsent(radio.deviceId, () => radio);
      }
    }
    _radios = byId.values.toList();
  }

  void _onConnectedRadiosChanged(int deviceId, String name, Object? data) {
    if (!mounted) return;
    setState(() {
      _loadConnectedRadios();
      // If the selected radio went away, fall back to the first available one.
      if (!_radios.any((r) => r.deviceId == _deviceId)) {
        if (_radios.isNotEmpty) {
          _switchToDevice(_radios.first.deviceId);
        } else {
          _unsubscribeFromDevice(_deviceId);
          _deviceId = -1;
          _info = null;
          _htStatus = null;
          _settings = null;
          _bssSettings = null;
          _position = null;
          _friendlyName = '';
        }
      }
    });
  }

  void _switchToDevice(int newDeviceId) {
    if (newDeviceId == _deviceId) return;
    if (_deviceId != -1) _unsubscribeFromDevice(_deviceId);

    _deviceId = newDeviceId;

    // Seed current values from the broker, then subscribe for live updates.
    _info = _broker.getJsonValue<RadioDevInfo>(
      newDeviceId,
      'Info',
      (json) => RadioDevInfo.fromJson(json),
    );
    _htStatus = _broker.getJsonValue<RadioHtStatus>(
      newDeviceId,
      'HtStatus',
      (json) => RadioHtStatus.fromJson(json),
    );
    _settings = _broker.getJsonValue<RadioSettings>(
      newDeviceId,
      'Settings',
      (json) => RadioSettings.fromJson(json),
    );
    _bssSettings = _broker.getJsonValue<RadioBssSettings>(
      newDeviceId,
      'BssSettings',
      (json) => RadioBssSettings.fromJson(json),
    );
    _position = _broker.getJsonValue<RadioPosition>(
      newDeviceId,
      'Position',
      (json) => RadioPosition.fromJson(json),
    );
    _friendlyName =
        _broker.getValue<String>(newDeviceId, 'FriendlyName', '') ?? '';

    _broker.subscribeMultiple(
      deviceId: newDeviceId,
      names: const [
        'Info',
        'HtStatus',
        'Settings',
        'BssSettings',
        'Position',
        'FriendlyName',
      ],
      callback: _onDeviceValueChanged,
    );
  }

  void _unsubscribeFromDevice(int deviceId) {
    if (deviceId <= 0) return;
    _broker.unsubscribe(deviceId, 'Info');
    _broker.unsubscribe(deviceId, 'HtStatus');
    _broker.unsubscribe(deviceId, 'Settings');
    _broker.unsubscribe(deviceId, 'BssSettings');
    _broker.unsubscribe(deviceId, 'Position');
    _broker.unsubscribe(deviceId, 'FriendlyName');
  }

  void _onDeviceValueChanged(int deviceId, String name, Object? data) {
    if (!mounted) return;
    if (deviceId != _deviceId) return;
    setState(() {
      switch (name) {
        case 'Info':
          _info = data is Map<String, dynamic>
              ? RadioDevInfo.fromJson(data)
              : null;
          break;
        case 'HtStatus':
          _htStatus = data is Map<String, dynamic>
              ? RadioHtStatus.fromJson(data)
              : null;
          break;
        case 'Settings':
          _settings = data is Map<String, dynamic>
              ? RadioSettings.fromJson(data)
              : null;
          break;
        case 'BssSettings':
          _bssSettings = data is Map<String, dynamic>
              ? RadioBssSettings.fromJson(data)
              : null;
          break;
        case 'Position':
          _position = data is Map<String, dynamic>
              ? RadioPosition.fromJson(data)
              : null;
          break;
        case 'FriendlyName':
          _friendlyName = data is String ? data : '';
          break;
      }
    });
  }

  String _radioLabel(ConnectedRadioInfo radio) {
    if (radio.friendlyName.isNotEmpty) {
      return '${radio.friendlyName} (${radio.macAddress})';
    }
    return radio.macAddress.isNotEmpty
        ? radio.macAddress
        : AppLocalizations.of(context).riRadioFallback(radio.deviceId);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 550, maxHeight: 650),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  l10n.riTitle,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              // Radio selector
              _buildRadioSelector(),
              const SizedBox(height: 12),
              // Scrollable content
              Expanded(child: _buildContent()),
              const SizedBox(height: 16),
              // Close button
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: DialogStyles.primaryButtonStyle(context),
                    child: Text(l10n.commonOk),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRadioSelector() {
    final scheme = Theme.of(context).colorScheme;
    if (_radios.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: _sectionDecoration(),
        child: Text(
          AppLocalizations.of(context).riNoRadioConnected,
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }

    final value = _radios.any((r) => r.deviceId == _deviceId)
        ? _deviceId
        : _radios.first.deviceId;

    return DropdownButtonFormField<int>(
      initialValue: value,
      decoration: InputDecoration(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      items: [
        for (final radio in _radios)
          DropdownMenuItem(
            value: radio.deviceId,
            child: Text(_radioLabel(radio)),
          ),
      ],
      onChanged: (newId) {
        if (newId != null) setState(() => _switchToDevice(newId));
      },
    );
  }

  Widget _buildContent() {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    if (_deviceId <= 0) {
      return Center(
        child: Text(
          l10n.riConnectPrompt,
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_friendlyName.isNotEmpty) ...[
            _buildSection(l10n.riSectionRadio, [
              _row(l10n.riName, _friendlyName),
            ]),
            const SizedBox(height: 12),
          ],
          _buildSection(l10n.riSectionDeviceInfo, _infoRows()),
          const SizedBox(height: 12),
          _buildSection(l10n.riSectionDeviceStatus, _statusRows()),
          const SizedBox(height: 12),
          _buildSection(l10n.riSectionDeviceSettings, _settingsRows()),
          const SizedBox(height: 12),
          _buildSection(l10n.riSectionBss, _bssRows()),
          const SizedBox(height: 12),
          _buildSection(l10n.riSectionPosition, _positionRows()),
        ],
      ),
    );
  }

  List<_InfoRow> _infoRows() {
    final l10n = AppLocalizations.of(context);
    final i = _info;
    if (i == null) return [_InfoRow(l10n.riStatus, l10n.riNoData)];

    String vendor = '${i.vendorId}';
    switch (i.vendorId) {
      case 1:
        vendor += ' - Vero';
        break;
      case 6:
        vendor += ' - BTech';
        break;
      case 255:
        vendor += ' - RadioOddity';
        break;
    }

    return [
      _row(l10n.riProductId, '${i.productId}'),
      _row(l10n.riVendorId, vendor),
      _row(l10n.riDmrSupport, _presentStr(i.supportDmr)),
      _row(l10n.riGmrsSupport, _presentStr(i.gmrs)),
      _row(l10n.riHardwareSpeaker, _presentStr(i.haveHmSpeaker)),
      _row(l10n.riHardwareVersion, '${i.hwVer}'),
      _row(l10n.riSoftwareVersion, i.softwareVersion),
      _row(l10n.riRegionCount, '${i.regionCount}'),
      _row(l10n.riMediumPower, _supportedStr(i.supportMediumPower)),
      _row(l10n.riChannelCount, '${i.channelCount}'),
      _row(l10n.riNoaa, _supportedStr(i.supportNoaa)),
      _row(l10n.riRadioLabel, _supportedStr(i.supportRadio)),
      _row(l10n.riVfo, _supportedStr(i.supportVfo)),
      _row(l10n.riFreqRangeCount, '${i.freqRangeCount}'),
    ];
  }

  List<_InfoRow> _statusRows() {
    final l10n = AppLocalizations.of(context);
    final s = _htStatus;
    if (s == null) return [_InfoRow(l10n.riStatus, l10n.riNoData)];
    return [
      _row(l10n.riPowerOn, _boolStr(s.isPowerOn)),
      _row(l10n.riInTx, _boolStr(s.isInTx)),
      _row('is_sq', _boolStr(s.isSq)),
      _row(l10n.riInRx, _boolStr(s.isInRx)),
      _row(l10n.riDoubleChannelLabel, s.doubleChannel.name.toUpperCase()),
      _row(l10n.riScanning, _boolStr(s.isScan)),
      _row(l10n.riRadioLabel, _boolStr(s.isRadio)),
      _row(l10n.riCurrentChannelId, '${s.currChId + 1}'),
      _row(l10n.riGpsLockedLabel, _boolStr(s.isGpsLocked)),
      _row(l10n.riHfpConnected, _boolStr(s.isHfpConnected)),
      _row(l10n.riAocConnected, _boolStr(s.isAocConnected)),
      _row(l10n.riRssi, '${s.rssi}'),
      _row(l10n.riCurrentRegion, '${s.currRegion}'),
    ];
  }

  List<_InfoRow> _settingsRows() {
    final l10n = AppLocalizations.of(context);
    final s = _settings;
    if (s == null) return [_InfoRow(l10n.riSettingsLabel, l10n.riNoData)];
    final autoShareLocCh = s.autoShareLocCh == 0
        ? l10n.riCurrent
        : l10n.riChannelValue(s.autoShareLocCh);
    return [
      _row('VFO A', l10n.riChannelValue(s.channelA + 1)),
      _row('VFO B', l10n.riChannelValue(s.channelB + 1)),
      _row('Scan', _boolStr(s.scan)),
      _row('AGHFP Call Mode', _boolStr(s.aghfpCallMode)),
      _row('Double Channel', '${s.doubleChannel}'),
      _row('Squelch Level', '${s.squelchLevel}'),
      _row('Tail elim', _boolStr(s.tailElim)),
      _row('Auto relay en', _boolStr(s.autoRelayEn)),
      _row('Auto power on', _boolStr(s.autoPowerOn)),
      _row('Keep AGHFP link', _boolStr(s.keepAghfpLink)),
      _row('Mic gain', '${s.micGain}'),
      _row('TX hold time', '${s.txHoldTime}'),
      _row('TX time limit', '${s.txTimeLimit}'),
      _row('Local Speaker', '${s.localSpeaker}'),
      _row('BT mic gain', '${s.btMicGain}'),
      _row('Adaptive Response', _boolStr(s.adaptiveResponse)),
      _row('DIS Tone', _boolStr(s.disTone)),
      _row('Power saving mode', _boolStr(s.powerSavingMode)),
      _row('Auto power off', '${s.autoPowerOff}'),
      _row('Auto share location ch', autoShareLocCh),
      _row('HW speaker', '${s.hmSpeaker}'),
      _row('Positioning system', '${s.positioningSystem}'),
      _row('Time offset', '${s.timeOffset}'),
      _row('Use freq range 2', _boolStr(s.useFreqRange2)),
      _row('PTT lock', _boolStr(s.pttLock)),
      _row('Leading sync bit en', _boolStr(s.leadingSyncBitEn)),
      _row('Pairing at power on', _boolStr(s.pairingAtPowerOn)),
      _row('Screen Timeout', '${s.screenTimeout}'),
      _row('VFO x', '${s.vfoX}'),
      _row('Imperial Units', _boolStr(s.imperialUnit)),
      _row('Weather Mode', '${s.wxMode}'),
      _row('NOAA Channel', '${s.noaaCh}'),
      _row('VFOl tx power', '${s.vfolTxPowerX}'),
      _row('VFO2 tx power', '${s.vfo2TxPowerX}'),
      _row('Dis digital mute', _boolStr(s.disDigitalMute)),
      _row('Signaling ecc en', _boolStr(s.signalingEccEn)),
      _row('Ch data lock', _boolStr(s.chDataLock)),
      _row('VFO1 mod freq', '${s.vfo1ModFreqX}'),
      _row('VFO2 mod freq', '${s.vfo2ModFreqX}'),
    ];
  }

  List<_InfoRow> _bssRows() {
    final l10n = AppLocalizations.of(context);
    final b = _bssSettings;
    if (b == null) return [_InfoRow(l10n.riSettingsLabel, l10n.riNoData)];
    final shareInterval = b.locationShareInterval == 0
        ? l10n.riOff
        : l10n.riSeconds(b.locationShareInterval);
    return [
      _row('Allow Position Check', _boolStr(b.allowPositionCheck)),
      _row('APRS Callsign', '${b.aprsCallsign}-${b.aprsSsid}'),
      _row('APRS Symbol', b.aprsSymbol),
      _row('Beacon Message', b.beaconMessage),
      _row('BSS User Id Lower', '${b.bssUserIdLower}'),
      _row('Location Share Interval', shareInterval),
      _row('Max Fwd Times', '${b.maxFwdTimes}'),
      _row('Packet Format', '${b.packetFormat}'),
      _row('PTT Release ID Info', b.pttReleaseIdInfo),
      _row('PTT Release Send BSS User Id', _boolStr(b.pttReleaseSendBssUserId)),
      _row('PTT Release Send Id Info', _boolStr(b.pttReleaseSendIdInfo)),
      _row('PTT Release Send Location', _boolStr(b.pttReleaseSendLocation)),
      _row('Send Pwr Voltage', _boolStr(b.sendPwrVoltage)),
      _row('Should Share Location', _boolStr(b.shouldShareLocation)),
      _row('Time To Live', '${b.timeToLive}'),
    ];
  }

  List<_InfoRow> _positionRows() {
    final l10n = AppLocalizations.of(context);
    final p = _position;
    if (p == null) return [_InfoRow(l10n.riStatus, l10n.riNoGpsData)];
    if (!p.locked) return [_InfoRow(l10n.riStatus, l10n.riNoGpsLock)];
    final rows = <_InfoRow>[
      _row(l10n.riStatus, l10n.riGpsLocked),
      _row(l10n.gpsLatitude, _dmsStr(p.latitude, isLatitude: true)),
      _row(l10n.gpsLongitude, _dmsStr(p.longitude, isLatitude: false)),
      _row(l10n.riAccuracy, l10n.riMeters(p.accuracy.toStringAsFixed(0))),
      _row(l10n.gpsAltitude, l10n.riMeters(p.altitude.toStringAsFixed(0))),
      _row(l10n.gpsSpeed, p.speed.toStringAsFixed(0)),
      _row(l10n.gpsHeading, l10n.riDegrees(p.heading.toStringAsFixed(0))),
    ];
    if (p.receivedTime != null) {
      rows.add(_row(l10n.riReceivedTime, _formatTime(p.receivedTime!)));
    }
    if (p.timestamp != null) {
      rows.add(_row(l10n.riGpsTimeLocal, _formatTime(p.timestamp!.toLocal())));
      rows.add(_row(l10n.riGpsTimeUtcLabel, _formatTime(p.timestamp!.toUtc())));
    }
    return rows;
  }

  String _boolStr(bool v) =>
      v ? AppLocalizations.of(context).riTrue : AppLocalizations.of(context).riFalse;

  String _presentStr(bool v) => v
      ? AppLocalizations.of(context).riPresent
      : AppLocalizations.of(context).riNotPresent;

  String _supportedStr(bool v) => v
      ? AppLocalizations.of(context).riSupported
      : AppLocalizations.of(context).riNotSupported;

  /// Formats a decimal degree value as degrees/minutes/seconds with a
  /// hemisphere suffix, matching the C# `ConvertLatitudeToDms` output.
  static String _dmsStr(double value, {required bool isLatitude}) {
    final direction = value >= 0
        ? (isLatitude ? 'N' : 'E')
        : (isLatitude ? 'S' : 'W');
    final abs = value.abs();
    final degrees = abs.floor();
    final minutesDecimal = (abs - degrees) * 60;
    final minutes = minutesDecimal.floor();
    final seconds = (minutesDecimal - minutes) * 60;
    return '$degrees\u00B0 $minutes\' ${seconds.toStringAsFixed(2)}" $direction';
  }

  static String _formatTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  _InfoRow _row(String label, String value) => _InfoRow(label, value);

  /// Shows a "Copy" context menu (long-press or right-click) that copies the
  /// given [value] to the clipboard.
  Future<void> _showRowContextMenu(Offset globalPosition, String value) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem<String>(value: 'copy', child: Text('Copy')),
      ],
    );
    if (selected != 'copy') return;
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Widget _buildSection(String title, List<_InfoRow> rows) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _sectionDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 16, color: scheme.outlineVariant),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPressStart: (details) =>
                  _showRowContextMenu(details.globalPosition, rows[i].value),
              onSecondaryTapDown: (details) =>
                  _showRowContextMenu(details.globalPosition, rows[i].value),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: Text(
                      rows[i].label,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  Expanded(
                    flex: 6,
                    child: Text(
                      rows[i].value,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  BoxDecoration _sectionDecoration() {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return BoxDecoration(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: theme.shadowColor.withValues(alpha: 0.05),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }
}

/// A single label/value pair shown inside an info section.
class _InfoRow {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);
}
