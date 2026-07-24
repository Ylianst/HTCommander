import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/data_broker_client.dart';
import '../models/radio_models.dart';
import '../echolink/echolink_client.dart' show echoLinkDeviceId;
import '../echolink/echolink_station.dart';

/// A slim horizontal radio status bar shown in compact (mobile) mode below the
/// menu bar and above the tabs, when the "Radio" tab is not selected.
///
/// It mirrors the summary information from the Radio status tab
/// (see [RadioPanelControl]) and is hooked up to the same DataBroker streams.
class RadioStatusBar extends StatefulWidget {
  /// The device ID to display. Set to -1 for disconnected state.
  final int deviceId;

  /// Callback when the connect button is pressed.
  final VoidCallback? onConnectPressed;

  const RadioStatusBar({super.key, this.deviceId = -1, this.onConnectPressed});

  @override
  State<RadioStatusBar> createState() => _RadioStatusBarState();
}

class _RadioStatusBarState extends State<RadioStatusBar> {
  // DataBroker client for subscriptions
  final DataBrokerClient _broker = DataBrokerClient();

  // Cached state from broker
  String? _currentState;
  RadioHtStatus? _currentHtStatus;
  RadioSettings? _currentSettings;
  RadioFmRadioStatus? _fmRadioStatus;
  // Live tuned frequency (Hz) while in frequency mode, pushed by the radio via
  // the freqModeStatusChanged notification. 0 when unknown / not in freq mode.
  int _freqModeFreqHz = 0;
  // True while the radio is in frequency (VFO) mode, derived from the reliable
  // freqModeStatusChanged status flags (curr channel id is not reliable).
  bool _freqModeActive = false;
  List<RadioChannelInfo>? _currentChannels;
  RadioLockState? _lockState;
  bool _gpsEnabled = false;
  RadioPosition? _position;

  int _vfo2LastChannelId = -1;

  // EchoLink (device 200) state, used when this bar displays EchoLink.
  String? _echoLinkState;
  StationData? _echoLinkConnected;
  // Receive level (0..1) and transmit state for the EchoLink RSSI/TX bar,
  // mirroring the physical radio's signal / transmit indicator.
  double _echoLinkRxLevel = 0;
  bool _echoLinkTransmitting = false;

  // Display colors (match the Radio status tab / C# app).
  static const Color _displayBgColor = Color(0xFF565658);
  static const Color _activeVfoColor = Color(0xFFDDD300); // Yellow when active
  static const Color _inactiveColor = Color(0xFFD3D3D3); // LightGray
  // Slightly darker shade of the panel color used to indicate RSSI level by
  // filling the background from the left as the signal gets stronger.
  static const Color _rssiFillColor = Color(0xFF3D3D3F);
  // Dark red tint used to fill the whole background while transmitting.
  static const Color _txFillColor = Color(0xFF5A2A2A);

  @override
  void initState() {
    super.initState();
    _subscribeToDevice();
  }

