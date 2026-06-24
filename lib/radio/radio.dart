/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';
import 'package:flutter/foundation.dart';

import '../services/data_broker_client.dart';
import 'radio_models.dart';
import 'radio_transport.dart';
import 'tnc_data_fragment.dart';
import 'ax25_packet.dart';
import 'bss_packet.dart';
import 'gaia_protocol.dart';
import 'utils.dart';

/// Maximum MTU for fragmenting data
const int _maxMtu = 50;

/// Radio update notification types
enum RadioUpdateNotification {
  state,
  channelInfo,
  batteryLevel,
  batteryVoltage,
  rcBatteryLevel,
  batteryAsPercentage,
  htStatus,
  settings,
  volume,
  allChannelsLoaded,
  regionChange,
  bssSettings,
}

/// Fragment in the transmit queue
class _FragmentInQueue {
  final Uint8List fragment;
  final bool isLast;
  final int fragId;
  String? tag;
  DateTime deadline;
  bool deleted = false;

  _FragmentInQueue({
    required this.fragment,
    required this.isLast,
    required this.fragId,
    this.tag,
    DateTime? deadline,
  }) : deadline = deadline ?? DateTime(9999);
}

/// Data for transmitting a frame
class TransmitDataFrameData {
  final AX25Packet? packet;
  final BSSPacket? bssPacket;
  final int channelId;
  final int regionId;

  TransmitDataFrameData({
    this.packet,
    this.bssPacket,
    this.channelId = -1,
    this.regionId = -1,
  });
}

/// Data for locking the radio
class SetLockData {
  final String usage;
  final int regionId;
  final int channelId;

  SetLockData({required this.usage, this.regionId = -1, this.channelId = -1});
}

/// Data for unlocking the radio
class SetUnlockData {
  final String usage;

  SetUnlockData({required this.usage});
}

/// Main Radio class for managing radio connections and communication
class Radio {
  final int deviceId;
  final String macAddress;
  String _friendlyName = '';

  final DataBrokerClient _broker;
  RadioTransport? _transport;
  TncDataFragment? _frameAccumulator;
  RadioState _state = RadioState.disconnected;
  bool _gpsEnabled = false;

  // GPS serial tracking
  double _lastGpsLat = double.nan;
  double _lastGpsLon = double.nan;

  // Transmit queue
  final List<_FragmentInQueue> _tncFragmentQueue = [];
  bool _tncFragmentInFlight = false;

  // Clear channel timer
  Timer? _clearChannelTimer;

  // Initialization retry timer
  Timer? _initRetryTimer;
  int _initRetryCount = 0;
  static const int _maxInitRetries = 3;
  bool _receivedAnyData = false;
  int _webInitCommandCount = 0;
  DateTime? _connectedAt;
  bool _webBleCompactMode = false;
  int _webBleCompactVariant = 0;
  int _compactRxLogCount = 0;
  int _lastCompactCmdValue = -1;
  int _lastCompactStatus = -1;
  DateTime _lastCompactLogAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _webBleCompactUnsupported = false;

  // Lock state
  RadioLockState? _lockState;
  int _savedRegionId = -1;
  int _savedChannelId = -1;
  bool _savedScan = false;
  int _savedDualWatch = 0;

  // Receive buffer for GAIA decoding
  final List<int> _receiveBuffer = [];

  // Public state
  RadioDevInfo? info;
  List<RadioChannelInfo?>? channels;
  RadioHtStatus? htStatus;
  RadioSettings? settings;
  RadioBssSettings? bssSettings;
  RadioPosition? position;
  bool hardwareModemEnabled = true;

  String get friendlyName => _friendlyName;
  RadioState get state => _state;
  int get transmitQueueLength => _tncFragmentQueue.length;
  String? get lockUsage =>
      (_lockState?.isLocked ?? false) ? _lockState?.usage : null;

  /// Update the friendly name for this radio
  void updateFriendlyName(String name) {
    if (name.isNotEmpty) {
      _friendlyName = name;
    }
  }

  bool get _packetTrace =>
      _broker.getValue<bool>(0, 'BluetoothFramesDebug') ?? false;
  bool get _loopbackMode => _broker.getValue<bool>(1, 'LoopbackMode') ?? false;
  bool get _allowTransmit =>
      (_broker.getValue<int>(0, 'AllowTransmit', 0) ?? 0) == 1;

  Radio({required this.deviceId, required this.macAddress})
    : _broker = DataBrokerClient() {
    _setupSubscriptions();
  }

  /// Helper method to dispatch data through the broker
  void _dispatch(String name, Object? data, {bool store = true}) {
    _broker.dispatch(deviceId: deviceId, name: name, data: data, store: store);
  }

  void _setupSubscriptions() {
    debugPrint(
      '[Radio $deviceId] Subscribing to ChannelChangeVfoA/B for device $deviceId',
    );
    // Subscribe to channel change events
    _broker.subscribeMultiple(
      deviceId: deviceId,
      names: ['ChannelChangeVfoA', 'ChannelChangeVfoB'],
      callback: _onChannelChangeEvent,
    );

    // Subscribe to settings change events
    _broker.subscribeMultiple(
      deviceId: deviceId,
      names: [
        'WriteSettings',
        'SetRegion',
        'DualWatch',
        'Scan',
        'SetGPS',
        'Region',
      ],
      callback: _onSettingsChangeEvent,
    );

    // Subscribe to channel write events
    _broker.subscribe(
      deviceId: deviceId,
      name: 'WriteChannel',
      callback: _onWriteChannelEvent,
    );

    // Subscribe to position events
    _broker.subscribe(
      deviceId: deviceId,
      name: 'GetPosition',
      callback: _onGetPositionEvent,
    );
    _broker.subscribe(
      deviceId: deviceId,
      name: 'SetPosition',
      callback: _onSetPositionEvent,
    );

    // Subscribe to transmit events
    _broker.subscribe(
      deviceId: deviceId,
      name: 'TransmitDataFrame',
      callback: _onTransmitDataFrameEvent,
    );

    // Subscribe to BSS settings
    _broker.subscribe(
      deviceId: deviceId,
      name: 'SetBssSettings',
      callback: _onSetBssSettingsEvent,
    );

    // Subscribe to lock/unlock events
    _broker.subscribe(
      deviceId: deviceId,
      name: 'SetLock',
      callback: _onSetLockEvent,
    );
    _broker.subscribe(
      deviceId: deviceId,
      name: 'SetUnlock',
      callback: _onSetUnlockEvent,
    );

    // Subscribe to volume events
    _broker.subscribe(
      deviceId: deviceId,
      name: 'SetVolumeLevel',
      callback: _onSetVolumeLevelEvent,
    );
    _broker.subscribe(
      deviceId: deviceId,
      name: 'SetSquelchLevel',
      callback: _onSetSquelchLevelEvent,
    );
    _broker.subscribe(
      deviceId: deviceId,
      name: 'GetVolume',
      callback: _onGetVolumeEvent,
    );

    // Subscribe to friendly name updates
    _broker.subscribe(
      deviceId: deviceId,
      name: 'UpdateFriendlyName',
      callback: _onUpdateFriendlyNameEvent,
    );

    // Subscribe to GPS serial data
    _broker.subscribe(
      deviceId: 1,
      name: 'GpsData',
      callback: _onGpsDataReceived,
    );
  }

