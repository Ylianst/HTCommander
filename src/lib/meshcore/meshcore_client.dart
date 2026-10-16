/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

//
// meshcore_client.dart - Transport-independent MeshCore companion client.
//
// The companion answers one command at a time, so commands are queued and only
// one is in flight. Push frames (codes >= 0x80) can arrive at any moment,
// including while a command is waiting, and are surfaced as [events].
//

import 'dart:async';
import 'dart:typed_data';

import 'meshcore_protocol.dart';

/// A frame-oriented link to a companion radio (BLE, serial or TCP).
abstract class MeshCoreTransport {
  /// Complete protocol frames received from the radio.
  Stream<Uint8List> get frames;

  /// Emits once when the link drops.
  Stream<void> get disconnected;

  Future<void> sendFrame(Uint8List frame);

  Future<void> close();
}

class MeshCoreException implements Exception {
  final String message;

  /// Firmware error code (see [MeshCoreErr]) when the radio rejected a command.
  final int? errorCode;

  const MeshCoreException(this.message, {this.errorCode});

  @override
  String toString() => message;
}

/// Bluetooth pairing was rejected (wrong or missing PIN). Retrying without
/// user action cannot succeed.
class MeshCorePairingException extends MeshCoreException {
  const MeshCorePairingException(super.message);
}

sealed class MeshCoreEvent {
  const MeshCoreEvent();
}

class MeshCoreMessageEvent extends MeshCoreEvent {
  final MeshCoreIncomingMessage message;
  const MeshCoreMessageEvent(this.message);
}

/// A contact was advertised or refreshed. [isNew] is true when the companion
/// reported it as newly discovered.
class MeshCoreContactEvent extends MeshCoreEvent {
  final MeshCoreContact contact;
  final bool isNew;
  const MeshCoreContactEvent(this.contact, this.isNew);
}

class MeshCoreContactDeletedEvent extends MeshCoreEvent {
  final Uint8List publicKey;
  const MeshCoreContactDeletedEvent(this.publicKey);
}

class MeshCoreContactsFullEvent extends MeshCoreEvent {
  const MeshCoreContactsFullEvent();
}

class MeshCoreSendConfirmedEvent extends MeshCoreEvent {
  final MeshCoreSendConfirmed confirmation;
  const MeshCoreSendConfirmedEvent(this.confirmation);
}

class MeshCoreDisconnectedEvent extends MeshCoreEvent {
  const MeshCoreDisconnectedEvent();
}

class _PendingCommand {
  final Uint8List frame;
  final Set<int> doneCodes;
  final Set<int> partialCodes;
  final Duration timeout;
  final List<Uint8List> frames = [];
  final Completer<List<Uint8List>> completer = Completer<List<Uint8List>>();
  Timer? timer;

  _PendingCommand(this.frame, this.doneCodes, this.partialCodes, this.timeout);
}

