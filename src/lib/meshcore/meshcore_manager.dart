/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

//
// meshcore_manager.dart - Owns the MeshCore companion connection (Data Broker
// device 204) in the host window and bridges it to the UI.
//
// Published on device 204 (stored, so late-opening tabs can read them):
//   MeshCoreState        {state, error, deviceId, deviceName}
//   MeshCoreInfo         companion identity, firmware, radio and battery
//   MeshCoreContacts     [{key, prefix, name, type, lat, lon, lastAdvert, onDevice}]
//   MeshCoreChannels     [{index, name, key, kind}] (secrets are never published)
//   MeshCoreScanResults  {scanning, devices, error}
// Events (not stored):
//   MeshCoreMessage, MeshCoreMessageList, MeshCoreMessagesCleared, MeshCoreResult
// Requests (UI -> manager): MeshCoreConnect, MeshCoreDisconnect, MeshCoreScan,
//   MeshCoreForgetPairing, MeshCoreSendDirect, MeshCoreSendGroup, MeshCoreResend,
//   MeshCoreAddChannel, MeshCoreRemoveChannel,
//   MeshCoreSendAdvert, MeshCoreRefresh, RequestMeshCoreMessages,
//   MeshCoreClearMessages
//

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/station_info.dart' show StationType;
import '../services/data_broker_client.dart';
import '../services/db/app_database.dart';
import '../services/notification_service.dart';
import '../services/notification_router.dart';
import 'meshcore_ble_transport.dart';
import 'meshcore_client.dart';
import 'meshcore_message.dart';
import 'meshcore_protocol.dart';
import 'meshcore_stream_transport.dart';

/// Data Broker device id for the MeshCore companion.
const int meshCoreDeviceId = 204;

/// How HTCommander reaches the companion radio.
abstract final class MeshCoreTransportKind {
  static const String ble = 'ble';
  static const String serial = 'serial';
  static const String tcp = 'tcp';
}

/// Connection states published in `MeshCoreState`.
abstract final class MeshCoreState {
  static const String disconnected = 'disconnected';
  static const String pairing = 'pairing';
  static const String connecting = 'connecting';
  static const String syncing = 'syncing';
  static const String connected = 'connected';
  static const String error = 'error';
}

/// Retry state for an outgoing direct message awaiting an acknowledgment.
class _PendingDirect {
  final MeshCoreMessage message;
  final int attempt;
  final Timer timer;

  _PendingDirect(this.message, this.attempt, this.timer);
}

class MeshCoreManager {
  static const int _maxDirectAttempts = 3;
  static const int _maxHistory = 2000;
  static const Duration _minRetry = Duration(seconds: 5);
  static const Duration _maxRetry = Duration(minutes: 1);

  final DataBrokerClient _broker = DataBrokerClient();

  MeshCoreClient? _client;
  StreamSubscription<MeshCoreEvent>? _eventSub;
  String _state = MeshCoreState.disconnected;
  String? _error;
  String? _deviceId;
  String _deviceName = '';
  String _transport = MeshCoreTransportKind.ble;
  bool _initialized = false;

  /// Mirrors the 'MeshCoreSupport' feature setting.
  bool _enabled = false;

  /// Set when the user asked to disconnect, which suppresses reconnection.
  bool _userDisconnected = true;
  int _generation = 0;
  Timer? _retryTimer;
  Timer? _batteryTimer;
  Duration _retryDelay = _minRetry;

  MeshCoreSelfInfo? _self;
  MeshCoreDeviceInfo? _device;
  MeshCoreBattery? _battery;

  /// Contacts keyed by full public-key hex.
  final Map<String, MeshCoreContact> _contacts = {};

  /// Keys of contacts stored on the companion (required for direct messages).
  final Set<String> _onDevice = {};
  List<MeshCoreChannel> _channels = const [];

  final List<MeshCoreMessage> _messages = [];
  final Set<String> _seen = {};

  /// Every ACK tag sent for each in-flight direct message.
  final Map<int, MeshCoreMessage> _ackTags = {};

  /// Pending retry per message id.
  final Map<int, _PendingDirect> _retries = {};
  int _localId = 0;

  bool _scanning = false;

  /// MeshCore users from the address book: public-key hex -> name.
  Map<String, String> _book = const {};
  bool _syncingBook = false;

