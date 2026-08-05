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
// allstar_node_handler.dart - Hosts an AllStarLink node that relays audio
// between a physical radio and the AllStarLink network.
//
// A background Data Broker handler (like BbsHandler / TorrentHandler). On
// AllStarNodeStart it locks the chosen radio to the 'AllStarLink' usage, opens
// an inbound IAX2 server on UDP 4569, registers the node with AllStarLink, and
// bridges audio both ways:
//   * radio RX (usage-tagged, 32 kHz) -> resample 8 kHz -> all linked peers
//   * linked-peer audio -> mix -> resample 32 kHz -> keys the radio PTT
// Half-duplex is arbitrated by the radio's RX carrier (HtStatus.isInRx): local
// RF always has priority, so network audio never keys the radio while a local
// station is transmitting.
//

import 'dart:async';
import 'dart:typed_data';

import '../allstar/allstar_node.dart';
import '../allstar/allstar_audio.dart';
import '../allstar/allstar_portal_service.dart';
import '../allstar/iax2_constants.dart';
import '../allstar/iax2_frame.dart';
import '../allstar/iax2_network.dart';
import '../allstar/iax2_network_io.dart';
import '../allstar/iax2_registrar.dart';
import '../allstar/iax2_server.dart';
import '../echolink/pcm_resampler.dart';
import '../radio/radio.dart';
import '../radio/radio_models.dart';
import '../services/data_broker_client.dart';

/// Owns the inbound IAX2 server + registration and the radio audio bridge.
class AllStarNodeHandler {
  /// Samples per outbound voice frame at 8 kHz (20 ms).
  static const int _frameSamples = allStarGsmFrameSamples; // 160

  /// Net->radio keying is released after this many idle mix ticks (~300 ms).
  static const int _txTailTicks = 15;

  /// Cap on buffered per-peer audio (~1 s) to bound memory under a stuck peer.
  static const int _maxPeerSamples = 8000;

  final DataBrokerClient _broker = DataBrokerClient();

  bool _initialized = false;
  bool _hosting = false;
  int _radioDeviceId = -1;

  DartIoIax2Network? _network;
  StreamSubscription<Iax2Datagram>? _netSub;
  Iax2Server? _server;
  Iax2Registrar? _registrar;
  AllStarPortalService? _portal;

  // Radio RX -> network.
  final LinearResampler _rxDown = LinearResampler.down32kTo8k();
  final List<int> _rxAccum = <int>[];
  bool _radioInRx = false;

  // Network -> radio (mixed).
  final LinearResampler _txUp = LinearResampler.up8kTo32k();
  final Map<int, List<int>> _peerAudio = <int, List<int>>{};
  Timer? _mixTimer;
  bool _radioKeyed = false;
  int _idleTicks = 0;

  void init() {
    if (_initialized) return;
    _initialized = true;
    _broker.subscribe(
      deviceId: allStarNodeDeviceId,
      name: 'AllStarNodeStart',
      callback: _onStartCommand,
    );
    _broker.subscribe(
      deviceId: allStarNodeDeviceId,
      name: 'AllStarNodeStop',
      callback: (_, _, _) => unawaited(stop()),
    );
    _publishState('Stopped');
    _publishRegState(Iax2RegState.idle);
    _publishPeers();
  }

  bool get isHosting => _hosting;
  int get hostedRadioDeviceId => _radioDeviceId;

  // --- Commands --------------------------------------------------------------

  void _onStartCommand(int deviceId, String name, Object? data) {
    int radioId = _radioDeviceId;
    if (data is Map) {
      final Object? r = data['radioDeviceId'] ?? data['RadioDeviceId'];
      if (r is int) radioId = r;
    } else if (data is int) {
      radioId = data;
    }
    if (radioId < 0) {
      _broker.logError('[AllStarNode] Start ignored: no radio selected');
      return;
    }
    unawaited(start(radioId));
  }

