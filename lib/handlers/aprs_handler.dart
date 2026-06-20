/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from the C# `HTCommander.AprsHandler` class.
*/

import '../aprs/aprs_auth.dart';
import '../aprs/aprs_events.dart';
import '../aprs/aprs_packet.dart';
import '../aprs/message_data.dart';
import '../aprs/packet_data_type.dart';
import '../models/radio_models.dart';
import '../radio/ax25_address.dart';
import '../radio/ax25_packet.dart';
import '../radio/radio.dart';
import '../radio/tnc_data_fragment.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';

/// A data handler that processes APRS packets from the "APRS" channel.
///
/// Subscribes to `UniqueDataFrame` events, decodes AX.25 and APRS frames,
/// validates authentication codes when present, stores the last
/// [_maxFrameHistory] APRS frames, and (on startup) loads previous APRS packets
/// from the [PacketStore]. Also handles `SendAprsMessage` requests from the UI
/// and auto-acknowledges addressed messages.
class AprsHandler {
  /// Maximum number of APRS frames to keep in history.
  static const int _maxFrameHistory = 1000;

  /// Device id used for APRS-related broker messages.
  static const int _aprsDeviceId = 1;

  final DataBrokerClient _broker = DataBrokerClient();
  final AprsAuth _auth = AprsAuth();

  final List<AprsPacket> _aprsFrames = [];
  bool _disposed = false;
  bool _storeReady = false;

  /// The local station callsign with station ID (e.g., "K7VZT-5"), or null.
  String? _localCallsignWithId;

  int _nextAprsMessageId = 1;

  bool get isStoreReady => _storeReady;
  bool get isDisposed => _disposed;
  int get frameCount => _aprsFrames.length;

  /// Returns a copy of the current APRS frame history.
  List<AprsPacket> getAprsFrames() => List<AprsPacket>.from(_aprsFrames);

  /// Initializes the handler: subscribes to broker events and loads persisted
  /// state. Safe to call once at startup.
  void init() {
    // Incoming frames from all radios.
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'UniqueDataFrame',
      callback: _onUniqueDataFrame,
    );

    // Historical packet store events.
    _broker.subscribe(
      deviceId: _aprsDeviceId,
      name: 'PacketStoreReady',
      callback: _onPacketStoreReady,
    );
    _broker.subscribe(
      deviceId: _aprsDeviceId,
      name: 'PacketList',
      callback: _onPacketList,
    );

    // Outbound message requests from the UI.
    _broker.subscribe(
      deviceId: _aprsDeviceId,
      name: 'SendAprsMessage',
      callback: _onSendAprsMessage,
    );

    // On-demand packet list requests.
    _broker.subscribe(
      deviceId: _aprsDeviceId,
      name: 'RequestAprsPackets',
      callback: _onRequestAprsPackets,
    );

    // Clear request from the UI.
    _broker.subscribe(
      deviceId: _aprsDeviceId,
      name: 'ClearAprsPackets',
      callback: (_, _, _) => clearFrames(),
    );

    // Station list (auth passwords) from device 0.
    _broker.subscribe(
      deviceId: 0,
      name: 'Stations',
      callback: _onStationsUpdate,
    );
    _loadStations(DataBroker.getValueDynamic(0, 'Stations', null));

    // Local callsign / station id from device 0.
    _broker.subscribeMultiple(
      deviceId: 0,
      names: const ['CallSign', 'StationId'],
      callback: _onCallsignOrStationIdChanged,
    );
    _updateLocalCallsignWithId();

    // If the PacketStore is already ready, request the historical list now.
    if (_broker.hasValue(_aprsDeviceId, 'PacketStoreReady')) {
      _broker.dispatch(
        deviceId: _aprsDeviceId,
        name: 'RequestPacketList',
        data: null,
        store: false,
      );
    }

