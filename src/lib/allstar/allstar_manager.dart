/*
Copyright 2026 Ylian Saint-Hilaire

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

//
// allstar_manager.dart - Wires the internet-only AllStarLink radio (device 202)
// into the running application.
//
// Main-isolate glue around the unit-tested [AllStarClient]: builds the real
// dart:io transport, reads the saved node list, exposes UI commands over the
// Data Broker, plays received audio through the shared PCM player and re-emits
// it as AudioData* events so the existing CommsHandler records + transcribes it,
// and turns outgoing TransmitVoicePCM into IAX2 voice frames.
//
// Like EchoLink, AllStarLink is deliberately NOT a physical radio: it is never
// added to device 1's `ConnectedRadios` aggregate and never participates in the
// radio lock. Availability is advertised on its own device-1 `AllStarAvailable`
// flag so the radio panel can list it in the radio switcher.
//

import 'dart:async';
import 'dart:typed_data';

import '../echolink/pcm_resampler.dart';
import '../radio/pcm_player.dart';
import '../services/data_broker_client.dart';
import 'allstar_client.dart';
import 'allstar_node.dart';
import 'allstar_portal_service.dart';
import 'iax2_network_io.dart';

/// Owns the [AllStarClient] and bridges it to the app's Data Broker, audio
/// player and voice pipeline. Registered as a Data Broker handler in `main()`
/// on platforms with a dart:io audio + socket stack (desktop / mobile).
class AllStarManager {
  AllStarManager();

  /// App audio sample rate (matches the radio audio engine / CommsHandler).
  static const int _appSampleRate = 32000;

  /// Received-audio run is finished after this much silence, so the recorder /
  /// speech-to-text engine gets discrete transmissions.
  static const int _rxRunEndMs = 2000;

  /// Peak level (0..1) a received frame must reach to count as real audio.
  /// AllStarLink nodes stream continuous frames (silence / comfort noise) even
  /// when idle; frames below this are treated as silence so the recorder only
  /// captures actual transmissions and idle audio is not played out.
  static const double _rxSilenceLevel = 0.02;

  final DataBrokerClient _broker = DataBrokerClient();

  AllStarClient? _client;
  bool _initialized = false;
  bool _opened = false;
  bool _reconciling = false;

  // --- Received-audio playback + re-dispatch -------------------------------
  final PcmPlayer _player = PcmPlayer();
  bool _playerReady = false;
  Future<void>? _playerInitFuture;
  int _bufferedFrames = 0;
  static const int _maxBufferedFrames = _appSampleRate;
  final LinearResampler _rxResampler = LinearResampler.up8kTo32k();
  bool _inRxRun = false;
  Timer? _rxEndTimer;
  int _rxRunStartMs = 0;

  int _selectedRadioDeviceId = -1;

  // --- Transmit (app -> AllStar) -------------------------------------------
  final LinearResampler _txResampler = LinearResampler.down32kTo8k();
  bool _txActive = false;
  Timer? _txTimer;
  static const int _txEndMs = 300;

  AllStarNode? _currentNode;

  /// Subscribes to settings + UI commands and prepares the client if a node is
  /// configured. Safe to call once.
  void init() {
    if (_initialized) return;
    _initialized = true;

    _broker.subscribe(
      deviceId: allStarDeviceId,
      name: 'AllStarGoOnline',
      callback: _onGoOnline,
    );
    _broker.subscribe(
      deviceId: allStarDeviceId,
      name: 'AllStarGoOffline',
      callback: _onGoOffline,
    );
    _broker.subscribe(
      deviceId: allStarDeviceId,
      name: 'AllStarConnect',
      callback: _onConnect,
    );
    _broker.subscribe(
      deviceId: allStarDeviceId,
      name: 'AllStarDisconnect',
      callback: _onDisconnect,
    );
    _broker.subscribe(
      deviceId: allStarDeviceId,
      name: 'TransmitVoicePCM',
      callback: _onTransmitVoicePcm,
    );

    // Re-check when the saved node list changes.
    _broker.subscribe(
      deviceId: 0,
      name: allStarNodesKey,
      callback: (_, _, _) => unawaited(_reconcile()),
    );

    // Availability now tracks the account authorization (WT token), so re-check
    // whenever the token is set or cleared (e.g. after a successful Test).
    _broker.subscribe(
      deviceId: 0,
      name: allStarWtTokenKey,
      callback: (_, _, _) => unawaited(_reconcile()),
    );

    _broker.subscribe(
      deviceId: 1,
      name: 'SelectedRadioDeviceId',
      callback: _onSelectedRadioChanged,
    );
    _selectedRadioDeviceId =
        _broker.getValue<int>(1, 'SelectedRadioDeviceId', -1) ?? -1;

    unawaited(_reconcile());
  }

  /// Enables or disables AllStarLink to match the account authorization. It is
  /// offered (Available=true) whenever the operator's portal account is
  /// authorized (a Web Transceiver token is stored). Configured channels are
  /// managed from the radio panel, not required for availability.
  Future<void> _reconcile() async {
    if (_reconciling) return;
    _reconciling = true;
    try {
      final List<AllStarNode> nodes = _readNodes();
      _publishNodeList(nodes);

      final bool shouldEnable = _wtToken() != null;
      if (!shouldEnable) {
        if (_client != null || _opened) {
          await _closeClient();
          _broker.logInfo('[AllStar] Disabled (account not authorized)');
        }
        _publishAvailable(false);
        return;
      }

      _publishAvailable(true);
      if (_client != null) return; // Already prepared.

      final AllStarClient client = AllStarClient(
        network: DartIoIax2Network()..onDiagnostic = _onDiagnostic,
      )
        ..onAudio = _onRxAudio
        ..onStateChanged = _onClientState
        ..onConnectedNode = _onConnectedNode
        ..onText = _onRxText
        ..onDiagnostic = _onDiagnostic;
      _client = client;
      _broker.logInfo(
          '[AllStar] Ready (account authorized, ${nodes.length} channel(s))');
      unawaited(_maybeAutoReconnect());
    } finally {
      _reconciling = false;
    }
  }

  Future<void> _maybeAutoReconnect() async {
    final bool wasOnline =
        _broker.getValue<bool>(0, allStarWasOnlineKey, false) ?? false;
    if (!wasOnline) return;
    final AllStarClient? client = _client;
    if (client == null) return;
    try {
      await client.open();
      final Object? last = _broker.getValueDynamic(0, lastAllStarNodeKey);
      if (last is Map) {
        client.connectTo(AllStarNode.fromMap(last), wtToken: _wtToken());
      }
    } catch (e) {
      _broker.logError('[AllStar] Auto-reconnect failed: $e');
    }
  }

  Future<void> _closeClient() async {
    final AllStarClient? client = _client;
    _client = null;
    _opened = false;
    _currentNode = null;
    _endRxRun();
    try {
      await client?.close();
    } catch (_) {}
    await _releasePlayer();
    _publishState(AllStarClientState.offline);
    _publishConnectedNode(null);
  }

  Future<void> _releasePlayer() async {
    _rxEndTimer?.cancel();
    _rxEndTimer = null;
    await _playerInitFuture;
    if (_playerReady) {
      try {
        await _player.release();
      } catch (_) {}
      _playerReady = false;
    }
  }

  // --- UI command handlers -------------------------------------------------

  void _onGoOnline(int deviceId, String name, Object? data) {
    final AllStarClient? client = _client;
    if (client == null) return;
    _broker.dispatch(
        deviceId: 0, name: allStarWasOnlineKey, data: true, store: true);
    unawaited(() async {
      try {
        // Authenticate against the portal to obtain a fresh Web Transceiver
        // token before opening the transport (tokens are short-lived).
        await _refreshToken();
        await client.open();
        _opened = true;
      } catch (e) {
        _broker.logError('[AllStar] Go online failed: $e');
      }
    }());
  }

  /// Re-authenticates with the AllStarLink portal using the stored account
  /// password and refreshes the Web Transceiver token. Silently no-ops when no
  /// password or call sign is configured, leaving any existing token in place.
  Future<void> _refreshToken() async {
    final String password =
        _broker.getValue<String>(0, allStarPasswordKey, '') ?? '';
    final String callSign =
        (_broker.getValue<String>(0, 'CallSign', '') ?? '').trim();
    if (password.isEmpty || callSign.isEmpty) return;
    final AllStarPortalService service = AllStarPortalService();
    try {
      final AllStarWtAuthResult result =
          await service.fetchToken(username: callSign, password: password);
      if (result.success && result.token.isNotEmpty) {
        _broker.dispatch(
            deviceId: 0,
            name: allStarWtTokenKey,
            data: result.token,
            store: true);
        _broker.logInfo('[AllStar] Authenticated (token refreshed)');
      } else {
        _broker.logError('[AllStar] Authentication failed: ${result.message}');
      }
    } catch (e) {
      _broker.logError('[AllStar] Authentication error: $e');
    } finally {
      service.dispose();
    }
  }

  void _onGoOffline(int deviceId, String name, Object? data) {
    final AllStarClient? client = _client;
    if (client == null) return;
    _broker.dispatch(
        deviceId: 0, name: lastAllStarNodeKey, data: null, store: true);
    _broker.dispatch(
        deviceId: 0, name: allStarWasOnlineKey, data: false, store: true);
    unawaited(() async {
      try {
        await client.close();
        _opened = false;
      } catch (e) {
        _broker.logError('[AllStar] Go offline failed: $e');
      }
    }());
  }

  void _onConnect(int deviceId, String name, Object? data) {
    final AllStarClient? client = _client;
    if (client == null || data is! Map) return;
    final AllStarNode node = AllStarNode.fromMap(data);
    if (node.effectiveHost.isEmpty || node.nodeNumber.isEmpty) {
      _broker.logError('[AllStar] Cannot connect: node missing host/number');
      return;
    }
    unawaited(() async {
      try {
        if (!_opened) {
          await client.open();
          _opened = true;
        }
        client.connectTo(node, wtToken: _wtToken());
      } catch (e) {
        _broker.logError('[AllStar] Connect failed: $e');
      }
    }());
  }

  void _onDisconnect(int deviceId, String name, Object? data) {
    _client?.disconnect();
  }

  void _onSelectedRadioChanged(int deviceId, String name, Object? data) {
    if (data is! int) return;
    if (data == _selectedRadioDeviceId) return;
    _selectedRadioDeviceId = data;
    if (_selectedRadioDeviceId >= 0 &&
        _selectedRadioDeviceId != allStarDeviceId) {
      _bufferedFrames = 0;
    }
  }

  // --- Client callbacks ----------------------------------------------------

  void _onClientState(AllStarClientState state) {
    _publishState(state);
    if (state == AllStarClientState.inCall && _currentNode != null) {
      _broker.dispatch(
        deviceId: 0,
        name: lastAllStarNodeKey,
        data: _currentNode!.toMap(),
        store: true,
      );
    }
    if (state == AllStarClientState.online ||
        state == AllStarClientState.offline) {
      _endRxRun();
      _setTxActive(false);
    }
  }

  void _onConnectedNode(AllStarNode? node) {
    _currentNode = node;
    _publishConnectedNode(node);
  }

  /// Surfaces a text message received from the node as an `AllStarChat` event so
  /// the CommsHandler records it in history and the Comms tab renders it as an
  /// "AllStarLink" message.
  void _onRxText(String text) {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final String source = _currentNode?.nodeNumber ?? '';
    _broker.dispatch(
      deviceId: allStarDeviceId,
      name: 'AllStarChat',
      data: <String, Object?>{
        'text': trimmed,
        'isReceived': true,
        'source': source,
        'time': DateTime.now().millisecondsSinceEpoch,
      },
      store: false,
    );
  }

  void _onDiagnostic(String message) {
    _broker.logInfo('[AllStar] $message');
  }

  // --- State publishing ----------------------------------------------------

  void _publishState(AllStarClientState state) {
    _broker.dispatch(
      deviceId: allStarDeviceId,
      name: 'State',
      data: _stateLabel(state),
      store: true,
    );
  }

  static String _stateLabel(AllStarClientState state) {
    switch (state) {
      case AllStarClientState.online:
        return 'Online';
      case AllStarClientState.connecting:
        return 'Connecting';
      case AllStarClientState.inCall:
        return 'Connected';
      case AllStarClientState.offline:
        return 'Disconnected';
    }
  }

  void _publishConnectedNode(AllStarNode? node) {
    _broker.dispatch(
      deviceId: allStarDeviceId,
      name: 'ConnectedNode',
      data: node?.toMap(),
      store: true,
    );
  }

  void _publishNodeList(List<AllStarNode> nodes) {
    _broker.dispatch(
      deviceId: allStarDeviceId,
      name: 'NodeList',
      data: nodes.map((AllStarNode n) => n.toMap()).toList(),
      store: true,
    );
  }

  void _publishAvailable(bool available) {
    _broker.dispatch(
        deviceId: 1, name: 'AllStarAvailable', data: available, store: true);
  }

  List<AllStarNode> _readNodes() {
    final Object? raw = _broker.getValueDynamic(0, allStarNodesKey);
    if (raw is! List) return <AllStarNode>[];
    final List<AllStarNode> nodes = <AllStarNode>[];
    for (final Object? e in raw) {
      if (e is Map) nodes.add(AllStarNode.fromMap(e));
    }
    return nodes;
  }

  /// The stored AllStarLink portal (Web Transceiver) token, or null if none.
  String? _wtToken() {
    final String t = _broker.getValue<String>(0, allStarWtTokenKey, '') ?? '';
    return t.isEmpty ? null : t;
  }

  // --- Received audio ------------------------------------------------------

  /// Called with one decoded 8 kHz voice frame per received IAX2 voice packet.
  void _onRxAudio(Int16List pcm8k) {
    final Int16List pcm32 = _rxResampler.process(pcm8k);
    if (pcm32.isEmpty) return;

    // Voice-operated gate: only frames above the silence level start or extend a
    // recording run, so the node's continuous idle frames are not recorded or
    // played out to the output device.
    final double level = _peakLevel(pcm8k);
    final bool loud = level >= _rxSilenceLevel;
    _publishRxLevel(loud ? level : 0.0);

    if (!_inRxRun) {
      if (!loud) return; // Idle: nothing worth playing or recording yet.
      _inRxRun = true;
      _rxRunStartMs = DateTime.now().millisecondsSinceEpoch;
      _broker.dispatch(
        deviceId: allStarDeviceId,
        name: 'AudioDataStart',
        data: <String, Object?>{
          'startTime': _rxRunStartMs,
          'channelName': _rxChannelName(),
          'transmit': false,
          'muted': false,
          'usage': null,
        },
        store: false,
      );
    }

    // Only feed the output device while a run is active, so no silent audio is
    // played between transmissions.
    unawaited(_playPcm(pcm32));

    final Uint8List bytes =
        pcm32.buffer.asUint8List(pcm32.offsetInBytes, pcm32.lengthInBytes);
    _broker.dispatch(
      deviceId: allStarDeviceId,
      name: 'AudioDataAvailable',
      data: <String, Object?>{
        'data': bytes,
        'offset': 0,
        'length': bytes.length,
        'channelName': _rxChannelName(),
        'transmit': false,
        'muted': false,
        'audioRunStartTime': _rxRunStartMs,
        'usage': null,
      },
      store: false,
    );

    // Extend the run only while real audio arrives; a gap of _rxRunEndMs of
    // silence lets the timer fire and end the run.
    if (loud) {
      _rxEndTimer?.cancel();
      _rxEndTimer = Timer(const Duration(milliseconds: _rxRunEndMs), _endRxRun);
    }
  }

  void _endRxRun() {
    _rxEndTimer?.cancel();
    _rxEndTimer = null;
    if (!_inRxRun) return;
    _inRxRun = false;
    _broker.dispatch(
      deviceId: allStarDeviceId,
      name: 'AudioDataEnd',
      data: <String, Object?>{
        'startTime': _rxRunStartMs,
        'transmit': false,
        'usage': null,
      },
      store: false,
    );
    _broker.dispatch(
        deviceId: allStarDeviceId, name: 'RxLevel', data: 0.0, store: false);
  }

  void _publishRxLevel(double level) {
    _broker.dispatch(
        deviceId: allStarDeviceId, name: 'RxLevel', data: level, store: false);
  }

  double _peakLevel(Int16List pcm) {
    int peak = 0;
    for (final int s in pcm) {
      final int a = s < 0 ? -s : s;
      if (a > peak) peak = a;
    }
    return (peak / 32768.0).clamp(0.0, 1.0);
  }

  String _rxChannelName() => _currentNode?.name ?? 'AllStarLink';

  Future<void> _playPcm(Int16List pcm) async {
    if (_selectedRadioDeviceId >= 0 &&
        _selectedRadioDeviceId != allStarDeviceId) {
      return;
    }
    if (!_playerReady) {
      await _initPlayer();
      if (!_playerReady) return;
    }
    if (_bufferedFrames > _maxBufferedFrames) return;
    _bufferedFrames += pcm.length;
    try {
      await _player.feed(pcm);
    } catch (_) {}
  }

  Future<void> _initPlayer() async {
    if (_playerReady) return;
    // Single-flight guard: bursts of received frames each fire _playPcm; without
    // this, concurrent setup()/start() on the one native device can deadlock.
    final Future<void>? inFlight = _playerInitFuture;
    if (inFlight != null) {
      await inFlight;
      return;
    }
    final Future<void> init = _doInitPlayer();
    _playerInitFuture = init;
    try {
      await init;
    } finally {
      _playerInitFuture = null;
    }
  }

  Future<void> _doInitPlayer() async {
    try {
      await _player.setLogLevelError();
      await _player.setup(sampleRate: _appSampleRate, channelCount: 1);
      await _player.setFeedThreshold(_appSampleRate ~/ 8);
      _player.setFeedCallback((int remaining) => _bufferedFrames = remaining);
      _player.start();
      _playerReady = true;
    } catch (e) {
      _broker.logError('[AllStar] PCM player init failed: $e');
    }
  }

  // --- Transmit audio ------------------------------------------------------

  void _onTransmitVoicePcm(int deviceId, String name, Object? data) {
    if (data is! Map) return;
    final Object? bytes = data['data'] ?? data['Data'];
    if (bytes is! Uint8List) {
      final bool hold = (data['hold'] ?? data['Hold']) as bool? ?? true;
      if (!hold) {
        _client?.flushAudio();
        _txResampler.reset();
        _setTxActive(false);
      }
      return;
    }
    final AllStarClient? client = _client;
    if (client == null) return;

    final Int16List pcm32 = _int16FromBytes(bytes);
    final Int16List pcm8k = _txResampler.process(pcm32);
    if (pcm8k.isNotEmpty) client.sendAudio(pcm8k);

    _setTxActive(true);
    _txTimer?.cancel();
    _txTimer =
        Timer(const Duration(milliseconds: _txEndMs), () => _setTxActive(false));

    final bool hold = (data['hold'] ?? data['Hold']) as bool? ?? true;
    if (!hold) {
      client.flushAudio();
      _txResampler.reset();
      _txTimer?.cancel();
      _setTxActive(false);
    }
  }

  void _setTxActive(bool active) {
    if (active == _txActive) return;
    _txActive = active;
    _broker.dispatch(
        deviceId: allStarDeviceId, name: 'TxActive', data: active, store: false);
  }

  static Int16List _int16FromBytes(Uint8List bytes) {
    if (bytes.offsetInBytes.isEven && bytes.lengthInBytes.isEven) {
      return bytes.buffer.asInt16List(bytes.offsetInBytes, bytes.length ~/ 2);
    }
    final int count = bytes.length ~/ 2;
    final Int16List out = Int16List(count);
    final ByteData bd = ByteData.sublistView(bytes);
    for (int i = 0; i < count; i++) {
      out[i] = bd.getInt16(i * 2, Endian.little);
    }
    return out;
  }
}
