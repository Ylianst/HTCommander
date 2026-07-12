import 'package:flutter/material.dart';
import '../services/data_broker_client.dart';
import '../models/radio_models.dart';
import '../dialogs/radio_channel_dialog.dart';
import '../dialogs/gps_details_dialog.dart';

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

  // Cached state from broker
  String? _currentState;
  RadioHtStatus? _currentHtStatus;
  RadioSettings? _currentSettings;
  List<RadioChannelInfo>? _currentChannels;
  String _friendlyName = '';
  bool _gpsEnabled = false;
  RadioPosition? _position;
  RadioLockState? _lockState;

  // UI state
  bool _showAllChannels = false;
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
    _broker.subscribe(
      deviceId: 0,
      name: 'ShowAllChannels',
      callback: _onShowAllChannelsChanged,
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

  void _clearCachedState() {
    _currentState = null;
    _currentHtStatus = null;
    _currentSettings = null;
    _currentChannels = null;
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
    _currentChannels = _broker.getJsonListValue<RadioChannelInfo>(
      widget.deviceId,
      'Channels',
      (json) => RadioChannelInfo.fromJson(json),
    );
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
        case 'Channels':
          if (data is List) {
            _currentChannels = data
                .whereType<Map<String, dynamic>>()
                .map((e) => RadioChannelInfo.fromJson(e))
                .toList();
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
    if (widget.deviceId <= 0 || _currentState == null) {
      return 'Disconnected';
    }
    switch (_currentState) {
      case 'Disconnected':
      case 'NotRadioFound':
      case 'BluetoothNotAvailable':
        return 'Disconnected';
      case 'Connecting':
        return 'Connecting...';
      case 'Connected':
        return 'Connected';
      case 'UnableToConnect':
        return 'Unable to Connect';
      case 'AccessDenied':
        return 'Access Denied';
      case 'MultiRadioSelect':
        return 'Select Radio';
      default:
        return _currentState ?? 'Disconnected';
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

  bool get _isNoaaChannel {
    if (_currentHtStatus != null && _currentHtStatus!.currChId >= 254) {
      return true;
    }
    if (_channelA != null && _channelA!.channelId >= 254) return true;
    return false;
  }

  bool get _isDualChannel => _currentSettings?.doubleChannel == 1;
  bool get _isScanning => _currentSettings?.scan ?? false;

  String get _vfo1Label {
    if (_isNoaaChannel &&
        _currentHtStatus != null &&
        _currentHtStatus!.currChId >= 254) {
      return 'NOAA';
    }
    final ch = _channelA;
    if (ch == null) return '';
    if (ch.channelId >= 254) return 'NOAA';
    if (ch.name.isNotEmpty) return ch.name;
    if (ch.rxFreq > 0) return (ch.rxFreq / 1000000).toStringAsFixed(3);
    return 'Empty';
  }

  String get _vfo1Freq {
    if (_isNoaaChannel &&
        _currentHtStatus != null &&
        _currentHtStatus!.currChId >= 254) {
      return '';
    }
    final ch = _channelA;
    if (ch == null) return '';
    if (ch.channelId >= 254 || ch.name.isNotEmpty) {
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
  bool get _isReceiving => _currentHtStatus?.isInRx ?? false;

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
    // When VFO B is active, VFO A goes white (inactive).
    if (_isVfo2Active) return _inactiveColor;
    return _activeVfoColor;
  }

  Color get _vfo2Color {
    if (!_isConnected || _vfo2Label.isEmpty) return _inactiveColor;
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

  void _showChannelContextMenu(
    BuildContext context,
    Offset position,
    RadioChannelInfo channel,
  ) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    final selectedChannelA = _channelA?.channelId ?? -1;
    final selectedChannelB = _channelB?.channelId ?? -1;

    showMenu<String>(
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
    ).then((value) {
      if (value == null) return;
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
    });
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
      // available height shrinks.
      if (_friendlyName.isNotEmpty)
        Positioned(
          left: leftMargin + 4,
          width: _kFixedImageWidth,
          top:
              scaledImageHeight * _kFriendlyNameTop +
              _kFriendlyNameTopOffset -
              topCrop,
          child: Center(
            child: Text(
              _friendlyName,
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
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

  Widget _buildRadioDisplay() {
    // Legacy method - kept for compatibility but redirects to new implementation
    return _buildRadioDisplayWithChannels();
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

    return Column(
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
    return Container(
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        width: double.infinity,
        height: 44,
        child: ElevatedButton(
          onPressed: _isConnecting ? null : _onConnect,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          child: Text(_isConnecting ? 'Connecting...' : 'Connect'),
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
      color: const Color(0xFFBDB76B), // DarkKhaki
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
      color: const Color(0xFFBDB76B), // DarkKhaki
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
    );
  }

  /// Builds a single channel tile shared by the normal and compact grids.
  Widget _buildChannelTile(
    RadioChannelInfo channel,
    int selectedChannelA,
    int selectedChannelB,
  ) {
    final isChannelA = channel.channelId == selectedChannelA;
    final isChannelB = _isDualChannel && channel.channelId == selectedChannelB;

    Color bgColor;
    if (_isNoaaChannel) {
      // NOAA active - no highlighting
      bgColor = const Color(0xFFBDB76B); // DarkKhaki
    } else if (isChannelA) {
      bgColor = const Color(0xFFEEE8AA); // PaleGoldenrod
    } else if (isChannelB) {
      bgColor = const Color(0xFFF0E68C); // Khaki
    } else {
      bgColor = const Color(0xFFBDB76B); // DarkKhaki
    }

    return GestureDetector(
      onTap: () => _onChannelTap(channel.channelId),
      onDoubleTap: () => _showChannelDetails(channel),
      onSecondaryTapDown: (details) {
        _showChannelContextMenu(context, details.globalPosition, channel);
      },
      onLongPressStart: (details) {
        _showChannelContextMenu(context, details.globalPosition, channel);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: Colors.grey.shade600, width: 0.5),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Only show frequency if there's enough vertical space (need ~28px for both)
            final bool showFrequency =
                channel.rxFreq > 0 && constraints.maxHeight >= 28;
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  channel.name.isNotEmpty
                      ? channel.name
                      : 'Ch ${channel.channelId + 1}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (showFrequency)
                  Text(
                    '${channel.frequencyDisplay} MHz',
                    style: TextStyle(fontSize: 9, color: Colors.grey.shade700),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
