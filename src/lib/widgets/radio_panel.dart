import 'dart:convert';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../services/data_broker_client.dart';
import '../models/radio_models.dart';
import '../radio/radio_models.dart' as radio;
import '../dialogs/radio_channel_dialog.dart';
import '../dialogs/gps_details_dialog.dart';
import '../dialogs/fm_radio_dialog.dart';
import '../utils/channel_colors.dart';
import '../utils/channel_share.dart';
import '../utils/web_channel_import/web_channel_import.dart';

/// Radio panel control widget - displays radio image, VFO frequencies, and status
class RadioPanelControl extends StatefulWidget {
  /// The device ID to display. Set to -1 for disconnected state.
  final int deviceId;

  /// Callback when the connect button is pressed
  final VoidCallback? onConnectPressed;

  const RadioPanelControl({
    super.key,
    this.deviceId = -1,
    this.onConnectPressed,
  });

  @override
  State<RadioPanelControl> createState() => _RadioPanelControlState();
}

class _RadioPanelControlState extends State<RadioPanelControl> {
  // DataBroker client for subscriptions
  final DataBrokerClient _broker = DataBrokerClient();

  // Per-channel tile keys, used to hit-test which slot a web page URL was
  // dropped onto so its channel can be imported into that slot.
  final Map<int, GlobalKey> _channelTileKeys = {};

  // Cached state from broker
  String? _currentState;
  RadioHtStatus? _currentHtStatus;
  RadioSettings? _currentSettings;
  RadioFmRadioStatus? _fmRadioStatus;
  // Preferred FM broadcast stations (freq in Hz + name), persisted on device 0
  // under 'FmRadioStations' by the FM Radio dialog. Used to label VFO B with the
  // station name when the tuned FM frequency matches a saved station.
  List<({int freqHz, String name})> _fmStations = const [];
  // Live tuned frequency (Hz) while in frequency mode, pushed by the radio via
  // the freqModeStatusChanged notification. 0 when unknown / not in freq mode.
  int _freqModeFreqHz = 0;
  // True while the radio is in frequency (VFO) mode, derived from the reliable
  // freqModeStatusChanged status flags (curr channel id is not reliable).
  bool _freqModeActive = false;
  List<RadioChannelInfo>? _currentChannels;
  // Full channel objects (with tones, de-emphasis, power, etc.) keyed by
  // channelId, used as the payload when a channel is dragged out to be shared.
  Map<int, radio.RadioChannelInfo> _fullChannels = {};
  String _friendlyName = '';
  bool _gpsEnabled = false;
  RadioPosition? _position;
  RadioLockState? _lockState;

  // UI state
  bool _showAllChannels = false;
  // Whether channel tiles display the frequency under the name (View menu).
  bool _showChannelFrequency = true;
  int _vfo2LastChannelId = -1;

  // In compact mode (limited height), false shows the radio display while true
  // shows the channel list filling the whole area. Toggled via a small button.
  bool _compactShowChannels = false;

  // Display panel background color (same as C# app)
  static const Color _displayBgColor = Color(0xFF565658);
  static const Color _activeVfoColor = Color(0xFFDDD300); // Yellow when active
  static const Color _inactiveColor = Color(0xFFD3D3D3); // LightGray

  // --- Radio image geometry (Radio.png is 341x848). The LCD display sits at
  // (84, 215) with size (205, 189) in the original image. ---------------------
  static const double _kImageAspectRatio = 848 / 341;
  static const double _kDisplayLeft = 84 / 341;
  static const double _kDisplayTop = 215 / 848;
  static const double _kDisplayWidth = 205 / 341;
  static const double _kDisplayHeight = 189 / 848;
  static const double _kFriendlyNameTop = 106 / 848; // above the display
  static const double _kFixedImageWidth = 280.0; // fixed radio width
  static const double _kDisplayLeftOffset = -8.0; // fine-tuning
  static const double _kFriendlyNameTopOffset = 8.0; // fine-tuning

  // Below this available height the panel switches to compact mode (show the
  // radio OR the channels, toggled by a button).
  static const double _kCompactModeMaxHeight = 320.0;
  // At/above this available height the decorative top of the radio image (and
  // friendly name) is shown in full. Between this height and the fully-cropped
  // height the top is progressively cropped down to 6px above the VFO A label.
  static const double _kCropStartHeight = 560.0;

  @override
  void initState() {
    super.initState();
    _showAllChannels =
        (_broker.getValue<int>(0, 'ShowAllChannels', 0) ?? 0) == 1;
    _showChannelFrequency =
        (_broker.getValue<int>(0, 'ShowChannelFrequency', 1) ?? 1) == 1;
    _broker.subscribe(
      deviceId: 0,
      name: 'ShowAllChannels',
      callback: _onShowAllChannelsChanged,
    );
    _broker.subscribe(
      deviceId: 0,
      name: 'ShowChannelFrequency',
      callback: _onShowChannelFrequencyChanged,
    );
    _loadFmStations();
    _broker.subscribe(
      deviceId: 0,
      name: 'FmRadioStations',
      callback: _onFmStationsChanged,
    );
    // Rebuild when the set of connected radios changes so the radio-name
    // switcher affordance appears/disappears as radios connect/disconnect.
    _broker.subscribe(
      deviceId: 1,
      name: 'ConnectedRadios',
      callback: _onConnectedRadiosChanged,
    );
    _subscribeToDevice();
  }