  @override
  void didUpdateWidget(RadioStatusBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deviceId != widget.deviceId) {
      _broker.unsubscribeAll();
      _clearCachedState();
      _subscribeToDevice();
    }
  }

  @override
  void dispose() {
    _broker.dispose();
    super.dispose();
  }

  void _clearCachedState() {
    _currentState = null;
    _currentHtStatus = null;
    _currentSettings = null;
    _fmRadioStatus = null;
    _freqModeFreqHz = 0;
    _freqModeActive = false;
    _currentChannels = null;
    _lockState = null;
    _gpsEnabled = false;
    _position = null;
    _echoLinkState = null;
    _echoLinkConnected = null;
    _echoLinkRxLevel = 0;
    _echoLinkTransmitting = false;
  }

  void _subscribeToDevice() {
    if (widget.deviceId <= 0) return;

    // EchoLink (device 200) is an internet-only radio with its own streams.
    if (widget.deviceId == echoLinkDeviceId) {
      _broker.subscribeMultiple(
        deviceId: echoLinkDeviceId,
        names: ['State', 'ConnectedStation'],
        callback: _onBrokerEvent,
      );
      _broker.subscribe(
        deviceId: echoLinkDeviceId,
        name: 'RxLevel',
        callback: _onBrokerEvent,
      );
      _broker.subscribe(
        deviceId: echoLinkDeviceId,
        name: 'TxActive',
        callback: _onBrokerEvent,
      );
      _loadInitialState();
      return;
    }

    _broker.subscribeMultiple(
      deviceId: widget.deviceId,
      names: [
        'State',
        'HtStatus',
        'Settings',
        'FmRadioStatus',
        'FreqModeFreq',
        'FreqModeActive',
        'Channels',
        'LockState',
        'GpsEnabled',
        'Position',
      ],
      callback: _onBrokerEvent,
    );

    _loadInitialState();
  }

  void _loadInitialState() {
    if (widget.deviceId <= 0) return;

    if (widget.deviceId == echoLinkDeviceId) {
      _echoLinkState = _broker.getValue<String>(echoLinkDeviceId, 'State');
      _echoLinkConnected = _stationFromMap(
        _broker.getValueDynamic(echoLinkDeviceId, 'ConnectedStation'),
      );
      final double rx =
          (_broker.getValue<num>(echoLinkDeviceId, 'RxLevel') ?? 0).toDouble();
      _echoLinkRxLevel = (rx.clamp(0.0, 1.0) * 15).round() / 15.0;
      _echoLinkTransmitting =
          _broker.getValue<bool>(echoLinkDeviceId, 'TxActive') ?? false;
      if (mounted) setState(() {});
      return;
    }

    _currentState = _broker.getValue<String>(widget.deviceId, 'State');
    _currentHtStatus = _broker.getJsonValue<RadioHtStatus>(
      widget.deviceId,
      'HtStatus',
      (json) => RadioHtStatus.fromJson(json),
    );
    _currentSettings = _broker.getJsonValue<RadioSettings>(
      widget.deviceId,
      'Settings',
      (json) => RadioSettings.fromJson(json),
    );
    _fmRadioStatus = _broker.getJsonValue<RadioFmRadioStatus>(
      widget.deviceId,
      'FmRadioStatus',
      (json) => RadioFmRadioStatus.fromJson(json),
    );
    _freqModeFreqHz =
        _broker.getValue<int>(widget.deviceId, 'FreqModeFreq') ?? 0;
    _freqModeActive =
        _broker.getValue<bool>(widget.deviceId, 'FreqModeActive') ?? false;
    _currentChannels = _broker.getJsonListValue<RadioChannelInfo>(
      widget.deviceId,
      'Channels',
      (json) => RadioChannelInfo.fromJson(json),
    );
    _lockState = _broker.getJsonValue<RadioLockState>(
      widget.deviceId,
      'LockState',
      (json) => RadioLockState.fromJson(json),
    );
    _gpsEnabled =
        _broker.getValue<bool>(widget.deviceId, 'GpsEnabled') ?? false;
    _position = _broker.getJsonValue<RadioPosition>(
      widget.deviceId,
      'Position',
      (json) => RadioPosition.fromJson(json),
    );

    if (mounted) setState(() {});
  }

  void _onBrokerEvent(int deviceId, String name, Object? data) {
    if (deviceId != widget.deviceId) return;
    if (!mounted) return;

    setState(() {
      if (widget.deviceId == echoLinkDeviceId) {
        switch (name) {
          case 'State':
            _echoLinkState = data as String?;
            break;
          case 'ConnectedStation':
            _echoLinkConnected = _stationFromMap(data);
            break;
          case 'RxLevel':
            final double raw = (data is num) ? data.toDouble() : 0.0;
            _echoLinkRxLevel = (raw.clamp(0.0, 1.0) * 15).round() / 15.0;
            break;
          case 'TxActive':
            _echoLinkTransmitting = data == true;
            break;
        }
        return;
      }
      switch (name) {
        case 'State':
          _currentState = data as String?;
          break;
        case 'HtStatus':
          if (data is Map<String, dynamic>) {
            _currentHtStatus = RadioHtStatus.fromJson(data);
          }
          break;
        case 'Settings':
          if (data is Map<String, dynamic>) {
            _currentSettings = RadioSettings.fromJson(data);
          }
          break;
        case 'FmRadioStatus':
          if (data is Map<String, dynamic>) {
            _fmRadioStatus = RadioFmRadioStatus.fromJson(data);
          }
          break;
        case 'FreqModeFreq':
          _freqModeFreqHz = data as int? ?? 0;
          break;
        case 'FreqModeActive':
          _freqModeActive = data as bool? ?? false;
          break;
        case 'Channels':
          if (data is List) {
            _currentChannels = data
                .whereType<Map<String, dynamic>>()
                .map((e) => RadioChannelInfo.fromJson(e))
                .toList();
          }
          break;
        case 'LockState':
          if (data is Map<String, dynamic>) {
            _lockState = RadioLockState.fromJson(data);
          }
          break;
        case 'GpsEnabled':
          _gpsEnabled = data as bool? ?? false;
          break;
        case 'Position':
          if (data is Map<String, dynamic>) {
            _position = RadioPosition.fromJson(data);
          }
          break;
      }
    });
  }

  void _onConnect() {
    if (widget.onConnectPressed != null) {
      widget.onConnectPressed!();
      return;
    }
    // Fallback: dispatch connect request to the main form via DataBroker.
    _broker.dispatch(
      deviceId: 1,
      name: 'RadioConnect',
      data: true,
      store: false,
    );
  }

  static StationData? _stationFromMap(Object? data) {
    if (data is! Map) return null;
    StationStatus status = StationStatus.unknown;
    final Object? s = data['Status'] ?? data['status'];
    if (s is String) {
      status = StationStatus.values.firstWhere(
        (v) => v.name == s,
        orElse: () => StationStatus.unknown,
      );
    }
    return StationData(
      callsign: (data['Callsign'] ?? data['callsign'] ?? '') as String,
      description: (data['Description'] ?? data['description'] ?? '') as String,
      status: status,
      time: (data['Time'] ?? data['time'] ?? '') as String,
      id: (data['Id'] ?? data['id'] ?? 0) as int,
      ip: (data['Ip'] ?? data['ip'] ?? '') as String,
    );
  }

  // --- Computed properties (mirroring RadioPanelControl) --------------------

  /// True when this bar is displaying the internet-only EchoLink radio.
  bool get _isEchoLink => widget.deviceId == echoLinkDeviceId;

  /// True while an EchoLink QSO is in progress.
  bool get _echoLinkInQso => _echoLinkState == 'Connected';

  /// VFO A large label for EchoLink: the connected station callsign while in a
  /// QSO, otherwise "EchoLink" (mirrors the Radio tab's EchoLink display).
  String get _echoLinkVfoLabel =>
      _echoLinkInQso ? (_echoLinkConnected?.callsign ?? '') : 'EchoLink';

  /// VFO A sub-line for EchoLink: the station description while in a QSO,
  /// otherwise the online state text.
  String get _echoLinkVfoSub {
    if (_echoLinkInQso) return _echoLinkConnected?.description ?? '';
    return switch (_echoLinkState) {
      'Connecting' => 'Connecting...',
      'Online' => 'Online',
      _ => 'Offline',
    };
  }

  Color get _echoLinkVfoColor =>
      _echoLinkInQso ? _activeVfoColor : _inactiveColor;

  bool get _isConnected => _currentState == 'Connected';

  String get _connectionState {
    final l10n = AppLocalizations.of(context);
    if (widget.deviceId <= 0 || _currentState == null) {
      return l10n.stateDisconnected;
    }
    switch (_currentState) {
      case 'Disconnected':
      case 'NotRadioFound':
      case 'BluetoothNotAvailable':
        return l10n.stateDisconnected;
      case 'Connecting':
        return l10n.stateConnecting;
      case 'Connected':
        return l10n.stateConnected;
      case 'UnableToConnect':
        return l10n.stateUnableToConnect;
      case 'AccessDenied':
        return l10n.stateAccessDenied;
      case 'MultiRadioSelect':
        return l10n.stateSelectRadio;
      default:
        return _currentState ?? l10n.stateDisconnected;
    }
  }

  RadioChannelInfo? get _channelA {
    if (_currentChannels == null || _currentSettings == null) return null;
    final idx = _currentSettings!.channelA;
    if (idx < 0 || idx >= _currentChannels!.length) return null;
    return _currentChannels![idx];
  }

  RadioChannelInfo? get _channelB {
    if (_currentChannels == null || _currentSettings == null) return null;
    final idx = _currentSettings!.channelB;
    if (idx < 0 || idx >= _currentChannels!.length) return null;
    return _currentChannels![idx];
  }

  /// True while the radio is in frequency (VFO) mode. Driven by the reliable
  /// freqModeStatusChanged status flags; NOAA weather (settings-based) is also
  /// treated as frequency mode so its live frequency is shown.
  bool get _isFrequencyMode => _freqModeActive || _isWeatherMode;

  /// True when the built-in FM broadcast receiver is on. FM broadcast is shown
  /// on VFO B, so this keeps VFO A on its normal channel.
  bool get _isFmBroadcast => _fmRadioStatus?.isOn ?? false;

  /// True when the radio is on the NOAA weather sub-band.
  bool get _isWeatherMode => (_currentSettings?.wxMode ?? 0) != 0;

  /// True when VFO A should show a live frequency instead of a channel name.
  /// FM broadcast (shown on VFO B) can be active at the same time as frequency
  /// mode, so it does not suppress the VFO A frequency display.
  bool get _showFrequencyMode => _isFrequencyMode;

  /// NOAA weather frequencies (Hz) mapped to their channel number (WX1..WX7).
  static const Map<int, int> _noaaWeatherChannel = {
    162550000: 1,
    162400000: 2,
    162475000: 3,
    162425000: 4,
    162450000: 5,
    162500000: 6,
    162525000: 7,
  };

  /// The current VFO / NOAA tuned frequency in Hz (0 when unknown).
  int get _vfoFreqHz {
    if (_freqModeFreqHz > 0) return _freqModeFreqHz;
    final s = _currentSettings;
    if (s != null) {
      final hz = s.vfoX == 2 ? s.vfo2FreqHz : s.vfo1FreqHz;
      if (hz > 0) return hz;
    }
    return 0;
  }

  /// The live VFO/NOAA frequency (MHz string, no unit) shown on VFO A while in
  /// frequency mode.
  String get _frequencyModeFreq {
    final hz = _vfoFreqHz;
    return hz > 0 ? (hz / 1000000).toStringAsFixed(3) : '';
  }

  /// The small-box caption shown under the VFO A frequency while in frequency
  /// mode: the numbered weather channel when the frequency matches a NOAA
  /// channel, otherwise a generic Weather label.
  String get _frequencyModeCaption {
    final l10n = AppLocalizations.of(context);
    final wx = _noaaWeatherChannel[_vfoFreqHz];
    if (wx != null) return l10n.riWeatherChannel(wx);
    if (_isWeatherMode) return l10n.riWeather;
    return '';
  }

  bool get _isDualChannel => _currentSettings?.doubleChannel == 1;
  bool get _isScanning => _currentSettings?.scan ?? false;

  String get _vfo1Label {
    // In frequency mode the large label shows the live frequency (with unit)
    // instead of a channel name; the mode caption drops to the frequency line.
    if (_showFrequencyMode) {
      final freq = _frequencyModeFreq;
      if (freq.isNotEmpty) return '$freq MHz';
      final caption = _frequencyModeCaption;
      if (caption.isNotEmpty) return caption;
      return '';
    }
    final ch = _channelA;
    if (ch == null) return '';
    if (ch.name.isNotEmpty) return ch.name;
    if (ch.rxFreq > 0) return (ch.rxFreq / 1000000).toStringAsFixed(3);
    return 'Empty';
  }

  String get _vfo1Freq {
    // In frequency mode the smaller line shows the mode caption (Weather /
    // Broadcast FM); empty for a plain VFO free-tune or until a frequency exists.
    if (_showFrequencyMode) {
      return _frequencyModeFreq.isNotEmpty ? _frequencyModeCaption : '';
    }
    final ch = _channelA;
    if (ch == null) return '';
    if (ch.name.isEmpty) return '';
    return ch.rxFreq > 0 ? '${ch.frequencyDisplay} MHz' : '';
  }

  String get _vfo2Freq {
    // FM broadcast uses VFO B: show "FM" under the frequency.
    if (_isFmBroadcast) return 'FM';
    // In frequency mode VFO B is not active; keep it blank.
    if (_showFrequencyMode) return '';
    if (_isScanning) {
      if (_currentHtStatus != null && _currentChannels != null) {
        final currChId = _currentHtStatus!.currChId;
        if (currChId < _currentChannels!.length) {
          final scanCh = _currentChannels![currChId];
          if (_channelA != null && scanCh.channelId == _channelA!.channelId) {
            if (_vfo2LastChannelId >= 0 &&
                _vfo2LastChannelId < _currentChannels!.length) {
              final ch = _currentChannels![_vfo2LastChannelId];
              return ch.rxFreq > 0 ? '${ch.frequencyDisplay} MHz' : '';
            }
            return '';
          }
          return scanCh.rxFreq > 0 ? '${scanCh.frequencyDisplay} MHz' : '';
        }
      }
      return '';
    }

    if (!_isDualChannel) return '';

    final ch = _channelB;
    if (ch == null || ch.name.isEmpty) return '';
    return ch.rxFreq > 0 ? '${ch.frequencyDisplay} MHz' : '';
  }

  String get _vfo2Label {
    // FM broadcast uses VFO B: show the FM station frequency (large text).
    if (_isFmBroadcast) {
      final fm = _fmRadioStatus;
      if (fm != null && fm.freqHz > 0) return '${fm.frequencyDisplay} MHz';
      return 'FM';
    }
    // In frequency mode VFO B is not active; keep it blank.
    if (_showFrequencyMode) return '';
    if (_isScanning) {
      if (_currentHtStatus != null && _currentChannels != null) {
        final currChId = _currentHtStatus!.currChId;
        if (currChId < _currentChannels!.length) {
          final scanCh = _currentChannels![currChId];
          if (_channelA != null && scanCh.channelId == _channelA!.channelId) {
            if (_vfo2LastChannelId >= 0 &&
                _vfo2LastChannelId < _currentChannels!.length) {
              return _currentChannels![_vfo2LastChannelId].name;
            }
            return 'Scanning...';
          }
          _vfo2LastChannelId = currChId;
          return scanCh.name;
        }
      }
      return 'Scanning...';
    }

    if (!_isDualChannel) return '';

    final ch = _channelB;
    if (ch == null) return '';
    if (ch.name.isNotEmpty) return ch.name;
    if (ch.rxFreq > 0) return (ch.rxFreq / 1000000).toStringAsFixed(3);
    return 'Empty';
  }

  int get _rssi => _currentHtStatus?.rssi ?? 0;
  bool get _isTransmitting => _currentHtStatus?.isInTx ?? false;
  bool get _isReceiving => _currentHtStatus?.isInRx ?? false;

  /// Summary of the radio state for the 3rd area (e.g. "Scanning", lock usage).
  /// When the radio is both scanning and has a usage, both are shown combined
  /// (e.g. "Scanning / BBS"). Generally a usage prevents scanning, so the same
  /// text area is reused for both.
  String get _radioStatusText {
    final bool scanning = _isScanning;
    final String usage =
        (_lockState != null && _lockState!.isLocked) ? _lockState!.usage : '';

    if (scanning && usage.isNotEmpty) return 'Scanning / $usage';
    if (scanning) return 'Scanning';
    if (usage.isNotEmpty) return usage;
    if (_isDualChannel) return 'Dual Watch';
    return '';
  }

  String get _gpsStatus {
    if (!_isConnected || !_gpsEnabled) return '';
    if (_position == null) return 'No GPS Lock';
    return _position!.locked ? 'GPS Lock' : 'No GPS Lock';
  }

  Color get _vfo1Color {
    if (!_isConnected) return _inactiveColor;

    // In frequency mode only VFO A is active.
    if (_showFrequencyMode) return _activeVfoColor;

    if (_channelB != null && _isDualChannel && _currentHtStatus != null) {
      if (_currentHtStatus!.doubleChannel == RadioChannelType.a) {
        if ((_isReceiving || _isTransmitting) &&
            _currentHtStatus!.currChId == _channelB!.channelId) {
          return _inactiveColor; // VFO1 inactive, VFO2 active
        }
      }
    }
    return _activeVfoColor;
  }

  Color get _vfo2Color {
    if (!_isConnected || _vfo2Label.isEmpty) return _inactiveColor;

    // In frequency mode VFO B is inactive.
    if (_showFrequencyMode) return _inactiveColor;

    if (_channelB != null && _isDualChannel && _currentHtStatus != null) {
      if (_currentHtStatus!.doubleChannel == RadioChannelType.a) {
        if ((_isReceiving || _isTransmitting) &&
            _currentHtStatus!.currChId == _channelB!.channelId) {
          return _activeVfoColor; // VFO2 active
        }
      }
    }
    return _inactiveColor;
  }

  // --- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(gradient: _rssiBackgroundGradient),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
        child: _isEchoLink
            ? _buildEchoLinkRow()
            : (_isConnected
                ? _buildConnectedRow()
                : _buildDisconnectedRow()),
      ),
    );
  }

  /// Background gradient that fills from the left as the RSSI value grows from
  /// 0 to 15, using a slightly darker shade of the base panel color. When
  /// transmitting, the whole bar is tinted with a dark red instead.
  LinearGradient get _rssiBackgroundGradient {
    // EchoLink has no RSSI; use its receive-level meter (0..1) and transmit
    // indicator to drive the same fill effect.
    if (_isEchoLink) {
      final bool active = _echoLinkRxLevel > 0 || _echoLinkTransmitting;
      if (!active) {
        return const LinearGradient(
          colors: [_displayBgColor, _displayBgColor],
        );
      }
      final Color fillColor =
          _echoLinkTransmitting ? _txFillColor : _rssiFillColor;
      final double fraction = _echoLinkTransmitting
          ? 1.0
          : _echoLinkRxLevel.clamp(0.0, 1.0);
      return LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [fillColor, fillColor, _displayBgColor, _displayBgColor],
        stops: [0.0, fraction, fraction, 1.0],
      );
    }

    final bool active = _isConnected && (_rssi > 0 || _isTransmitting);
    if (!active) {
      return const LinearGradient(
        colors: [_displayBgColor, _displayBgColor],
      );
    }

    final Color fillColor = _isTransmitting ? _txFillColor : _rssiFillColor;
    final double fraction = _isTransmitting
        ? 1.0
        : (_rssi / 15).clamp(0.0, 1.0);

    return LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [fillColor, fillColor, _displayBgColor, _displayBgColor],
      stops: [0.0, fraction, fraction, 1.0],
    );
  }

  Widget _buildDisconnectedRow() {
    final l10n = AppLocalizations.of(context);
    final bool isConnecting = _currentState == 'Connecting';
    return Row(
      children: [
        Expanded(
          child: Text(
            _connectionState,
            style: const TextStyle(
              color: _inactiveColor,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SizedBox(
          height: 30,
          child: ElevatedButton(
            onPressed: isConnecting ? null : _onConnect,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              visualDensity: VisualDensity.compact,
            ),
            child: Text(isConnecting ? l10n.stateConnecting : l10n.commonConnect),
          ),
        ),
      ],
    );
  }

  Widget _buildConnectedRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Area 1: VFO A channel name + frequency
        Expanded(child: _buildVfo(_vfo1Label, _vfo1Freq, _vfo1Color)),
        _buildAreaDivider(),
        // Area 2: VFO B channel name + frequency
        Expanded(child: _buildVfo(_vfo2Label, _vfo2Freq, _vfo2Color)),
        _buildAreaDivider(),
        // Area 3: Radio status + GPS status
        Expanded(child: _buildStatusArea()),
      ],
    );
  }

  Widget _buildAreaDivider() {
    return Container(
      width: 1,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: const Color(0xFF999999),
    );
  }

  /// Row shown when this bar displays the internet-only EchoLink radio: VFO A
  /// mirrors the Radio tab's EchoLink display (station/state), VFO B is blank,
  /// and the usage area shows "Internet".
  Widget _buildEchoLinkRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Area 1: EchoLink VFO A (two lines of text, like the Radio tab).
        Expanded(
          child: _buildVfo(
            _echoLinkVfoLabel,
            _echoLinkVfoSub,
            _echoLinkVfoColor,
          ),
        ),
        _buildAreaDivider(),
        // Area 2: VFO B is unused for EchoLink.
        Expanded(child: _buildVfo('', '', _inactiveColor)),
        _buildAreaDivider(),
        // Area 3: usage label.
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text(
                'Internet',
                style: TextStyle(
                  color: _inactiveColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVfo(String label, String freq, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.isEmpty ? '—' : label,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (freq.isNotEmpty)
          Text(
            freq,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w400,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }

  Widget _buildStatusArea() {
    final String radioStatus = _radioStatusText;
    final String gpsStatus = _gpsStatus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (radioStatus.isNotEmpty)
          Text(
            radioStatus,
            style: const TextStyle(
              color: _inactiveColor,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        if (gpsStatus.isNotEmpty)
          Text(
            gpsStatus,
            style: const TextStyle(color: _inactiveColor, fontSize: 10),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}