class MeshCoreClient {
  MeshCoreClient(
    this._transport, {
    this.appName = 'HTCommander',
    this.commandTimeout = const Duration(seconds: 6),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    _frameSub = _transport.frames.listen(_onFrame);
    _disconnectSub = _transport.disconnected.listen((_) => _onDisconnected());
  }

  final MeshCoreTransport _transport;
  final String appName;
  final Duration commandTimeout;
  final DateTime Function() _clock;

  final _events = StreamController<MeshCoreEvent>.broadcast();
  late final StreamSubscription<Uint8List> _frameSub;
  late final StreamSubscription<void> _disconnectSub;

  final List<_PendingCommand> _queue = [];
  _PendingCommand? _current;
  bool _closed = false;
  bool _draining = false;
  bool _drainAgain = false;

  MeshCoreSelfInfo? selfInfo;
  MeshCoreDeviceInfo? deviceInfo;

  Stream<MeshCoreEvent> get events => _events.stream;

  bool get isClosed => _closed;

  // ---------------------------------------------------------------------------
  // High-level operations
  // ---------------------------------------------------------------------------

  /// Negotiates the protocol version and reads device information. Sent first
  /// so the companion uses the V3 message formats for everything that follows.
  Future<MeshCoreDeviceInfo> queryDevice() async {
    final f = await _single(MeshCoreCommands.deviceQuery(), {
      MeshCoreResp.deviceInfo,
    });
    final info = MeshCoreDeviceInfo.parse(f);
    if (info == null) throw const MeshCoreException('Invalid device info');
    return deviceInfo = info;
  }

  Future<MeshCoreSelfInfo> appStart() async {
    final f = await _single(MeshCoreCommands.appStart(appName), {
      MeshCoreResp.selfInfo,
    });
    final info = MeshCoreSelfInfo.parse(f);
    if (info == null) throw const MeshCoreException('Invalid self info');
    return selfInfo = info;
  }

  /// Advances the companion clock to this computer's time when it is behind.
  /// The firmware rejects moving its clock backwards.
  Future<void> syncTime() async {
    final f = await _single(MeshCoreCommands.getDeviceTime(), {
      MeshCoreResp.currTime,
    });
    final deviceTime = parseCurrentTime(f) ?? 0;
    final now = _clock().millisecondsSinceEpoch ~/ 1000;
    if (deviceTime < now - 2) {
      await _single(MeshCoreCommands.setDeviceTime(now), {MeshCoreResp.ok});
    }
  }

  Future<List<MeshCoreContact>> getContacts() async {
    final frames = await _request(
      MeshCoreCommands.getContacts(),
      {MeshCoreResp.endOfContacts},
      partial: {MeshCoreResp.contactsStart, MeshCoreResp.contact},
      timeout: const Duration(seconds: 10),
    );
    final contacts = <MeshCoreContact>[];
    for (final f in frames) {
      if (f[0] != MeshCoreResp.contact) continue;
      final c = MeshCoreContact.parse(f);
      if (c != null) contacts.add(c);
    }
    return contacts;
  }

  Future<MeshCoreContact?> getContact(List<int> publicKey) async {
    try {
      final f = await _single(MeshCoreCommands.getContactByKey(publicKey), {
        MeshCoreResp.contact,
      });
      return MeshCoreContact.parse(f);
    } on MeshCoreException catch (e) {
      if (e.errorCode == MeshCoreErr.notFound) return null;
      rethrow;
    }
  }

  Future<void> addOrUpdateContact(MeshCoreContact contact) =>
      _single(MeshCoreCommands.addUpdateContact(contact), {MeshCoreResp.ok});

  Future<void> removeContact(List<int> publicKey) =>
      _single(MeshCoreCommands.removeContact(publicKey), {MeshCoreResp.ok});

  /// Clears the stored route so the next direct message is flooded.
  Future<void> resetPath(List<int> publicKey) =>
      _single(MeshCoreCommands.resetPath(publicKey), {MeshCoreResp.ok});

  /// Reads every channel slot. Empty slots are included so callers can find a
  /// free one.
  Future<List<MeshCoreChannel>> getChannels() async {
    final max = deviceInfo?.maxChannels ?? 0;
    final channels = <MeshCoreChannel>[];
    for (var i = 0; i < (max > 0 ? max : 255); i++) {
      final channel = await getChannel(i);
      if (channel == null) break;
      channels.add(channel);
    }
    return channels;
  }

  Future<MeshCoreChannel?> getChannel(int index) async {
    try {
      final f = await _single(MeshCoreCommands.getChannel(index), {
        MeshCoreResp.channelInfo,
      });
      return MeshCoreChannel.parse(f);
    } on MeshCoreException catch (e) {
      if (e.errorCode == MeshCoreErr.notFound) return null;
      rethrow;
    }
  }

  Future<void> setChannel(int index, String name, List<int> secret) => _single(
    MeshCoreCommands.setChannel(index, name, secret),
    {MeshCoreResp.ok},
  );

  Future<MeshCoreSentInfo> sendText(
    List<int> publicKey,
    String text, {
    required int timestamp,
    int attempt = 0,
  }) async {
    final f = await _single(
      MeshCoreCommands.sendText(
        publicKey,
        text,
        timestamp: timestamp,
        attempt: attempt,
      ),
      {MeshCoreResp.sent},
    );
    final info = MeshCoreSentInfo.parse(f);
    if (info == null) throw const MeshCoreException('Invalid send reply');
    return info;
  }

  Future<void> sendChannelText(
    int channelIndex,
    String text, {
    required int timestamp,
  }) => _single(
    MeshCoreCommands.sendChannelText(channelIndex, text, timestamp: timestamp),
    // The guide documents RESP_CODE_SENT; v1.16 firmware replies OK.
    {MeshCoreResp.ok, MeshCoreResp.sent},
  );

  Future<MeshCoreBattery?> getBattery() async {
    final f = await _single(MeshCoreCommands.getBattery(), {
      MeshCoreResp.battAndStorage,
    });
    return MeshCoreBattery.parse(f);
  }

  Future<void> sendAdvert({bool flood = true}) =>
      _single(MeshCoreCommands.sendSelfAdvert(flood: flood), {MeshCoreResp.ok});

  /// Pulls every queued message from the companion. Concurrent calls coalesce
  /// into one more pass so a message-waiting push is never missed.
  Future<void> drainMessages() async {
    if (_draining) {
      _drainAgain = true;
      return;
    }
    _draining = true;
    try {
      do {
        _drainAgain = false;
        for (var i = 0; i < 256 && !_closed; i++) {
          final f = await _single(MeshCoreCommands.syncNextMessage(), {
            MeshCoreResp.noMoreMessages,
            MeshCoreResp.contactMsgRecv,
            MeshCoreResp.channelMsgRecv,
            MeshCoreResp.contactMsgRecvV3,
            MeshCoreResp.channelMsgRecvV3,
            MeshCoreResp.channelDataRecv,
          });
          if (f[0] == MeshCoreResp.noMoreMessages) break;
          _emitMessage(f);
        }
      } while (_drainAgain && !_closed);
    } finally {
      _draining = false;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _failAll(const MeshCoreException('Connection closed'));
    await _frameSub.cancel();
    await _disconnectSub.cancel();
    await _transport.close();
    await _events.close();
  }

  // ---------------------------------------------------------------------------
  // Command queue
  // ---------------------------------------------------------------------------

  Future<Uint8List> _single(Uint8List frame, Set<int> done) async {
    final frames = await _request(frame, done);
    return frames.last;
  }

  Future<List<Uint8List>> _request(
    Uint8List frame,
    Set<int> done, {
    Set<int> partial = const {},
    Duration? timeout,
  }) {
    if (_closed) {
      return Future.error(const MeshCoreException('Not connected'));
    }
    final cmd = _PendingCommand(
      frame,
      done,
      partial,
      timeout ?? commandTimeout,
    );
    _queue.add(cmd);
    _pump();
    return cmd.completer.future;
  }

  void _pump() {
    if (_current != null || _queue.isEmpty || _closed) return;
    final cmd = _current = _queue.removeAt(0);
    _armTimer(cmd);
    _transport.sendFrame(cmd.frame).catchError((Object e) {
      _finish(cmd, error: MeshCoreException('Write failed: $e'));
    });
  }

  void _armTimer(_PendingCommand cmd) {
    cmd.timer?.cancel();
    cmd.timer = Timer(cmd.timeout, () {
      _finish(
        cmd,
        error: MeshCoreException(
          'Timed out waiting for reply to command ${cmd.frame[0]}',
        ),
      );
    });
  }

  void _finish(_PendingCommand cmd, {Object? error}) {
    if (!identical(_current, cmd)) return;
    cmd.timer?.cancel();
    _current = null;
    if (!cmd.completer.isCompleted) {
      if (error != null) {
        cmd.completer.completeError(error);
      } else {
        cmd.completer.complete(cmd.frames);
      }
    }
    _pump();
  }

  void _failAll(Object error) {
    final pending = [?_current, ..._queue];
    _current = null;
    _queue.clear();
    for (final cmd in pending) {
      cmd.timer?.cancel();
      if (!cmd.completer.isCompleted) cmd.completer.completeError(error);
    }
  }

  // ---------------------------------------------------------------------------
  // Inbound frames
  // ---------------------------------------------------------------------------

  void _onFrame(Uint8List f) {
    if (f.isEmpty || _closed) return;
    final code = f[0];
    if (MeshCorePush.isPush(code)) {
      _handlePush(f);
      return;
    }

    final cmd = _current;
    if (cmd != null) {
      if (code == MeshCoreResp.err) {
        final err = parseErrorCode(f);
        _finish(
          cmd,
          error: MeshCoreException(
            'Radio rejected command ${cmd.frame[0]}: '
            '${MeshCoreErr.describe(err)}',
            errorCode: err,
          ),
        );
        return;
      }
      if (code == MeshCoreResp.disabled) {
        _finish(cmd, error: const MeshCoreException('Command disabled'));
        return;
      }
      if (cmd.doneCodes.contains(code)) {
        cmd.frames.add(f);
        _finish(cmd);
        return;
      }
      if (cmd.partialCodes.contains(code)) {
        cmd.frames.add(f);
        _armTimer(cmd);
        return;
      }
    }

    // An unsolicited message frame (e.g. from an older firmware pushing
    // directly) is still delivered rather than dropped.
    if (MeshCoreResp.isMessage(code)) _emitMessage(f);
  }

  void _emitMessage(Uint8List f) {
    final msg = MeshCoreIncomingMessage.parse(f);
    if (msg != null) _add(MeshCoreMessageEvent(msg));
  }

  void _handlePush(Uint8List f) {
    switch (f[0]) {
      case MeshCorePush.msgWaiting:
        unawaited(drainMessages().catchError((_) {}));
      case MeshCorePush.newAdvert:
        final c = MeshCoreContact.parse(f);
        if (c != null) _add(MeshCoreContactEvent(c, true));
      case MeshCorePush.advert:
      case MeshCorePush.pathUpdated:
        final key = parsePushPublicKey(f);
        if (key != null) unawaited(_refreshContact(key));
      case MeshCorePush.sendConfirmed:
        final c = MeshCoreSendConfirmed.parse(f);
        if (c != null) _add(MeshCoreSendConfirmedEvent(c));
      case MeshCorePush.contactDeleted:
        final key = parsePushPublicKey(f);
        if (key != null) _add(MeshCoreContactDeletedEvent(key));
      case MeshCorePush.contactsFull:
        _add(const MeshCoreContactsFullEvent());
    }
  }

  Future<void> _refreshContact(Uint8List key) async {
    try {
      final c = await getContact(key);
      if (c != null) _add(MeshCoreContactEvent(c, false));
    } catch (_) {
      // Best effort; the contact list is refreshed again on reconnect.
    }
  }

  void _onDisconnected() {
    if (_closed) return;
    _failAll(const MeshCoreException('Disconnected'));
    _add(const MeshCoreDisconnectedEvent());
  }

  void _add(MeshCoreEvent e) {
    if (!_events.isClosed) _events.add(e);
  }
}