  /// Starts hosting on [radioDeviceId]. Idempotent while already hosting.
  Future<void> start(int radioDeviceId) async {
    if (_hosting) return;

    final String nodeNumber =
        (_broker.getValue<String>(0, allStarNodeNumberKey, '') ?? '').trim();
    final String secret =
        _broker.getValue<String>(0, allStarNodePasswordKey, '') ?? '';
    if (nodeNumber.isEmpty || secret.isEmpty) {
      _broker.logError('[AllStarNode] Cannot host: node number/password not set');
      _publishState('Error');
      return;
    }
    final int bindPort =
        _broker.getValue<int>(0, allStarBindPortKey, iax2DefaultPort) ??
            iax2DefaultPort;
    final AllStarRegMethod regMethod = allStarRegMethodFromString(
        _broker.getValue<String>(0, allStarRegMethodKey, 'iax'));
    final bool allowWt =
        _broker.getValue<bool>(0, allStarAllowWtKey, false) ?? false;

    _publishState('Starting');

    final DartIoIax2Network network = DartIoIax2Network()
      ..onDiagnostic = (String m) => _broker.logInfo('[AllStarNode] $m');
    try {
      await network.open(bindPort: bindPort);
    } catch (e) {
      _broker.logError('[AllStarNode] Could not bind UDP $bindPort: $e');
      _publishState('Error');
      return;
    }
    _network = network;

    // Web Transceiver callers additionally have their portal token validated.
    if (allowWt) _portal = AllStarPortalService();

    _server = Iax2Server(
      onSend: (String host, int port, Uint8List d) =>
          network.send(host, port, d),
      nodeNumber: nodeNumber,
      secret: secret,
      allowWebTransceiver: allowWt,
      webTransceiverValidator:
          allowWt ? (String t) => _portal!.verifyWebTransceiverToken(t) : null,
      onSessionConnected: _onPeerConnected,
      onSessionEnded: _onPeerEnded,
      onAudio: _onPeerAudio,
      onKeyed: _onPeerKeyed,
      onText: _onPeerText,
      onDiagnostic: (String m) => _broker.logInfo('[AllStarNode] $m'),
    );

    if (regMethod == AllStarRegMethod.iax) {
      _registrar = Iax2Registrar(
        onSend: (Uint8List d) =>
            network.send(allStarRegistrationServer, iax2DefaultPort, d),
        nodeNumber: nodeNumber,
        secret: secret,
        onStateChanged: (Iax2RegState s, {String? detail}) =>
            _publishRegState(s, detail: detail),
        onDiagnostic: (String m) => _broker.logInfo('[AllStarNode] $m'),
      )..start();
    } else if (regMethod == AllStarRegMethod.http) {
      _broker.logInfo('[AllStarNode] HTTP registration not yet supported; '
          'node reachable by direct IP/DNS only');
      _publishRegState(Iax2RegState.idle);
    } else {
      _publishRegState(Iax2RegState.idle);
    }

    _netSub = network.datagramsIn.listen(_onDatagram);

    _radioDeviceId = radioDeviceId;
    // Lock the radio to this usage so the rest of the app leaves it dedicated.
    _broker.dispatch(
      deviceId: radioDeviceId,
      name: 'SetLock',
      data: SetLockData(usage: kAllStarNodeLockUsage),
      store: false,
    );
    _subscribeRadio(radioDeviceId);

    _mixTimer = Timer.periodic(const Duration(milliseconds: 20), (_) => _mixTick());

    _hosting = true;
    _broker.dispatch(
        deviceId: 0, name: allStarHostEnabledKey, data: true, store: true);
    _publishState('Hosting');
    _broker.logInfo('[AllStarNode] Hosting node $nodeNumber on UDP $bindPort, '
        'radio device $radioDeviceId${allowWt ? ', Web Transceiver enabled' : ''}');
  }

  /// Stops hosting: unlocks the radio, closes the server and deregisters.
  Future<void> stop() async {
    if (!_hosting) {
      _publishState('Stopped');
      return;
    }
    _hosting = false;
    _mixTimer?.cancel();
    _mixTimer = null;
    _releaseRadioTx();

    if (_radioDeviceId >= 0) {
      _unsubscribeRadio(_radioDeviceId);
      _broker.dispatch(
        deviceId: _radioDeviceId,
        name: 'SetUnlock',
        data: SetUnlockData(usage: kAllStarNodeLockUsage),
        store: false,
      );
    }
    _radioDeviceId = -1;

    _registrar?.stop();
    _registrar = null;
    _server?.close();
    _server = null;
    _portal?.dispose();
    _portal = null;
    await _netSub?.cancel();
    _netSub = null;
    await _network?.close();
    _network = null;

    _peerAudio.clear();
    _rxAccum.clear();
    _radioInRx = false;

    _broker.dispatch(
        deviceId: 0, name: allStarHostEnabledKey, data: false, store: true);
    _publishState('Stopped');
    _publishRegState(Iax2RegState.idle);
    _publishPeers();
    _broker.logInfo('[AllStarNode] Hosting stopped');
  }

  // --- Datagram routing ------------------------------------------------------