  void init() {
    if (_initialized) return;
    _initialized = true;

    _broker.subscribeMultiple(
      deviceId: meshCoreDeviceId,
      names: const [
        'MeshCoreConnect',
        'MeshCoreDisconnect',
        'MeshCoreScan',
        'MeshCoreForgetPairing',
        'MeshCoreSendDirect',
        'MeshCoreSendGroup',
        'MeshCoreResend',
        'MeshCoreAddChannel',
        'MeshCoreRemoveChannel',
        'MeshCoreSendAdvert',
        'MeshCoreRefresh',
        'RequestMeshCoreMessages',
        'MeshCoreClearMessages',
      ],
      callback: _onRequest,
    );

    _publishState();
    _publishScan(const []);
    unawaited(_loadHistory());

    _loadAddressBook(_broker.getValueDynamic(0, 'Stations', null));
    _broker.subscribe(
      deviceId: 0,
      name: 'Stations',
      callback: (_, _, data) {
        _loadAddressBook(data);
        unawaited(_syncAddressBook());
      },
    );

    // MeshCore is opt-in (Settings > Application > Features).
    _enabled = (_broker.getValue<int>(0, 'MeshCoreSupport', 0) ?? 0) == 1;
    _broker.subscribe(
      deviceId: 0,
      name: 'MeshCoreSupport',
      callback: (_, _, data) => _setEnabled(data == 1),
    );
    if (_enabled) _autoConnect();
  }

  void _autoConnect() {
    final last = _lastDevice();
    final auto = (_broker.getValue<int>(0, 'MeshCoreAutoConnect', 1) ?? 1) != 0;
    if (auto && last != null && _transportSupported(last.transport)) {
      _userDisconnected = false;
      _retryDelay = _minRetry;
      unawaited(_connect(last.transport, last.id, last.name, ''));
    }
  }

  static bool _transportSupported(String transport) => switch (transport) {
    MeshCoreTransportKind.serial => meshCoreSerialSupported,
    MeshCoreTransportKind.tcp => meshCoreTcpSupported,
    _ =>
      MeshCoreBleTransport.isSupported &&
          MeshCoreBleTransport.supportsAutoConnect,
  };

  void _setEnabled(bool enabled) {
    if (enabled == _enabled) return;
    _enabled = enabled;
    if (enabled) {
      _autoConnect();
    } else {
      _userDisconnected = true;
      _retryTimer?.cancel();
      _generation++;
      unawaited(_teardown().then((_) => _setState(MeshCoreState.disconnected)));
    }
  }

  // ---------------------------------------------------------------------------
  // Requests
  // ---------------------------------------------------------------------------

  void _onRequest(int deviceId, String name, Object? data) {
    if (!_enabled) return;
    final map = data is Map ? data : const {};
    switch (name) {
      case 'MeshCoreConnect':
        final id = map['id']?.toString() ?? '';
        if (id.isEmpty) return;
        _userDisconnected = false;
        _retryDelay = _minRetry;
        unawaited(
          _connect(
            map['transport']?.toString() ?? MeshCoreTransportKind.ble,
            id,
            map['name']?.toString() ?? id,
            map['pin']?.toString() ?? '',
          ),
        );
      case 'MeshCoreDisconnect':
        _userDisconnected = true;
        _retryTimer?.cancel();
        _generation++;
        unawaited(
          _teardown().then((_) => _setState(MeshCoreState.disconnected)),
        );
      case 'MeshCoreScan':
        unawaited(_scan());
      case 'MeshCoreForgetPairing':
        final id = map['id']?.toString() ?? _deviceId ?? '';
        if (id.isNotEmpty) {
          unawaited(
            MeshCoreBleTransport.forgetPairing(id).then(
              (ok) => _result('forgetPairing', ok, ok ? null : 'Not paired'),
            ),
          );
        }
      case 'MeshCoreSendDirect':
        unawaited(
          _sendDirect(
            map['peer']?.toString() ?? '',
            map['text']?.toString() ?? '',
          ),
        );
      case 'MeshCoreSendGroup':
        unawaited(
          _sendGroup(
            map['peer']?.toString() ?? '',
            map['text']?.toString() ?? '',
          ),
        );
      case 'MeshCoreResend':
        unawaited(_resend((map['id'] as num?)?.toInt() ?? 0));
      case 'MeshCoreAddChannel':
        unawaited(
          _addChannel(
            map['name']?.toString() ?? '',
            map['secret']?.toString() ?? '',
          ),
        );
      case 'MeshCoreRemoveChannel':
        unawaited(_removeChannel(map['peer']?.toString() ?? ''));
      case 'MeshCoreSendAdvert':
        unawaited(_sendAdvert());
      case 'MeshCoreRefresh':
        unawaited(_refresh());
      case 'RequestMeshCoreMessages':
        _publishMessageList();
      case 'MeshCoreClearMessages':
        unawaited(
          _clearMessages(map['kind']?.toString(), map['peer']?.toString()),
        );
    }
  }