    // Restore the next APRS message id (persisted across restarts).
    _nextAprsMessageId = _broker.getValue<int>(0, 'NextAprsMessageId', 1) ?? 1;
    if (_nextAprsMessageId < 1 || _nextAprsMessageId > 999) {
      _nextAprsMessageId = 1;
    }
  }

  void _loadStations(Object? data) {
    if (data is List) {
      final list = <AprsStationInfo>[];
      for (final item in data) {
        if (item is Map<String, dynamic>) {
          final station = AprsStationInfo.fromJson(item);
          if (station != null) list.add(station);
        } else if (item is AprsStationInfo) {
          list.add(item);
        }
      }
      _auth.stations = list;
    }
  }

  void _onStationsUpdate(int deviceId, String name, Object? data) {
    if (_disposed) return;
    _loadStations(data);
  }

  void _updateLocalCallsignWithId() {
    final callsign = _broker.getValue<String>(0, 'CallSign', '') ?? '';
    final stationId = _broker.getValue<int>(0, 'StationId', 0) ?? 0;
    if (callsign.isEmpty) {
      _localCallsignWithId = null;
    } else if (stationId > 0) {
      _localCallsignWithId = '$callsign-$stationId';
    } else {
      _localCallsignWithId = callsign;
    }
  }

  void _onCallsignOrStationIdChanged(int deviceId, String name, Object? data) {
    if (_disposed) return;
    _updateLocalCallsignWithId();
  }

  /// Returns the next APRS message id (1..999), persisting the successor.
  int _getNextAprsMessageId() {
    final msgId = _nextAprsMessageId++;
    if (_nextAprsMessageId > 999) _nextAprsMessageId = 1;
    _broker.dispatch(
      deviceId: 0,
      name: 'NextAprsMessageId',
      data: _nextAprsMessageId,
      store: true,
    );
    return msgId;
  }

  /// Returns the channel id of the "APRS" channel for [radioDeviceId], or -1.
  int _getAprsChannelId(int radioDeviceId) {
    final channels = _broker.getJsonListValue<RadioChannelInfo>(
      radioDeviceId,
      'Channels',
      (json) => RadioChannelInfo.fromJson(json),
    );
    if (channels == null) return -1;
    for (final channel in channels) {
      if (channel.name == 'APRS') return channel.channelId;
    }
    return -1;
  }

  void _trimFrames() {
    while (_aprsFrames.length > _maxFrameHistory) {
      _aprsFrames.removeAt(0);
    }
  }

  void _onSendAprsMessage(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (data is! AprsSendMessageData) return;
    final messageData = data;

    final callsign = _broker.getValue<String>(0, 'CallSign', '') ?? '';
    final stationIdInt = _broker.getValue<int>(0, 'StationId', 0) ?? 0;
    final stationId = stationIdInt > 0 ? stationIdInt.toString() : '';

    if (callsign.isEmpty) {
      _broker.logError('Cannot send APRS message: Callsign not configured');
      return;
    }

    final srcCallsignWithId = stationId.isEmpty
        ? callsign
        : '$callsign-$stationId';

    final msgId = _getNextAprsMessageId();
    final now = DateTime.now();
    final authResult = _auth.addAprsAuth(
      srcCallsignWithId,
      messageData.destination,
      messageData.message,
      msgId,
      now,
    );

    // Build the AX.25 address list.
    final addresses = <AX25Address>[];
    var destAddress = 'APRS';
    final route = messageData.route;
    if (route != null && route.length >= 2) {
      destAddress = route[1];
    }
    final destAddr = AX25Address.parse(destAddress);
    final srcAddr = AX25Address.parse(srcCallsignWithId);
    if (destAddr == null || srcAddr == null) {
      _broker.logError('Cannot send APRS message: invalid address');
      return;
    }
    addresses.add(destAddr);
    addresses.add(srcAddr);
    if (route != null && route.length > 2) {
      for (int i = 2; i < route.length; i++) {
        if (route[i].isNotEmpty) {
          final digi = AX25Address.parse(route[i]);
          if (digi != null) addresses.add(digi);
        }
      }
    }

    final aprsChannelId = _getAprsChannelId(messageData.radioDeviceId);
    if (aprsChannelId < 0) {
      _broker.logError(
        'Cannot send APRS message: No APRS channel found on radio '
        '${messageData.radioDeviceId}',
      );
      return;
    }

    final ax25Packet = AX25Packet(
      addresses: addresses,
      dataStr: authResult.content,
      type: FrameType.uFrameUi,
      command: true,
      time: now,
    );
    ax25Packet.pid = 240;
    ax25Packet.incoming = false;
    ax25Packet.sent = false;
    ax25Packet.authState = authResult.applied
        ? AuthState.success
        : AuthState.none;
    ax25Packet.channelId = aprsChannelId;
    ax25Packet.channelName = 'APRS';

    _broker.dispatch(
      deviceId: messageData.radioDeviceId,
      name: 'TransmitDataFrame',
      data: TransmitDataFrameData(
        packet: ax25Packet,
        channelId: aprsChannelId,
        regionId: -1,
      ),
      store: false,
    );

    // Echo the outgoing packet to the UI as a sent message.
    final aprsPacket = AprsPacket.parse(ax25Packet);
    if (aprsPacket != null) {
      _aprsFrames.add(aprsPacket);
      _trimFrames();
      _broker.dispatch(
        deviceId: _aprsDeviceId,
        name: 'AprsFrame',
        data: AprsFrameEventArgs(aprsPacket, ax25Packet, null),
        store: false,
      );
    }
  }

  void _onPacketStoreReady(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (_storeReady) return;
    _broker.dispatch(
      deviceId: _aprsDeviceId,
      name: 'RequestPacketList',
      data: null,
      store: false,
    );
  }

  void _onPacketList(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (_storeReady) return;
    if (data is! List) return;

    final localCallsign = _localCallsignWithId;

    for (final frame in data) {
      if (frame is! TncDataFragment) continue;
      if (frame.channelName != 'APRS') continue;

      final ax25Packet = AX25Packet.decode(frame);
      if (ax25Packet == null) continue;
      if (ax25Packet.type != FrameType.uFrameUi &&
          ax25Packet.type != FrameType.uFrame) {
        continue;
      }

      final aprsPacket = AprsPacket.parse(ax25Packet);
      if (aprsPacket == null) continue;

      _applyAuthState(ax25Packet, aprsPacket, localCallsign);
      _aprsFrames.add(aprsPacket);
    }
    _trimFrames();

    _storeReady = true;
    _broker.dispatch(
      deviceId: _aprsDeviceId,
      name: 'AprsStoreReady',
      data: true,
      store: false,
    );
  }

  void _onRequestAprsPackets(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (!_storeReady) return;
    _broker.dispatch(
      deviceId: _aprsDeviceId,
      name: 'AprsPacketList',
      data: List<AprsPacket>.from(_aprsFrames),
      store: false,
    );
  }

  void _applyAuthState(
    AX25Packet ax25Packet,
    AprsPacket aprsPacket,
    String? localCallsign,
  ) {
    final authCode = aprsPacket.authCode;
    if (authCode != null && authCode.isNotEmpty) {
      if (ax25Packet.addresses.length >= 2) {
        final srcAddress = ax25Packet.addresses[1].callSignWithId;
        final isSender =
            localCallsign != null &&
            localCallsign.isNotEmpty &&
            srcAddress.toLowerCase() == localCallsign.toLowerCase();
        ax25Packet.authState = _auth.checkAprsAuth(
          isSender,
          srcAddress,
          ax25Packet.dataStr,
          ax25Packet.time,
        );
      }
    } else {
      ax25Packet.authState = AuthState.none;
    }
  }

  void _onUniqueDataFrame(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (data is! TncDataFragment) return;
    final frame = data;
    if (frame.channelName != 'APRS') return;

    final ax25Packet = AX25Packet.decode(frame);
    if (ax25Packet == null) return;
    if (ax25Packet.type != FrameType.uFrameUi &&
        ax25Packet.type != FrameType.uFrame) {
      return;
    }

    final aprsPacket = AprsPacket.parse(ax25Packet);
    if (aprsPacket == null) return;

    _applyAuthState(ax25Packet, aprsPacket, _localCallsignWithId);

    _aprsFrames.add(aprsPacket);
    _trimFrames();

    _broker.dispatch(
      deviceId: _aprsDeviceId,
      name: 'AprsFrame',
      data: AprsFrameEventArgs(aprsPacket, ax25Packet, frame),
      store: false,
    );

    _sendAckIfNeeded(aprsPacket, ax25Packet, frame, deviceId);
  }

  void _sendAckIfNeeded(
    AprsPacket aprsPacket,
    AX25Packet ax25Packet,
    TncDataFragment frame,
    int radioDeviceId,
  ) {
    if (aprsPacket.dataType != PacketDataType.message) return;
    if (aprsPacket.messageData.msgType == MessageType.mtAck) return;
    if (aprsPacket.messageData.msgType == MessageType.mtRej) return;
    if (aprsPacket.messageData.seqId.isEmpty) return;

    final localCallsign = _localCallsignWithId;
    if (localCallsign == null || localCallsign.isEmpty) return;

    final addressee = aprsPacket.messageData.addressee;
    if (addressee.isEmpty) return;

    final callsignOnly = _broker.getValue<String>(0, 'CallSign', '') ?? '';
    final isForUs =
        addressee.toLowerCase() == localCallsign.toLowerCase() ||
        (callsignOnly.isNotEmpty &&
            addressee.toLowerCase() == callsignOnly.toLowerCase());
    if (!isForUs) return;

    if (ax25Packet.addresses.length < 2) return;
    final senderCallsign = ax25Packet.addresses[1].callSignWithId;

    final aprsChannelId = _getAprsChannelId(radioDeviceId);
    if (aprsChannelId < 0) return;

    final ackMessage = 'ack${aprsPacket.messageData.seqId}';
    final now = DateTime.now();

    final useAuth = ax25Packet.authState == AuthState.success;
    bool authApplied = false;
    String aprsContent;
    if (useAuth) {
      final result = _auth.addAprsAckAuth(
        localCallsign,
        senderCallsign,
        ackMessage,
        now,
      );
      aprsContent = result.content;
      authApplied = result.applied;
    } else {
      var paddedAddr = senderCallsign;
      while (paddedAddr.length < 9) {
        paddedAddr += ' ';
      }
      aprsContent = ':$paddedAddr:$ackMessage';
    }

    final destAddr = AX25Address.parse('APRS');
    final srcAddr = AX25Address.parse(localCallsign);
    if (destAddr == null || srcAddr == null) return;

    final ackAx25Packet = AX25Packet(
      addresses: [destAddr, srcAddr],
      dataStr: aprsContent,
      type: FrameType.uFrameUi,
      command: true,
      time: now,
    );
    ackAx25Packet.pid = 240;
    ackAx25Packet.incoming = false;
    ackAx25Packet.sent = false;
    ackAx25Packet.authState = authApplied ? AuthState.success : AuthState.none;
    ackAx25Packet.channelId = aprsChannelId;
    ackAx25Packet.channelName = 'APRS';

    _broker.dispatch(
      deviceId: radioDeviceId,
      name: 'TransmitDataFrame',
      data: TransmitDataFrameData(
        packet: ackAx25Packet,
        channelId: aprsChannelId,
        regionId: -1,
      ),
      store: false,
    );

    final ackAprsPacket = AprsPacket.parse(ackAx25Packet);
    if (ackAprsPacket != null) {
      _aprsFrames.add(ackAprsPacket);
      _trimFrames();
      _broker.dispatch(
        deviceId: _aprsDeviceId,
        name: 'AprsFrame',
        data: AprsFrameEventArgs(ackAprsPacket, ackAx25Packet, null),
        store: false,
      );
    }
  }

  /// Clears all stored APRS frames.
  void clearFrames() => _aprsFrames.clear();

  /// Disposes the handler, unsubscribing from the broker.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _broker.dispose();
    _aprsFrames.clear();
  }
}