  void _onDatagram(Iax2Datagram dg) {
    final Uint8List data = dg.data;
    // Route replies to the registration leg (call numbers >= 0x4000) to it;
    // everything else is an inbound peer session.
    final Iax2Registrar? reg = _registrar;
    if (reg != null && iax2IsFullFrame(data) && data.length >= 4) {
      final int destCall = ((data[2] & 0x7F) << 8) | data[3];
      if (destCall != 0 && destCall == reg.localCall) {
        reg.handleDatagram(data);
        return;
      }
    }
    _server?.handleDatagram(dg.host, dg.port, data);
  }

  // --- Radio subscriptions ---------------------------------------------------

  void _subscribeRadio(int radioId) {
    _broker.subscribe(
        deviceId: radioId, name: 'AudioDataStart', callback: _onRadioAudioStart);
    _broker.subscribe(
        deviceId: radioId,
        name: 'AudioDataAvailable',
        callback: _onRadioAudioAvailable);
    _broker.subscribe(
        deviceId: radioId, name: 'AudioDataEnd', callback: _onRadioAudioEnd);
    _broker.subscribe(
        deviceId: radioId, name: 'HtStatus', callback: _onRadioHtStatus);
  }

  void _unsubscribeRadio(int radioId) {
    _broker.unsubscribe(radioId, 'AudioDataStart');
    _broker.unsubscribe(radioId, 'AudioDataAvailable');
    _broker.unsubscribe(radioId, 'AudioDataEnd');
    _broker.unsubscribe(radioId, 'HtStatus');
  }

  // --- Radio RX -> network ---------------------------------------------------

  bool _isOurRadioRx(Map data) {
    final Object? usage = data['usage'] ?? data['Usage'];
    final bool transmit = (data['transmit'] ?? data['Transmit']) as bool? ?? false;
    final bool muted = (data['muted'] ?? data['Muted']) as bool? ?? false;
    if (transmit || muted) return false;
    return usage == kAllStarNodeLockUsage;
  }

  void _onRadioAudioStart(int deviceId, String name, Object? data) {
    if (!_hosting || data is! Map || !_isOurRadioRx(data)) return;
    _rxDown.reset();
    _rxAccum.clear();
    _server?.broadcastKey(true);
  }

  void _onRadioAudioAvailable(int deviceId, String name, Object? data) {
    if (!_hosting || data is! Map || !_isOurRadioRx(data)) return;
    final Object? raw = data['data'] ?? data['Data'];
    if (raw is! Uint8List) return;
    final int length = (data['length'] ?? data['Length']) as int? ?? raw.length;
    final int offset = (data['offset'] ?? data['Offset']) as int? ?? 0;
    final Int16List pcm32 = _int16FromBytes(raw, offset, length);
    final Int16List pcm8 = _rxDown.process(pcm32);
    if (pcm8.isEmpty) return;
    _rxAccum.addAll(pcm8);
    final Iax2Server? server = _server;
    if (server == null) return;
    while (_rxAccum.length >= _frameSamples) {
      final Int16List frame =
          Int16List.fromList(_rxAccum.sublist(0, _frameSamples));
      _rxAccum.removeRange(0, _frameSamples);
      server.broadcastVoiceFrame(frame);
    }
  }

  void _onRadioAudioEnd(int deviceId, String name, Object? data) {
    if (!_hosting) return;
    if (data is Map && !_isOurRadioRx(data)) return;
    if (_rxAccum.isNotEmpty) {
      final Int16List frame = Int16List(_frameSamples);
      for (int i = 0; i < _rxAccum.length && i < _frameSamples; i++) {
        frame[i] = _rxAccum[i];
      }
      _server?.broadcastVoiceFrame(frame);
      _rxAccum.clear();
    }
    _server?.broadcastKey(false);
  }

  void _onRadioHtStatus(int deviceId, String name, Object? data) {
    if (data is! Map) return;
    final bool inRx = (data['isInRx'] ?? data['IsInRx']) as bool? ?? false;
    _radioInRx = inRx;
  }

  // --- Network -> radio (mixed) ---------------------------------------------

  void _onPeerAudio(Iax2ServerSession session, Int16List pcm8k) {
    final List<int> buf = _peerAudio.putIfAbsent(session.localCall, () => <int>[]);
    if (buf.length > _maxPeerSamples) return; // Drop under overflow.
    buf.addAll(pcm8k);
  }