  // Event handlers
  void _onUpdateFriendlyNameEvent(int devId, String name, dynamic data) {
    if (devId != deviceId) return;
    final newName = data as String? ?? '';
    if (newName.isNotEmpty) {
      _friendlyName = newName;
      _dispatch('FriendlyName', _friendlyName);
    }
  }

  void _onChannelChangeEvent(int devId, String name, dynamic data) {
    if (devId != deviceId) {
      _debug('Ignoring - wrong device ID');
      return;
    }
    if (settings == null) {
      _debug('Ignoring - settings not loaded yet');
      return;
    }
    if (_lockState?.isLocked == true) {
      _debug('Ignoring - radio is locked');
      return;
    }

    final channelId = data as int;
    switch (name) {
      case 'ChannelChangeVfoA':
        writeSettings(settings!.toByteArrayWith(channelA: channelId));
        break;
      case 'ChannelChangeVfoB':
        writeSettings(settings!.toByteArrayWith(channelB: channelId));
        break;
    }
  }

  void _onSettingsChangeEvent(int devId, String name, dynamic data) {
    if (devId != deviceId) return;

    switch (name) {
      case 'WriteSettings':
        if (_lockState != null) return;
        if (data is Uint8List) {
          writeSettings(data);
        }
        break;
      case 'SetRegion':
      case 'Region':
        if (_lockState != null) return;
        if (data is int) {
          setRegion(data);
        }
        break;
      case 'SetGPS':
        if (data is bool) {
          gpsEnabled = data;
        }
        break;
      case 'DualWatch':
        if (_lockState != null || settings == null) return;
        if (data is bool) {
          writeSettings(settings!.toByteArrayWith(doubleChannel: data ? 1 : 0));
        }
        break;
      case 'Scan':
        if (_lockState != null || settings == null) return;
        if (data is bool) {
          writeSettings(settings!.toByteArrayWith(scan: data));
        }
        break;
    }
  }

  void _onWriteChannelEvent(int devId, String name, dynamic data) {
    if (devId != deviceId) return;
    if (data is RadioChannelInfo) {
      setChannel(data);
    }
  }

  void _onGetPositionEvent(int devId, String name, dynamic data) {
    if (devId != deviceId) return;
    getPosition();
  }

  void _onSetPositionEvent(int devId, String name, dynamic data) {
    if (devId != deviceId) return;
    if (data is RadioPosition) {
      setPosition(data);
    }
  }

  void _onTransmitDataFrameEvent(int devId, String name, dynamic data) {
    if (devId != deviceId) return;
    if (data is! TransmitDataFrameData) return;

    final txData = data;
    if (txData.packet != null) {
      final packet = txData.packet!;
      if (txData.channelId >= 0) {
        packet.channelId = txData.channelId;
      }
      final outboundData = packet.toByteArray();
      transmitTncData(
        outboundData,
        packet.channelName,
        channelId: txData.channelId,
        regionId: txData.regionId,
        tag: packet.tag,
        deadline: packet.deadline,
      );
    } else if (txData.bssPacket != null) {
      // BSS packets carry no channel name; an empty name plus channelId -1
      // makes transmitTncData fall back to the current VFO A channel.
      final outboundData = txData.bssPacket!.encode();
      transmitTncData(
        outboundData,
        '',
        channelId: txData.channelId,
        regionId: txData.regionId,
      );
    }
  }

  void _onSetBssSettingsEvent(int devId, String name, dynamic data) {
    if (devId != deviceId) return;
    if (data is RadioBssSettings) {
      setBssSettings(data);
    }
  }

  void _onSetLockEvent(int devId, String name, dynamic data) {
    if (devId != deviceId) return;
    if (data is! SetLockData) return;
    if (_lockState != null || settings == null || htStatus == null) return;

    final lockData = data;

    // Save current state
    _savedRegionId = htStatus!.currRegion;
    _savedChannelId = settings!.channelA;
    _savedScan = settings!.scan;
    _savedDualWatch = settings!.doubleChannel;

    // Use current if -1
    final targetRegionId = lockData.regionId >= 0
        ? lockData.regionId
        : htStatus!.currRegion;
    final targetChannelId = lockData.channelId >= 0
        ? lockData.channelId
        : settings!.channelA;

    _lockState = RadioLockState(
      isLocked: true,
      usage: lockData.usage,
      regionId: targetRegionId,
      channelId: targetChannelId,
    );

    _dispatch('LockState', _lockState!.toJson());
    _debug(
      "Radio locked for usage '${lockData.usage}' - Region: $targetRegionId, Channel: $targetChannelId",
    );

    // Apply lock settings
    if (targetRegionId != htStatus!.currRegion) {
      setRegion(targetRegionId);
    }

    writeSettings(
      settings!.toByteArrayWith(
        channelA: targetChannelId,
        doubleChannel: 0,
        scan: false,
      ),
    );
  }

  void _onSetUnlockEvent(int devId, String name, dynamic data) {
    if (devId != deviceId) return;
    if (data is! SetUnlockData) return;
    if (_lockState == null) return;

    final unlockData = data;
    if (_lockState!.usage != unlockData.usage) return;
    if (settings == null) return;

    _debug(
      "Radio unlocked from usage '${unlockData.usage}' - Restoring previous settings",
    );

    // Restore region
    if (htStatus != null &&
        _savedRegionId != htStatus!.currRegion &&
        _savedRegionId >= 0) {
      setRegion(_savedRegionId);
    }

    // Restore settings
    writeSettings(
      settings!.toByteArrayWith(
        channelA: _savedChannelId,
        doubleChannel: _savedDualWatch,
        scan: _savedScan,
      ),
    );

    _lockState = null;

    final unlockedState = RadioLockState(
      isLocked: false,
      usage: null,
      regionId: -1,
      channelId: -1,
    );
    _dispatch('LockState', unlockedState.toJson());
  }

  void _onSetVolumeLevelEvent(int devId, String name, dynamic data) {
    if (devId != deviceId) return;
    if (data is int) {
      setVolumeLevel(data);
    }
  }

  void _onSetSquelchLevelEvent(int devId, String name, dynamic data) {
    if (devId != deviceId) return;
    if (data is int && settings != null) {
      setSquelchLevel(data);
    }
  }

  void _onGetVolumeEvent(int devId, String name, dynamic data) {
    if (devId != deviceId) return;
    getVolumeLevel();
  }