  // ---------------------------------------------------------------------------
  // Connection
  // ---------------------------------------------------------------------------

  ({String transport, String id, String name})? _lastDevice() {
    final raw = _broker.getValueDynamic(0, 'MeshCoreLastDevice', null);
    if (raw is! Map) return null;
    final id = raw['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    return (
      // Saved before USB/Wi-Fi support existed means Bluetooth.
      transport: raw['transport']?.toString() ?? MeshCoreTransportKind.ble,
      id: id,
      name: raw['name']?.toString() ?? id,
    );
  }

  /// Opens the link. [id] is the Bluetooth device id, the serial port name, or
  /// "host:port" for TCP.
  Future<MeshCoreTransport> _openTransport(
    String transport,
    String id,
    String pin,
    int gen,
  ) async {
    switch (transport) {
      case MeshCoreTransportKind.serial:
        return MeshCoreSerialTransport.open(id);
      case MeshCoreTransportKind.tcp:
        final target = parseMeshCoreTcpTarget(id);
        if (target == null) {
          throw MeshCoreException('Invalid address "$id"');
        }
        return MeshCoreTcpTransport.connect(target.host, target.port);
      default:
        return MeshCoreBleTransport.connect(
          id,
          pin: pin,
          onStatus: (s) {
            if (gen == _generation) {
              _setState(
                s == 'pairing'
                    ? MeshCoreState.pairing
                    : MeshCoreState.connecting,
              );
            }
          },
        );
    }
  }

  /// Device query with retries for wired links: opening a USB port can reset
  /// an ESP32 board, which then needs a few seconds to boot.
  Future<MeshCoreDeviceInfo> _queryDevice(
    MeshCoreClient client,
    String transport,
  ) async {
    final attempts = transport == MeshCoreTransportKind.ble ? 1 : 3;
    for (var i = 1; ; i++) {
      try {
        return await client.queryDevice();
      } on MeshCoreException {
        if (i >= attempts || client.isClosed) rethrow;
      }
    }
  }