  void _mixTick() {
    if (!_hosting) return;

    // Half-duplex: local RF carrier wins. Never key the radio over a local
    // transmission; drop any buffered network audio while it is present.
    if (_radioInRx) {
      _releaseRadioTx();
      for (final List<int> b in _peerAudio.values) {
        b.clear();
      }
      return;
    }

    final Int32List acc = Int32List(_frameSamples);
    bool any = false;
    for (final List<int> buf in _peerAudio.values) {
      if (buf.length < _frameSamples) continue;
      any = true;
      for (int i = 0; i < _frameSamples; i++) {
        acc[i] += buf[i];
      }
      buf.removeRange(0, _frameSamples);
    }

    if (!any) {
      if (_radioKeyed) {
        _idleTicks++;
        if (_idleTicks >= _txTailTicks) _releaseRadioTx();
      }
      return;
    }

    _idleTicks = 0;
    final Int16List mix = Int16List(_frameSamples);
    for (int i = 0; i < _frameSamples; i++) {
      int s = acc[i];
      if (s > 32767) s = 32767;
      if (s < -32768) s = -32768;
      mix[i] = s;
    }
    final Int16List pcm32 = _txUp.process(mix);
    if (pcm32.isEmpty) return;
    final Uint8List bytes =
        pcm32.buffer.asUint8List(pcm32.offsetInBytes, pcm32.lengthInBytes);
    _broker.dispatch(
      deviceId: _radioDeviceId,
      name: 'TransmitVoicePCM',
      data: <String, Object?>{'data': bytes, 'hold': true},
      store: false,
    );
    if (!_radioKeyed) {
      _radioKeyed = true;
      _broker.dispatch(
          deviceId: allStarNodeDeviceId, name: 'Keyed', data: true, store: false);
    }
  }

  void _releaseRadioTx() {
    _idleTicks = 0;
    _txUp.reset();
    if (!_radioKeyed) return;
    _radioKeyed = false;
    _broker.dispatch(
      deviceId: _radioDeviceId,
      name: 'TransmitVoicePCM',
      data: <String, Object?>{'hold': false},
      store: false,
    );
    _broker.dispatch(
        deviceId: allStarNodeDeviceId, name: 'Keyed', data: false, store: false);
  }

  // --- Peer session events ---------------------------------------------------

  void _onPeerConnected(Iax2ServerSession session) {
    _peerAudio.putIfAbsent(session.localCall, () => <int>[]);
    _publishPeers();
  }

  void _onPeerEnded(Iax2ServerSession session) {
    _peerAudio.remove(session.localCall);
    _publishPeers();
  }

  void _onPeerKeyed(Iax2ServerSession session, bool keyed) {
    // Informational: a peer started/stopped talking. Audio arbitration is
    // handled per-frame in _mixTick; nothing required here for MVP.
  }

  void _onPeerText(Iax2ServerSession session, String text) {
    _broker.logInfo(
        '[AllStarNode] Text from ${session.callerIdNumber}: $text');
  }

  // --- State publishing ------------------------------------------------------

  void _publishState(String state) {
    _broker.dispatch(
        deviceId: allStarNodeDeviceId, name: 'State', data: state, store: false);
  }

  void _publishRegState(Iax2RegState s, {String? detail}) {
    _broker.dispatch(
      deviceId: allStarNodeDeviceId,
      name: 'RegistrationState',
      data: <String, Object?>{'state': s.name, 'detail': detail},
      store: false,
    );
  }

  void _publishPeers() {
    final Iterable<Iax2ServerSession> peers =
        _server?.connectedSessions ?? const <Iax2ServerSession>[];
    final List<Map<String, Object?>> list = peers
        .map((Iax2ServerSession s) => <String, Object?>{
              'node': s.callerIdNumber,
              'name': s.callerIdName,
            })
        .toList();
    _broker.dispatch(
        deviceId: allStarNodeDeviceId,
        name: 'PeerCount',
        data: list.length,
        store: false);
    _broker.dispatch(
        deviceId: allStarNodeDeviceId, name: 'Peers', data: list, store: false);
  }

  // --- Helpers ---------------------------------------------------------------

  static Int16List _int16FromBytes(Uint8List bytes, int offset, int length) {
    final int start = bytes.offsetInBytes + offset;
    final int count = length ~/ 2;
    if (start.isEven) {
      return bytes.buffer.asInt16List(start, count);
    }
    final Int16List out = Int16List(count);
    final ByteData bd = ByteData.sublistView(bytes, offset, offset + length);
    for (int i = 0; i < count; i++) {
      out[i] = bd.getInt16(i * 2, Endian.little);
    }
    return out;
  }
}