  void _onGpsDataReceived(int devId, String name, dynamic data) {
    if (_state != RadioState.connected) return;
    if (data is! Map) return;

    final gps = data;
    final isFixed = gps['isFixed'] as bool? ?? false;
    if (!isFixed) return;

    final lat = (gps['latitude'] as num?)?.toDouble() ?? 0.0;
    final lon = (gps['longitude'] as num?)?.toDouble() ?? 0.0;

    // Check if moved far enough
    if (!_lastGpsLat.isNaN && !_lastGpsLon.isNaN) {
      final dist = RadioUtils.haversineMetres(
        _lastGpsLat,
        _lastGpsLon,
        lat,
        lon,
      );
      if (dist < 10) return;
    }

    // Build and send position
    final pos = RadioPosition.fromCoordinates(
      lat: lat,
      lon: lon,
      altitudeMetres: (gps['altitude'] as num?)?.toDouble() ?? 0.0,
      speedKnots: (gps['speed'] as num?)?.toDouble() ?? 0.0,
      headingDegrees: (gps['heading'] as num?)?.toDouble() ?? 0.0,
      utcTime: DateTime.now().toUtc(),
    );
    setPosition(pos);

    _lastGpsLat = lat;
    _lastGpsLon = lon;
  }

  // Connection management
  Future<void> connect(RadioTransport transport) async {
    if (_state == RadioState.connected || _state == RadioState.connecting) {
      return;
    }

    _transport = transport;
    _updateState(RadioState.connecting);
    _debug('Attempting to connect to radio MAC: $macAddress');

    // Listen to transport events
    _transport!.stateStream.listen(_onTransportStateChanged);
    _transport!.dataStream.listen(_onDataReceived);

    // If the transport is already connected, trigger connected handling
    if (_transport!.state == TransportState.connected) {
      _onTransportConnected();
    }
  }

  void _onTransportStateChanged(TransportState state) {
    switch (state) {
      case TransportState.connected:
        _onTransportConnected();
        break;
      case TransportState.disconnected:
        _handleDisconnect('Transport disconnected');
        break;
      case TransportState.connecting:
        _updateState(RadioState.connecting);
        break;
      case TransportState.disconnecting:
        break;
    }
  }

  void _onTransportConnected() {
    _updateState(RadioState.connected);
    _receivedAnyData = false;
    _initRetryCount = 0;
    _webInitCommandCount = 0;
    _connectedAt = DateTime.now();
    _webBleCompactMode = false;
    _webBleCompactVariant = 0;
    _compactRxLogCount = 0;
    _lastCompactCmdValue = -1;
    _lastCompactStatus = -1;
    _lastCompactLogAt = DateTime.fromMillisecondsSinceEpoch(0);
    _webBleCompactUnsupported = false;

    if (kIsWeb) {
      _broker.logInfo('[Radio $deviceId] [WEB-BLE] Transport connected');
    }

    // Add a small delay before sending initial commands
    // Some radios need time to initialize the RFCOMM channel
    Future.delayed(const Duration(milliseconds: 200), () {
      if (_transport?.state != TransportState.connected) return;
      _sendInitialCommands();
    });
  }

  void _sendInitialCommands() {
    if (_transport?.state != TransportState.connected) return;

    final maxInitRetries = (kIsWeb && _webBleCompactMode) ? 6 : _maxInitRetries;

    _debug(
      'Sending initial commands (attempt ${_initRetryCount + 1}/$maxInitRetries)',
    );
    if (kIsWeb) {
      _broker.logInfo(
        '[Radio $deviceId] [WEB-BLE] Sending init command batch '
        '${_initRetryCount + 1}/$maxInitRetries',
      );
      if (_webBleCompactMode) {
        final variantName = switch (_webBleCompactVariant) {
          0 => 'cmd16-be',
          1 => 'group+cmd8',
          2 => 'cmd8',
          3 => 'cmd16-le',
          4 => 'group+cmd16-be',
          _ => 'group+cmd16-le',
        };
        _broker.logInfo(
          '[Radio $deviceId] [WEB-BLE] Compact variant: $variantName',
        );
      }
    }

    // Request initial data
    _sendCommand(
      RadioCommandGroup.basic,
      RadioBasicCommand.getDevInfo,
      Uint8List.fromList([3]),
    );
    _sendCommand(RadioCommandGroup.basic, RadioBasicCommand.readSettings, null);
    _sendCommand(
      RadioCommandGroup.basic,
      RadioBasicCommand.readBssSettings,
      null,
    );
    _requestPowerStatus(RadioPowerStatus.batteryLevelAsPercentage);

    // Set up retry timer - if we don't receive any data within 2 seconds, retry
    _initRetryTimer?.cancel();
    _initRetryTimer = Timer(const Duration(seconds: 2), () {
      if (!_receivedAnyData && _transport?.state == TransportState.connected) {
        _initRetryCount++;
        if (_initRetryCount < maxInitRetries) {
          _debug('No response received, retrying initial commands...');
          if (kIsWeb) {
            if (_webBleCompactMode) {
              _webBleCompactVariant = (_webBleCompactVariant + 1) % 6;
              final variantName = switch (_webBleCompactVariant) {
                0 => 'cmd16-be',
                1 => 'group+cmd8',
                2 => 'cmd8',
                3 => 'cmd16-le',
                4 => 'group+cmd16-be',
                _ => 'group+cmd16-le',
              };
              _broker.logInfo(
                '[Radio $deviceId] [WEB-BLE] Switching compact variant to '
                '$variantName',
              );
            }
            final connectedAt = _connectedAt;
            final elapsedMs = connectedAt == null
                ? 0
                : DateTime.now().difference(connectedAt).inMilliseconds;
            _broker.logInfo(
              '[Radio $deviceId] [WEB-BLE] No RX yet after ${elapsedMs}ms; '
              'retrying init commands',
            );
          }
          _sendInitialCommands();
        } else {
          _debug(
            'No response after $maxInitRetries attempts, radio may not be responding',
          );
          if (kIsWeb) {
            final connectedAt = _connectedAt;
            final elapsedMs = connectedAt == null
                ? 0
                : DateTime.now().difference(connectedAt).inMilliseconds;
            if (_webBleCompactMode) {
              _webBleCompactUnsupported = true;
              _broker.logError(
                '[Radio $deviceId] [WEB-BLE] Radio rejected all compact BLE '
                'control variants (status=notSupported). This firmware/browser '
                'path does not support web BLE control for this device.',
              );
            }
            _broker.logError(
              '[Radio $deviceId] [WEB-BLE] No RX after $maxInitRetries init '
              'attempts (${elapsedMs}ms since connected)',
            );
            if (_webBleCompactMode && _transport?.state == TransportState.connected) {
              _handleDisconnect(
                'Web BLE control not supported by this radio/browser path',
                RadioState.unableToConnect,
              );
            }
          }
        }
      }
    });
  }

  void disconnect([String? message]) {
    _handleDisconnect(message);
  }