  @override
  void didUpdateWidget(RadioPanelControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deviceId != widget.deviceId) {
      // Device ID changed - resubscribe
      _broker.unsubscribeAll();
      _broker.subscribe(
        deviceId: 0,
        name: 'ShowAllChannels',
        callback: _onShowAllChannelsChanged,
      );
      _broker.subscribe(
        deviceId: 0,
        name: 'ShowChannelFrequency',
        callback: _onShowChannelFrequencyChanged,
      );
      _broker.subscribe(
        deviceId: 0,
        name: 'FmRadioStations',
        callback: _onFmStationsChanged,
      );
      _broker.subscribe(
        deviceId: 1,
        name: 'ConnectedRadios',
        callback: _onConnectedRadiosChanged,
      );
      _clearCachedState();
      _subscribeToDevice();
    }
  }

  @override
  void dispose() {
    _broker.dispose();
    super.dispose();
  }

  /// Handle ShowAllChannels changes broadcast on device 0 (e.g. from the main
  /// menu "All Channels" item).
  void _onShowAllChannelsChanged(int deviceId, String name, Object? data) {
    final newValue = (data as int?) == 1;
    if (newValue == _showAllChannels) return;
    setState(() {
      _showAllChannels = newValue;
    });
  }

  /// Handle ShowChannelFrequency changes broadcast on device 0 (from the main
  /// menu "Channel Frequency" item).
  void _onShowChannelFrequencyChanged(int deviceId, String name, Object? data) {
    final newValue = (data as int?) == 1;
    if (newValue == _showChannelFrequency) return;
    setState(() {
      _showChannelFrequency = newValue;
    });
  }

  /// Handle preferred FM station changes broadcast on device 0 (from the FM
  /// Radio dialog adding/renaming/removing stations).
  void _onFmStationsChanged(int deviceId, String name, Object? data) {
    if (!mounted) return;
    setState(_loadFmStations);
  }

  /// Rebuilds when the set of connected radios changes (device 1's
  /// `ConnectedRadios`) so the radio-name switcher affordance stays in sync.
  void _onConnectedRadiosChanged(int deviceId, String name, Object? data) {
    if (!mounted) return;
    setState(() {});
  }

  /// Loads and parses the persisted preferred FM stations from device 0.
  void _loadFmStations() {
    final raw = _broker.getValue<String>(0, 'FmRadioStations');
    final list = <({int freqHz, String name})>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              final freq = (item['freqHz'] as num?)?.toInt();
              if (freq != null) {
                list.add((freqHz: freq, name: item['name'] as String? ?? ''));
              }
            }
          }
        }
      } catch (_) {
        // Ignore malformed stored data.
      }
    }
    _fmStations = list;
  }

  /// Returns the saved name of the preferred FM station matching [freqHz], or
  /// null if the current frequency is not one of the user's preferred stations.
  String? _fmStationName(int freqHz) {
    for (final s in _fmStations) {
      if ((s.freqHz - freqHz).abs() < 1000 && s.name.isNotEmpty) {
        return s.name;
      }
    }
    return null;
  }

  void _clearCachedState() {
    _currentState = null;
    _currentHtStatus = null;
    _currentSettings = null;
    _fmRadioStatus = null;
    _freqModeFreqHz = 0;
    _freqModeActive = false;
    _currentChannels = null;
    _fullChannels = {};
    _friendlyName = '';
    _gpsEnabled = false;
    _position = null;
    _lockState = null;
  }

  void _subscribeToDevice() {
    if (widget.deviceId <= 0) return;

    // Subscribe to device events
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
        'FriendlyName',
        'GpsEnabled',
        'Position',
        'LockState',
      ],
      callback: _onBrokerEvent,
    );

    // Load initial state from broker
    _loadInitialState();
  }

  void _loadInitialState() {
    if (widget.deviceId <= 0) return;

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
    final fullList = _broker.getJsonListValue<radio.RadioChannelInfo>(
      widget.deviceId,
      'Channels',
      (json) => radio.RadioChannelInfo.fromJson(json),
    );
    _fullChannels = {
      for (final c in fullList ?? const <radio.RadioChannelInfo>[])
        c.channelId: c,
    };
    _friendlyName =
        _broker.getValue<String>(widget.deviceId, 'FriendlyName') ?? '';
    _gpsEnabled =
        _broker.getValue<bool>(widget.deviceId, 'GpsEnabled') ?? false;
    _position = _broker.getJsonValue<RadioPosition>(
      widget.deviceId,
      'Position',
      (json) => RadioPosition.fromJson(json),
    );
    _lockState = _broker.getJsonValue<RadioLockState>(
      widget.deviceId,
      'LockState',
      (json) => RadioLockState.fromJson(json),
    );

    // Try to get FriendlyName from ConnectedRadios if not set
    if (_friendlyName.isEmpty) {
      _friendlyName = _getFriendlyNameFromConnectedRadios(widget.deviceId);
    }

    if (mounted) setState(() {});
  }

  String _getFriendlyNameFromConnectedRadios(int deviceId) {
    final connectedRadios = _broker.getJsonListValue<ConnectedRadioInfo>(
      1,
      'ConnectedRadios',
      (json) => ConnectedRadioInfo.fromJson(json),
    );
    if (connectedRadios == null) return '';

    for (final radio in connectedRadios) {
      if (radio.deviceId == deviceId) {
        return radio.friendlyName;
      }
    }
    return '';
  }

  /// Returns the de-duplicated list of currently connected radios (device 1's
  /// `ConnectedRadios`), preserving order.
  List<ConnectedRadioInfo> _connectedRadios() {
    final radios = _broker.getJsonListValue<ConnectedRadioInfo>(
      1,
      'ConnectedRadios',
      (json) => ConnectedRadioInfo.fromJson(json),
    );
    if (radios == null) return const [];
    final seen = <int>{};
    final unique = <ConnectedRadioInfo>[];
    for (final r in radios) {
      if (seen.add(r.deviceId)) unique.add(r);
    }
    return unique;
  }

  /// Shows a context menu listing all connected radios (with a checkmark next to
  /// the currently displayed / preferred one) and switches to the chosen radio
  /// by dispatching `SetPreferredRadio` to the main form. Does nothing unless at
  /// least two radios are connected.
  Future<void> _showRadioSelectionMenu(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final radios = _connectedRadios();
    if (radios.length < 2) return;

    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<int>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        for (final r in radios)
          PopupMenuItem<int>(
            value: r.deviceId,
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: r.deviceId == widget.deviceId
                      ? const Icon(Icons.check, size: 18)
                      : null,
                ),
                Text(
                  r.friendlyName.isNotEmpty
                      ? r.friendlyName
                      : 'Radio ${r.deviceId}',
                ),
              ],
            ),
          ),
      ],
    );

    if (selected != null && selected != widget.deviceId) {
      _broker.dispatch(deviceId: 1, name: 'SetPreferredRadio', data: selected);
    }
  }

  void _onBrokerEvent(int deviceId, String name, Object? data) {
    if (deviceId != widget.deviceId) return;
    if (!mounted) return;

    setState(() {
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
            _fullChannels = {
              for (final e in data.whereType<Map<String, dynamic>>())
                (e['channelId'] as int? ?? e['channel_id'] as int? ?? 0):
                    radio.RadioChannelInfo.fromJson(e),
            };
          }
          break;
        case 'FriendlyName':
          _friendlyName = data as String? ?? '';
          break;
        case 'GpsEnabled':
          _gpsEnabled = data as bool? ?? false;
          break;
        case 'Position':
          if (data is Map<String, dynamic>) {
            _position = RadioPosition.fromJson(data);
          }
          break;
        case 'LockState':
          if (data is Map<String, dynamic>) {
            _lockState = RadioLockState.fromJson(data);
          }
          break;
      }
    });
  }

  void _onConnect() {
    // Dispatch connect request to main form via DataBroker
    // MainForm subscribes to this event and handles the connection flow
    _broker.dispatch(
      deviceId: 1,
      name: 'RadioConnect',
      data: true,
      store: false,
    );
  }

  void _onChannelTap(int channelId) {
    if (widget.deviceId <= 0) {
      return;
    }
    _broker.dispatch(
      deviceId: widget.deviceId,
      name: 'ChannelChangeVfoA',
      data: channelId,
      store: false,
    );
  }

  void _setChannelA(int channelId) {
    if (widget.deviceId <= 0) return;
    _broker.dispatch(
      deviceId: widget.deviceId,
      name: 'ChannelChangeVfoA',
      data: channelId,
      store: false,
    );
  }

  void _setChannelB(int channelId) {
    if (widget.deviceId <= 0) return;
    _broker.dispatch(
      deviceId: widget.deviceId,
      name: 'ChannelChangeVfoB',
      data: channelId,
      store: false,
    );
  }

  // Computed properties based on broker state
  bool get _isConnected => _currentState == 'Connected';
  bool get _isConnecting => _currentState == 'Connecting';

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

  // VFO display computed properties
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
    // In frequency mode the large top box shows the live frequency (with unit)
    // instead of a channel name; the mode caption drops to the small box below.
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
    // In frequency mode the small box shows the mode caption (Weather / Broadcast
    // FM) beneath the large frequency; empty for a plain VFO free-tune or until a
    // frequency is available.
    if (_showFrequencyMode) {
      return _frequencyModeFreq.isNotEmpty ? _frequencyModeCaption : '';
    }
    final ch = _channelA;
    if (ch == null) return '';
    if (ch.name.isNotEmpty) {
      return ch.rxFreq > 0 ? '${ch.frequencyDisplay} MHz' : '';
    }
    if (ch.rxFreq > 0) return ' MHz';
    return '';
  }

  String get _vfo1Status {
    if (_lockState != null && _lockState!.isLocked) {
      return _lockState!.usage;
    }
    return '';
  }

  String get _vfo2Label {
    // FM broadcast uses VFO B: show the FM station frequency in the large text.
    if (_isFmBroadcast) {
      final fm = _fmRadioStatus;
      if (fm != null && fm.freqHz > 0) return '${fm.frequencyDisplay} MHz';
      return 'FM';
    }
    // In frequency mode VFO B is not active; keep it blank.
    if (_showFrequencyMode) return '';
    if (_isScanning) {
      // Scanning mode
      if (_currentHtStatus != null && _currentChannels != null) {
        final currChId = _currentHtStatus!.currChId;
        if (currChId < _currentChannels!.length) {
          final scanCh = _currentChannels![currChId];
          if (_channelA != null && scanCh.channelId == _channelA!.channelId) {
            // Current channel is same as VFO A - show last scanned
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

  String get _vfo2Freq {
    // FM broadcast uses VFO B: show the preferred station name in the small text
    // under the frequency when the tuned frequency matches a saved station,
    // otherwise fall back to "FM".
    if (_isFmBroadcast) {
      final fm = _fmRadioStatus;
      if (fm != null && fm.freqHz > 0) {
        final name = _fmStationName(fm.freqHz);
        if (name != null) return name;
      }
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
    if (ch == null) return '';
    if (ch.name.isNotEmpty) {
      return ch.rxFreq > 0 ? '${ch.frequencyDisplay} MHz' : '';
    }
    if (ch.rxFreq > 0) return ' MHz';
    return '';
  }

  String get _vfo2Status {
    // FM broadcast uses VFO B; no extra status text.
    if (_isFmBroadcast) return '';
    // In frequency mode VFO B is not active; keep it blank.
    if (_showFrequencyMode) return '';
    if (_isScanning) {
      // Only show "Scanning..." as the status when a channel name is shown in
      // the label. When the label itself shows "Scanning..." (no valid channel),
      // the status stays empty to avoid displaying "Scanning..." twice.
      if (_currentHtStatus != null && _currentChannels != null) {
        final currChId = _currentHtStatus!.currChId;
        if (currChId < _currentChannels!.length) {
          final scanCh = _currentChannels![currChId];
          if (_channelA != null && scanCh.channelId == _channelA!.channelId) {
            // Current channel is same as VFO A - status only if last channel is valid
            return (_vfo2LastChannelId >= 0 &&
                    _vfo2LastChannelId < _currentChannels!.length)
                ? 'Scanning...'
                : '';
          }
          return 'Scanning...';
        }
      }
      return '';
    }
    return '';
  }

  String get _gpsStatus {
    if (!_isConnected) return '';
    if (!_gpsEnabled) return '';
    if (_position == null) return 'No GPS Lock';
    return _position!.locked ? 'GPS Lock' : 'No GPS Lock';
  }

  int get _rssi => _currentHtStatus?.rssi ?? 0;
  bool get _isTransmitting => _currentHtStatus?.isInTx ?? false;

  /// True when VFO B is the active receiver: the radio's current channel ID
  /// matches VFO B's channel and there is signal (RSSI > 0).
  bool get _isVfo2Active {
    if (!_isConnected) return false;
    if (_channelB == null || !_isDualChannel || _currentHtStatus == null) {
      return false;
    }
    return _rssi > 0 && _currentHtStatus!.currChId == _channelB!.channelId;
  }

  Color get _vfo1Color {
    if (!_isConnected) return _inactiveColor;
    // In frequency mode only VFO A is active.
    if (_showFrequencyMode) return _activeVfoColor;
    // When VFO B is active, VFO A goes white (inactive).
    if (_isVfo2Active) return _inactiveColor;
    return _activeVfoColor;
  }

  Color get _vfo2Color {
    if (!_isConnected || _vfo2Label.isEmpty) return _inactiveColor;
    // In frequency mode VFO B is inactive.
    if (_showFrequencyMode) return _inactiveColor;
    // VFO B turns yellow only while it is the active receiver.
    if (_isVfo2Active) return _activeVfoColor;
    return _inactiveColor;
  }

  void _showChannelDetails(RadioChannelInfo channel) {
    if (widget.deviceId <= 0) return;
    showRadioChannelDialog(
      context,
      deviceId: widget.deviceId,
      channelId: channel.channelId,
      radioName: _friendlyName,
    );
  }

  Future<void> _showChannelContextMenu(
    Offset position,
    RadioChannelInfo channel,
  ) async {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    final selectedChannelA = _channelA?.channelId ?? -1;
    final selectedChannelB = _channelB?.channelId ?? -1;

    // Read the clipboard up front so we can enable "Paste" only when it holds a
    // shared channel token (HTC:...) or a supported web page URL. The menu
    // items must be built synchronously, so this has to be resolved before
    // showMenu is called.
    radio.RadioChannelInfo? clipboardChannel;
    String? clipboardUrl;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text != null) {
        final matches = ChannelShare.findAll(text);
        if (matches.isNotEmpty) {
          clipboardChannel = matches.first.channel;
        } else if (WebChannelImport.isSupportedUrl(text.trim())) {
          // A URL from a supported site (e.g. a repeater details page): paste
          // imports it exactly like dropping the URL onto the channel.
          clipboardUrl = text.trim();
        }
      }
    } catch (_) {
      // Clipboard may be unavailable on some platforms; just omit "Paste".
    }
    if (!mounted) return;

    // Enable "Paste" when the clipboard holds a supported URL, or a shared
    // channel token whose content differs from what is already stored in this
    // slot. The channel-share token does not carry the slot id, so compare by
    // re-encoding both channels: an identical channel produces an identical
    // token.
    bool pasteEnabled = widget.deviceId > 0 &&
        (clipboardChannel != null || clipboardUrl != null);
    if (pasteEnabled && clipboardChannel != null) {
      final currentFull =
          _fullChannels[channel.channelId] ?? _asFullChannel(channel);
      if (ChannelShare.encode(clipboardChannel!) ==
          ChannelShare.encode(currentFull)) {
        pasteEnabled = false;
      }
    }

    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem<String>(value: 'show', child: Text('Edit...')),
        PopupMenuItem<String>(
          value: 'setA',
          enabled: channel.channelId != selectedChannelA,
          child: const Text('Set VFO A'),
        ),
        PopupMenuItem<String>(
          value: 'setB',
          enabled: channel.channelId != selectedChannelB,
          child: const Text('Set VFO B'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(value: 'copy', child: Text('Copy')),
        PopupMenuItem<String>(
          value: 'paste',
          enabled: pasteEnabled,
          child: const Text('Paste'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'showAll',
          child: Row(
            children: [
              if (_showAllChannels)
                const Icon(Icons.check, size: 18)
              else
                const SizedBox(width: 18),
              const SizedBox(width: 8),
              const Text('Show All Channels'),
            ],
          ),
        ),
      ],
    );

    if (value == null || !mounted) return;
    switch (value) {
      case 'show':
        _showChannelDetails(channel);
        break;
      case 'setA':
        _setChannelA(channel.channelId);
        break;
      case 'setB':
        _setChannelB(channel.channelId);
        break;
      case 'copy':
        _copyChannel(channel);
        break;
      case 'paste':
        if (!pasteEnabled) break;
        if (clipboardChannel != null) {
          _onChannelDroppedOnSlot(clipboardChannel, channel.channelId);
        } else if (clipboardUrl != null) {
          _importChannelFromUrl(clipboardUrl, channel.channelId);
        }
        break;
      case 'showAll':
        // Toggle the shared ShowAllChannels state via the DataBroker so the
        // main menu "All Channels" item stays in sync.
        final newValue = !_showAllChannels;
        _broker.dispatch(
          deviceId: 0,
          name: 'ShowAllChannels',
          data: newValue ? 1 : 0,
        );
        break;
    }
  }

  /// Encodes [channel] as a channel-share token and copies it to the clipboard
  /// so it can be pasted into another radio slot or into a chat message.
  void _copyChannel(RadioChannelInfo channel) {
    final full = _fullChannels[channel.channelId] ?? _asFullChannel(channel);
    final token = ChannelShare.encode(full);
    Clipboard.setData(ClipboardData(text: token));
    if (!mounted) return;
    final name = channel.name.isNotEmpty
        ? channel.name
        : 'Channel ${channel.channelId + 1}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied "$name" to the clipboard'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF808080), // 50% gray
      child: _buildRadioDisplayWithChannels(),
    );
  }

  Widget _buildRadioDisplayWithChannels() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxHeight = constraints.maxHeight;
        // Use fixed image width, centered in container.
        const double imageWidth = _kFixedImageWidth;
        final double leftMargin = (constraints.maxWidth - imageWidth) / 2;
        final double scaledImageHeight = imageWidth * _kImageAspectRatio;
        final double displayPanelTop = scaledImageHeight * _kDisplayTop;

        // Maximum amount we can crop off the top: bring the top edge to 6px
        // above the VFO A label. The VFO A label sits ~18px above the display
        // panel top (Transform.translate -20 + 2px container padding).
        final double maxTopCrop = (displayPanelTop - 18 - 6).clamp(
          0.0,
          double.infinity,
        );

        // Decide compact mode (very limited height).
        final bool compact = maxHeight < _kCompactModeMaxHeight;

        // Progressive top crop based on available height.
        final double topCrop = compact
            ? maxTopCrop
            : (_kCropStartHeight - maxHeight).clamp(0.0, maxTopCrop);

        // RSSI bar position: just below GPS text (shifted up by the crop).
        final double rssiTop =
            scaledImageHeight * (_kDisplayTop + _kDisplayHeight) +
            2 -
            50 -
            topCrop;

        if (compact) {
          return _buildCompactLayout(
            constraints: constraints,
            leftMargin: leftMargin,
            scaledImageHeight: scaledImageHeight,
            topCrop: topCrop,
            rssiTop: rssiTop,
          );
        }

        // Maximum channels panel height (24 pixels below RSSI bar).
        final double maxChannelsPanelTop = rssiTop + 6 + 24;
        final double maxChannelsPanelHeight = maxHeight - maxChannelsPanelTop;

        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            ..._buildRadioLayers(
              leftMargin: leftMargin,
              scaledImageHeight: scaledImageHeight,
              topCrop: topCrop,
              rssiTop: rssiTop,
            ),
            // Bottom panel - connect button or channels panel (full width,
            // overlapping the radio image).
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildBottomPanel(
                constraints.maxWidth,
                maxChannelsPanelHeight,
              ),
            ),
          ],
        );
      },
    );
  }

  /// Builds the radio image, LCD display panel, friendly name and RSSI bar as
  /// a list of positioned layers. Everything is shifted up by [topCrop] so the
  /// decorative top of the radio (and the friendly name) is cropped away.
  List<Widget> _buildRadioLayers({
    required double leftMargin,
    required double scaledImageHeight,
    required double topCrop,
    required double rssiTop,
  }) {
    return [
      // Radio background image - fixed width, centered, cropped at the top.
      Positioned(
        top: -topCrop,
        left: leftMargin,
        width: _kFixedImageWidth,
        height: scaledImageHeight,
        child: Image.asset(
          'assets/images/Radio.png',
          fit: BoxFit.fitWidth,
          alignment: Alignment.topCenter,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: Colors.grey.shade800,
              child: const Center(
                child: Icon(Icons.radio, size: 100, color: Colors.white54),
              ),
            );
          },
        ),
      ),

      // Overlay the display panel on top of the radio LCD area.
      Positioned(
        left:
            leftMargin +
            (_kFixedImageWidth * _kDisplayLeft) +
            _kDisplayLeftOffset,
        top: scaledImageHeight * _kDisplayTop - topCrop,
        width: _kFixedImageWidth * _kDisplayWidth,
        child: _buildDisplayPanel(),
      ),

      // Friendly name overlay (above the display). Cropped away first when the
      // available height shrinks. When more than one radio is connected, tapping
      // or right-clicking the name opens a menu to switch the active radio.
      if (_friendlyName.isNotEmpty)
        Positioned(
          left: leftMargin + 4,
          width: _kFixedImageWidth,
          top:
              scaledImageHeight * _kFriendlyNameTop +
              _kFriendlyNameTopOffset -
              topCrop,
          child: Center(
            child: Builder(
              builder: (ctx) {
                final hasMultiple = _connectedRadios().length >= 2;
                final text = Text(
                  _friendlyName,
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                );
                if (!hasMultiple) return text;
                return MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) =>
                        _showRadioSelectionMenu(ctx, d.globalPosition),
                    onSecondaryTapDown: (d) =>
                        _showRadioSelectionMenu(ctx, d.globalPosition),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        text,
                        Icon(
                          Icons.arrow_drop_down,
                          size: 18,
                          color: Colors.grey.shade500,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),

      // RSSI / Transmit bar.
      if (_isConnected && (_rssi > 0 || _isTransmitting))
        Positioned(
          left:
              leftMargin +
              (_kFixedImageWidth * _kDisplayLeft) +
              _kDisplayLeftOffset,
          top: rssiTop,
          width: _kFixedImageWidth * _kDisplayWidth,
          height: 6,
          child: _isTransmitting
              ? Container(color: Colors.red)
              : ClipRRect(
                  borderRadius: BorderRadius.circular(1),
                  child: LinearProgressIndicator(
                    value: _rssi / 15,
                    backgroundColor: _displayBgColor,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.green,
                    ),
                  ),
                ),
        ),
    ];
  }

  /// Compact layout used when the available height is very small. Shows either
  /// the radio display or the channel list (filling the whole area), toggled
  /// via a small button in the top-right corner.
  Widget _buildCompactLayout({
    required BoxConstraints constraints,
    required double leftMargin,
    required double scaledImageHeight,
    required double topCrop,
    required double rssiTop,
  }) {
    final bool hasChannels = _isConnected && _hasVisibleChannels;
    final bool showChannels = hasChannels && _compactShowChannels;

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        if (showChannels)
          Positioned.fill(
            child: _buildChannelsGridFull(
              constraints.maxWidth,
              constraints.maxHeight,
            ),
          )
        else ...[
          ..._buildRadioLayers(
            leftMargin: leftMargin,
            scaledImageHeight: scaledImageHeight,
            topCrop: topCrop,
            rssiTop: rssiTop,
          ),
          // Connect button when disconnected (no channels to show).
          if (!_isConnected)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildConnectPanel(),
            ),
        ],
        // Toggle between the radio and the channels (only when channels exist).
        if (hasChannels)
          Positioned(top: 4, right: 4, child: _buildCompactToggleButton()),
      ],
    );
  }

  /// Small circular button shown in compact mode to switch between the radio
  /// display and the channel list.
  Widget _buildCompactToggleButton() {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () =>
            setState(() => _compactShowChannels = !_compactShowChannels),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            _compactShowChannels ? Icons.radio : Icons.list,
            size: 18,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildDisplayPanel() {
    if (!_isConnected) {
      // Show connection state when not connected
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _displayBgColor,
          borderRadius: BorderRadius.circular(2),
        ),
        child: Center(
          child: Text(
            _connectionState,
            style: const TextStyle(
              color: Color(0xFFD3D3D3),
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // Connected panel with VFO info
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: _displayBgColor,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // VFO 1 - shifted up 20px
          Transform.translate(
            offset: const Offset(0, -20),
            child: _buildVfo1Row(),
          ),
          // Divider line - shifted up 14px
          Transform.translate(
            offset: const Offset(0, -14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Container(height: 1, color: const Color(0xFF999999)),
            ),
          ),
          // VFO 2 - shifted up 14px
          Transform.translate(
            offset: const Offset(0, -14),
            child: _buildVfo2Row(),
          ),
          // Bottom row: Voice indicator and GPS status - shifted up 12px
          Transform.translate(
            offset: const Offset(0, -12),
            child: _buildStatusRow(),
          ),
        ],
      ),
    );
  }

  Widget _buildVfo1Row() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // VFO1 main label (channel name) - large font
        SizedBox(
          height: 32,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _vfo1Label.isEmpty ? '' : _vfo1Label,
                style: TextStyle(
                  color: _vfo1Color,
                  fontSize: 22,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
        // Frequency and status row
        Row(
          children: [
            Expanded(
              child: Text(
                _vfo1Freq,
                style: TextStyle(color: _vfo1Color, fontSize: 10),
              ),
            ),
            Text(
              _vfo1Status,
              style: TextStyle(color: _vfo1Color, fontSize: 10),
              textAlign: TextAlign.right,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildVfo2Row() {
    if (_vfo2Label.isEmpty && _vfo2Freq.isEmpty) {
      // Reserve the same vertical space VFO 2 occupies when populated (the
      // 32px label SizedBox plus the ~14px frequency/status row) so the GPS
      // status row below stays at a fixed location even when VFO B is empty.
      return const SizedBox(height: 46);
    }

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // VFO2 main label (channel name) - large font
        SizedBox(
          height: 32,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _vfo2Label.isEmpty ? '' : _vfo2Label,
                style: TextStyle(
                  color: _vfo2Color,
                  fontSize: 22,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
        // Frequency and status row
        Row(
          children: [
            Expanded(
              child: Text(
                _vfo2Freq,
                style: TextStyle(color: _vfo2Color, fontSize: 10),
              ),
            ),
            Text(
              _vfo2Status,
              style: TextStyle(color: _vfo2Color, fontSize: 10),
              textAlign: TextAlign.right,
            ),
          ],
        ),
      ],
    );

    // While the FM broadcast receiver is active, VFO B shows the FM station.
    // Tapping it opens the FM Radio dialog so the user can quickly change the
    // station.
    if (_isFmBroadcast) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showFmRadioDialog(context, deviceId: widget.deviceId),
        child: content,
      );
    }
    return content;
  }

  Widget _buildStatusRow() {
    final gpsText = Text(
      _gpsStatus,
      style: TextStyle(color: Colors.grey.shade500, fontSize: 10),
      textAlign: TextAlign.right,
    );
    return Row(
      children: [
        const Spacer(),
        // GPS status - tap to open the GPS details dialog when GPS is enabled.
        if (_gpsStatus.isEmpty)
          gpsText
        else
          InkWell(
            onTap: () =>
                showGpsDetailsDialog(context, deviceId: widget.deviceId),
            child: gpsText,
          ),
      ],
    );
  }

  Widget _buildBottomPanel(double panelWidth, double maxHeight) {
    if (_isConnected) {
      // Show channels panel when connected
      return _buildChannelsPanel(panelWidth, maxHeight);
    } else {
      // Show connect button when disconnected
      return _buildConnectPanel();
    }
  }

  Widget _buildConnectPanel() {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        width: double.infinity,
        height: 44,
        child: ElevatedButton(
          onPressed: _isConnecting ? null : _onConnect,
          style: ElevatedButton.styleFrom(
            backgroundColor: scheme.surface,
            foregroundColor: scheme.onSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          child: Text(_isConnecting ? l10n.stateConnecting : l10n.commonConnect),
        ),
      ),
    );
  }

  /// Channels visible given the current `_showAllChannels` setting.
  List<RadioChannelInfo> get _visibleChannels {
    final channels = _currentChannels;
    if (channels == null || channels.isEmpty) return const [];
    if (_showAllChannels) return channels;
    return channels.where((ch) => ch.name.isNotEmpty || ch.rxFreq > 0).toList();
  }

  /// Whether there are any channels to display.
  bool get _hasVisibleChannels => _visibleChannels.isNotEmpty;

  Widget _buildChannelsPanel(double panelWidth, double maxHeight) {
    final visibleChannels = _visibleChannels;
    if (visibleChannels.isEmpty) {
      return const SizedBox.shrink();
    }

    final selectedChannelA = _channelA?.channelId ?? -1;
    final selectedChannelB = _channelB?.channelId ?? -1;

    // Calculate panel height based on number of visible channels (3 per row)
    // Similar to C# implementation
    final int rowCount =
        ((visibleChannels.length + 2) ~/ 3); // Integer division rounds down

    // Calculate block height, cap at 50
    double blockHeight = maxHeight / rowCount;
    if (blockHeight > 50) blockHeight = 50;

    // Total panel height
    final double panelHeight = blockHeight * rowCount;

    // Guard against zero/negative dimensions during layout, which would make
    // childAspectRatio non-positive and trigger a SliverGrid assertion failure.
    double childAspectRatio = (panelWidth / 3) / blockHeight;
    if (!childAspectRatio.isFinite || childAspectRatio <= 0) {
      childAspectRatio = 1.0;
    }

    return Container(
      width: panelWidth,
      height: panelHeight,
      color: ChannelPalette.of(context).base,
      child: DropTarget(
        onDragDone: _onUrlDroppedOnChannels,
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: childAspectRatio,
            crossAxisSpacing: 0,
            mainAxisSpacing: 0,
          ),
          itemCount: visibleChannels.length,
          itemBuilder: (context, index) => _buildChannelTile(
            visibleChannels[index],
            selectedChannelA,
            selectedChannelB,
          ),
        ),
      ),
    );
  }

  /// Channels grid that fills the whole area and scrolls if needed. Used in
  /// compact mode to overlay the channels over the entire radio.
  Widget _buildChannelsGridFull(double panelWidth, double maxHeight) {
    final visibleChannels = _visibleChannels;
    if (visibleChannels.isEmpty) {
      return const SizedBox.shrink();
    }

    final selectedChannelA = _channelA?.channelId ?? -1;
    final selectedChannelB = _channelB?.channelId ?? -1;

    return Container(
      color: ChannelPalette.of(context).base,
      child: DropTarget(
        onDragDone: _onUrlDroppedOnChannels,
        child: GridView.builder(
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisExtent: 44,
            crossAxisSpacing: 0,
            mainAxisSpacing: 0,
          ),
          itemCount: visibleChannels.length,
          itemBuilder: (context, index) => _buildChannelTile(
            visibleChannels[index],
            selectedChannelA,
            selectedChannelB,
          ),
        ),
      ),
    );
  }

  /// Builds a single channel tile shared by the normal and compact grids.
  Widget _buildChannelTile(
    RadioChannelInfo channel,
    int selectedChannelA,
    int selectedChannelB,
  ) {
    final isChannelA = channel.channelId == selectedChannelA;
    // While FM broadcast is active VFO B shows the FM station rather than a
    // memory channel, so don't highlight VFO B's channel in the grid.
    final isChannelB = _isDualChannel &&
        !_isFmBroadcast &&
        channel.channelId == selectedChannelB;
    final palette = ChannelPalette.of(context);

    Color bgColor;
    if (_isFrequencyMode) {
      // Frequency mode active - no channel highlighting
      bgColor = palette.base;
    } else if (isChannelA) {
      bgColor = palette.selected;
    } else if (isChannelB) {
      bgColor = palette.channelB;
    } else {
      bgColor = palette.base;
    }

    final tile = GestureDetector(
      onTap: () => _onChannelTap(channel.channelId),
      onDoubleTap: () => _showChannelDetails(channel),
      onSecondaryTapDown: (details) {
        _showChannelContextMenu(details.globalPosition, channel);
      },
      onLongPressStart: (details) {
        _showChannelContextMenu(details.globalPosition, channel);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: palette.border, width: 0.5),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Only show frequency if there's enough vertical space (need ~28px for both)
            final bool showFrequency =
                _showChannelFrequency &&
                channel.rxFreq > 0 &&
                constraints.maxHeight >= 28;
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: showFrequency
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                Text(
                  channel.name.isNotEmpty
                      ? channel.name
                      : 'Ch ${channel.channelId + 1}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: palette.onChannel,
                  ),
                  textAlign: showFrequency ? TextAlign.start : TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
                if (showFrequency)
                  Text(
                    '${channel.frequencyDisplay} MHz',
                    style: TextStyle(fontSize: 9, color: palette.onChannelSecondary),
                  ),
              ],
            );
          },
        ),
      ),
    );

    // Make the channel draggable so it can be dropped into the Comms/APRS tabs
    // to be shared with another operator. The payload is the full channel
    // (tones, de-emphasis, power, ...) so nothing is lost when it is encoded.
    final full = _fullChannels[channel.channelId] ?? _asFullChannel(channel);
    final draggable = Draggable<radio.RadioChannelInfo>(
      data: full,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _buildChannelDragFeedback(channel),
      childWhenDragging: Opacity(opacity: 0.4, child: tile),
      child: tile,
    );

    // Also accept a dropped channel (e.g. a "yellow block" shared in chat, or
    // another slot) to program this slot on the radio.
    return DragTarget<radio.RadioChannelInfo>(
      key: _channelTileKey(channel.channelId),
      onWillAcceptWithDetails: (details) =>
          widget.deviceId > 0 && details.data.channelId != channel.channelId,
      onAcceptWithDetails: (details) =>
          _onChannelDroppedOnSlot(details.data, channel.channelId),
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        return Stack(
          children: [
            Positioned.fill(child: draggable),
            if (hovering)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.blue, width: 2),
                      color: Colors.blue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Programs [slotId] on the radio with a dropped [channel] after asking the
  /// operator to confirm, since this overwrites the channel on the device.
  Future<void> _onChannelDroppedOnSlot(
    radio.RadioChannelInfo channel,
    int slotId,
  ) async {
    if (widget.deviceId <= 0) return;
    final name = channel.name.isNotEmpty ? channel.name : 'Channel';
    final freq =
        channel.rxFreq > 0 ? ' (${channel.frequencyDisplay} MHz)' : '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Program channel'),
        content: Text(
          'Program slot ${slotId + 1} with "$name"$freq?\n\n'
          'This overwrites the channel currently stored on the radio.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Program'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    _broker.dispatch(
      deviceId: widget.deviceId,
      name: 'WriteChannel',
      data: channel.copyWith(channelId: slotId),
      store: false,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Programming slot ${slotId + 1} with "$name"...'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Returns the stable [GlobalKey] for the tile of [channelId], creating one on
  /// first use. Used to hit-test which slot a dropped URL landed on.
  GlobalKey _channelTileKey(int channelId) =>
      _channelTileKeys.putIfAbsent(channelId, () => GlobalKey());

  /// Returns the channel id of the tile currently under [globalPosition], or
  /// null when the drop did not land on a tile.
  int? _channelIdAt(Offset globalPosition) {
    for (final entry in _channelTileKeys.entries) {
      final ctx = entry.value.currentContext;
      final box = ctx?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      final topLeft = box.localToGlobal(Offset.zero);
      final rect = topLeft & box.size;
      if (rect.contains(globalPosition)) return entry.key;
    }
    return null;
  }

  /// Handles a web page URL dropped onto the channels grid. When the URL is a
  /// supported site, its page is fetched and parsed into a
  /// proposed channel, and the channel editor opens pre-filled for the slot the
  /// URL was dropped onto so the operator can confirm before programming.
  Future<void> _onUrlDroppedOnChannels(DropDoneDetails details) async {
    if (widget.deviceId <= 0 || details.files.isEmpty) return;

    // A dragged browser link arrives as a single item whose path is the URL.
    final url = details.files.first.path.trim();
    final uri = Uri.tryParse(url);
    final isHttpUrl =
        uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    if (!isHttpUrl) return; // Ignore dropped files/other content silently.

    if (!WebChannelImport.isSupportedUrl(url)) {
      _showChannelImportSnack(
        AppLocalizations.of(context).channelImportUnsupportedSite,
      );
      return;
    }

    final channelId = _channelIdAt(details.globalPosition);
    if (channelId == null) return;

    await _importChannelFromUrl(url, channelId);
  }

  /// Fetches and parses [url] into a proposed channel, then opens the channel
  /// editor pre-filled for [channelId] so the operator can confirm. Shared by
  /// the URL drag-and-drop and the right-click "Paste" flows.
  Future<void> _importChannelFromUrl(String url, int channelId) async {
    final l10n = AppLocalizations.of(context);
    _showChannelImportSnack(l10n.channelImportFetching);
    final result = await WebChannelImport.fetchFromUrl(url);
    if (!mounted) return;

    switch (result.status) {
      case WebChannelImportStatus.ok:
        await showRadioChannelDialog(
          context,
          deviceId: widget.deviceId,
          channelId: channelId,
          radioName: _friendlyName,
          proposedChannel: result.channel,
        );
        break;
      case WebChannelImportStatus.fetchFailed:
        _showChannelImportSnack(l10n.channelImportFetchFailed);
        break;
      case WebChannelImportStatus.parseFailed:
        _showChannelImportSnack(l10n.channelImportParseFailed);
        break;
      case WebChannelImportStatus.unsupportedSite:
        _showChannelImportSnack(l10n.channelImportUnsupportedSite);
        break;
    }
  }

  void _showChannelImportSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  /// Small floating tile shown under the pointer while a channel is dragged.
  Widget _buildChannelDragFeedback(RadioChannelInfo channel) {
    final palette = ChannelPalette.of(context);
    return Material(
      color: Colors.transparent,
      child: Opacity(
        opacity: 0.9,
        child: Container(
          width: 120,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: palette.selected,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: palette.border, width: 1),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                channel.name.isNotEmpty
                    ? channel.name
                    : 'Ch ${channel.channelId + 1}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: palette.onChannel,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (channel.rxFreq > 0)
                Text(
                  '${channel.frequencyDisplay} MHz',
                  style: TextStyle(fontSize: 9, color: palette.onChannelSecondary),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Converts the lightweight panel channel model into the full channel model
  /// used for sharing. Used only as a fallback when the full channel (with
  /// tones/de-emphasis/power) isn't available in [_fullChannels].
  radio.RadioChannelInfo _asFullChannel(RadioChannelInfo c) {
    return radio.RadioChannelInfo(
      channelId: c.channelId,
      name: c.name,
      rxFreq: c.rxFreq,
      txFreq: c.txFreq,
      scan: c.scan,
      txDisable: c.txDisable,
      mute: c.mute,
      txMod: radio.RadioModulationType.values[c.txMod.index],
      rxMod: radio.RadioModulationType.values[c.rxMod.index],
      bandwidth: c.bandwidth == RadioBandwidthType.wide
          ? radio.RadioBandwidthType.wide
          : radio.RadioBandwidthType.narrow,
    );
  }
}
