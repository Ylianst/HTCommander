/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';
import 'package:flutter/foundation.dart';

import '../services/data_broker_client.dart';
import '../gps/gps_data.dart';
import 'radio_models.dart';
import 'radio_transport.dart';
import 'tnc_data_fragment.dart';
import 'ax25_packet.dart';
import 'bss_packet.dart';
import 'gaia_protocol.dart';
import 'firmware_vm_protocol.dart';
import 'utils.dart';

/// Maximum MTU for fragmenting data
const int _maxMtu = 50;

/// SmartBeaconing parameters (classic APRS algorithm) used when forwarding the
/// serial GPS position to the radio. Speeds are in knots to match the NMEA RMC
/// speed-over-ground reported by the serial GPS.
const double _sbLowSpeedKnots = 5.0; // at/below this, beacon at the slow rate
const double _sbHighSpeedKnots = 60.0; // at/above this, beacon at the fast rate
const int _sbFastRateSecs = 60; // minimum interval between beacons (fast)
const int _sbSlowRateSecs = 1800; // maximum interval between beacons (slow)
const double _sbTurnMinDegrees = 28.0; // minimum turn angle for corner pegging
const double _sbTurnSlope = 26.0; // corner-peg sensitivity vs. speed
const int _sbTurnTimeSecs = 30; // minimum interval between corner-peg beacons

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

/// A queued channel (READ_RF_CH) or region-name (READ_REGION_NAME) read that is
/// awaiting its reply before the next read is sent. See [Radio._readQueue].
class _PendingRead {
  final RadioBasicCommand cmd;
  final int index;
  _PendingRead(this.cmd, this.index);
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

  // Whether the radio's position-change notification is currently registered.
  // The radio only transmits APRS position beacons while this is registered, so
  // it must be active whenever the internal GPS (File > GPS) is on or the user
  // is sharing a serial GPS position. Tracked so commands are only sent when
  // the desired state actually changes. Reset on disconnect (a power cycle
  // clears the radio-side registration).
  bool _positionNotifyRegistered = false;

  // GPS serial SmartBeaconing tracking
  DateTime? _lastGpsSentTime;
  double _lastGpsSentHeading = double.nan;

  // Tracks the last serial-GPS diagnostic reason we logged, so repeated
  // identical messages (a GPS emits several sentences per second) don't flood
  // the debug log. Only state transitions are logged.
  String? _lastGpsDebugReason;

  // Transmit queue
  final List<_FragmentInQueue> _tncFragmentQueue = [];
  bool _tncFragmentInFlight = false;

  // Clear channel timer
  Timer? _clearChannelTimer;

  // Battery poll timer (every 60 seconds while connected)
  Timer? _batteryPollTimer;

  // Initialization retry timer
  Timer? _initRetryTimer;
  int _initRetryCount = 0;
  static const int _maxInitRetries = 3;
  bool _receivedAnyData = false;
  DateTime? _connectedAt;
  bool _webBleCompactMode = false;
  int _webBleCompactVariant = 0;
  int _compactRxLogCount = 0;
  int _lastCompactCmdValue = -1;
  int _lastCompactStatus = -1;
  DateTime _lastCompactLogAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _webBleCompactUnsupported = false;
  final List<Timer> _pendingChannelReadTimers = [];

  // Serialized read queue for channel (READ_RF_CH) and region-name
  // (READ_REGION_NAME) enumeration. The radio can drop replies when many read
  // requests are sent back-to-back, leaving the channel/region list
  // incomplete. To avoid flooding the Bluetooth control channel these reads are
  // sent one at a time: the next request is only sent once the matching reply
  // arrives, or after a short timeout that retries a couple of times before
  // moving on.
  final List<_PendingRead> _readQueue = [];
  _PendingRead? _readInFlight;
  Timer? _readTimeoutTimer;
  int _readRetryCount = 0;
  static const Duration _readResponseTimeout = Duration(milliseconds: 700);
  static const int _maxReadRetries = 2;

  // Trusted (Bluetooth paired) device enumeration. The radio returns the list
  // one entry at a time via GET_TRUSTED_DEVICE, indexed from 0. Requesting an
  // index past the end replies with an `invalidParameter` status, which marks
  // the end of the list. Results are accumulated here and dispatched as the
  // `TrustedDevices` value for the Trusted Devices dialog.
  final List<Map<String, Object?>> _trustedDevices = [];
  int _trustedDeviceIndex = 0;
  bool _trustedDeviceQueryActive = false;
  Timer? _trustedDeviceTimer;
  static const Duration _trustedDeviceTimeout = Duration(milliseconds: 1500);

  // Lock state
  RadioLockState? _lockState;
  int _savedRegionId = -1;
  int _savedChannelId = -1;
  bool _savedScan = false;
  int _savedDualWatch = 0;

  // Tracks the FM broadcast (is_radio) state so we request the FM frequency once
  // when the radio enters FM broadcast mode.
  bool _wasFmBroadcast = false;

  // Receive buffer for GAIA decoding
  final List<int> _receiveBuffer = [];

  // Firmware-update (GAIA VM protocol) event stream. Emits VMU packets and VM
  // command replies for the FirmwareUpdater state machine. Broadcast so the
  // updater can subscribe/unsubscribe without affecting other listeners.
  final StreamController<RadioVmEvent> _vmEventController =
      StreamController<RadioVmEvent>.broadcast();

  /// Stream of GAIA VM firmware-update events (VMU packets and VM command
  /// replies). Used by the firmware updater.
  Stream<RadioVmEvent> get vmEvents => _vmEventController.stream;

  // Public state
  RadioDevInfo? info;
  List<RadioChannelInfo?>? channels;
  // Names of the radio's regions, indexed by region id. An entry is null until
  // its READ_REGION_NAME reply has been received. Sized to info.regionCount
  // once device info is known.
  List<String?> regionNames = const [];
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