  void _handleDisconnect([
    String? message,
    RadioState newState = RadioState.disconnected,
  ]) {
    if (message != null) _debug(message);

    _updateState(newState);
    _initRetryTimer?.cancel();
    _transport?.disconnect();

    // Clear data via broker
    _dispatch('Info', null);
    _dispatch('Channels', null);
    _dispatch('HtStatus', null);
    _dispatch('Settings', null);
    _dispatch('BssSettings', null);
    _dispatch('Position', null);
    _dispatch('AllChannelsLoaded', false);
    _dispatch('GpsEnabled', false);
    _dispatch('LockState', null);
    _dispatch('Volume', 0);
    _dispatch('BatteryAsPercentage', 0);
    _dispatch('BatteryLevel', 0);
    _dispatch('BatteryVoltage', 0.0);
    _dispatch('RcBatteryLevel', 0);

    // Clear local state
    info = null;
    channels = null;
    htStatus = null;
    settings = null;
    bssSettings = null;
    position = null;
    _frameAccumulator = null;
    _tncFragmentQueue.clear();
    _tncFragmentInFlight = false;
    _lockState = null;
    _gpsEnabled = false;
    _receiveBuffer.clear();
    _clearChannelTimer?.cancel();
    _clearChannelTimer = null;
  }

  void _updateState(RadioState newState) {
    if (_state == newState) return;
    _state = newState;
    // Capitalize first letter for UI display (e.g., "connected" -> "Connected")
    final stateName =
        newState.name[0].toUpperCase() + newState.name.substring(1);
    _dispatch('State', stateName);
    _debug('State changed to: $stateName');
  }

  // Channel management
  RadioChannelInfo? getChannelByFrequency(
    double freq,
    RadioModulationType mod,
  ) {
    if (channels == null) return null;
    final xfreq = (freq * 1000000).round();
    for (final ch in channels!) {
      if (ch != null &&
          ch.rxFreq == xfreq &&
          ch.txFreq == xfreq &&
          ch.rxMod == mod &&
          ch.txMod == mod) {
        return ch;
      }
    }
    return null;
  }

  RadioChannelInfo? getChannelByName(String name) {
    if (channels == null) return null;
    for (final ch in channels!) {
      if (ch?.name == name) return ch;
    }
    return null;
  }

  bool allChannelsLoaded() {
    if (channels == null) return false;
    for (final ch in channels!) {
      if (ch == null) return false;
    }
    return true;
  }

  void setChannel(RadioChannelInfo channel) {
    _sendCommand(
      RadioCommandGroup.basic,
      RadioBasicCommand.writeRfCh,
      channel.toByteArray(),
    );
  }

  void setRegion(int region) {
    _sendCommand(
      RadioCommandGroup.basic,
      RadioBasicCommand.setRegion,
      Uint8List.fromList([region]),
    );
  }

  void _updateChannels() {
    if (_state != RadioState.connected || info == null) return;
    for (int i = 0; i < info!.channelCount; i++) {
      _sendCommand(
        RadioCommandGroup.basic,
        RadioBasicCommand.readRfCh,
        Uint8List.fromList([i]),
      );
    }
  }

  String _getChannelNameById(int channelId) {
    if (channelId >= 254) return 'NOAA';
    if (channels != null &&
        channels!.length > channelId &&
        channels![channelId] != null) {
      return channels![channelId]!.name;
    }
    return '';
  }

  /// The id (curr_ch_id from the HT status) of the channel currently being
  /// received — i.e. the active VFO. Returns 0 if the status is not yet known.
  int get currentChannelId => htStatus?.currChId ?? 0;

  /// The name of the channel currently being received (the active VFO), or an
  /// empty string if the channel list / HT status is not yet available.
  String get currentChannelName => _getChannelNameById(htStatus?.currChId ?? 0);

  bool isOnMuteChannel() {
    if (_state != RadioState.connected ||
        channels == null ||
        htStatus == null) {
      return true;
    }
    // NOAA weather channels (curr_ch_id >= 254) are never muted; they cover a
    // range of sub-channels, so any id at or above 254 is NOAA, not just 254.
    if (htStatus!.currChId >= 254) return false;
    if (htStatus!.currChId >= channels!.length) return true;
    if (channels![htStatus!.currChId] == null) return true;
    return channels![htStatus!.currChId]!.mute;
  }

  // GPS management
  set gpsEnabled(bool enabled) {
    if (_gpsEnabled == enabled) return;
    _gpsEnabled = enabled;

    _dispatch('GpsEnabled', _gpsEnabled);

    if (_state == RadioState.connected) {
      final cmd = _gpsEnabled
          ? RadioBasicCommand.registerNotification
          : RadioBasicCommand.cancelNotification;
      _sendCommand(
        RadioCommandGroup.basic,
        cmd,
        Uint8List.fromList([0, 0, 0, RadioNotification.positionChange.value]),
      );
    }

    if (!_gpsEnabled) {
      position = null;
      _dispatch('Position', null);
    }
  }

  bool get gpsEnabled => _gpsEnabled;

  void getPosition() {
    _sendCommand(RadioCommandGroup.basic, RadioBasicCommand.getPosition, null);
  }

  void setPosition(RadioPosition pos) {
    _sendCommand(
      RadioCommandGroup.basic,
      RadioBasicCommand.setPosition,
      pos.toByteArray(),
    );
  }

  // Settings and status
  void writeSettings(Uint8List data) {
    _sendCommand(
      RadioCommandGroup.basic,
      RadioBasicCommand.writeSettings,
      data,
    );
  }

  void getVolumeLevel() {
    _sendCommand(RadioCommandGroup.basic, RadioBasicCommand.getVolume, null);
  }

  void setVolumeLevel(int level) {
    if (level < 0 || level > 15) return;
    _sendCommand(
      RadioCommandGroup.basic,
      RadioBasicCommand.setVolume,
      Uint8List.fromList([level]),
    );
  }

  void setSquelchLevel(int level) {
    if (settings == null) return;
    writeSettings(settings!.toByteArrayWith(squelchLevel: level));
  }

  void setBssSettings(RadioBssSettings bss) {
    _sendCommand(
      RadioCommandGroup.basic,
      RadioBasicCommand.writeBssSettings,
      bss.toByteArray(),
    );
  }

  void getBatteryLevel() => _requestPowerStatus(RadioPowerStatus.batteryLevel);
  void getBatteryVoltage() =>
      _requestPowerStatus(RadioPowerStatus.batteryVoltage);
  void getBatteryRcLevel() =>
      _requestPowerStatus(RadioPowerStatus.rcBatteryLevel);
  void getBatteryLevelAsPercentage() =>
      _requestPowerStatus(RadioPowerStatus.batteryLevelAsPercentage);

  void _requestPowerStatus(RadioPowerStatus status) {
    _sendCommand(
      RadioCommandGroup.basic,
      RadioBasicCommand.readStatus,
      Uint8List.fromList([0, status.value]),
    );
  }

