/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

//
// aprs_cloud_service.dart - Registers this station with the HTCloudServer push
// backend (aprs.meshcentral.com) and delivers APRS messages addressed to the
// station as push notifications, even when the app is closed.
//
// The service is Android-only at runtime: it relies on Firebase Cloud Messaging
// and the bundled android/app/google-services.json. On other native platforms
// (Windows/macOS/Linux/iOS) it is a no-op because no Firebase configuration is
// shipped for them. The web build uses aprs_cloud_service_stub.dart instead.
//
// Flow:
//   1. The user enables "Push notifications" in Settings. This is only allowed
//      once APRS-IS is enabled with a valid passcode, which doubles as the
//      server authentication token (AprsUtil.aprsValidationCode).
//   2. The service obtains an FCM token and POSTs it to /v1/register together
//      with the callsign/SSID and passcode, pulling any message backlog.
//   3. Received messages are surfaced to the APRS + Comms tabs via the existing
//      `AprsMessageReceived` broker event. Backlog is injected silently; new
//      messages arrive as push notifications shown by the OS (background) or are
//      pulled with /v1/sync when the app is foregrounded.
//

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:crypto/crypto.dart' show sha256;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:http/http.dart' as http;

import '../aprs/aprs_util.dart';
import 'data_broker_client.dart';

/// Background isolate handler for FCM messages received while the app is not in
/// the foreground. The OS displays notification-type messages itself; this
/// handler only needs to exist (and initialize Firebase) so the plugin does not
/// drop the callback. It runs in a separate isolate with no access to the app's
/// DataBroker, so it performs no work.
@pragma('vm:entry-point')
Future<void> aprsCloudBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Best-effort: nothing to do if initialization fails in the background.
  }
}

/// Owns the connection to the HTCloudServer push backend. Registered in
/// `main()` on Android and driven entirely by settings changes.
class AprsCloudService {
  AprsCloudService._();

  /// Singleton instance.
  static final AprsCloudService instance = AprsCloudService._();

  /// HTCloudServer host and base URL. HTTPS on 443.
  static const String _host = 'aprs.meshcentral.com';
  static const int _port = 443;
  static String get _baseUrl => 'https://$_host:$_port';

  /// Reported to the server's push dispatcher so it routes via FCM.
  static const String _platform = 'android';

  /// Broker device id the APRS + Map tabs listen on for AprsFrame events.
  static const int _aprsDeviceId = 1;

  /// How often to refresh the registration (and rotated token) with the server.
  static const Duration _heartbeatInterval = Duration(hours: 6);

  /// Network timeout for a single request.
  static const Duration _requestTimeout = Duration(seconds: 20);

  final DataBrokerClient _broker = DataBrokerClient();
  final http.Client _http = http.Client();

  bool _initialized = false;
  bool _firebaseReady = false;
  bool _listenersReady = false;
  bool _reconciling = false;

  /// Identity currently registered with the server, used to detect changes and
  /// to unregister cleanly when settings change.
  String? _registeredCallsign;
  int? _registeredSsid;
  String? _registeredToken;

  /// The most recent FCM registration token.
  String? _fcmToken;

  /// Identities of messages already injected this session, so overlapping
  /// register/sync pulls (or a live APRS-IS copy) never show the same message
  /// twice. Bounded FIFO to cap memory.
  final Set<String> _injectedKeys = <String>{};
  final List<String> _injectedOrder = <String>[];
  static const int _maxInjectedKeys = 500;

  /// DataBroker key (device 0) of the persisted map of avatars learned from push
  /// notifications, keyed by uppercased callsign -> { icon, image, hash, ts }.
  static const String _cloudAvatarsKey = 'AprsCloudAvatars';
  static const int _maxCloudAvatars = 500;

  Timer? _debounce;
  Timer? _heartbeat;

  /// Whether the platform can run the cloud push client. Android only.
  static bool get _supported => !kIsWeb && Platform.isAndroid;

  /// Subscribes to the settings that control the connection and reconciles once.
  void init() {
    if (_initialized) return;
    _initialized = true;
    if (!_supported) return;

    _broker.subscribeMultiple(
      deviceId: 0,
      names: const [
        'CallSign',
        'StationId',
        'AprsIsEnabled',
        'AprsIsPasscode',
        'AprsCloudNotifications',
        'AvatarIcon',
        'AvatarImage',
      ],
      callback: (_, _, _) => _scheduleReconcile(),
    );

    _scheduleReconcile();
  }