    // Subscribe to region rename events
    _broker.subscribe(
      deviceId: deviceId,
      name: 'SetRegionName',
      callback: _onSetRegionNameEvent,
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

    // Subscribe to raw command send events (used by the web server WebSocket
    // bridge, which forwards the browser's raw GATT command frames).
    _broker.subscribe(
      deviceId: deviceId,
      name: 'SendRawCommand',
      callback: _onSendRawCommandEvent,
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

    // Subscribe to programmable-function button-table requests from the
    // Configure Buttons dialog (read GET_PF, write SET_PF).
    _broker.subscribe(
      deviceId: deviceId,
      name: 'QueryProgFunctions',
      callback: _onQueryProgFunctionsEvent,
    );
    _broker.subscribe(
      deviceId: deviceId,
      name: 'SetProgFunctions',
      callback: _onSetProgFunctionsEvent,
    );

    // Subscribe to trusted (Bluetooth paired) device list requests and delete
    // requests from the Trusted Devices dialog.
    _broker.subscribe(
      deviceId: deviceId,
      name: 'QueryTrustedDevices',
      callback: _onQueryTrustedDevicesEvent,
    );
    _broker.subscribe(
      deviceId: deviceId,
      name: 'DeleteTrustedDevice',
      callback: _onDeleteTrustedDeviceEvent,
    );

    // Subscribe to FM broadcast radio control events from the FM Radio dialog.
    _broker.subscribe(
      deviceId: deviceId,
      name: 'FmRadioSetMode',
      callback: _onFmRadioSetModeEvent,
    );
    _broker.subscribe(
      deviceId: deviceId,
      name: 'FmRadioSetFrequency',
      callback: _onFmRadioSetFrequencyEvent,
    );
    _broker.subscribe(
      deviceId: deviceId,
      name: 'FmRadioSeekUp',
      callback: _onFmRadioSeekUpEvent,
    );
    _broker.subscribe(
      deviceId: deviceId,
      name: 'FmRadioSeekDown',
      callback: _onFmRadioSeekDownEvent,
    );
    _broker.subscribe(
      deviceId: deviceId,
      name: 'QueryFmRadioStatus',
      callback: _onQueryFmRadioStatusEvent,
    );

    // Subscribe to GPS serial data
    _broker.subscribe(
      deviceId: 1,
      name: 'GpsData',
      callback: _onGpsDataReceived,
    );

    // Subscribe to serial GPS sharing changes so the radio's position-change
    // notification can be registered/cancelled live while connected.
    _broker.subscribe(
      deviceId: 0,
      name: 'ShareSerialGpsLocation',
      callback: _onShareSerialGpsChanged,
    );
  }

  void _onShareSerialGpsChanged(int devId, String name, dynamic data) {
    _syncPositionNotification();
  }

  void _onQueryProgFunctionsEvent(int devId, String name, dynamic data) {
    if (devId != deviceId) return;
    queryProgFunctions();
  }

  void _onSetProgFunctionsEvent(int devId, String name, dynamic data) {
    if (devId != deviceId) return;
    if (data is Uint8List) {
      writeProgFunctions(data);
    } else if (data is List<int>) {
      writeProgFunctions(Uint8List.fromList(data));
    }
  }

  void _onQueryTrustedDevicesEvent(int devId, String name, dynamic data) {
    if (devId != deviceId) return;
    queryTrustedDevices();
  }

  void _onDeleteTrustedDeviceEvent(int devId, String name, dynamic data) {
    if (devId != deviceId) return;
    if (data is String) {
      deleteTrustedDevice(data);
    } else if (data is Map && data['mac'] is String) {
      deleteTrustedDevice(data['mac'] as String);
    }
  }

  void _onFmRadioSetModeEvent(int devId, String name, dynamic data) {
    if (devId != deviceId) return;
    if (data is bool) {
      setFmRadioMode(data);
    } else if (data is int) {
      setFmRadioMode(data != 0);
    }
  }

  void _onFmRadioSetFrequencyEvent(int devId, String name, dynamic data) {
    if (devId != deviceId) return;
    if (data is int) {
      setFmRadioFrequency(data);
    }
  }

  void _onFmRadioSeekUpEvent(int devId, String name, dynamic data) {
    if (devId != deviceId) return;
    fmRadioSeekUp();
  }

  void _onFmRadioSeekDownEvent(int devId, String name, dynamic data) {
    if (devId != deviceId) return;
    fmRadioSeekDown();
  }

  void _onQueryFmRadioStatusEvent(int devId, String name, dynamic data) {
    if (devId != deviceId) return;
    queryFmRadioStatus();
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
    _cancelPendingChannelReads();
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

  void _onSetRegionNameEvent(int devId, String name, dynamic data) {
    if (devId != deviceId) return;
    if (_lockState != null) return;
    if (data is Map) {
      final index = data['index'];
      final regionName = data['name'];
      if (index is int && regionName is String) {
        setRegionName(index, regionName);
      }
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
    if (_state != RadioState.connected) {
      _debugGpsReason(
        'notConnected',
        'Serial GPS: dropping fix - radio not connected (state=$_state)',
      );
      return;
    }

    // Only forward the serial GPS position when the user has enabled sharing.
    // The setting is persisted as an int (0/1), so read it as an int rather
    // than a bool: getValue<bool> would fail the type check on the stored int
    // and always return the default, silently disabling GPS sharing.
    final shareEnabled =
        (_broker.getValue<int>(0, 'ShareSerialGpsLocation', 0) ?? 0) == 1;
    if (!shareEnabled) {
      _debugGpsReason(
        'sharingDisabled',
        'Serial GPS: dropping fix - sharing disabled '
        '(ShareSerialGpsLocation is off)',
      );
      return;
    }

    // The GPS serial handler dispatches a GpsData object; a persisted value may
    // come back as a JSON map, so accept both forms.
    GpsData? gps;
    if (data is GpsData) {
      gps = data;
    } else if (data is Map) {
      gps = GpsData.fromJson(Map<String, dynamic>.from(data));
    }
    if (gps == null) {
      _debugGpsReason(
        'badType',
        'Serial GPS: dropping event - unrecognized data type '
        '(${data.runtimeType})',
      );
      return;
    }
    if (!gps.isFixed) {
      _debugGpsReason(
        'noFix',
        'Serial GPS: dropping fix - no valid GPS lock yet (isFixed=false)',
      );
      return;
    }

    final lat = gps.latitude;
    final lon = gps.longitude;
    final heading = gps.heading;
    final speedKnots = gps.speed;
    final now = DateTime.now();

    if (!_shouldBeaconPosition(
      heading: heading,
      speedKnots: speedKnots,
      now: now,
    )) {
      _debugGpsReason(
        'throttled',
        'Serial GPS: holding fix - SmartBeaconing throttle '
        '(${speedKnots.toStringAsFixed(1)} kn, '
        '${heading.toStringAsFixed(0)}\u00b0, waiting for next beacon)',
      );
      return;
    }

    // Build and send the position to the radio.
    final gpsTime = gps.gpsTime;
    final pos = RadioPosition.fromCoordinates(
      lat: lat,
      lon: lon,
      altitudeMetres: gps.altitude,
      speedKnots: speedKnots,
      headingDegrees: heading,
      utcTime: gpsTime.millisecondsSinceEpoch == 0
          ? now.toUtc()
          : gpsTime.toUtc(),
    );
    setPosition(pos);
    // Always log a successful send (these are already rate-limited by
    // SmartBeaconing) and reset the throttle so the next hold is logged again.
    _lastGpsDebugReason = 'sent';
    _debug(
      'Serial GPS position sent to radio: '
      '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)} '
      '(${speedKnots.toStringAsFixed(1)} kn, ${heading.toStringAsFixed(0)}\u00b0)',
    );

    _lastGpsSentHeading = heading;
    _lastGpsSentTime = now;
  }

  /// Emits a serial-GPS diagnostic message only when the [reason] differs from
  /// the previously logged reason. A GPS emits several sentences per second, so
  /// logging every dropped/held fix would flood the debug log; this reports
  /// only state transitions (e.g. the first time sharing is found disabled).
  void _debugGpsReason(String reason, String message) {
    if (_lastGpsDebugReason == reason) return;
    _lastGpsDebugReason = reason;
    _debug(message);
  }

  /// Decides whether a new position should be sent to the radio using the
  /// classic APRS SmartBeaconing algorithm: beacon faster when moving quickly,
  /// slower when stopped, and early ("corner pegging") on sharp turns.
  bool _shouldBeaconPosition({
    required double heading,
    required double speedKnots,
    required DateTime now,
  }) {
    // Always beacon the first fix after connecting / enabling sharing.
    if (_lastGpsSentTime == null) return true;

    final secsSinceLast = now.difference(_lastGpsSentTime!).inSeconds;

    // Speed-dependent beacon rate (seconds between beacons).
    final int beaconRateSecs;
    if (speedKnots <= _sbLowSpeedKnots) {
      beaconRateSecs = _sbSlowRateSecs;
    } else if (speedKnots >= _sbHighSpeedKnots) {
      beaconRateSecs = _sbFastRateSecs;
    } else {
      final rate = (_sbFastRateSecs * _sbHighSpeedKnots / speedKnots).round();
      beaconRateSecs = rate.clamp(_sbFastRateSecs, _sbSlowRateSecs);
    }

    // Corner pegging: beacon early on a sharp heading change, but no more often
    // than the turn-time minimum. Heading is unreliable when nearly stationary,
    // so only apply this above the low-speed threshold.
    if (speedKnots > _sbLowSpeedKnots && !_lastGpsSentHeading.isNaN) {
      final turnThreshold = _sbTurnMinDegrees + _sbTurnSlope / speedKnots;
      final headingChange = _headingDelta(_lastGpsSentHeading, heading);
      if (headingChange > turnThreshold && secsSinceLast >= _sbTurnTimeSecs) {
        return true;
      }
    }

    return secsSinceLast >= beaconRateSecs;
  }

  /// Smallest absolute difference between two headings in degrees (0-180).
  static double _headingDelta(double a, double b) {
    var diff = (a - b).abs() % 360.0;
    if (diff > 180.0) diff = 360.0 - diff;
    return diff;
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
    _broker.logInfo(
      '[Radio $deviceId] Transport state changed to ${state.name}',
    );
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
    _connectedAt = DateTime.now();
    _webBleCompactMode = false;
    _webBleCompactVariant = 0;
    _compactRxLogCount = 0;
    _lastCompactCmdValue = -1;
    _lastCompactStatus = -1;
    _lastCompactLogAt = DateTime.fromMillisecondsSinceEpoch(0);
    _webBleCompactUnsupported = false;

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

    // Request initial data.
    // On web BLE, stage init to avoid losing early responses when
    // notifications are unreliable and read-poll fallback is active.
    _sendCommand(
      RadioCommandGroup.basic,
      RadioBasicCommand.getDevInfo,
      Uint8List.fromList([3]),
    );
    if (!kIsWeb) {
      _sendCommand(
        RadioCommandGroup.basic,
        RadioBasicCommand.readSettings,
        null,
      );
      _sendCommand(
        RadioCommandGroup.basic,
        RadioBasicCommand.readBssSettings,
        null,
      );
      _requestPowerStatus(RadioPowerStatus.batteryLevelAsPercentage);
    }

    // Start periodic battery polling (every 60 seconds)
    _batteryPollTimer?.cancel();
    _batteryPollTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (_transport?.state == TransportState.connected) {
        _requestPowerStatus(RadioPowerStatus.batteryLevelAsPercentage);
      }
    });

    // Set up retry timer - if we don't receive any data within 2 seconds, retry
    _initRetryTimer?.cancel();
    _initRetryTimer = Timer(const Duration(seconds: 2), () {
      final needsWebInitData = kIsWeb && (info == null || settings == null);
      if ((!_receivedAnyData || needsWebInitData) &&
          _transport?.state == TransportState.connected) {
        _initRetryCount++;
        if (_initRetryCount < maxInitRetries) {
          _debug('No response received, retrying initial commands...');
          _broker.logInfo(
            '[Radio $deviceId] No RX yet; retrying initial command batch '
            '(${_initRetryCount + 1}/$maxInitRetries)',
          );
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
          _broker.logError(
            '[Radio $deviceId] No response after $maxInitRetries init attempts',
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
            if (_webBleCompactMode &&
                _transport?.state == TransportState.connected) {
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
    _positionNotifyRegistered = false;
    _cancelPendingChannelReads();
    _receiveBuffer.clear();
    _clearChannelTimer?.cancel();
    _clearChannelTimer = null;
    _batteryPollTimer?.cancel();
    _batteryPollTimer = null;
    _trustedDeviceTimer?.cancel();
    _trustedDeviceTimer = null;
    _trustedDeviceQueryActive = false;
    _trustedDevices.clear();
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

  // ---------------------------------------------------------------------------
  // Programmable functions (PF) — discovery
  // ---------------------------------------------------------------------------
  //
  // The radio exposes a "programmable function" subsystem that maps physical
  // buttons to effects. The Configure Buttons dialog reads the current table
  // (GET_PF) and writes changes back (SET_PF). The GET_PF reply is parsed by
  // [_handleGetPf] and dispatched as `PfTable`.

  /// Requests the current programmable-function button table (GET_PF). The
  /// reply lists each mapped button as `button_id + action + effect`.
  void queryProgFunctions() {
    _sendCommand(RadioCommandGroup.basic, RadioBasicCommand.getPf, null);
  }

  /// Writes the programmable-function button table (SET_PF). [entryBytes] is one
  /// effect byte per slot, in the slot order returned by GET_PF. After writing,
  /// the table is re-read so the cached `PfTable` reflects the radio's state.
  void writeProgFunctions(Uint8List entryBytes) {
    _sendCommand(RadioCommandGroup.basic, RadioBasicCommand.setPf, entryBytes);
    // The radio does not notify of the change after a PF write, and it commits
    // the write asynchronously — re-reading immediately returns a transient /
    // half-updated table. Wait before re-reading so the cached value reflects
    // the settled state.
    Future.delayed(const Duration(milliseconds: 800), () {
      if (_state == RadioState.connected) queryProgFunctions();
    });
  }

  // ---------------------------------------------------------------------------
  // Trusted (Bluetooth paired) devices
  // ---------------------------------------------------------------------------
  //
  // The radio stores a list of trusted Bluetooth devices that it will accept
  // connections from. The list is read one entry at a time (GET_TRUSTED_DEVICE)
  // starting at index 0; requesting an index past the last entry replies with
  // an `invalidParameter` status, which marks the end of the list. Each
  // successful reply carries the device index, its 6-byte MAC address and a
  // UTF-8 name. The accumulated list is dispatched as `TrustedDevices`.

  /// Starts (re)reading the radio's trusted-device list from index 0. Results
  /// are dispatched incrementally as `TrustedDevices` (a map with `loading` and
  /// `devices` keys) so the dialog can show progress and the final list.
  void queryTrustedDevices() {
    if (_state != RadioState.connected) return;
    _trustedDeviceTimer?.cancel();
    _trustedDevices.clear();
    _trustedDeviceIndex = 0;
    _trustedDeviceQueryActive = true;
    _dispatchTrustedDevices(loading: true);
    _sendTrustedDeviceQuery();
  }

  /// Sends the GET_TRUSTED_DEVICE request for the current index and (re)arms a
  /// watchdog so a missing reply still ends the enumeration.
  void _sendTrustedDeviceQuery() {
    _sendCommand(
      RadioCommandGroup.basic,
      RadioBasicCommand.getTrustedDevice,
      Uint8List.fromList([_trustedDeviceIndex & 0xFF]),
    );
    _trustedDeviceTimer?.cancel();
    _trustedDeviceTimer =
        Timer(_trustedDeviceTimeout, _finishTrustedDeviceQuery);
  }

  /// Ends the trusted-device enumeration and publishes the final list.
  void _finishTrustedDeviceQuery() {
    _trustedDeviceTimer?.cancel();
    _trustedDeviceTimer = null;
    _trustedDeviceQueryActive = false;
    _dispatchTrustedDevices(loading: false);
  }

  void _dispatchTrustedDevices({required bool loading}) {
    _dispatch('TrustedDevices', {
      'loading': loading,
      'devices': _trustedDevices
          .map((d) => Map<String, Object?>.from(d))
          .toList(),
    });
  }

  /// Requests the radio delete the trusted device with the given [mac]
  /// (DEL_TRUSTED_DEVICE), then re-reads the list so the cached value reflects
  /// the radio's new state. [mac] is a colon-separated address (e.g.
  /// `60:B7:6E:0E:D2:61`); the radio expects the 6 raw address bytes.
  void deleteTrustedDevice(String mac) {
    if (_state != RadioState.connected) return;
    final macBytes = _parseMacBytes(mac);
    if (macBytes == null) return;
    _sendCommand(
      RadioCommandGroup.basic,
      RadioBasicCommand.delTrustedDevice,
      macBytes,
    );
    // The radio does not push an updated list after a delete, so re-read it
    // after a short delay to let the change settle.
    Future.delayed(const Duration(milliseconds: 500), () {
      if (_state == RadioState.connected) queryTrustedDevices();
    });
  }

  /// Parses a colon-separated MAC address into its 6 raw bytes, or returns null
  /// if it is not a valid 6-byte address.
  Uint8List? _parseMacBytes(String mac) {
    final parts = mac.split(':');
    if (parts.length != 6) return null;
    final bytes = Uint8List(6);
    for (int i = 0; i < 6; i++) {
      final value = int.tryParse(parts[i], radix: 16);
      if (value == null || value < 0 || value > 255) return null;
      bytes[i] = value;
    }
    return bytes;
  }

  /// Parses a GET_TRUSTED_DEVICE reply. Full command frame layout:
  ///   cmd[0..3]  = vendor + command header
  ///   cmd[4]     = reply status (0 = success, 5 = invalidParameter = end)
  ///   cmd[5]     = device index
  ///   cmd[6]     = reserved/flags (observed as 0)
  ///   cmd[7..12] = 6-byte Bluetooth MAC address
  ///   cmd[13..]  = UTF-8 device name
  void _handleGetTrustedDevice(Uint8List cmd) {
    if (!_trustedDeviceQueryActive) return;
    _trustedDeviceTimer?.cancel();
    _trustedDeviceTimer = null;

    final status = cmd.length > 4 ? cmd[4] : 0xFF;
    if (status != 0) {
      // invalidParameter (or any error) marks the end of the list.
      _finishTrustedDeviceQuery();
      return;
    }

    if (cmd.length >= 13) {
      final index = cmd[5];
      final mac = List<int>.generate(
        6,
        (i) => cmd[7 + i],
      ).map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(':');
      final name = cmd.length > 13
          ? RadioUtils.decodeUtf8Trimmed(cmd, 13, cmd.length - 13)
          : '';
      _trustedDevices.add({'index': index, 'mac': mac, 'name': name});
      _dispatchTrustedDevices(loading: true);
    }

    // Ask for the next entry (bounded so a misbehaving radio can't loop
    // forever).
    _trustedDeviceIndex++;
    if (_trustedDeviceIndex > 255) {
      _finishTrustedDeviceQuery();
      return;
    }
    _sendTrustedDeviceQuery();
  }

  /// Maximum number of UTF-8 bytes stored for a region name. Confirmed against
  /// a real radio: the READ_REGION_NAME reply carries a 10-byte null-padded
  /// name field (offsets 6..15), matching the channel name field. The write
  /// payload is null-padded to the same length.
  static const int _regionNameLength = 10;

  /// Requests the name of a single region (READ_REGION_NAME). The reply is
  /// handled by [_handleReadRegionName]. Queued through the serialized read
  /// queue so it waits for the reply before the next read is sent.
  void readRegionName(int region) {
    _enqueueRead(RadioBasicCommand.readRegionName, region);
  }

  /// Writes a new name for [region] (WRITE_REGION_NAME). The payload is the
  /// region index followed by the UTF-8 name, null-padded to a fixed length.
  /// The local [regionNames] cache is updated immediately (and broadcast via
  /// the `RegionNames` event) so the UI reflects the change without waiting for
  /// the radio to acknowledge and be re-read.
  void setRegionName(int region, String name) {
    if (info == null || region < 0 || region >= info!.regionCount) return;
    final nameBytes = RadioUtils.encodeUtf8Padded(name, _regionNameLength);
    final payload = Uint8List(1 + _regionNameLength);
    payload[0] = region;
    payload.setRange(1, 1 + _regionNameLength, nameBytes);
    _sendCommand(
      RadioCommandGroup.basic,
      RadioBasicCommand.writeRegionName,
      payload,
    );

    // Optimistically update the cached name and notify listeners. Store the
    // name as the radio will (truncated to the fixed byte length) so a later
    // READ_REGION_NAME reply produces an identical value.
    if (region < regionNames.length) {
      regionNames[region] = RadioUtils.decodeUtf8Trimmed(
        nameBytes,
        0,
        _regionNameLength,
      );
      _dispatch(
        'RegionNames',
        List<String?>.from(regionNames),
        store: true,
      );
    }
  }

  /// Requests the names of every region the radio reports. Called once device
  /// info (and therefore the region count) is known.
  void _updateRegionNames() {
    if (_state != RadioState.connected || info == null) return;
    final count = info!.regionCount;
    if (count <= 0) return;
    // Serialize the reads (see [_readQueue]) so each reply is received before
    // the next request is sent, rather than flooding the radio all at once.
    for (int i = 0; i < count; i++) {
      _enqueueRead(RadioBasicCommand.readRegionName, i);
    }
  }

  void _updateChannels() {
    if (_state != RadioState.connected || info == null) return;
    _cancelPendingChannelReads();
    // Serialize the reads (see [_readQueue]) so each reply is received before
    // the next request is sent, rather than flooding the radio all at once.
    for (int i = 0; i < info!.channelCount; i++) {
      _enqueueRead(RadioBasicCommand.readRfCh, i);
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

    // Turning the internal GPS off must not cancel the position notification
    // while serial GPS sharing still needs it, so route through the helper
    // which considers both sources.
    _syncPositionNotification();

    if (!_gpsEnabled) {
      position = null;
      _dispatch('Position', null);
    }
  }

  bool get gpsEnabled => _gpsEnabled;

  /// Registers or cancels the radio's position-change notification so it
  /// matches the desired state. The radio only transmits APRS position beacons
  /// while this notification is registered, so it must be active whenever the
  /// internal GPS is enabled (File > GPS) or the user is sharing a serial GPS
  /// position. Sends a command only when the registration state actually needs
  /// to change, and does nothing while disconnected (registration is
  /// (re)applied from [_handleDevInfo] on the next connection).
  void _syncPositionNotification() {
    if (_state != RadioState.connected) return;
    // ShareSerialGpsLocation is persisted as an int (0/1); reading it as a bool
    // would always fail the type check and silently disable sharing.
    final shareSerialGps =
        (_broker.getValue<int>(0, 'ShareSerialGpsLocation', 0) ?? 0) == 1;
    final wantRegistered = _gpsEnabled || shareSerialGps;
    if (wantRegistered == _positionNotifyRegistered) return;
    _positionNotifyRegistered = wantRegistered;
    _sendCommand(
      RadioCommandGroup.basic,
      wantRegistered
          ? RadioBasicCommand.registerNotification
          : RadioBasicCommand.cancelNotification,
      Uint8List.fromList([0, 0, 0, RadioNotification.positionChange.value]),
    );
  }

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
    _cancelPendingChannelReads();
    _sendCommand(
      RadioCommandGroup.basic,
      RadioBasicCommand.writeSettings,
      data,
    );
  }

  void _cancelPendingChannelReads() {
    _readQueue.clear();
    _readInFlight = null;
    _readRetryCount = 0;
    _readTimeoutTimer?.cancel();
    _readTimeoutTimer = null;
    if (_pendingChannelReadTimers.isEmpty) return;
    for (final timer in _pendingChannelReadTimers) {
      timer.cancel();
    }
    _pendingChannelReadTimers.clear();
  }

  /// Adds a channel/region read to the serialized queue and starts it if the
  /// queue is idle. See [_readQueue].
  void _enqueueRead(RadioBasicCommand cmd, int index) {
    if (_state != RadioState.connected) return;
    _readQueue.add(_PendingRead(cmd, index));
    _pumpReadQueue();
  }

  /// Sends the next queued read if nothing is currently awaiting a reply.
  void _pumpReadQueue() {
    if (_readInFlight != null) return;
    if (_readQueue.isEmpty) return;
    if (_state != RadioState.connected) {
      _readQueue.clear();
      return;
    }
    _readInFlight = _readQueue.removeAt(0);
    _readRetryCount = 0;
    _sendQueuedRead();
  }

  /// Sends the in-flight read and (re)arms the response-timeout watchdog.
  void _sendQueuedRead() {
    final r = _readInFlight;
    if (r == null) return;
    _sendCommand(
      RadioCommandGroup.basic,
      r.cmd,
      Uint8List.fromList([r.index]),
    );
    _readTimeoutTimer?.cancel();
    _readTimeoutTimer = Timer(_readResponseTimeout, _onReadResponseTimeout);
  }

  /// Fires when a queued read gets no reply in time. Retries the same request a
  /// couple of times before giving up on it and moving to the next.
  void _onReadResponseTimeout() {
    final r = _readInFlight;
    if (r == null) return;
    if (_state != RadioState.connected) {
      _readInFlight = null;
      _readQueue.clear();
      return;
    }
    if (_readRetryCount < _maxReadRetries) {
      _readRetryCount++;
      _debug(
        'Read ${r.cmd.name}[${r.index}] timed out, retry '
        '$_readRetryCount/$_maxReadRetries',
      );
      _sendQueuedRead();
    } else {
      _debug(
        'Read ${r.cmd.name}[${r.index}] gave up after $_maxReadRetries retries',
      );
      _readInFlight = null;
      _pumpReadQueue();
    }
  }

  /// Called from the channel/region reply handlers so the next queued read can
  /// be sent. Only advances when the reply matches the in-flight request.
  void _onReadReplyReceived(RadioBasicCommand cmd, int index) {
    final r = _readInFlight;
    if (r == null) return;
    if (r.cmd != cmd || r.index != index) return;
    _readTimeoutTimer?.cancel();
    _readTimeoutTimer = null;
    _readInFlight = null;
    _pumpReadQueue();
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

  // ---------------------------------------------------------------------------
  // FM broadcast radio control
  // ---------------------------------------------------------------------------
  //
  // The radio has a built-in FM broadcast receiver controlled by the RADIO_*
  // commands. RADIO_SET_MODE turns it on/off, RADIO_SET_FREQ tunes to an exact
  // frequency, RADIO_SEEK_UP/RADIO_SEEK_DOWN scan for the next station, and
  // RADIO_GET_STATUS reads the current state. Live changes are pushed via the
  // radioStatusChanged notification (registered on connect) and parsed by
  // [_handleRadioStatus], which dispatches `FmRadioStatus`.

  /// Requests the current FM broadcast receiver status (RADIO_GET_STATUS). The
  /// reply is parsed by [_handleRadioStatus] and dispatched as `FmRadioStatus`.
  void queryFmRadioStatus() {
    _sendCommand(
      RadioCommandGroup.basic,
      RadioBasicCommand.radioGetStatus,
      null,
    );
  }

  /// Turns the FM broadcast receiver on or off (RADIO_SET_MODE). The mode byte
  /// is `2` to enable FM reception and `0` to disable it (values observed on a
  /// real radio).
  void setFmRadioMode(bool on) {
    _sendCommand(
      RadioCommandGroup.basic,
      RadioBasicCommand.radioSetMode,
      Uint8List.fromList([on ? 2 : 0]),
    );
  }

  /// Tunes the FM broadcast receiver to [freqHz] (RADIO_SET_FREQ). The radio
  /// expects the frequency as a big-endian uint16 in units of 10 kHz
  /// (e.g. 91.5 MHz -> 9150 -> 0x23BE).
  void setFmRadioFrequency(int freqHz) {
    if (freqHz <= 0) return;
    final units = (freqHz / 10000).round();
    _sendCommand(
      RadioCommandGroup.basic,
      RadioBasicCommand.radioSetFreq,
      Uint8List.fromList([(units >> 8) & 0xFF, units & 0xFF]),
    );
  }

  /// Seeks up to the next FM broadcast station (RADIO_SEEK_UP). Progress is
  /// reported through `FmRadioStatus` notifications.
  void fmRadioSeekUp() {
    _sendCommand(RadioCommandGroup.basic, RadioBasicCommand.radioSeekUp, null);
  }

  /// Seeks down to the previous FM broadcast station (RADIO_SEEK_DOWN).
  void fmRadioSeekDown() {
    _sendCommand(
      RadioCommandGroup.basic,
      RadioBasicCommand.radioSeekDown,
      null,
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
    } else if (_activeSoftwareModemModeFor(fragment).isNotEmpty) {
      // The audio channel is enabled and a software modem mode applies to this
      // frame's channel, so encode the frame with the software modem and send
      // it as PCM audio rather than handing it to the radio's hardware TNC.
      _transmitSoftwareModem(fragment, _activeSoftwareModemModeFor(fragment));
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

  /// Returns the software modem mode string to use for transmitting [fragment]
  /// ('AFSK1200' / 'PSK2400'), or '' to use the radio's hardware TNC. Frames
  /// targeting the APRS channel are governed by the independent APRS modem
  /// setting (off or AFSK 1200); all other frames by the general software modem
  /// setting. The audio channel must be enabled either way.
  ///
  /// The software modem transmits its PCM audio on VFO A only, so it can only be
  /// used for APRS when VFO A is itself the APRS channel. If APRS is on VFO B
  /// (or elsewhere), transmitting via the software modem would send the data on
  /// the wrong frequency, so we fall back to the hardware TNC, which targets the
  /// correct channel.
  String _activeSoftwareModemModeFor(TncDataFragment fragment) {
    final bool audioOn =
        _broker.getValue<bool>(deviceId, 'AudioState', false) ?? false;
    if (!audioOn) return '';

    final int aprsId = _aprsChannelId();
    final bool isAprs = fragment.channelName == 'APRS' ||
        (aprsId >= 0 && fragment.channelId == aprsId);
    if (isAprs) {
      final String aprsMode =
          _broker.getValue<String>(0, 'AprsSoftwareModemMode', 'None') ?? 'None';
      if (aprsMode.isEmpty || aprsMode.toLowerCase() == 'none') return '';
      // Only use the software AFSK 1200 modem when VFO A is the APRS channel,
      // otherwise the audio would be transmitted on the wrong frequency. Fall
      // back to the hardware TNC in that case.
      final bool vfoAIsAprs =
          aprsId >= 0 && settings != null && settings!.channelA == aprsId;
      if (!vfoAIsAprs) return '';
      // The APRS modem only supports AFSK 1200.
      return 'AFSK1200';
    }

    final String mode =
        _broker.getValue<String>(0, 'SoftwareModemMode', 'None') ?? 'None';
    if (mode.isEmpty || mode.toLowerCase() == 'none') return '';
    return mode;
  }

  /// The channel id of this radio's channel named 'APRS', or -1.
  int _aprsChannelId() {
    final list = channels;
    if (list == null) return -1;
    for (final ch in list) {
      if (ch != null && ch.name == 'APRS') return ch.channelId;
    }
    return -1;
  }

  FragmentEncodingType _softwareEncodingFor(String mode) {
    switch (mode.toUpperCase()) {
      case 'AFSK1200':
        return FragmentEncodingType.softwareAfsk1200;
      case 'PSK2400':
        return FragmentEncodingType.softwarePsk2400;
      case 'DART':
        return FragmentEncodingType.softwareDart;
      default:
        return FragmentEncodingType.unknown;
    }
  }

  /// Sends [fragment] via the software modem: the frame is logged for capture
  /// with the software encoding and handed to the SoftwareModem handler, which
  /// encodes it to PCM and transmits it over the audio channel (using the
  /// p-persistent CSMA channel-access logic).
  void _transmitSoftwareModem(TncDataFragment fragment, String mode) {
    fragment.encoding = _softwareEncodingFor(mode);
    // DART carries its own LDPC FEC and CRC; the AFSK/PSK modems apply FX.25
    // (falling back to plain AX.25 for frames too large for any FX.25 block).
    fragment.frameType = fragment.encoding == FragmentEncodingType.softwareDart
        ? FragmentFrameType.ax25
        : FragmentFrameType.fx25;

    // Tag the DART level for the capture log, from the user-selected transmit
    // level ('0'..'5' or 'F' → mode index 0..6).
    if (fragment.encoding == FragmentEncodingType.softwareDart) {
      final String level =
          (_broker.getValue<String>(0, 'DartTxMode', '0') ?? '0').toUpperCase();
      fragment.dartMode = level == 'F' ? 6 : (int.tryParse(level) ?? 0);
    }

    // Log / capture the outgoing frame with the correct software encoding.
    _dispatchDataFrame(fragment);

    // Hand the frame to the software modem for PCM encoding + audio transmit.
    _broker.dispatch(
      deviceId: deviceId,
      name: 'SoftModemTransmitPacket',
      data: fragment,
      store: false,
    );
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
  /// True when the active transport speaks BLE GATT (web, iOS, Linux), where
  /// the radio expects the command un-wrapped:
  /// `[group_hi, group_lo, cmd_hi, cmd_lo, payload...]`. Bluetooth Classic /
  /// RFCOMM transports (macOS, Windows, Android) instead need the command
  /// wrapped in the `0xFF 0x01 ...` GAIA serial framing.
  bool get _useGattFraming =>
      kIsWeb || _transport?.connectedDevice?.type == BluetoothType.ble;

  void _sendCommand(
    RadioCommandGroup group,
    RadioBasicCommand cmd,
    Uint8List? data,
  ) {
    if (_transport == null) return;

    Uint8List gaiaFrame;
    if (_useGattFraming &&
        !_webBleCompactMode &&
        group == RadioCommandGroup.basic) {
      // Match the working reference web implementation:
      // [group_hi, group_lo, cmd_hi, cmd_lo, payload...]
      // and send a trailing 0 byte when no payload is provided.
      final payloadLen = (data == null || data.isEmpty) ? 1 : data.length;
      gaiaFrame = Uint8List(4 + payloadLen);
      gaiaFrame[0] = 0x00;
      gaiaFrame[1] = group.value & 0xFF;
      gaiaFrame[2] = 0x00;
      gaiaFrame[3] = cmd.value & 0xFF;
      if (data != null && data.isNotEmpty) {
        for (int i = 0; i < data.length; i++) {
          gaiaFrame[4 + i] = data[i];
        }
      } else {
        gaiaFrame[4] = 0x00;
      }
    } else if (kIsWeb &&
        _webBleCompactMode &&
        group == RadioCommandGroup.basic) {
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

    _transport!.send(gaiaFrame);
  }

  /// Sends a GAIA extended command (command group [RadioCommandGroup.extended]).
  ///
  /// Used by the firmware-update (VM) protocol to send `VM_CONNECT`,
  /// `VM_CONTROL` and `VM_DISCONNECT`. The command is wrapped in GAIA serial
  /// framing for Bluetooth Classic transports (the only transports firmware
  /// update supports).
  void sendVmCommand(RadioExtendedCommand cmd, [Uint8List? body]) {
    if (_transport == null) return;
    final cmdData = GaiaProtocol.buildRawCommand(
      RadioCommandGroup.extended.value,
      cmd.value,
      body,
    );
    final frame = _useGattFraming ? cmdData : GaiaProtocol.encode(cmdData);
    if (_packetTrace) {
      _debug('TX VM ${cmd.name}: ${RadioUtils.bytesToHex(frame)}');
    }
    _transport!.send(frame);
  }

  /// Sends a raw, un-framed GATT command frame to the radio. [data] is the
  /// `[group_hi, group_lo, cmd_hi, cmd_lo, payload...]` frame as produced by
  /// the browser's `SendCommand`/`writeToCharacteristic`. The frame is wrapped
  /// in GAIA serial framing for Bluetooth Classic transports, or sent as-is for
  /// BLE GATT transports. Used by the web server WebSocket bridge.
  void _onSendRawCommandEvent(int devId, String name, dynamic data) {
    if (devId != deviceId) return;
    if (_transport == null || _state != RadioState.connected) return;
    if (data is! Uint8List || data.length < 4) return;
    final framed = _useGattFraming ? data : GaiaProtocol.encode(data);
    _transport!.send(framed);
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
      final shouldLog =
          _compactRxLogCount < 120 &&
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

  bool _tryHandleWebDirectResponse(Uint8List data) {
    if (!_useGattFraming || data.length < 5) return false;
    if (_webBleCompactUnsupported) return true;

    final groupValue = (data[0] << 8) | data[1];
    final isKnownGroup =
        groupValue == RadioCommandGroup.basic.value ||
        groupValue == RadioCommandGroup.extended.value;
    if (!isKnownGroup) return false;

    if (!_receivedAnyData) {
      _receivedAnyData = true;
      _initRetryTimer?.cancel();
    }

    if (_packetTrace) {
      _debug('RX web-direct: ${RadioUtils.bytesToHex(data)}');
    }
    _handleCommand(data);
    return true;
  }

  void _onDataReceived(Uint8List data) {
    if (_tryHandleWebDirectResponse(data)) {
      return;
    }

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

    // Try to decode GAIA frames. Walk the buffer with a read cursor and compact
    // it only once at the end, instead of copying the whole buffer into a new
    // Uint8List on every decode attempt and shifting it with removeAt/removeRange
    // (both O(n)) for every consumed frame or skipped byte.
    int offset = 0;
    while (_receiveBuffer.length - offset >= 8) {
      final result = GaiaProtocol.decode(
        _receiveBuffer,
        offset,
        _receiveBuffer.length - offset,
      );

      if (result.consumed == -1) {
        // Error, skip one byte
        offset++;
      } else if (result.consumed == 0) {
        // Need more data
        break;
      } else {
        // Got a command
        offset += result.consumed;
        if (result.command != null) {
          _handleCommand(result.command!);
        }
      }
    }

    if (offset > 0) {
      _receiveBuffer.removeRange(0, offset);
    }
  }

  void _handleCommand(Uint8List cmd) {
    if (cmd.length < 4) return;

    // Bridge: forward the raw, un-framed GATT command frame
    // (`[group_hi, group_lo, cmd_hi, cmd_lo, payload...]`) to any listeners.
    // The web server WebSocket bridge relays these to browsers, which parse
    // them with the same format via radio.js `handleNotificationsEx()`.
    _dispatch('RawCommandRx', cmd, store: false);

    final parsed = GaiaProtocol.parseResponse(cmd);
    final payload = cmd.length > 4
        ? Uint8List.fromList(cmd.sublist(4))
        : Uint8List(0);

    // Extended command group carries the firmware-update (VM) protocol, whose
    // command values fall outside RadioBasicCommand. Route it separately.
    if (parsed.group == RadioCommandGroup.extended) {
      _handleExtendedCommand(cmd, payload, parsed.isResponse);
      return;
    }

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
      case RadioBasicCommand.writeSettings:
        // After a successful settings write the radio does not always notify of
        // the change (older firmware, e.g. 0.8.9.1, sends no htStatusChanged /
        // htSettingsChanged event), so re-read the settings to refresh the
        // cached values and the on-screen channel selection. Newer firmware
        // also pushes a notification, making this re-read redundant but
        // harmless. cmd[4] is the status byte (0 = success).
        if (cmd.length > 4 && cmd[4] == 0) {
          _sendCommand(
            RadioCommandGroup.basic,
            RadioBasicCommand.readSettings,
            null,
          );
        }
        break;
      case RadioBasicCommand.getHtStatus:
        _handleHtStatus(cmd);
        break;
      case RadioBasicCommand.radioGetStatus:
        _handleRadioStatus(cmd);
        break;
      case RadioBasicCommand.freqModeGetStatus:
        _handleFreqModeStatus(cmd);
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
          _enqueueRead(RadioBasicCommand.readRfCh, cmd[5]);
        }
        break;
      case RadioBasicCommand.readRegionName:
        _handleReadRegionName(cmd);
        break;
      case RadioBasicCommand.writeRegionName:
        // The radio does not notify of the change after a region name write,
        // so re-read that region's name to refresh the cached value. cmd[4]
        // is the status byte (0 = success) and cmd[5] is the region index.
        if (cmd.length > 5 && cmd[4] == 0) {
          readRegionName(cmd[5]);
        }
        break;
      case RadioBasicCommand.readBssSettings:
        _handleBssSettings(cmd);
        break;
      case RadioBasicCommand.getPosition:
        _handleGetPosition(cmd);
        break;
      case RadioBasicCommand.getPf:
        _handleGetPf(payload);
        break;
      case RadioBasicCommand.getTrustedDevice:
        _handleGetTrustedDevice(cmd);
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

  /// Handles the GET_PF reply: a status byte followed by two bytes per slot
  /// (`[(button<<4)|action, effect]`). The decoded table is dispatched as
  /// `PfTable` (a list of maps) for the Configure Buttons dialog.
  void _handleGetPf(Uint8List payload) {
    if (payload.isEmpty) return;
    final entries = <Map<String, Object?>>[];
    for (int i = 1; i + 1 < payload.length; i += 2) {
      final rawByte0 = payload[i];
      final rawByte1 = payload[i + 1];
      final buttonId = (rawByte0 >> 4) & 0x0F;
      final actionRaw = rawByte0 & 0x0F;
      final action = PFActionType.fromValue(actionRaw);
      final effect = PFEffectType.fromValue(rawByte1);
      entries.add({
        'buttonId': buttonId,
        'action': action.name,
        'actionValue': actionRaw,
        'effect': effect.name,
        'effectValue': rawByte1,
      });
    }
    _dispatch('PfTable', entries, store: true);
  }

  void _handleDevInfo(Uint8List data) {
    info = RadioDevInfo.fromBytes(data);
    if (info != null) {
      // Only use RadioDevInfo name if no Bluetooth friendly name was provided
      if (_friendlyName.isEmpty) {
        _friendlyName = info!.name;
      }
      channels = List<RadioChannelInfo?>.filled(info!.channelCount, null);
      regionNames = List<String?>.filled(info!.regionCount, null);
      _dispatch('Info', info!.toJson());
      _dispatch('FriendlyName', _friendlyName);
      _dispatch('GpsEnabled', _gpsEnabled);
      _dispatch('AllChannelsLoaded', false);

      // Register for HT status changes and frequency-mode (VFO) frequency
      // changes in a single command. The radio's REGISTER_NOTIFICATION accepts a
      // list of notification bytes, so both are subscribed at once. The
      // freqModeStatusChanged event pushes the live tuned frequency while
      // scanning/tuning, avoiding the need to poll FREQ_MODE_GET_STATUS.
      _sendCommand(
        RadioCommandGroup.basic,
        RadioBasicCommand.registerNotification,
        Uint8List.fromList([
          RadioNotification.htStatusChanged.value,
          RadioNotification.freqModeStatusChanged.value,
        ]),
      );

      // Register for FM broadcast radio status changes (only when the radio has
      // the FM broadcast receiver) so its frequency stays in sync while active.
      if (info?.supportRadio ?? false) {
        _sendCommand(
          RadioCommandGroup.basic,
          RadioBasicCommand.registerNotification,
          Uint8List.fromList([RadioNotification.radioStatusChanged.value]),
        );
      }

      // On web BLE, issue staged init reads after dev info is parsed.
      if (kIsWeb) {
        _sendCommand(
          RadioCommandGroup.basic,
          RadioBasicCommand.readSettings,
          null,
        );
      }

      // Register for position change notifications when either the radio's
      // internal GPS is enabled (File > GPS) or the user is sharing a serial
      // GPS position. The radio only transmits APRS position beacons while this
      // notification is registered, even when the position is fed externally
      // via setPosition. A radio power cycle resets this registration, so the
      // tracked state is cleared here and (re)applied on every connection.
      _positionNotifyRegistered = false;
      _syncPositionNotification();

      // Request HT status and channels.
      _sendCommand(
        RadioCommandGroup.basic,
        RadioBasicCommand.getHtStatus,
        null,
      );
      _updateChannels();
      _updateRegionNames();
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

  /// Parses the FREQ_MODE_GET_STATUS reply. Layout (full command frame):
  ///   data[4]    = reply status (0 = success)
  ///   data[5..8] = current frequency in Hz, big-endian (top 2 bits = modulation)
  /// e.g. 09 B0 50 F0 -> 162_550_000 Hz -> 162.550 MHz. Dispatched as
  /// 'FreqModeFreq' (int Hz) for the radio panel / status bar.
  void _handleFreqModeStatus(Uint8List data) {
    if (data.length < 9 || data[4] != 0) return;
    final freqHz = RadioUtils.getInt(data, 5) & 0x3FFFFFFF;
    if (freqHz > 0) {
      _dispatch('FreqModeFreq', freqHz);
    }
  }

  /// Parses a freqModeStatusChanged (notification 14) event, pushed by the radio
  /// whenever the tuned/scanned frequency changes in frequency (VFO) mode.
  /// Layout (full command frame):
  ///   data[4]       = notification type (14)
  ///   data[5..8]    = live RX frequency in Hz, big-endian (top 2 bits = modulation)
  ///   data[9..12]   = TX frequency in Hz
  ///   data[13..16]  = sub-audio
  ///   data[17..18]  = status flags
  /// The final flags byte (data[18]) is the reliable frequency (VFO) mode
  /// indicator: non-zero (e.g. 0x40) while in frequency mode, 0 when back on a
  /// preset channel. The high flags byte can stay set outside frequency mode
  /// (e.g. 0x8000 on exit), so only the low byte is authoritative. The active
  /// state is dispatched as 'FreqModeActive' (bool) and the RX frequency as
  /// 'FreqModeFreq' (int Hz). Leaving frequency mode clears the frequency to 0.
  void _handleFreqModeStatusChanged(Uint8List data) {
    if (data.length < 19) return;
    final active = data[18] != 0;
    _dispatch('FreqModeActive', active);
    if (active) {
      final freqHz = RadioUtils.getInt(data, 5) & 0x3FFFFFFF;
      if (freqHz > 0) {
        _dispatch('FreqModeFreq', freqHz);
      }
    } else {
      _dispatch('FreqModeFreq', 0);
    }
  }

  /// Parses the FM broadcast receiver status from a RADIO_GET_STATUS reply or a
  /// radioStatusChanged notification (both put the payload at offset 5) and
  /// dispatches it as `FmRadioStatus` for the radio panel / status bar.
  void _handleRadioStatus(Uint8List data) {
    final fm = RadioFmRadioStatus.fromBytes(data);
    _dispatch('FmRadioStatus', fm.toJson());
  }

  void _handleReadRfCh(Uint8List data) {
    final channel = RadioChannelInfo.fromBytes(data);
    // Advance the serialized read queue now that this channel's reply arrived.
    _onReadReplyReceived(RadioBasicCommand.readRfCh, channel.channelId);
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

  /// Parses a READ_REGION_NAME reply. Layout (full command frame):
  ///   data[0..3] = vendor + command header
  ///   data[4]    = reply status (0 = success)
  ///   data[5]    = region index
  ///   data[6..]  = UTF-8 region name (null-padded)
  void _handleReadRegionName(Uint8List data) {
    if (data.length < 6) return;
    final region = data[5];
    // Advance the serialized read queue now that this region's reply arrived,
    // regardless of the reply status so a failed read still moves things along.
    _onReadReplyReceived(RadioBasicCommand.readRegionName, region);
    if (data[4] != 0) return;
    if (region < 0 || region >= regionNames.length) return;
    final name = RadioUtils.decodeUtf8Trimmed(data, 6, data.length - 6);
    regionNames[region] = name;
    _dispatch(
      'RegionNames',
      List<String?>.from(regionNames),
      store: true,
    );
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
    // Payload layout (matching C# offsets relative to value[4]):
    //   data[0] = response status byte (0 = success)
    //   data[1..2] = power status type (big-endian short)
    //   data[3] = value (or data[3..4] for voltage)
    if (data.length < 4) return;
    final statusValue = (data[1] << 8) | data[2];
    final statusType = RadioPowerStatus.values.firstWhere(
      (e) => e.value == statusValue,
      orElse: () => RadioPowerStatus.unknown,
    );

    switch (statusType) {
      case RadioPowerStatus.batteryLevel:
        _dispatch('BatteryLevel', data[3]);
        break;
      case RadioPowerStatus.batteryVoltage:
        if (data.length > 4) {
          final voltage = RadioUtils.getShort(data, 3) / 100.0;
          _dispatch('BatteryVoltage', voltage);
        }
        break;
      case RadioPowerStatus.rcBatteryLevel:
        _dispatch('RcBatteryLevel', data[3]);
        break;
      case RadioPowerStatus.batteryLevelAsPercentage:
        _dispatch('BatteryAsPercentage', data[3]);
        break;
      default:
        break;
    }
  }

  void _handleGetVolume(Uint8List data) {
    // data[0] = response status byte (skip), data[1] = volume level
    if (data.length > 1) {
      _dispatch('Volume', data[1]);
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
      case RadioNotification.radioStatusChanged:
        // FM broadcast receiver status (frequency/seek) changed.
        _handleRadioStatus(data);
        break;
      case RadioNotification.freqModeStatusChanged:
        // Frequency-mode (VFO) tuned frequency changed while scanning/tuning.
        _handleFreqModeStatusChanged(data);
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

      // When the FM broadcast receiver becomes active, request its current
      // frequency once (subsequent changes arrive via radioStatusChanged).
      if (htStatus!.isRadio && !_wasFmBroadcast) {
        _sendCommand(
          RadioCommandGroup.basic,
          RadioBasicCommand.radioGetStatus,
          null,
        );
      }
      _wasFmBroadcast = htStatus!.isRadio;

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
      // `append` merges this fragment's data into the passed-in fragment and
      // returns it (it does NOT mutate the accumulator in place), so the result
      // must be reassigned. Mirrors the C# `frameAccumulator.Append(fragment)`.
      _frameAccumulator = _frameAccumulator!.append(fragment);
    }

    if (_frameAccumulator != null && _frameAccumulator!.isLast) {
      _frameAccumulator!.encoding = FragmentEncodingType.hardwareAfsk1200;
      _frameAccumulator!.frameType = FragmentFrameType.ax25;

      // Populate the usage field if the radio is locked and the data was
      // received on the locked channel. Mirrors the C# `AccumulateFragment`:
      // handlers (Torrent / BBS / Terminal) filter incoming frames by usage, so
      // without this they would never receive any locked-mode traffic.
      final lock = _lockState;
      if (lock != null &&
          lock.isLocked &&
          _frameAccumulator!.channelId == lock.channelId) {
        _frameAccumulator!.usage = lock.usage;
        if (_packetTrace) {
          _debug(
            "DataFrame usage set to '${lock.usage}' (channel ${lock.channelId})",
          );
        }
      }

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
      // `append` merges this fragment's data into the passed-in fragment and
      // returns it (it does NOT mutate the accumulator in place), so the result
      // must be reassigned. Mirrors the C# `frameAccumulator.Append(fragment)`.
      _frameAccumulator = _frameAccumulator!.append(fragment);
    }

    if (_frameAccumulator != null && _frameAccumulator!.isLast) {
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

  /// Handles an incoming extended-group command. Only the firmware-update VM
  /// protocol uses this group: `BT_EVENT_NOTIFICATION` carries VMU packets and
  /// `VM_CONNECT`/`VM_CONTROL`/`VM_DISCONNECT` are acknowledged with a status
  /// byte. Parsed events are forwarded to [vmEvents].
  void _handleExtendedCommand(Uint8List cmd, Uint8List payload, bool isReply) {
    final cmdValue = RadioUtils.getShort(cmd, 2) & 0x7FFF;
    final extCmd = RadioExtendedCommand.fromValue(cmdValue);

    if (_packetTrace) {
      _debug(
        'RX VM ${extCmd.name}${isReply ? ' (reply)' : ''}: '
        '${RadioUtils.bytesToHex(payload)}',
      );
    }

    switch (extCmd) {
      case RadioExtendedCommand.btEventNotification:
        final vmu = VmuPacket.fromBtEventPayload(payload);
        if (vmu != null) {
          _vmEventController.add(RadioVmEvent.vmuPacket(vmu));
        }
        break;
      case RadioExtendedCommand.vmConnect:
      case RadioExtendedCommand.vmDisconnect:
      case RadioExtendedCommand.vmControl:
        if (isReply) {
          final status = payload.isNotEmpty ? payload[0] : 0;
          _vmEventController.add(RadioVmEvent.replyTo(extCmd, status));
        }
        break;
      default:
        break;
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
    _vmEventController.close();
    _broker.dispose();
  }
}