  // Data transmission
  int transmitTncData(
    Uint8List outboundData,
    String channelName, {
    int channelId = -1,
    int regionId = -1,
    String? tag,
    DateTime? deadline,
  }) {
    if (!_allowTransmit) return 0;

    // Fill defaults from current settings
    if (channelId == -1 && settings != null) channelId = settings!.channelA;
    if (regionId == -1 && htStatus != null) regionId = htStatus!.currRegion;

    // Fill channel name if not specified
    if (channelName.isEmpty &&
        channelId >= 0 &&
        channels != null &&
        channelId < channels!.length &&
        channels![channelId] != null) {
      channelName = channels![channelId]!.name;
    }

    final t = DateTime.now();
    final fragmentChannelName = _getFragmentChannelName(channelId, channelName);
    final fragment = _createOutboundFragment(
      outboundData,
      channelId,
      regionId,
      t,
      fragmentChannelName,
    );

    if (_loopbackMode) {
      _transmitLoopback(
        fragment,
        outboundData,
        channelId,
        regionId,
        t,
        fragmentChannelName,
      );
    } else if (hardwareModemEnabled) {
      _transmitHardwareModem(
        fragment,
        outboundData,
        channelId,
        regionId,
        tag,
        deadline ?? DateTime(9999),
      );
    }

    return outboundData.length;
  }

  String _getFragmentChannelName(int channelId, String fallback) {
    if (channels != null &&
        channelId >= 0 &&
        channelId < channels!.length &&
        channels![channelId] != null) {
      return channels![channelId]!.name;
    }
    return fallback;
  }

  TncDataFragment _createOutboundFragment(
    Uint8List data,
    int channelId,
    int regionId,
    DateTime time,
    String channelName,
  ) {
    final fragment = TncDataFragment(
      finalFragment: true,
      fragmentId: 0,
      data: data,
      channelId: channelId,
      regionId: regionId,
    );
    fragment.incoming = false;
    fragment.time = time;
    fragment.channelName = channelName;
    return fragment;
  }

  void _transmitLoopback(
    TncDataFragment fragment,
    Uint8List data,
    int channelId,
    int regionId,
    DateTime time,
    String channelName,
  ) {
    fragment.encoding = FragmentEncodingType.loopback;
    fragment.frameType = FragmentFrameType.ax25;
    _dispatchDataFrame(fragment);

    // Simulate receive
    final fragment2 = TncDataFragment(
      finalFragment: true,
      fragmentId: 0,
      data: data,
      channelId: channelId,
      regionId: regionId,
    );
    fragment2.incoming = true;
    fragment2.time = time;
    fragment2.encoding = FragmentEncodingType.loopback;
    fragment2.frameType = FragmentFrameType.ax25;
    fragment2.channelName = channelName;
    _dispatchDataFrame(fragment2);
  }

  void _transmitHardwareModem(
    TncDataFragment fragment,
    Uint8List outboundData,
    int channelId,
    int regionId,
    String? tag,
    DateTime deadline,
  ) {
    fragment.encoding = FragmentEncodingType.hardwareAfsk1200;
    fragment.frameType = FragmentFrameType.ax25;
    _dispatchDataFrame(fragment);

    // Fragment for Bluetooth MTU
    int i = 0;
    int fragId = 0;
    while (i < outboundData.length) {
      final fragmentSize = (outboundData.length - i).clamp(0, _maxMtu);
      final fragmentData = Uint8List.fromList(
        outboundData.sublist(i, i + fragmentSize),
      );
      final isFinal = (i + fragmentData.length) == outboundData.length;

      final tncFragment = TncDataFragment(
        finalFragment: isFinal,
        fragmentId: fragId,
        data: fragmentData,
        channelId: channelId,
        regionId: regionId,
      );

      _tncFragmentQueue.add(
        _FragmentInQueue(
          fragment: tncFragment.toByteArray(),
          isLast: isFinal,
          fragId: fragId,
          tag: tag,
          deadline: deadline,
        ),
      );

      i += fragmentSize;
      fragId++;
    }

    _trySendNextFragment();
  }

  void _trySendNextFragment() {
    if (_tncFragmentInFlight || _tncFragmentQueue.isEmpty) return;
    if (htStatus == null || htStatus!.rssi != 0 || htStatus!.isInTx) return;

    _tncFragmentInFlight = true;
    _sendCommand(
      RadioCommandGroup.basic,
      RadioBasicCommand.htSendData,
      _tncFragmentQueue.first.fragment,
    );
  }

  void deleteTransmitByTag(String tag) {
    for (final f in _tncFragmentQueue) {
      if (f.tag == tag) f.deleted = true;
    }
  }

  void _clearTransmitQueue() {
    if (_tncFragmentQueue.isEmpty || _tncFragmentQueue.first.fragId != 0) {
      return;
    }

    final now = DateTime.now();
    _tncFragmentQueue.removeWhere((f) => f.deleted || f.deadline.isBefore(now));
  }

  void _dispatchDataFrame(TncDataFragment fragment) {
    _dispatch('DataFrameTx', fragment.toJson(), store: false);
    _emitDataFrame(fragment);
  }

  /// Dispatches the unified "DataFrame" event carrying the fragment object,
  /// matching the C# architecture. Consumed by the FrameDeduplicator handler.
  void _emitDataFrame(TncDataFragment fragment) {
    fragment.radioMac = macAddress;
    fragment.radioDeviceId = deviceId;
    _dispatch('DataFrame', fragment, store: false);
  }

