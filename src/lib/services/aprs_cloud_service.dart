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

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:http/http.dart' as http;

import '../aprs/aprs_events.dart';
import '../aprs/aprs_packet.dart';
import '../aprs/aprs_util.dart';
import '../aprsis/tnc2_codec.dart';
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
      // message straight into the list.
      FirebaseMessaging.onMessage.listen((_) => unawaited(_syncNow()));
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

    _injectMessages(resp['messages']);
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
    _updateLastSync(resp['serverTime']);
  }

  /// Refreshes the registration/token on a slow timer so the server keeps this
  /// station in its APRS-IS filter and prunes dead tokens.
  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(_heartbeatInterval, (_) async {
      if (!_shouldRegister || _registeredCallsign == null) return;
      final body = <String, Object?>{
        'callsign': _registeredCallsign,
        'ssid': _registeredSsid ?? 0,
        'platform': _platform,
        'pushToken': _fcmToken,
        'auth': _passcode,
      };
      await _post('/v1/heartbeat', body);
    });
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

      // Rebuild a TNC2 line and decode it so the message flows through the same
      // pipeline as APRS-IS traffic: it lands in the APRS tab under the sender's
      // conversation (via AprsFrame) and is de-duplicated against any RF or
      // APRS-IS copy of the same message.
      final line = _buildMessageTnc2Line(
        source: peer,
        addressee: self,
        text: text,
        seqId: seqId,
      );
      final ax25 = Tnc2Codec.decode(line, time: time);
      final aprs = ax25 == null ? null : AprsPacket.parse(ax25);
      if (ax25 != null && aprs != null) {
        aprs.fromAprsIs = true;
        _broker.dispatch(
          deviceId: _aprsDeviceId,
          name: 'AprsFrame',
          data: AprsFrameEventArgs(aprs, ax25, null),
          store: false,
        );
      }

      // Also surface to the Comms tab. The OS notification already announced the
      // push, so suppress a second (in-app) notification here.
      _broker.dispatch(
        deviceId: _aprsDeviceId,
        name: 'AprsMessageReceived',
        data: <String, Object?>{
          'text': text,
          'channel': 'APRS-IS',
          'time': time.millisecondsSinceEpoch,
          'source': peer,
          'destination': self,
          'suppressNotification': true,
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

  /// Pulls the latest messages, then navigates to the sender's APRS
  /// conversation. Invoked when the user taps a push notification.
  Future<void> _handleNotificationTap(RemoteMessage message) async {
    await _syncNow();
    final from = (message.data['from'] as String?)?.trim() ?? '';
    if (from.isEmpty) return;
    _broker.dispatch(
      deviceId: 0,
      name: 'RequestSelectTab',
      data: 'APRS',
      store: false,
    );
    // Defer opening the conversation until the APRS tab has (re)built and
    // subscribed, mirroring how the Map tab starts a conversation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _broker.dispatch(
        deviceId: 0,
        name: 'AprsMessageStation',
        data: from,
        store: false,
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