  /// Coalesces the burst of setting dispatches emitted when the settings dialog
  /// is saved into a single reconcile.
  void _scheduleReconcile() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      unawaited(_reconcile());
    });
  }

  /// The passcode expected for the current callsign (server auth token).
  String get _passcode {
    final callsign = _broker.getValue<String>(0, 'CallSign', '') ?? '';
    return callsign.isEmpty ? '' : AprsUtil.aprsValidationCode(callsign);
  }

  /// Chosen built-in avatar logo name, or '' when none is set.
  String get _avatarIcon =>
      (_broker.getValue<String>(0, 'AvatarIcon', '') ?? '').trim();

  /// Base64 custom avatar image, or '' when none is set.
  String get _avatarImage =>
      (_broker.getValue<String>(0, 'AvatarImage', '') ?? '').trim();

  /// Stable identity of the current avatar, used to detect changes. Empty when
  /// the operator has no avatar. A custom image is hashed (so a large picture is
  /// only re-sent when it actually changes); a built-in icon needs no image hash
  /// — its name is already a compact identity, so `icon:<name>` is used directly.
  String get _avatarHash {
    final icon = _avatarIcon;
    final image = _avatarImage;
    if (image.isNotEmpty) {
      return sha256.convert(utf8.encode('$icon\n$image')).toString();
    }
    return icon.isEmpty ? '' : 'icon:$icon';
  }

  /// Hash of the avatar the server has confirmed it stored for us. Persisted so
  /// the (potentially multi-KB) image is only re-sent when it actually changes.
  String get _confirmedAvatarHash =>
      _broker.getValue<String>(0, 'AprsCloudAvatarHash', '') ?? '';

  void _setConfirmedAvatarHash(String hash) {
    if (hash == _confirmedAvatarHash) return;
    _broker.dispatch(
      deviceId: 0,
      name: 'AprsCloudAvatarHash',
      data: hash,
      store: true,
    );
  }

  /// Adds avatar fields to a register/heartbeat [body]. The lightweight
  /// `avatarHash` is always included; the full icon/image is only sent (flagged
  /// with `avatarUpdate`) when it differs from what the server last confirmed,
  /// keeping ordinary heartbeats small.
  void _addAvatarFields(Map<String, Object?> body) {
    final hash = _avatarHash;
    body['avatarHash'] = hash;
    if (hash != _confirmedAvatarHash) {
      final icon = _avatarIcon;
      final image = _avatarImage;
      body['avatarUpdate'] = true;
      body['avatarIcon'] = icon.isEmpty ? null : icon;
      body['avatarImage'] = image.isEmpty ? null : image;
    }
  }

  /// Records the avatar hash the server reports it now holds. When it matches
  /// our current avatar the image is considered synced; a mismatch (e.g. the
  /// server was reset) leaves the difference so the next request re-uploads it.
  void _handleAvatarResponse(Map<String, Object?> resp) {
    if (!resp.containsKey('avatarHash')) return; // Older server: ignore.
    _setConfirmedAvatarHash((resp['avatarHash'] as String?) ?? '');
  }

  /// True when the user enabled cloud notifications AND the prerequisites
  /// (callsign, APRS-IS enabled, matching passcode) are satisfied.
  bool get _shouldRegister {
    final enabled =
        (_broker.getValue<int>(0, 'AprsCloudNotifications', 0) ?? 0) == 1;
    if (!enabled) return false;
    final aprsIsEnabled =
        (_broker.getValue<int>(0, 'AprsIsEnabled', 0) ?? 0) == 1;
    if (!aprsIsEnabled) return false;
    final callsign = (_broker.getValue<String>(0, 'CallSign', '') ?? '').trim();
    if (callsign.isEmpty) return false;
    final passcode =
        (_broker.getValue<String>(0, 'AprsIsPasscode', '') ?? '').trim();
    return passcode.isNotEmpty && passcode == _passcode;
  }

  /// Applies the current settings: registers, updates or unregisters as needed.
  Future<void> _reconcile() async {
    if (!_supported || _reconciling) return;
    _reconciling = true;
    try {
      if (!_shouldRegister) {
        await _unregister();
        return;
      }

      await _ensureFirebase();
      if (_fcmToken == null || _fcmToken!.isEmpty) {
        _broker.logError('[APRS-Cloud] No FCM token; cannot register.');
        return;
      }

      final callsign =
          (_broker.getValue<String>(0, 'CallSign', '') ?? '').trim();
      final ssid = _broker.getValue<int>(0, 'StationId', 0) ?? 0;

      // If the identity or token changed, unregister the stale entry first.
      final identityChanged = _registeredCallsign != null &&
          (_registeredCallsign != callsign || _registeredSsid != ssid);
      if (identityChanged) {
        await _unregister();
      }

      // Already registered with the same identity and token: just keep alive.
      if (!identityChanged &&
          _registeredCallsign == callsign &&
          _registeredSsid == ssid &&
          _registeredToken == _fcmToken) {
        // The avatar may have changed while we were already registered; push it
        // without a full re-registration.
        if (_avatarHash != _confirmedAvatarHash) await _sendHeartbeat();
        _startHeartbeat();
        return;
      }

      await _register(callsign: callsign, ssid: ssid);
      _startHeartbeat();
    } catch (e) {
      _broker.logError('[APRS-Cloud] Reconcile failed: $e');
    } finally {
      _reconciling = false;
    }
  }

  /// Lazily initializes Firebase, requests notification permission, obtains the
  /// FCM token and wires up the message listeners. Safe to call repeatedly.
  Future<void> _ensureFirebase() async {
    if (_firebaseReady) return;

    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
    FirebaseMessaging.onBackgroundMessage(aprsCloudBackgroundHandler);

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();
    _fcmToken = await messaging.getToken();

    if (!_listenersReady) {
      _listenersReady = true;
      // App in the foreground: the OS does not show a banner, so pull the
      // message straight into the list. The push also carries the sender's
      // avatar (when the server has one), which we cache here for display.
      FirebaseMessaging.onMessage.listen((m) {
        _consumeAvatarFromPush(m);
        unawaited(_syncNow());
      });
      // User tapped a background notification: pull anything we missed and jump
      // to the sender's conversation.
      FirebaseMessaging.onMessageOpenedApp
          .listen((m) => unawaited(_handleNotificationTap(m)));
      // Token rotation: re-register with the new token.
      messaging.onTokenRefresh.listen((token) {
        _fcmToken = token;
        _scheduleReconcile();
      });
      // Launched from a terminated state by tapping a notification.
      final initial = await messaging.getInitialMessage();
      if (initial != null) unawaited(_handleNotificationTap(initial));
    }

    _firebaseReady = true;
  }

  /// Registers with the server and injects any returned message backlog.
  Future<void> _register({required String callsign, required int ssid}) async {
    final body = <String, Object?>{
      'callsign': callsign,
      'ssid': ssid,
      'platform': _platform,
      'pushToken': _fcmToken,
      'ackMessages': false,
      'wantHistory': true,
      'since': _lastSyncMs,
      'auth': _passcode,
    };
    _addAvatarFields(body);

    final resp = await _post('/v1/register', body);
    if (resp == null) return;
    if (resp['error'] != null) {
      _broker.logError('[APRS-Cloud] Register rejected: ${resp['error']}');
      return;
    }

    _registeredCallsign = callsign;
    _registeredSsid = ssid;
    _registeredToken = _fcmToken;
    _broker.logInfo('[APRS-Cloud] Registered $callsign-$ssid for push.');

    _handleAvatarResponse(resp);
    _injectMessages(resp['messages']);
    _handleAvatarHashes(resp);
    _updateLastSync(resp['serverTime']);
  }

  /// Pulls messages received since the last sync and injects them.
  Future<void> _syncNow() async {
    if (!_shouldRegister || _registeredCallsign == null) return;
    final body = <String, Object?>{
      'callsign': _registeredCallsign,
      'ssid': _registeredSsid ?? 0,
      'since': _lastSyncMs,
      'auth': _passcode,
    };
    final resp = await _post('/v1/sync', body);
    if (resp == null || resp['error'] != null) return;
    _injectMessages(resp['messages']);
    _handleAvatarHashes(resp);
    _updateLastSync(resp['serverTime']);
  }

  /// Refreshes the registration/token on a slow timer so the server keeps this
  /// station in its APRS-IS filter and prunes dead tokens.
  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(_heartbeatInterval, (_) => _sendHeartbeat());
  }

  /// Sends a single heartbeat, carrying the avatar hash (and the full avatar
  /// when it changed) so the server keeps our stored avatar current.
  Future<void> _sendHeartbeat() async {
    if (!_shouldRegister || _registeredCallsign == null) return;
    final body = <String, Object?>{
      'callsign': _registeredCallsign,
      'ssid': _registeredSsid ?? 0,
      'platform': _platform,
      'pushToken': _fcmToken,
      'auth': _passcode,
    };
    _addAvatarFields(body);
    final resp = await _post('/v1/heartbeat', body);
    if (resp != null && resp['error'] == null) _handleAvatarResponse(resp);
  }

  /// Unregisters the current station (if any) and stops the heartbeat.
  Future<void> _unregister() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    final callsign = _registeredCallsign;
    if (callsign == null) return;
    _registeredCallsign = null;
    final ssid = _registeredSsid ?? 0;
    _registeredSsid = null;
    _registeredToken = null;
    // The server drops the station (and its stored avatar) on unregister, so
    // forget the confirmed hash to force a fresh upload on the next register.
    _setConfirmedAvatarHash('');
    try {
      await _post('/v1/unregister', {
        'callsign': callsign,
        'ssid': ssid,
        'auth': AprsUtil.aprsValidationCode(callsign),
      });
      _broker.logInfo('[APRS-Cloud] Unregistered $callsign-$ssid.');
    } catch (_) {
      // Best-effort; the server prunes stale tokens on its own.
    }
  }

  /// Surfaces received messages to the APRS + Comms tabs. Backlog is injected
  /// without raising notifications (they are old); live pushes are already
  /// announced by the OS notification.
  void _injectMessages(Object? messages) {
    if (messages is! List) return;
    final self = _localCallsignWithId;
    for (final raw in messages) {
      if (raw is! Map) continue;
      if ((raw['direction'] as String?) != 'received') continue;
      final type = raw['type'] as String?;
      if (type == 'ack' || type == 'rej') continue;
      final text = (raw['text'] as String?) ?? '';
      if (text.isEmpty) continue;
      final peer = (raw['peer'] as String?)?.trim() ?? '';
      if (peer.isEmpty) continue;
      final ts = raw['timestamp'];
      final time =
          ts is int ? DateTime.fromMillisecondsSinceEpoch(ts) : DateTime.now();
      final seqId = (raw['seqId'] as String?)?.trim() ?? '';

      // Skip anything already surfaced this session (repeated sync/register
      // pulls, or a copy already delivered by the live APRS-IS connection).
      final key = '$peer\u0000$seqId\u0000$text\u0000${time.millisecondsSinceEpoch}';
      if (!_markInjected(key)) continue;

      // Rebuild a TNC2 line and hand it to the APRS-IS manager, which persists
      // it (so it survives a restart) and surfaces it to the APRS + Comms tabs
      // exactly like live APRS-IS traffic: it lands in the APRS tab under the
      // sender's conversation and is de-duplicated against any RF or APRS-IS
      // copy. Dispatching a transient frame here instead would not persist and
      // would be lost whenever the APRS tab was not already listening.
      final line = _buildMessageTnc2Line(
        source: peer,
        addressee: self,
        text: text,
        seqId: seqId,
      );
      _broker.dispatch(
        deviceId: _aprsDeviceId,
        name: 'IngestCloudMessage',
        data: <String, Object?>{
          'line': line,
          'time': time.millisecondsSinceEpoch,
        },
        store: false,
      );
    }
  }

  /// Records [key] as injected. Returns false if it was already seen, so the
  /// caller can skip re-injecting a duplicate. Evicts the oldest key past the
  /// cap.
  bool _markInjected(String key) {
    if (!_injectedKeys.add(key)) return false;
    _injectedOrder.add(key);
    if (_injectedOrder.length > _maxInjectedKeys) {
      _injectedKeys.remove(_injectedOrder.removeAt(0));
    }
    return true;
  }

  /// Stores the sender's avatar carried by a push notification so the APRS tab
  /// can show it, using only what already arrived — no extra network request is
  /// ever made. The server sends the small logo name and hash always and inlines
  /// the image only when it fits the push size budget; whatever is present is
  /// cached, and a sender whose custom image was too large simply falls back to
  /// its initials.
  void _consumeAvatarFromPush(RemoteMessage message) {
    final data = message.data;
    final from = (data['fromCall'] as String?)?.trim() ?? '';
    if (from.isEmpty) return;
    // Tombstone: the sender cleared their avatar; drop any cached copy.
    if ((data['fromAvatarCleared'] as String?) == '1') {
      _removeCloudAvatar(from);
      return;
    }
    final icon = (data['fromAvatarIcon'] as String?)?.trim() ?? '';
    final image = (data['fromAvatarImage'] as String?)?.trim() ?? '';
    final hash = (data['fromAvatarHash'] as String?)?.trim() ?? '';
    if (icon.isEmpty && image.isEmpty) return; // Nothing displayable arrived.
    _storeCloudAvatar(callsign: from, icon: icon, image: image, hash: hash);
  }

  /// Upserts a cloud avatar into the persisted [_cloudAvatarsKey] cache, keyed
  /// by uppercased callsign. Skips the write when the hash is unchanged so an
  /// unchanged avatar never rewrites the store.
  void _storeCloudAvatar({
    required String callsign,
    required String icon,
    required String image,
    required String hash,
  }) {
    final key = callsign.toUpperCase();
    final map = <String, dynamic>{};
    final raw = _broker.getValueDynamic(0, _cloudAvatarsKey, null);
    if (raw is Map) raw.forEach((k, v) => map['$k'] = v);

    final existing = map[key];
    if (existing is Map && hash.isNotEmpty && '${existing['hash'] ?? ''}' == hash) {
      return; // Unchanged.
    }

    map[key] = <String, dynamic>{
      'icon': icon.isEmpty ? null : icon,
      'image': image.isEmpty ? null : image,
      'hash': hash,
      'ts': DateTime.now().millisecondsSinceEpoch,
    };
    _pruneCloudAvatars(map);
    _broker.dispatch(
      deviceId: 0,
      name: _cloudAvatarsKey,
      data: map,
      store: true,
    );
  }

  /// Removes a cached cloud avatar (a sender cleared theirs). No-op when absent,
  /// so a tombstone for an unknown sender never rewrites the store.
  void _removeCloudAvatar(String callsign) {
    final key = callsign.toUpperCase();
    final raw = _broker.getValueDynamic(0, _cloudAvatarsKey, null);
    if (raw is! Map || !raw.containsKey(key)) return;
    final map = <String, dynamic>{};
    raw.forEach((k, v) => map['$k'] = v);
    map.remove(key);
    _broker.dispatch(
      deviceId: 0,
      name: _cloudAvatarsKey,
      data: map,
      store: true,
    );
  }

  /// Handles the `avatars` map (peer callsign -> hash) returned by register and
  /// sync. Any peer whose hash differs from our cached copy is fetched in full;
  /// unchanged avatars cost nothing beyond the hash we already received.
  void _handleAvatarHashes(Map<String, Object?> resp) {
    final avatars = resp['avatars'];
    if (avatars is! Map) return;
    final needed = <String>[];
    avatars.forEach((k, v) {
      final key = '$k'.trim().toUpperCase();
      final hash = '$v'.trim();
      if (key.isEmpty || hash.isEmpty) return;
      if (_cachedAvatarHash(key) != hash) needed.add(key);
    });
    if (needed.isNotEmpty) unawaited(_fetchAvatars(needed));
  }

  /// The hash of the avatar we have cached for [key] (uppercased callsign), or
  /// '' when we have none.
  String _cachedAvatarHash(String key) {
    final raw = _broker.getValueDynamic(0, _cloudAvatarsKey, null);
    if (raw is! Map) return '';
    final entry = raw[key];
    return (entry is Map) ? '${entry['hash'] ?? ''}' : '';
  }

  /// Fetches full avatars (icon + image) for the given stations and caches them.
  /// Only called for stations whose hash changed, so the image travels once.
  Future<void> _fetchAvatars(List<String> stations) async {
    if (_registeredCallsign == null) return;
    final resp = await _post('/v1/avatars', <String, Object?>{
      'callsign': _registeredCallsign,
      'ssid': _registeredSsid ?? 0,
      'auth': _passcode,
      'stations': stations.take(50).toList(),
    });
    if (resp == null || resp['error'] != null) return;
    final avatars = resp['avatars'];
    if (avatars is! Map) return;
    avatars.forEach((k, v) {
      if (v is! Map) return;
      final icon = (v['icon'] as String?)?.trim() ?? '';
      final image = (v['image'] as String?)?.trim() ?? '';
      final hash = (v['hash'] as String?)?.trim() ?? '';
      if (icon.isEmpty && image.isEmpty) return;
      _storeCloudAvatar(callsign: '$k', icon: icon, image: image, hash: hash);
    });
  }

  /// Evicts the least-recently-updated entries when the cache grows past the cap.
  void _pruneCloudAvatars(Map<String, dynamic> map) {
    if (map.length <= _maxCloudAvatars) return;
    final entries = map.entries.toList()
      ..sort((a, b) {
        final ta = (a.value is Map) ? (a.value['ts'] as int? ?? 0) : 0;
        final tb = (b.value is Map) ? (b.value['ts'] as int? ?? 0) : 0;
        return ta.compareTo(tb);
      });
    final remove = map.length - _maxCloudAvatars;
    for (var i = 0; i < remove; i++) {
      map.remove(entries[i].key);
    }
  }

  /// Pulls the latest messages, then navigates to the sender's APRS
  /// conversation. Invoked when the user taps a push notification.
  Future<void> _handleNotificationTap(RemoteMessage message) async {
    // Cache the sender's avatar carried by the tapped notification.
    _consumeAvatarFromPush(message);
    // Switch to the APRS tab immediately — before the sync round-trip — so a
    // tap always lands the user there even if the network is slow or the
    // notification carries no sender.
    _broker.dispatch(
      deviceId: 0,
      name: 'RequestSelectTab',
      data: 'APRS',
      store: false,
    );
    await _syncNow();
    // `fromCall` (not the FCM-reserved `from`) carries the sender callsign.
    final from = (message.data['fromCall'] as String?)?.trim() ?? '';
    if (from.isEmpty) return;
    // Ask the APRS tab to open the sender's conversation. A retained signal
    // (store: true) is used so the tab opens it even when it is being built for
    // the first time as a result of the tab switch above — a plain broadcast
    // would be missed by the not-yet-subscribed tab. The tab clears the signal
    // once consumed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _broker.dispatch(
        deviceId: _aprsDeviceId,
        name: 'AprsOpenConversation',
        data: from,
        store: true,
      );
    });
  }

  /// Our callsign in `CALL` or `CALL-SSID` form for message addressing.
  String get _localCallsignWithId {
    final call = (_broker.getValue<String>(0, 'CallSign', '') ?? '').trim();
    final ssid = _broker.getValue<int>(0, 'StationId', 0) ?? 0;
    return ssid == 0 ? call : '$call-$ssid';
  }

  /// Builds a TNC2 APRS message line: `SRC>APRS,TCPIP*::ADDRESSEE :text{seq`.
  /// The addressee is padded to the fixed 9-character APRS message field width.
  String _buildMessageTnc2Line({
    required String source,
    required String addressee,
    required String text,
    required String seqId,
  }) {
    final padded = addressee.length >= 9
        ? addressee.substring(0, 9)
        : addressee.padRight(9);
    final suffix = seqId.isEmpty ? '' : '{$seqId';
    return '$source>APRS,TCPIP*::$padded:$text$suffix';
  }

  /// Epoch-ms timestamp of the last successful sync, persisted across launches.
  int get _lastSyncMs => _broker.getValue<int>(0, 'AprsCloudLastSync', 0) ?? 0;

  void _updateLastSync(Object? serverTime) {
    final ts = serverTime is int ? serverTime : null;
    if (ts != null && ts > _lastSyncMs) {
      _broker.dispatch(
        deviceId: 0,
        name: 'AprsCloudLastSync',
        data: ts,
        store: true,
      );
    }
  }

  /// POSTs a JSON body and returns the decoded JSON object, or null on failure.
  Future<Map<String, Object?>?> _post(String path, Map<String, Object?> body) async {
    try {
      final resp = await _http
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_requestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        _broker.logError(
            '[APRS-Cloud] $path -> HTTP ${resp.statusCode}');
        // Still try to decode an error body for callers to inspect.
      }
      if (resp.body.isEmpty) return <String, Object?>{};
      final decoded = jsonDecode(resp.body);
      return decoded is Map<String, Object?>
          ? decoded
          : (decoded is Map ? decoded.cast<String, Object?>() : null);
    } catch (e) {
      _broker.logError('[APRS-Cloud] $path failed: $e');
      return null;
    }
  }

  /// Cancels timers and closes the HTTP client. Called at shutdown.
  Future<void> dispose() async {
    _debounce?.cancel();
    _heartbeat?.cancel();
    _broker.dispose();
    _http.close();
  }
}