  // Command handling
  void _sendCommand(
    RadioCommandGroup group,
    RadioBasicCommand cmd,
    Uint8List? data,
  ) {
    if (_transport == null) return;

    Uint8List gaiaFrame;
    if (kIsWeb && _webBleCompactMode && group == RadioCommandGroup.basic) {
      // Web BLE compact mode: radios may use one of several compact command
      // layouts. We rotate variants across retries until one responds.
      final payloadLen = data?.length ?? 0;
      if (_webBleCompactVariant == 1) {
        // FF 01 <group8> <cmd8> [data]
        gaiaFrame = Uint8List(4 + payloadLen);
        gaiaFrame[0] = 0xFF;
        gaiaFrame[1] = 0x01;
        gaiaFrame[2] = group.value & 0xFF;
        gaiaFrame[3] = cmd.value & 0xFF;
        if (data != null) {
          for (int i = 0; i < data.length; i++) {
            gaiaFrame[4 + i] = data[i];
          }
        }
      } else if (_webBleCompactVariant == 2) {
        // FF 01 <cmd8> [data]
        gaiaFrame = Uint8List(3 + payloadLen);
        gaiaFrame[0] = 0xFF;
        gaiaFrame[1] = 0x01;
        gaiaFrame[2] = cmd.value & 0xFF;
        if (data != null) {
          for (int i = 0; i < data.length; i++) {
            gaiaFrame[3 + i] = data[i];
          }
        }
      } else if (_webBleCompactVariant == 3) {
        // FF 01 <cmd16_le> [data]
        gaiaFrame = Uint8List(4 + payloadLen);
        gaiaFrame[0] = 0xFF;
        gaiaFrame[1] = 0x01;
        gaiaFrame[2] = cmd.value & 0xFF;
        gaiaFrame[3] = (cmd.value >> 8) & 0xFF;
        if (data != null) {
          for (int i = 0; i < data.length; i++) {
            gaiaFrame[4 + i] = data[i];
          }
        }
      } else if (_webBleCompactVariant == 4) {
        // FF 01 <group8> <cmd16_be> [data]
        gaiaFrame = Uint8List(5 + payloadLen);
        gaiaFrame[0] = 0xFF;
        gaiaFrame[1] = 0x01;
        gaiaFrame[2] = group.value & 0xFF;
        gaiaFrame[3] = (cmd.value >> 8) & 0xFF;
        gaiaFrame[4] = cmd.value & 0xFF;
        if (data != null) {
          for (int i = 0; i < data.length; i++) {
            gaiaFrame[5 + i] = data[i];
          }
        }
      } else if (_webBleCompactVariant == 5) {
        // FF 01 <group8> <cmd16_le> [data]
        gaiaFrame = Uint8List(5 + payloadLen);
        gaiaFrame[0] = 0xFF;
        gaiaFrame[1] = 0x01;
        gaiaFrame[2] = group.value & 0xFF;
        gaiaFrame[3] = cmd.value & 0xFF;
        gaiaFrame[4] = (cmd.value >> 8) & 0xFF;
        if (data != null) {
          for (int i = 0; i < data.length; i++) {
            gaiaFrame[5 + i] = data[i];
          }
        }
      } else {
        // FF 01 <cmd16_be> [data]
        gaiaFrame = Uint8List(4 + payloadLen);
        gaiaFrame[0] = 0xFF;
        gaiaFrame[1] = 0x01;
        gaiaFrame[2] = (cmd.value >> 8) & 0xFF;
        gaiaFrame[3] = cmd.value & 0xFF;
        if (data != null) {
          for (int i = 0; i < data.length; i++) {
            gaiaFrame[4 + i] = data[i];
          }
        }
      }
    } else {
      final cmdData = GaiaProtocol.buildCommand(group, cmd, data);
      gaiaFrame = GaiaProtocol.encode(cmdData);
    }

    if (_packetTrace) {
      _debug('TX: ${RadioUtils.bytesToHex(gaiaFrame)}');
    }

    if (kIsWeb && !_receivedAnyData && _webInitCommandCount < 20) {
      _webInitCommandCount++;
      _broker.logInfo(
        '[Radio $deviceId] [WEB-BLE] TX init[$_webInitCommandCount] '
        '${cmd.name} (${gaiaFrame.length} bytes)',
      );
    }

    _transport!.send(gaiaFrame);
  }

  bool _tryHandleWebCompactResponse(Uint8List data) {
    if (!kIsWeb || data.length < 5) return false;
    if (_webBleCompactUnsupported) return true;
    if (data[0] != 0xFF || data[1] != 0x01) return false;

    final cmdHi = data[2];
    final cmdLo = data[3];
    final isResponse = (cmdHi & 0x80) != 0;
    if (!isResponse) return false;

    // Signature seen on UV-PRO web BLE when using GAIA framing against a
    // compact command endpoint: FF 01 80 02 01 (error for cmd 0x0002).
    if (!_webBleCompactMode && cmdHi == 0x80 && cmdLo == 0x02 && data[4] == 1) {
      _webBleCompactMode = true;
      _webBleCompactVariant = 0;
      _broker.logInfo(
        '[Radio $deviceId] [WEB-BLE] Detected compact BLE protocol; '
        'switching command framing and retrying init',
      );

      _receivedAnyData = false;
      _initRetryCount = 0;
      _webInitCommandCount = 0;
      _initRetryTimer?.cancel();

      Future<void>.delayed(const Duration(milliseconds: 120), () {
        if (_transport?.state == TransportState.connected) {
          _sendInitialCommands();
        }
      });
      return true;
    }

    if (!_webBleCompactMode) return false;

    final status = data[4];
    // Two response forms have been observed:
    // - FF 01 80 05 01      (response bit in cmd hi, cmd=0x0005)
    // - FF 01 82 05 01      (response bit + group8 in byte2, cmd8 in byte3)
    // Normalize both to a 16-bit command id for logging/dispatch.
    final compactCmdValue = ((cmdHi & 0x7F) == RadioCommandGroup.basic.value)
        ? cmdLo
        : (((cmdHi & 0x7F) << 8) | cmdLo);
    final compactCmd = RadioBasicCommand.fromValue(compactCmdValue);
    final isStatusOnlyNak = data.length == 5 && status != 0;
    final statusName = switch (status) {
      0 => 'success',
      1 => 'notSupported',
      2 => 'notAuthenticated',
      3 => 'insufficientResources',
      4 => 'authenticating',
      5 => 'invalidParameter',
      6 => 'incorrectState',
      7 => 'inProgress',
      _ => 'unknown',
    };

    if (kIsWeb) {
      final now = DateTime.now();
      final shouldLog = _compactRxLogCount < 120 &&
          (compactCmdValue != _lastCompactCmdValue ||
              status != _lastCompactStatus ||
              now.difference(_lastCompactLogAt).inMilliseconds >= 1500);
      if (shouldLog) {
        _compactRxLogCount++;
        _lastCompactCmdValue = compactCmdValue;
        _lastCompactStatus = status;
        _lastCompactLogAt = now;
        _broker.logInfo(
          '[Radio $deviceId] [WEB-BLE] Compact RX cmd=${compactCmd.name} '
          '(0x${compactCmdValue.toRadixString(16).padLeft(4, '0')}) '
          'status=$status($statusName) len=${data.length}',
        );
      }
    }

    // Compact frame counts as RX for init retry logic.
    // Keep retry logic active for status-only NAK frames so we can rotate
    // compact command variants automatically.
    if (!_receivedAnyData && !isStatusOnlyNak) {
      _receivedAnyData = true;
      _initRetryTimer?.cancel();
      if (kIsWeb) {
        final connectedAt = _connectedAt;
        final elapsedMs = connectedAt == null
            ? 0
            : DateTime.now().difference(connectedAt).inMilliseconds;
        _broker.logInfo(
          '[Radio $deviceId] [WEB-BLE] First compact RX data received '
          '(${data.length} bytes, ${elapsedMs}ms after connect)',
        );
      }
    }

    if (isStatusOnlyNak) {
      return true;
    }

    // Convert compact response to the internal command shape expected by
    // _handleCommand: [group_hi group_lo cmd_hi cmd_lo status payload...].
    final cmd = Uint8List(data.length);
    cmd[0] = 0x00;
    cmd[1] = RadioCommandGroup.basic.value;
    cmd[2] = data[2];
    cmd[3] = data[3];
    for (int i = 4; i < data.length; i++) {
      cmd[i] = data[i];
    }

    if (_packetTrace) {
      _debug(
        'RX compact: ${RadioUtils.bytesToHex(data)} -> ${RadioUtils.bytesToHex(cmd)}',
      );
    }
    _handleCommand(cmd);
    return true;
  }

