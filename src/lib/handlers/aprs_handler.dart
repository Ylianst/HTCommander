/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from the C# `HTCommander.AprsHandler` class.
*/

import 'dart:async';
import 'dart:math';

import '../aprs/aprs_auth.dart';
import '../aprs/aprs_outbox.dart';
import '../aprs/aprs_conversation.dart';
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
import '../services/host_bridge.dart';
import '../services/notification_service.dart';
import '../services/notification_router.dart';
import '../services/aprs_outbox_store.dart';
import '../aprsis/aprsis_client.dart' show aprsIsDeviceId;

/// A data handler that processes APRS packets from the "APRS" channel.
///
/// Subscribes to `UniqueDataFrame` events, decodes AX.25 and APRS frames,
/// validates authentication codes when present, stores the last
/// [_maxFrameHistory] APRS frames, and (on startup) loads previous APRS packets
/// from the [PacketStore]. Also handles `SendAprsMessage` requests from the UI
/// and auto-acknowledges addressed messages.
class AprsHandler {
  AprsHandler({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final AprsOutboxStore _outboxStore = AprsOutboxStore();
  final Map<String, AprsOutgoingMessage> _outbox = {};
  final Set<String> _receivedAnswers = {};
  Future<void> _work = Future.value();
  Timer? _retryTimer;
  bool _outboxReady = false;
  bool _tickQueued = false;
  Future<void> get ready async {
    while (true) {
      final current = _work;
      await current;
      if (identical(current, _work)) return;
    }
  }
  List<AprsOutgoingMessage> get outgoingMessages => _outbox.values.toList();
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
      callback: _onClearAprsPackets,
    );
    _broker.subscribe(
      deviceId: _aprsDeviceId,
      name: clearAprsConversationEvent,
      callback: _onClearAprsConversation,
    );

    // One-shot history snapshot from the desktop host (web build served by the
    // desktop app). Seeds past APRS packets so the APRS tab isn't empty.
    _broker.subscribe(
      deviceId: _aprsDeviceId,
      name: 'WebHistorySnapshot',
      callback: _onWebHistorySnapshot,
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

    if (!HostBridge.isHosted) {
      _broker.subscribe(deviceId: 1, name: 'AprsFrame', callback: _observeDelivery);
      _broker.subscribe(deviceId: DataBroker.allDevices, name: 'AprsTransmitResult', callback: _onTransmitResult);
      _broker.subscribeMultiple(deviceId: 1, names: const ['RetryAprsMessage', 'StopAprsMessage'], callback: _onOutboxAction);
      _run(() async {
        for (final saved in await _outboxStore.load()) {
          final restored = saved.withParts([
            for (final part in saved.parts)
              part.pending ? part.update(state: AprsDelivery.paused) : part,
          ]);
          await _outboxStore.save(restored);
          if (_disposed) return;
          _outbox[restored.id] = restored;
          _echoOutboxMessage(restored);
        }
        _outboxReady = true;
        _publishOutbox();
      });
      _retryTimer = Timer.periodic(const Duration(seconds: 1), (_) => processOutbox());
    }

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
    if (_nextAprsMessageId < 1 || _nextAprsMessageId > 99999) {
      _nextAprsMessageId = 1;
    }
  }

  void _loadStations(Object? data) {
    _auth.loadStations(data);
    if (!HostBridge.isHosted) {
      _broker.dispatch(deviceId: 1, name: 'AprsAuthenticatedDestinations',
        data: _auth.stations.where((s) => s.isAprs && s.authPassword.isNotEmpty)
          .map((s) => aprsPeerKey(s.callsign)).toList(), store: true);
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

  /// Retained IDs are not reused, so late ACKs cannot answer a newer message.
  int _getNextAprsMessageId(Set<int> reserved) {
    final used = {...reserved, for (final m in _outbox.values) for (final p in m.parts) p.wireId};
    for (var i = 0; used.contains(_nextAprsMessageId); i++) {
      if (i >= 99999) throw StateError('APRS message IDs exhausted');
      _nextAprsMessageId = _nextAprsMessageId % 99999 + 1;
    }
    final msgId = _nextAprsMessageId++;
    if (_nextAprsMessageId > 99999) _nextAprsMessageId = 1;
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

  /// Whether [radioDeviceId] is locked in APRSSat mode (tracking an APRS
  /// satellite via VFO A), in which case all its traffic is treated as APRS.
  bool _isRadioInAprsSatMode(int radioDeviceId) {
    final ls = _broker.getValueDynamic(radioDeviceId, 'LockState', null);
    if (ls is! Map) return false;
    final isLocked = (ls['isLocked'] ?? ls['IsLocked']) == true;
    final usage = (ls['usage'] ?? ls['Usage']) as String?;
    return isLocked && usage == 'APRSSat';
  }

  void _trimFrames() {
    while (_aprsFrames.length > _maxFrameHistory) {
      _aprsFrames.removeAt(0);
    }
  }

  void _onSendAprsMessage(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (data is! AprsSendMessageData) return;
    if (HostBridge.isHosted) return; // The bridge forwards the command to its host.
    _run(() async {
      if (!_outboxReady) throw StateError('APRS outbox is unavailable');
      final policy = data.policy.resolve(radioDeviceId: data.radioDeviceId,
        internetEnabled: (_broker.getValue<int>(0, 'AprsIsEnabled', 0) ?? 0) != 0);
      if (policy.permitsRf && data.radioDeviceId <= 0) {
        throw const AprsComposeException(AprsComposeError.radio);
      }
      final radioDeviceId = policy.permitsRf ? data.radioDeviceId : -1;
      final destination = aprsPeerKey(data.destination);
      final source = aprsPeerKey(_localCallsignWithId ?? '');
      if (!RegExp(r'^[A-Z0-9]{1,6}(?:-(?:[0-9]|1[0-5]))?$').hasMatch(source) ||
          !RegExp(r'^[A-Z0-9]{1,6}(?:-(?:[0-9]|1[0-5]))?$').hasMatch(destination)) {
        throw const AprsComposeException(AprsComposeError.address);
      }
      final authenticated = _auth.authenticates(destination);
      final texts = splitAprsMessage(data.message, destination, authenticated: authenticated);
      final reserved = <int>{};
      final parts = <AprsOutboxPart>[];
      for (final text in texts) {
        final id = _getNextAprsMessageId(reserved);
        reserved.add(id);
        parts.add(AprsOutboxPart(wireId: id, text: text));
      }
      final now = _clock();
      final message = AprsOutgoingMessage(
        id: '${now.microsecondsSinceEpoch}-${Random.secure().nextInt(0xFFFFFFFF)}',
        source: source, destination: destination, text: data.message, created: now,
        radioDeviceId: radioDeviceId,
        radioMac: _broker.getValue<String>(radioDeviceId, 'MacAddress'),
        linkPolicy: policy,
        authenticated: authenticated, parts: parts, route: data.route,
        maxAttempts: (_broker.getValue<int>(0, 'AprsRetryAttempts', 6) ?? 6).clamp(1, 10),
        retrySeconds: (_broker.getValue<int>(0, 'AprsRetrySeconds', 30) ?? 30).clamp(10, 300),
      );
      _makeOutboxPacket(message, parts.first); // Validate the complete route before persisting.
      await _commit(message);
      if (_disposed) return;
      _echoOutboxMessage(message);
      _broker.dispatch(deviceId: 1, name: 'AprsMessageQueued', data: data.toJson(), store: false);
      _broker.dispatch(deviceId: 1, name: 'AprsSendError', data: null, store: true);
      await _processOutbox();
    });
  }

  void _run(Future<void> Function() action) {
    _work = _work.then((_) async {
      if (_disposed) return;
      try {
        await action();
      } catch (error) {
        _broker.logError('APRS outbox: $error');
        if (!_disposed) {
          _broker.dispatch(deviceId: 1, name: 'AprsSendError', data: {
            'reason': error is AprsComposeException ? error.reason.name : 'storage',
            'detail': '$error',
          }, store: true);
        }
      }
    });
  }

  Future<void> _commit(AprsOutgoingMessage message) async {
    await _outboxStore.save(message);
    if (_disposed) return;
    _outbox[message.id] = message;
    final finished = _outbox.values.where((m) => !m.active).toList()
      ..sort((a, b) => a.created.compareTo(b.created));
    final expired = finished.take((finished.length - _maxFrameHistory).clamp(0, finished.length)).toList();
    if (expired.isNotEmpty) {
      await _outboxStore.delete(expired.map((m) => m.id).toList());
      for (final old in expired) {
        _outbox.remove(old.id);
      }
    }
    _publishOutbox();
  }

  void _publishOutbox() => _broker.dispatch(
    deviceId: 1, name: 'AprsOutbox',
    data: _outbox.values.map((m) => m.toJson()).toList(), store: true,
  );

  bool get _internetAvailable =>
      (_broker.getValue<int>(0, 'AprsIsEnabled', 0) ?? 0) != 0 &&
      (_broker.getValue<bool>(aprsIsDeviceId, 'AprsIsVerified', false) ?? false);

  int? _outboxRadio(AprsOutgoingMessage message) {
    if (!message.linkPolicy.permitsRf || message.radioDeviceId < 0) return null;
    final radios = _broker.getValueDynamic(1, 'ConnectedRadios', null);
    if (radios is! List) return null;
    for (final radio in radios) {
      if (radio is! Map || radio['DeviceId'] is! int) continue;
      final id = radio['DeviceId'] as int;
      if (message.radioMac?.isNotEmpty == true
          ? radio['MacAddress'] != message.radioMac
          : id != message.radioDeviceId) {
        continue;
      }
      final lock = _broker.getValueDynamic(id, 'LockState', null);
      if (lock is Map && (lock['isLocked'] ?? lock['IsLocked']) == true &&
          !const ['Digipeater', 'APRSSat'].contains(lock['usage'] ?? lock['Usage'])) {
        continue;
      }
      if (_getAprsChannelId(id) >= 0 || _isRadioInAprsSatMode(id)) return id;
    }
    return null;
  }

  String _partTag(AprsOutgoingMessage message, AprsOutboxPart part) =>
      'aprs-outbox:${message.id}:${part.wireId}';

  AX25Packet _makeOutboxPacket(AprsOutgoingMessage message, AprsOutboxPart part, {bool displayOnly = false}) {
    final auth = _auth.addAprsAuth(message.source, message.destination, part.text, part.wireId, _clock());
    if (!displayOnly && auth.applied != message.authenticated) throw StateError('APRS authentication configuration changed');
    final route = message.route;
    final names = [route != null && route.length >= 2 ? route[1] : 'APRS', message.source,
      if (route != null && route.length > 2) ...route.skip(2).where((s) => s.isNotEmpty)];
    final addresses = <AX25Address>[];
    if (names.length > 10) throw const AprsComposeException(AprsComposeError.address);
    for (final name in names) {
      if (!RegExp(r'^[A-Z0-9]{1,6}(?:-(?:[0-9]|1[0-5]))?$', caseSensitive: false).hasMatch(name)) {
        throw const AprsComposeException(AprsComposeError.address);
      }
      final address = AX25Address.parse(name);
      if (address == null) throw const AprsComposeException(AprsComposeError.address);
      addresses.add(address);
    }
    return AX25Packet(addresses: addresses, dataStr: auth.content, command: true, time: message.created)
      ..channelName = 'APRS'
      ..authState = message.authenticated && !auth.applied ? AuthState.unknown :
        auth.applied ? AuthState.success : AuthState.none
      ..tag = _partTag(message, part);
  }

  void _echoOutboxMessage(AprsOutgoingMessage message) {
    for (final part in message.parts) {
      final packet = _makeOutboxPacket(message, part, displayOnly: true);
      final aprs = AprsPacket.parse(packet);
      if (aprs == null) throw StateError('Unable to parse outgoing APRS message');
      _aprsFrames.add(aprs);
      _trimFrames();
      _broker.dispatch(deviceId: 1, name: 'AprsFrame', data: AprsFrameEventArgs(aprs, packet, null), store: false);
    }
  }

  /// Also used by deterministic retry tests; the timer never overlaps a tick.
  Future<void> processOutbox() {
    if (_tickQueued || _disposed || HostBridge.isHosted) return ready;
    _tickQueued = true;
    _run(() async {
      try {
        if (_outboxReady) await _processOutbox();
      } finally {
        _tickQueued = false;
      }
    });
    return ready;
  }

  Future<void> _processOutbox() async {
    for (final original in _outbox.values.toList()) {
      // Initial multipart copies precede every retry of that logical message.
      final order = List<int>.generate(original.parts.length, (i) => i)
        ..sort((a, b) => original.parts[a].attempts.compareTo(original.parts[b].attempts));
      for (final index in order) {
        if (_disposed) return;
        var message = _outbox[original.id];
        if (message == null) break;
        final part = message.parts[index];
        if (_receivedAnswers.contains(_partTag(message, part))) continue;
        if (!part.pending || (part.nextAttempt?.isAfter(_clock()) ?? false)) continue;
        if (part.attempts >= message.maxAttempts) {
          final parts = [...message.parts];
          parts[index] = part.update(state: AprsDelivery.failed);
          await _commit(message.withParts(parts));
          continue;
        }
        if (message.source != aprsPeerKey(_localCallsignWithId ?? '') ||
            (_broker.getValue<int>(0, 'AllowTransmit', 1) ?? 1) == 0) {
          continue;
        }
        final radioId = _outboxRadio(message);
        final internet = message.internet && _internetAvailable;
        if (radioId == null && !internet) continue;
        if (_auth.authenticates(message.destination) != message.authenticated) {
          final parts = [...message.parts];
          parts[index] = part.update(state: AprsDelivery.paused, error: 'APRS authentication configuration changed');
          await _commit(message.withParts(parts));
          _broker.logError('APRS outbox paused: authentication configuration changed');
          continue;
        }
        final attempts = part.attempts + 1;
        final next = _clock().add(Duration(seconds: (message.retrySeconds * attempts).clamp(10, 300)));
        final parts = [...message.parts];
        parts[index] = part.update(state: AprsDelivery.queued, attempts: attempts, nextAttempt: next);
        message = message.withParts(parts);
        final packet = _makeOutboxPacket(message, parts[index])
          ..deadline = next
          ..tag = '${_partTag(message, part)}:$attempts';
        await _commit(message); // A crash after dispatch must not reset its retry budget.
        if (_disposed) return;
        if (_receivedAnswers.contains(_partTag(message, part))) continue;
        if (radioId != null) {
          final channel = _isRadioInAprsSatMode(radioId) ? 0 : _getAprsChannelId(radioId);
          packet.channelId = channel;
          _broker.dispatch(deviceId: radioId, name: 'TransmitDataFrame',
            data: TransmitDataFrameData(packet: packet, channelId: channel, regionId: -1), store: false);
        }
        if (internet) {
          final aprs = AprsPacket.parse(packet)!;
          _broker.dispatch(deviceId: 1, name: 'SendAprsIsMessage', data: AprsFrameEventArgs(aprs, packet, null), store: false);
        }
      }
    }
  }

  void _onTransmitResult(int deviceId, String name, Object? data) {
    if (data is! Map || data['tag'] is! String) return;
    _run(() async {
      for (final message in _outbox.values.toList()) {
        final parts = [...message.parts];
        for (var i = 0; i < parts.length; i++) {
          final part = parts[i];
          if ('${_partTag(message, part)}:${part.attempts}' != data['tag'] || !part.pending) continue;
          if (data['accepted'] == true) {
            parts[i] = part.update(state: part.state == AprsDelivery.digipeated ? part.state : AprsDelivery.sent, nextAttempt: part.nextAttempt);
          } else {
            parts[i] = part.update(nextAttempt: part.nextAttempt, error: data['error']?.toString());
          }
          await _commit(message.withParts(parts));
          return;
        }
      }
    });
  }

  void _observeDelivery(int deviceId, String name, Object? data) {
    if (data is! AprsFrameEventArgs || data.historical || !data.ax25Packet.incoming ||
        data.aprsPacket.dataType != PacketDataType.message) {
      return;
    }
    final aprs = data.aprsPacket;
    final md = aprs.messageData;
    for (final message in _outbox.values) {
      for (final part in message.parts) {
        if (_matchingAnswer(message, part, data) != null) {
          _receivedAnswers.add(_partTag(message, part));
        }
      }
    }
    _run(() async {
      for (final message in _outbox.values.toList()) {
        final parts = [...message.parts];
        for (var i = 0; i < parts.length; i++) {
          final part = parts[i];
          if (part.attempts == 0 || md.seqId != '${part.wireId}' || part.answered) continue;
          final response = md.msgType == MessageType.mtAck || md.msgType == MessageType.mtRej;
          final answer = _matchingAnswer(message, part, data);
          if (answer != null) {
            parts[i] = part.update(state: answer);
          } else if (!response && part.pending && !aprs.fromAprsIs &&
              data.fragment?.encoding != FragmentEncodingType.loopback &&
              aprsPeerKey(aprs.sourceCallsignWithId) == message.source &&
              aprsPeerKey(md.addressee) == message.destination && md.msgText == part.text &&
              data.ax25Packet.addresses.skip(2).any((a) => a.crBit1 &&
                !const ['TCPIP', 'TCPXX'].contains(a.address.toUpperCase()))) {
            parts[i] = part.update(state: AprsDelivery.digipeated, nextAttempt: part.nextAttempt);
          } else {
            continue;
          }
          await _commit(message.withParts(parts));
          _receivedAnswers.remove(_partTag(message, part));
          return;
        }

      }
    });
  }

  AprsDelivery? _matchingAnswer(AprsOutgoingMessage message, AprsOutboxPart part, AprsFrameEventArgs data) {
    final aprs = data.aprsPacket;
    final md = aprs.messageData;
    if (part.attempts == 0 || part.answered || md.seqId != '${part.wireId}' ||
        (md.msgType != MessageType.mtAck && md.msgType != MessageType.mtRej) ||
        aprsPeerKey(aprs.sourceCallsignWithId) != message.destination ||
        aprsPeerKey(md.addressee) != message.source) {
      return null;
    }
    if (message.authenticated) {
      var content = data.ax25Packet.dataStr;
      if (aprs.thirdPartySourceCallsign != null && content != null) {
        content = content.substring(content.indexOf(':') + 1);
      }
      if (_auth.checkAprsAuth(false, message.destination, content, data.ax25Packet.time) != AuthState.success) {
        return null;
      }
    }
    return md.msgType == MessageType.mtAck ? AprsDelivery.delivered : AprsDelivery.rejected;
  }

  void _onOutboxAction(int deviceId, String name, Object? data) {
    if (data is! String) return;
    _run(() async {
      final message = _outbox[data];
      if (message == null) throw StateError('APRS message no longer exists');
      if (name == 'RetryAprsMessage' && message.parts.any((p) => p.pending)) {
        throw StateError('An active APRS message cannot be retried manually');
      }
      final parts = [
        for (final part in message.parts)
          if (part.answered) part
          else if (name == 'StopAprsMessage') part.update(state: AprsDelivery.stopped, attempts: part.attempts)
          else part.update(state: AprsDelivery.queued,
            attempts: part.state == AprsDelivery.paused && part.attempts < message.maxAttempts ? part.attempts : 0),
      ];
      await _commit(message.withParts(parts));
      if (_disposed) return;
      for (final part in message.parts) {
        final radioId = _outboxRadio(message);
        if (radioId != null) {
          _broker.dispatch(deviceId: radioId, name: 'CancelAprsTransmit', data: _partTag(message, part), store: false);
        }
      }
      await _processOutbox();
    });
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
      if (frame.aprsHidden) continue;

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

  /// Seeds the APRS frame history from the desktop host's snapshot (web build
  /// only). Applied once while the local history is empty, then published so the
  /// APRS tab renders the past packets.
  void _onWebHistorySnapshot(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (_aprsFrames.isNotEmpty) return;
    if (data is! Map) return;
    final aprs = data['aprs'];
    if (aprs is! List) return;

    for (final raw in aprs) {
      if (raw is! Map) continue;
      try {
        final pkt = AprsPacket.fromJson(raw.cast<String, dynamic>());
        if (pkt.packet != null) _aprsFrames.add(pkt);
      } catch (_) {
        // Skip malformed packets.
      }
    }
    _trimFrames();
    if (_aprsFrames.isEmpty) return;

    _storeReady = true;
    _broker.dispatch(
      deviceId: _aprsDeviceId,
      name: 'AprsStoreReady',
      data: true,
      store: false,
    );
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
        final srcAddress = aprsPeerKey(aprsPacket.sourceCallsignWithId);
        final isSender =
            localCallsign != null &&
            localCallsign.isNotEmpty &&
            srcAddress == aprsPeerKey(localCallsign);
        var content = ax25Packet.dataStr;
        if (aprsPacket.thirdPartySourceCallsign != null && content != null) {
          content = content.substring(content.indexOf(':') + 1);
        }
        ax25Packet.authState = _auth.checkAprsAuth(
          isSender,
          srcAddress,
          content,
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
    // Normally only frames from the "APRS" channel are APRS. In APRSSat mode the
    // radio is tuned to an APRS satellite via VFO A (no APRS channel), so every
    // frame it receives is tagged 'APRSSat' (and named 'APRS') and is treated
    // as APRS here.
    if (frame.channelName != 'APRS' && frame.usage != 'APRSSat') return;

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

    final messageData = aprsPacket.messageData;
    if (aprsPacket.dataType == PacketDataType.message &&
        messageData.msgType != MessageType.mtAck &&
        messageData.msgType != MessageType.mtRej &&
        messageData.msgText.isNotEmpty) {
      final source = aprsPacket.sourceCallsignWithId;
      _broker.dispatch(
        deviceId: deviceId,
        name: 'AprsMessageReceived',
        data: <String, Object?>{
          'text': messageData.msgText,
          'channel': frame.channelName,
          'time': frame.time.millisecondsSinceEpoch,
          'source': source,
          'destination': messageData.addressee,
          'latitude': aprsPacket.position.coordinateSet.latitude.value,
          'longitude': aprsPacket.position.coordinateSet.longitude.value,
          'suppressNotification': true,
        },
        store: false,
      );
    }

    _sendAckIfNeeded(aprsPacket, ax25Packet, frame, deviceId);
    _notifyIncomingAprsMessage(aprsPacket);
  }

  /// Raises a system notification when an APRS message addressed to our station
  /// arrives. [NotificationService] itself suppresses the pop-up while the app
  /// is in the foreground.
  void _notifyIncomingAprsMessage(
    AprsPacket aprsPacket,
  ) {
    // The desktop host raises the notification; on the hosted web build it would
    // be a duplicate of the host's own pop-up.
    if (HostBridge.isHosted) return;
    if (aprsPacket.dataType != PacketDataType.message) return;
    final messageData = aprsPacket.messageData;
    if (messageData.msgType == MessageType.mtAck) return;
    if (messageData.msgType == MessageType.mtRej) return;
    if (messageData.msgText.isEmpty) return;

    final addressee = messageData.addressee;
    if (addressee.isEmpty) return;

    final localCallsign = _localCallsignWithId;
    final callsignOnly = _broker.getValue<String>(0, 'CallSign', '') ?? '';
    final isForUs =
        (localCallsign != null &&
            addressee.toLowerCase() == localCallsign.toLowerCase()) ||
        (callsignOnly.isNotEmpty &&
            addressee.toLowerCase() == callsignOnly.toLowerCase());
    if (!isForUs) return;

    final from = aprsPacket.sourceCallsignWithId;
    NotificationService.instance.showMessage(
      title: from.isNotEmpty ? 'APRS message from $from' : 'APRS message',
      body: messageData.msgText,
      payload: aprsNotificationPayload(
        _conversationPeer(from, messageData.msgText),
      ),
    );
  }

  /// The Messaging-tab conversation for a message from [from]: replies relayed
  /// by the SMS gateway (`@phone text`) thread under the phone's digits,
  /// everything else under the sender callsign.
  static String _conversationPeer(String from, String text) {
    final base = from.split('-').first.toUpperCase();
    if ((base == 'SMS' || base == 'SMSGTE') && text.startsWith('@')) {
      final sp = text.indexOf(' ');
      if (sp > 1) {
        final phone = text.substring(1, sp).replaceAll(RegExp(r'[^0-9]'), '');
        if (phone.isNotEmpty) return phone;
      }
    }
    return from;
  }

  void _sendAckIfNeeded(
    AprsPacket aprsPacket,
    AX25Packet ax25Packet,
    TncDataFragment frame,
    int radioDeviceId,
  ) {
    // The desktop host auto-acknowledges incoming messages; on the hosted web
    // build a second ACK would be transmitted over the shared radio.
    if (HostBridge.isHosted) return;
    if (aprsPacket.dataType != PacketDataType.message) return;
    if (aprsPacket.messageData.msgType == MessageType.mtAck) return;
    if (aprsPacket.messageData.msgType == MessageType.mtRej) return;
    if (aprsPacket.messageData.seqId.isEmpty) return;
    if (ax25Packet.authState == AuthState.failed) return;

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

    // Address the ACK to the station that actually sent the message. For an
    // IGate-relayed (third-party) message this is the original internet sender,
    // not the IGate; sending it over RF lets an IGate gate the ACK back to them.
    final senderCallsign = aprsPeerKey(aprsPacket.sourceCallsignWithId);
    if (senderCallsign.isEmpty) return;

    // In APRSSat mode ACK through the satellite on VFO A, like outgoing
    // messages (see _onSendAprsMessage).
    final aprsChannelId = _isRadioInAprsSatMode(radioDeviceId)
        ? 0
        : _getAprsChannelId(radioDeviceId);
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

  /// Handles the `ClearAprsPackets` request from the UI: clears the stored
  /// frames and notifies listeners (e.g. the map) so they can remove all APRS
  /// markers.
  void _onClearAprsPackets(int deviceId, String name, Object? data) {
    if (_disposed) return;
    _deleteOutbox((_) => true);
    clearFrames();
    _broker.dispatch(
      deviceId: _aprsDeviceId,
      name: 'AprsPacketsCleared',
      data: null,
      store: false,
    );
  }

  /// Handles a [clearAprsConversationEvent] from the UI: drops the messages of
  /// that conversation (`data['peer']`) from the in-memory history so a tab
  /// rebuild does not bring them back. The PacketStore persists the change.
  void _onClearAprsConversation(int deviceId, String name, Object? data) {
    if (_disposed) return;
    final peer = data is Map ? data['peer']?.toString() : null;
    if (peer == null || peer.isEmpty) return;
    final local = AprsLocalStation.fromSettings(
      _broker.getValue<String>(0, 'CallSign', '') ?? '',
      _broker.getValue<int>(0, 'StationId', 0) ?? 0,
    );
    _deleteOutbox((m) => aprsConversationPeer(
      sender: m.source, addressee: m.destination, text: m.text,
      outgoing: true, local: local,
    ) == peer);
    _aprsFrames.removeWhere((p) {
      final packet = p.packet;
      if (packet == null) return false;
      return aprsPacketConversationPeer(
            p,
            outgoing: !packet.incoming,
            local: local,
          ) ==
          peer;
    });
  }

  /// Disposes the handler, unsubscribing from the broker.
  void _deleteOutbox(bool Function(AprsOutgoingMessage) matches) {
    if (HostBridge.isHosted) return;
    _run(() async {
      final removed = _outbox.values.where(matches).toList();
      await _outboxStore.delete(removed.map((m) => m.id).toList());
      if (_disposed) return;
      for (final message in removed) {
        final radioId = _outboxRadio(message);
        if (radioId != null) {
          for (final part in message.parts) {
            _broker.dispatch(deviceId: radioId, name: 'CancelAprsTransmit', data: _partTag(message, part), store: false);
          }
        }
        _outbox.remove(message.id);
      }
      _publishOutbox();
    });
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _retryTimer?.cancel();
    _broker.dispose();
    _aprsFrames.clear();
  }
}