  Future<void> _connect(
    String transport,
    String id,
    String name,
    String pin,
  ) async {
    _retryTimer?.cancel();
    await _teardown();
    final gen = ++_generation;
    _transport = transport;
    _deviceId = id;
    _deviceName = name;
    _setState(MeshCoreState.connecting);
    _log('Connecting to $name ($transport $id)');

    MeshCoreClient? client;
    try {
      final link = await _openTransport(transport, id, pin, gen);
      if (gen != _generation) {
        await link.close();
        return;
      }
      client = MeshCoreClient(link);
      _client = client;
      _eventSub = client.events.listen(_onEvent);
      _setState(MeshCoreState.syncing);

      _device = await _queryDevice(client, transport);
      _self = await client.appStart();
      try {
        await client.syncTime();
      } catch (e) {
        _log('Clock sync failed: $e');
      }
      await _syncContacts(client);
      _channels = await client.getChannels();
      _battery = await _readBattery(client);
      if (gen != _generation) return;

      _broker.dispatch(
        deviceId: 0,
        name: 'MeshCoreLastDevice',
        data: {'transport': transport, 'id': id, 'name': name},
      );
      _retryDelay = _minRetry;
      _setState(MeshCoreState.connected);
      _publishInfo();
      _publishContacts();
      _publishChannels();
      await _syncAddressBook();
      _log(
        'Connected to ${_self!.name} (${_device!.model} ${_device!.version}), '
        '${_contacts.length} contact(s), '
        '${_channels.where((c) => !c.isEmpty).length} channel(s)',
      );
      _batteryTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
        final c = _client;
        if (c == null) return;
        _battery = await _readBattery(c);
        _publishInfo();
      });
      await client.drainMessages();
    } catch (e) {
      if (gen != _generation) return;
      _logError('Connection failed: $e');
      await _teardown();
      _setState(MeshCoreState.error, error: e.toString());
      if (e is! MeshCorePairingException) _scheduleReconnect();
    }
  }

  Future<MeshCoreBattery?> _readBattery(MeshCoreClient client) async {
    try {
      return await client.getBattery();
    } catch (_) {
      return _battery;
    }
  }

  void _scheduleReconnect() {
    if (_userDisconnected || _deviceId == null) return;
    _retryTimer?.cancel();
    final delay = _retryDelay;
    _retryDelay = Duration(
      milliseconds: math.min(
        _retryDelay.inMilliseconds * 2,
        _maxRetry.inMilliseconds,
      ),
    );
    _retryTimer = Timer(delay, () {
      if (_userDisconnected || _deviceId == null) return;
      unawaited(_connect(_transport, _deviceId!, _deviceName, ''));
    });
  }

  Future<void> _teardown() async {
    _batteryTimer?.cancel();
    _batteryTimer = null;
    for (final p in _retries.values) {
      p.timer.cancel();
      _markFailed(p.message);
    }
    _retries.clear();
    _ackTags.clear();
    await _eventSub?.cancel();
    _eventSub = null;
    final client = _client;
    _client = null;
    if (client != null) {
      try {
        await client.close();
      } catch (_) {}
    }
  }

  void _onEvent(MeshCoreEvent e) {
    switch (e) {
      case MeshCoreMessageEvent(:final message):
        unawaited(_onIncoming(message));
      case MeshCoreContactEvent(:final contact, :final isNew):
        _contacts[contact.publicKeyHex] = contact;
        // A "new advert" push means the radio did NOT store the contact
        // (auto-add off, hop limit or full table); stored ones arrive as
        // plain adverts.
        if (!isNew) _onDevice.add(contact.publicKeyHex);
        _publishContacts();
      case MeshCoreContactDeletedEvent(:final publicKey):
        final key = bytesToHex(publicKey);
        _contacts.remove(key);
        _onDevice.remove(key);
        _publishContacts();
      case MeshCoreContactsFullEvent():
        _logError('The MeshCore contact table is full');
      case MeshCoreSendConfirmedEvent(:final confirmation):
        _onDelivered(confirmation.ackTag);
      case MeshCoreDisconnectedEvent():
        _logError('Connection to $_deviceName lost');
        _generation++;
        unawaited(
          _teardown().then((_) {
            _setState(MeshCoreState.disconnected, error: 'Connection lost');
            _scheduleReconnect();
          }),
        );
    }
  }

  Future<void> _syncContacts(MeshCoreClient client) async {
    final contacts = await client.getContacts();
    _contacts.clear();
    _onDevice.clear();
    for (final c in contacts) {
      _contacts[c.publicKeyHex] = c;
      _onDevice.add(c.publicKeyHex);
    }
  }

  Future<void> _refresh() async {
    final client = _client;
    if (client == null) return;
    try {
      await _syncContacts(client);
      _channels = await client.getChannels();
      _battery = await _readBattery(client);
      _publishInfo();
      _publishContacts();
      _publishChannels();
      await _syncAddressBook();
      await client.drainMessages();
    } catch (e) {
      _logError('Refresh failed: $e');
    }
  }

  Future<void> _scan() async {
    if (_scanning) return;
    _scanning = true;
    var devices = <MeshCoreBleDevice>[];
    _publishScan(devices);
    try {
      await MeshCoreBleTransport.scan(
        onUpdate: (d) {
          devices = d;
          _publishScan(devices);
        },
      );
      _scanning = false;
      _publishScan(devices);
    } catch (e) {
      _scanning = false;
      _publishScan(devices, error: e.toString());
    }
  }

  Future<void> _sendAdvert() async {
    final client = _client;
    if (client == null) return;
    try {
      await client.sendAdvert(flood: true);
      _result('advert', true, null);
    } catch (e) {
      _result('advert', false, e.toString());
    }
  }

  // ---------------------------------------------------------------------------
  // Messages
  // ---------------------------------------------------------------------------

  Future<void> _loadHistory() async {
    final dao = AppDatabase.instance?.meshcore;
    if (dao == null) return;
    try {
      final List<MeshCoreMessage> history = await dao.recent(_maxHistory);
      // Anything still in flight when the app closed can no longer be
      // acknowledged.
      for (final m in history) {
        if (m.outgoing &&
            (m.state == MeshCoreDelivery.pending ||
                m.state == MeshCoreDelivery.sent) &&
            m.kind == MeshCoreKind.user) {
          m.state = MeshCoreDelivery.failed;
          unawaited(_safeUpdate(dao, m));
        }
        if (!m.outgoing) {
          _seen.add(_dedupeKey(m.kind, m.peer, m.senderTime, m.text));
        }
      }
      _messages.insertAll(0, history);
      _publishMessageList();
    } catch (e) {
      _logError('Unable to load message history: $e');
    }
  }

  static String _dedupeKey(String kind, String peer, int ts, String text) =>
      '$kind|$peer|$ts|$text';

  Future<void> _onIncoming(MeshCoreIncomingMessage m) async {
    if (m.txtType == MeshCoreTxtType.cliData) return;
    final String kind;
    final String peer;
    final String sender;
    final String text;
    if (m.isChannel) {
      kind = MeshCoreKind.group;
      final ch = _channelByIndex(m.channelIndex);
      peer = ch?.key ?? 'slot${m.channelIndex}';
      final split = splitChannelText(m.text);
      sender = split.sender ?? '';
      text = split.text;
    } else {
      kind = MeshCoreKind.user;
      peer = m.senderPrefixHex ?? '';
      sender = _contactByPrefix(peer)?.name ?? peer;
      text = m.text;
    }
    if (!_seen.add(_dedupeKey(kind, peer, m.senderTimestamp, text))) return;

    final msg = MeshCoreMessage(
      time: DateTime.now(),
      senderTime: m.senderTimestamp,
      kind: kind,
      peer: peer,
      outgoing: false,
      sender: sender,
      text: text,
      pathLen: m.pathLen,
      snr: m.snr,
      state: MeshCoreDelivery.received,
    );
    await _store(msg);
    _publishMessage(msg);
    _notifyIfDirect(msg);
  }

  /// Raises a system notification for an incoming direct message (one
  /// addressed to this companion). Group/channel traffic never notifies.
  /// [NotificationService] suppresses it while the app is in the foreground
  /// and honours the "Message Notifications" setting.
  void _notifyIfDirect(MeshCoreMessage msg) {
    if (!isDirectMessageToUs(msg) || msg.text.trim().isEmpty) return;
    final bookName = _bookNameForPeer(msg.peer);
    final from = (bookName != null && bookName.isNotEmpty)
        ? bookName
        : msg.sender;
    unawaited(
      NotificationService.instance.showMessage(
        title: from.isNotEmpty
            ? 'MeshCore message from $from'
            : 'MeshCore message',
        body: msg.text,
        payload: meshCoreNotificationPayload(msg.conversationKey),
      ),
    );
  }

  /// Address-book name for a direct-message peer (key prefix), if unique.
  String? _bookNameForPeer(String peer) {
    final matches = _book.entries.where(
      (e) => meshCorePeerForKey(e.key) == peer,
    );
    return matches.length == 1 ? matches.first.value : null;
  }

  Future<void> _sendDirect(String peer, String text) async {
    text = text.trim();
    if (peer.isEmpty || text.isEmpty) return;
    final msg = MeshCoreMessage(
      time: DateTime.now(),
      senderTime: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      kind: MeshCoreKind.user,
      peer: peer,
      outgoing: true,
      sender: _self?.name ?? '',
      text: utf8DecodeTruncated(text, MeshCoreConst.maxTextBytes),
      state: MeshCoreDelivery.pending,
    );
    await _store(msg);
    _publishMessage(msg);
    await _attemptDirect(msg, 0);
  }

  Future<void> _attemptDirect(MeshCoreMessage msg, int attempt) async {
    final client = _client;
    final contact =
        _contactByPrefix(msg.peer) ?? _bookContactByPrefix(msg.peer);
    if (client == null) {
      _markFailed(msg);
      return;
    }
    try {
      final key = contact?.publicKey ?? hexToBytes(msg.peer);
      if (contact != null && !_onDevice.contains(contact.publicKeyHex)) {
        await client.addOrUpdateContact(contact);
        _onDevice.add(contact.publicKeyHex);
      }
      // The last attempt drops the cached route so the message is flooded.
      if (attempt == _maxDirectAttempts - 1 && contact != null) {
        try {
          await client.resetPath(contact.publicKey);
        } catch (_) {}
      }
      final info = await client.sendText(
        key,
        msg.text,
        timestamp: msg.senderTime,
        attempt: attempt,
      );
      msg.ackTag = info.ackTag;
      // Each attempt has its own ACK tag. Keep all of them mapped to the
      // message so a late ACK for an earlier attempt still counts.
      _ackTags[info.ackTag] = msg;
      if (msg.state != MeshCoreDelivery.delivered) {
        _updateState(msg, MeshCoreDelivery.sent);
        final wait = Duration(
          milliseconds: (info.timeoutMs * 1.5).round().clamp(8000, 60000),
        );
        _retries[msg.id]?.timer.cancel();
        _retries[msg.id] = _PendingDirect(
          msg,
          attempt,
          Timer(wait, () => _onAckTimeout(msg.id)),
        );
      }
    } catch (e) {
      _logError('Direct message failed: $e');
      _markFailed(msg);
    }
  }

  void _onAckTimeout(int messageId) {
    final pending = _retries.remove(messageId);
    if (pending == null) return;
    if (pending.attempt + 1 < _maxDirectAttempts && _client != null) {
      unawaited(_attemptDirect(pending.message, pending.attempt + 1));
    } else {
      _markFailed(pending.message);
    }
  }

  void _onDelivered(int ackTag) {
    final msg = _ackTags[ackTag];
    if (msg == null) return;
    _ackTags.removeWhere((_, m) => identical(m, msg));
    _retries.remove(msg.id)?.timer.cancel();
    if (msg.state != MeshCoreDelivery.delivered) {
      _updateState(msg, MeshCoreDelivery.delivered);
    }
  }

  Future<void> _sendGroup(String peer, String text) async {
    text = text.trim();
    final ch = _channelByKey(peer);
    if (ch == null || text.isEmpty) return;
    final selfName = _self?.name ?? '';
    final msg = MeshCoreMessage(
      time: DateTime.now(),
      senderTime: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      kind: MeshCoreKind.group,
      peer: peer,
      outgoing: true,
      sender: selfName,
      text: utf8DecodeTruncated(text, maxChannelTextBytes(selfName)),
      state: MeshCoreDelivery.pending,
    );
    await _store(msg);
    _publishMessage(msg);
    await _attemptGroup(msg, ch);
  }

  Future<void> _attemptGroup(MeshCoreMessage msg, MeshCoreChannel ch) async {
    final client = _client;
    if (client == null) {
      _markFailed(msg);
      return;
    }
    try {
      await client.sendChannelText(
        ch.index,
        msg.text,
        timestamp: msg.senderTime,
      );
      _updateState(msg, MeshCoreDelivery.sent);
    } catch (e) {
      _logError('Group message failed: $e');
      _markFailed(msg);
    }
  }

  Future<void> _resend(int id) async {
    final msg = _messages.where((m) => m.id == id).firstOrNull;
    if (msg == null || !msg.outgoing || msg.state != MeshCoreDelivery.failed) {
      return;
    }
    _updateState(msg, MeshCoreDelivery.pending);
    // A fresh timestamp makes the packet differ from earlier attempts, which
    // repeaters and the recipient would otherwise drop as already seen.
    msg.senderTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (msg.kind == MeshCoreKind.user) {
      await _attemptDirect(msg, 0);
    } else {
      final ch = _channelByKey(msg.peer);
      if (ch == null) {
        _markFailed(msg);
      } else {
        await _attemptGroup(msg, ch);
      }
    }
  }

  Future<void> _store(MeshCoreMessage msg) async {
    final dao = AppDatabase.instance?.meshcore;
    if (dao != null) {
      try {
        msg.id = await dao.insert(msg);
      } catch (e) {
        _logError('Unable to store message: $e');
      }
    }
    if (msg.id == 0) msg.id = --_localId;
    _messages.add(msg);
    if (_messages.length > _maxHistory) {
      _messages.removeRange(0, _messages.length - _maxHistory);
    }
  }

  void _markFailed(MeshCoreMessage msg) =>
      _updateState(msg, MeshCoreDelivery.failed);

  void _updateState(MeshCoreMessage msg, String state) {
    msg.state = state;
    final dao = AppDatabase.instance?.meshcore;
    if (dao != null && msg.id > 0) {
      unawaited(_safeUpdate(dao, msg));
    }
    _publishMessage(msg);
  }

  Future<void> _safeUpdate(dynamic dao, MeshCoreMessage msg) async {
    try {
      await dao.updateState(msg.id, msg.state, msg.ackTag);
    } catch (_) {}
  }

  Future<void> _clearMessages(String? kind, String? peer) async {
    if (kind == null || peer == null) {
      _messages.clear();
    } else {
      _messages.removeWhere((m) => m.kind == kind && m.peer == peer);
    }
    final dao = AppDatabase.instance?.meshcore;
    if (dao != null) {
      try {
        await dao.clear(kind: kind, peer: peer);
      } catch (_) {}
    }
    _broker.dispatch(
      deviceId: meshCoreDeviceId,
      name: 'MeshCoreMessagesCleared',
      data: {'kind': kind, 'peer': peer},
      store: false,
    );
  }

  // ---------------------------------------------------------------------------
  // Contacts and channels
  // ---------------------------------------------------------------------------

  MeshCoreContact? _contactByPrefix(String prefix) {
    MeshCoreContact? match;
    for (final c in _contacts.values) {
      if (c.prefixHex == prefix) {
        // An ambiguous prefix must not be attributed to either contact.
        if (match != null) return null;
        match = c;
      }
    }
    return match;
  }

  MeshCoreChannel? _channelByIndex(int? index) =>
      _channels.where((c) => c.index == index && !c.isEmpty).firstOrNull;

  /// An address-book user matching [prefix] that is not yet on the radio,
  /// as a contact record that can be added before sending.
  MeshCoreContact? _bookContactByPrefix(String prefix) {
    final matches = _book.keys.where((k) => meshCorePeerForKey(k) == prefix);
    if (matches.length != 1) return null;
    return MeshCoreContact(
      publicKey: hexToBytes(matches.first),
      type: MeshCoreAdvType.chat,
      name: _book[matches.first]!,
    );
  }

  MeshCoreChannel? _channelByKey(String key) =>
      _channels.where((c) => !c.isEmpty && c.key == key).firstOrNull;

  /// Adds address-book MeshCore users that are missing from the companion's
  /// contact table, so direct messages to them can be sent. Contacts already
  /// on the radio are left alone: their names come from the node's own adverts.
  Future<void> _syncAddressBook() async {
    final client = _client;
    if (client == null || _state != MeshCoreState.connected || _syncingBook) {
      return;
    }
    _syncingBook = true;
    var changed = false;
    try {
      for (final entry in _book.entries) {
        if (_client != client) return;
        final key = entry.key;
        if (_onDevice.contains(key) || key == _self?.publicKeyHex) continue;
        try {
          final contact = MeshCoreContact(
            publicKey: hexToBytes(key),
            type: MeshCoreAdvType.chat,
            name: entry.value,
          );
          await client.addOrUpdateContact(contact);
          _contacts[key] =
              await client.getContact(contact.publicKey) ?? contact;
          _onDevice.add(key);
          changed = true;
        } on MeshCoreException catch (e) {
          _logError('Unable to add ${entry.value} to the radio: $e');
          if (e.errorCode == MeshCoreErr.tableFull) break;
        }
      }
    } finally {
      _syncingBook = false;
      if (changed) _publishContacts();
    }
  }

  /// Reads MeshCore users (public key -> name) from the address book.
  void _loadAddressBook(Object? raw) {
    final book = <String, String>{};
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final type = item['StationType'] ?? item['stationType'];
        if (type != StationType.meshCore.index &&
            '$type'.toLowerCase() != StationType.meshCore.name.toLowerCase()) {
          continue;
        }
        final key = normalizePublicKeyHex(
          (item['Callsign'] ?? item['callsign'] ?? '').toString(),
        );
        if (key == null) continue;
        book[key] = (item['Name'] ?? item['name'] ?? '').toString().trim();
      }
    }
    _book = book;
  }

  Future<void> _addChannel(String name, String secretHex) async {
    final client = _client;
    final secret = normalizeChannelSecretHex(secretHex);
    name = name.trim();
    if (client == null || secret == null || name.isEmpty) {
      _result('addChannel', false, 'Not connected or invalid group');
      return;
    }
    try {
      _channels = await client.getChannels();
      final key = channelKeyForSecret(hexToBytes(secret));
      if (_channelByKey(key) != null) {
        _publishChannels();
        _result('addChannel', true, null, peer: key);
        return;
      }
      final free = _channels.where((c) => c.isEmpty).firstOrNull;
      if (free == null) {
        _result('addChannel', false, 'No free group slots on the radio');
        return;
      }
      await client.setChannel(free.index, name, hexToBytes(secret));
      final readBack = await client.getChannel(free.index);
      if (readBack == null || readBack.key != key) {
        throw const MeshCoreException('The radio did not store the group');
      }
      _channels = [
        for (final c in _channels) c.index == free.index ? readBack : c,
      ];
      _publishChannels();
      _result('addChannel', true, null, peer: key);
    } catch (e) {
      _result('addChannel', false, e.toString());
    }
  }

  Future<void> _removeChannel(String key) async {
    final client = _client;
    final ch = _channelByKey(key);
    if (client == null || ch == null) return;
    try {
      await client.setChannel(ch.index, '', Uint8List(16));
      _channels = await client.getChannels();
      _publishChannels();
    } catch (e) {
      _logError('Unable to remove group: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Publishing
  // ---------------------------------------------------------------------------

  void _setState(String state, {String? error}) {
    _state = state;
    _error = error;
    _publishState();
  }

  void _publishState() {
    _broker.dispatch(
      deviceId: meshCoreDeviceId,
      name: 'MeshCoreState',
      data: {
        'state': _state,
        'error': _error,
        'deviceId': _deviceId,
        'deviceName': _deviceName,
        'transport': _transport,
      },
    );
  }

  void _publishInfo() {
    final self = _self;
    final dev = _device;
    _broker.dispatch(
      deviceId: meshCoreDeviceId,
      name: 'MeshCoreInfo',
      data: self == null
          ? null
          : {
              'name': self.name,
              'publicKey': self.publicKeyHex,
              'lat': self.latitude,
              'lon': self.longitude,
              'freqMhz': self.radioFreqMhz,
              'bwKhz': self.radioBandwidthKhz,
              'sf': self.spreadingFactor,
              'cr': self.codingRate,
              'txPower': self.txPowerDbm,
              'model': dev?.model,
              'version': dev?.version,
              'buildDate': dev?.buildDate,
              'maxContacts': dev?.maxContacts,
              'maxChannels': dev?.maxChannels,
              'batteryMv': _battery?.millivolts,
            },
    );
  }

  void _publishContacts() {
    final list = [
      for (final c in _contacts.values)
        {
          'key': c.publicKeyHex,
          'prefix': c.prefixHex,
          'name': c.name,
          'type': c.type,
          'lat': c.latitude,
          'lon': c.longitude,
          'lastAdvert': c.lastAdvert,
          'lastMod': c.lastModified,
          'onDevice': _onDevice.contains(c.publicKeyHex),
        },
    ];
    _broker.dispatch(
      deviceId: meshCoreDeviceId,
      name: 'MeshCoreContacts',
      data: list,
      allowEmpty: true,
    );
  }

  void _publishChannels() {
    final list = [
      for (final c in _channels)
        if (!c.isEmpty)
          {'index': c.index, 'name': c.name, 'key': c.key, 'kind': c.kind.name},
    ];
    _broker.dispatch(
      deviceId: meshCoreDeviceId,
      name: 'MeshCoreChannels',
      data: list,
      allowEmpty: true,
    );
  }

  void _publishScan(List<MeshCoreBleDevice> devices, {String? error}) {
    _broker.dispatch(
      deviceId: meshCoreDeviceId,
      name: 'MeshCoreScanResults',
      data: {
        'scanning': _scanning,
        'devices': [for (final d in devices) d.toJson()],
        'error': error,
      },
    );
  }

  void _publishMessage(MeshCoreMessage msg) {
    _broker.dispatch(
      deviceId: meshCoreDeviceId,
      name: 'MeshCoreMessage',
      data: msg.toJson(),
      store: false,
    );
  }

  void _publishMessageList() {
    _broker.dispatch(
      deviceId: meshCoreDeviceId,
      name: 'MeshCoreMessageList',
      data: [for (final m in _messages) m.toJson()],
      store: false,
    );
  }

  void _result(String op, bool ok, String? error, {String? peer}) {
    _broker.dispatch(
      deviceId: meshCoreDeviceId,
      name: 'MeshCoreResult',
      data: {'op': op, 'ok': ok, 'error': error, 'peer': peer},
      store: false,
    );
  }

  void _log(String msg) => _broker.logInfo('[MeshCore] $msg');

  void _logError(String msg) => _broker.logError('[MeshCore] $msg');
}

/// Truncates [text] to at most [maxBytes] UTF-8 bytes on a character boundary,
/// matching exactly what the radio will transmit.
String utf8DecodeTruncated(String text, int maxBytes) =>
    utf8.decode(utf8Truncate(text, maxBytes));