  void _onDataReceived(Uint8List data) {
    if (_tryHandleWebCompactResponse(data)) {
      return;
    }

    // Mark that we received data (for init retry logic)
    if (!_receivedAnyData) {
      _receivedAnyData = true;
      _initRetryTimer?.cancel();
      _debug('First data received from radio');
      if (kIsWeb) {
        final connectedAt = _connectedAt;
        final elapsedMs = connectedAt == null
            ? 0
            : DateTime.now().difference(connectedAt).inMilliseconds;
        _broker.logInfo(
          '[Radio $deviceId] [WEB-BLE] First RX data received '
          '(${data.length} bytes, ${elapsedMs}ms after connect)',
        );
      }
    }

    if (_packetTrace) {
      _debug('RX raw: ${RadioUtils.bytesToHex(data)}');
    }
    _receiveBuffer.addAll(data);

    // Try to decode GAIA frames
    while (_receiveBuffer.length >= 8) {
      final result = GaiaProtocol.decode(
        Uint8List.fromList(_receiveBuffer),
        0,
        _receiveBuffer.length,
      );

      if (result.consumed == -1) {
        // Error, skip one byte
        _receiveBuffer.removeAt(0);
      } else if (result.consumed == 0) {
        // Need more data
        break;
      } else {
        // Got a command
        _receiveBuffer.removeRange(0, result.consumed);
        if (result.command != null) {
          _handleCommand(result.command!);
        }
      }
    }
  }

  void _handleCommand(Uint8List cmd) {
    if (cmd.length < 4) return;

    final parsed = GaiaProtocol.parseResponse(cmd);
    final payload = cmd.length > 4
        ? Uint8List.fromList(cmd.sublist(4))
        : Uint8List(0);

    if (_packetTrace) {
      _debug('RX: ${parsed.command.name} - ${RadioUtils.bytesToHex(payload)}');
    }

    // Handle the command - pass full cmd to handlers that need vendor+cmd+payload offsets
    // (matching C# behavior where models expect data starting at offset 4 for payload)
    switch (parsed.command) {
      case RadioBasicCommand.getDevInfo:
        _handleDevInfo(cmd);
        break;
      case RadioBasicCommand.readSettings:
        _handleReadSettings(cmd);
        break;
      case RadioBasicCommand.getHtStatus:
        _handleHtStatus(cmd);
        break;
      case RadioBasicCommand.readRfCh:
        _handleReadRfCh(cmd);
        break;
      case RadioBasicCommand.writeRfCh:
        // After a successful channel write the radio does not notify of the
        // change, so re-read that channel to refresh the cached value (matches
        // the C# Radio.cs WRITE_RF_CH handling). cmd[4] is the status byte
        // (0 = success) and cmd[5] is the channel id that was written.
        if (cmd.length > 5 && cmd[4] == 0) {
          _sendCommand(
            RadioCommandGroup.basic,
            RadioBasicCommand.readRfCh,
            Uint8List.fromList([cmd[5]]),
          );
        }
        break;
      case RadioBasicCommand.readBssSettings:
        _handleBssSettings(cmd);
        break;
      case RadioBasicCommand.getPosition:
        _handleGetPosition(cmd);
        break;
      case RadioBasicCommand.readStatus:
        _handleReadStatus(payload); // Uses payload-relative offsets
        break;
      case RadioBasicCommand.getVolume:
        _handleGetVolume(payload); // Uses payload-relative offsets
        break;
      case RadioBasicCommand.eventNotification:
        _handleEventNotification(cmd);
        break;
      case RadioBasicCommand.htSendData:
        _handleHtSendData(payload); // Uses payload-relative offsets
        break;
      case RadioBasicCommand.rxData:
        _handleRxData(cmd); // Needs full cmd for TncDataFragment offset
        break;
      default:
        break;
    }
  }

  void _handleDevInfo(Uint8List data) {
    info = RadioDevInfo.fromBytes(data);
    if (info != null) {
      // Only use RadioDevInfo name if no Bluetooth friendly name was provided
      if (_friendlyName.isEmpty) {
        _friendlyName = info!.name;
      }
      channels = List<RadioChannelInfo?>.filled(info!.channelCount, null);
      _dispatch('Info', info!.toJson());
      _dispatch('FriendlyName', _friendlyName);
      _dispatch('GpsEnabled', _gpsEnabled);
      _dispatch('AllChannelsLoaded', false);

      // Register for HT status change notifications
      _sendCommand(
        RadioCommandGroup.basic,
        RadioBasicCommand.registerNotification,
        Uint8List.fromList([RadioNotification.htStatusChanged.value]),
      );

      // If GPS is enabled, register for position change notifications
      if (_gpsEnabled) {
        _sendCommand(
          RadioCommandGroup.basic,
          RadioBasicCommand.registerNotification,
          Uint8List.fromList([RadioNotification.positionChange.value]),
        );
      }

      // Request channels
      _updateChannels();

      // Request HT status
      _sendCommand(
        RadioCommandGroup.basic,
        RadioBasicCommand.getHtStatus,
        null,
      );
    }
  }

  void _handleReadSettings(Uint8List data) {
    _debug(
      'Received settings data, length: ${data.length}, data: ${RadioUtils.bytesToHex(data)}',
    );
    settings = RadioSettings.fromBytes(data);
    if (settings != null) {
      _debug(
        'Settings parsed: channelA=${settings!.channelA}, channelB=${settings!.channelB}, rawData.length=${settings!.rawData.length}',
      );
      _dispatch('Settings', settings!.toJson());
    } else {
      _debug('Failed to parse settings');
    }
  }

  void _handleHtStatus(Uint8List data) {
    htStatus = RadioHtStatus.fromBytes(data);
    if (htStatus != null) {
      _dispatch('HtStatus', htStatus!.toJson());
    }
  }

  void _handleReadRfCh(Uint8List data) {
    final channel = RadioChannelInfo.fromBytes(data);
    if (channels != null && channel.channelId < channels!.length) {
      channels![channel.channelId] = channel;
      _dispatch('Channel_${channel.channelId}', channel.toJson());

      if (allChannelsLoaded()) {
        _dispatch('AllChannelsLoaded', true);
        // Dispatch the full channels list for UI
        _dispatch(
          'Channels',
          channels!.where((c) => c != null).map((c) => c!.toJson()).toList(),
        );
      }
    }
  }

  void _handleBssSettings(Uint8List data) {
    bssSettings = RadioBssSettings.fromBytes(data);
    if (bssSettings != null) {
      _dispatch('BssSettings', bssSettings!.toJson());
    }
  }

  void _handleGetPosition(Uint8List data) {
    position = RadioPosition.fromBytes(data);
    if (position != null) {
      _dispatch('Position', position!.toJson());
    }
  }

  void _handleReadStatus(Uint8List data) {
    if (data.isEmpty) return;
    final statusType = RadioPowerStatus.values.firstWhere(
      (e) => e.value == data[0],
      orElse: () => RadioPowerStatus.unknown,
    );

    switch (statusType) {
      case RadioPowerStatus.batteryLevel:
        if (data.length > 1) {
          _dispatch('BatteryLevel', data[1]);
        }
        break;
      case RadioPowerStatus.batteryVoltage:
        if (data.length > 2) {
          final voltage = RadioUtils.getShort(data, 1) / 100.0;
          _dispatch('BatteryVoltage', voltage);
        }
        break;
      case RadioPowerStatus.rcBatteryLevel:
        if (data.length > 1) {
          _dispatch('RcBatteryLevel', data[1]);
        }
        break;
      case RadioPowerStatus.batteryLevelAsPercentage:
        if (data.length > 1) {
          _dispatch('BatteryAsPercentage', data[1]);
        }
        break;
      default:
        break;
    }
  }

  void _handleGetVolume(Uint8List data) {
    if (data.isNotEmpty) {
      _dispatch('Volume', data[0]);
    }
  }

  void _handleEventNotification(Uint8List data) {
    if (data.length < 5) {
      return; // Need at least vendor(2) + cmd(2) + notification(1)
    }

    // Notification type is a single byte at offset 4 (after vendor + cmd bytes)
    final notificationType = RadioUtils.getByte(data, 4);
    final notification = RadioNotification.values.firstWhere(
      (e) => e.value == notificationType,
      orElse: () => RadioNotification.unknown,
    );

    if (_packetTrace) {
      _debug('Event notification: ${notification.name}');
    }

    switch (notification) {
      case RadioNotification.htStatusChanged:
        // The notification contains the HT status data inline (starting at offset 5)
        _handleHtStatusChanged(data);
        break;
      case RadioNotification.htChChanged:
        // Channel changed - request fresh settings
        _sendCommand(
          RadioCommandGroup.basic,
          RadioBasicCommand.readSettings,
          null,
        );
        break;
      case RadioNotification.htSettingsChanged:
        // The notification contains the settings data inline (starting at offset 5)
        _handleSettingsChanged(data);
        break;
      case RadioNotification.bssSettingsChanged:
        _sendCommand(
          RadioCommandGroup.basic,
          RadioBasicCommand.readBssSettings,
          null,
        );
        break;
      case RadioNotification.positionChange:
        // Position change notification contains position data inline
        _handlePositionChange(data);
        break;
      case RadioNotification.dataRxd:
        _handleDataReceived(data);
        break;
      default:
        break;
    }
  }

  void _handleHtStatusChanged(Uint8List data) {
    final oldRegion = htStatus?.currRegion ?? -1;
    htStatus = RadioHtStatus.fromBytes(data);
    if (htStatus != null) {
      _dispatch('HtStatus', htStatus!.toJson());

      // Check if region changed
      if (oldRegion != htStatus!.currRegion && oldRegion != -1) {
        _dispatch('RegionChange', null, store: false);
        _dispatch('AllChannelsLoaded', false);
        if (channels != null) {
          for (int i = 0; i < channels!.length; i++) {
            channels![i] = null;
          }
        }
        _dispatch('Channels', null);
        _updateChannels();
      }

      _trySendNextFragment();
    }
  }

  void _handleSettingsChanged(Uint8List data) {
    settings = RadioSettings.fromBytes(data);
    if (settings != null) {
      _dispatch('Settings', settings!.toJson());
    }
  }

  void _handlePositionChange(Uint8List data) {
    // Set status byte to success for position parsing
    if (data.length > 4) {
      final modifiedData = Uint8List.fromList(data);
      modifiedData[4] = 0; // Set status to success
      position = RadioPosition.fromBytes(modifiedData);
      if (position != null && _gpsEnabled) {
        _dispatch('Position', position!.toJson());
      }
    }
  }

  void _handleDataReceived(Uint8List data) {
    if (!hardwareModemEnabled) return;

    if (_packetTrace) {
      _debug('RawData: ${RadioUtils.bytesToHex(data)}');
    }

    final fragment = TncDataFragment.fromBytes(data);
    fragment.encoding = FragmentEncodingType.hardwareAfsk1200;
    fragment.corrections = 0;
    fragment.incoming = true;
    fragment.time = DateTime.now();
    if (fragment.channelId == -1 && htStatus != null) {
      fragment.channelId = htStatus!.currChId;
    }
    fragment.channelName = _getChannelNameById(fragment.channelId);

    if (_packetTrace) {
      _debug(
        'DataFragment, FragId=${fragment.fragmentId}, IsFinal=${fragment.isLast}, ChannelId=${fragment.channelId}, DataLen=${fragment.data.length}',
      );
    }

    _accumulateFragment(fragment);
  }

  void _accumulateFragment(TncDataFragment fragment) {
    if (_frameAccumulator == null) {
      if (fragment.fragmentId == 0) {
        _frameAccumulator = fragment;
      }
    } else {
      _frameAccumulator!.append(fragment);
    }

    if (fragment.isLast && _frameAccumulator != null) {
      _frameAccumulator!.encoding = FragmentEncodingType.hardwareAfsk1200;
      _frameAccumulator!.frameType = FragmentFrameType.ax25;
      _dispatch('DataFrameRx', _frameAccumulator!.toJson(), store: false);
      _emitDataFrame(_frameAccumulator!);
      _frameAccumulator = null;
    }
  }

  void _handleHtSendData(Uint8List data) {
    // Fragment sent successfully
    if (_tncFragmentQueue.isNotEmpty) {
      _tncFragmentQueue.removeAt(0);
    }
    _tncFragmentInFlight = false;
    _clearTransmitQueue();
    _trySendNextFragment();
  }

  void _handleRxData(Uint8List data) {
    final fragment = TncDataFragment.fromBytes(data);

    fragment.incoming = true;
    fragment.time = DateTime.now();
    fragment.channelName = _getChannelNameById(fragment.channelId);

    if (fragment.fragmentId == 0) {
      _frameAccumulator = fragment;
    } else if (_frameAccumulator != null) {
      _frameAccumulator!.append(fragment);
    }

    if (fragment.isLast && _frameAccumulator != null) {
      _frameAccumulator!.encoding = FragmentEncodingType.hardwareAfsk1200;
      _frameAccumulator!.frameType = FragmentFrameType.ax25;

      // Dispatch the complete frame
      _dispatch('DataFrameRx', _frameAccumulator!.toJson(), store: false);
      _emitDataFrame(_frameAccumulator!);

      // Try to decode as AX.25 packet
      final packet = AX25Packet.decode(_frameAccumulator!);
      if (packet != null) {
        _dispatch('AX25PacketRx', {
          'addresses': packet.addresses.map((a) => a.toString()).toList(),
          'type': packet.frameTypeName,
          'data': packet.dataStr,
          'incoming': true,
          'channelId': packet.channelId,
          'channelName': packet.channelName,
        }, store: false);
      }

      _frameAccumulator = null;
    }
  }

  void _debug(String message) {
    // If packet tracing is enabled, dispatch to DataBroker for debug tab
    if (_packetTrace) {
      _broker.logInfo('[Radio $deviceId] $message');
    }
  }

  void dispose() {
    _handleDisconnect('Disposing radio');
    _broker.dispose();
  }
}
