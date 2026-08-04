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
// allstar_client.dart - AllStarLink internet radio for Data Broker device 202.
//
// Orchestrates a single outbound IAX2 call to a saved node (client-to-node,
// DVSwitch / iaxrpt style) and exposes a simple online/connecting/in-call
// lifecycle. Networking is injected so the orchestration is unit-testable
// without real sockets; the IAX2 protocol itself lives in [Iax2Call].
//

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'allstar_audio.dart';
import 'allstar_node.dart';
import 'iax2_call.dart';
import 'iax2_network.dart';

/// Data Broker device id for the internet-only AllStarLink radio.
const int allStarDeviceId = 202;

/// IAX2 username matched by a node's `[allstar-public]` context for AllStarLink
/// portal (Web Transceiver) authentication.
const String allStarPublicUser = 'allstar-public';

/// Fixed IAX2 secret used to satisfy the `[allstar-public]` MD5 challenge; the
/// real authorization is the WT token carried in the CallerID name.
const String allStarPublicSecret = 'allstar';

/// High-level state of the AllStarLink client.
enum AllStarClientState { offline, online, connecting, inCall }

class AllStarClient {
  final Iax2Network network;

  /// Fired with decoded 8 kHz mono PCM received from the node.
  void Function(Int16List pcm8k)? onAudio;

  /// Fired on client-state transitions.
  void Function(AllStarClientState state)? onStateChanged;

  /// Fired with human-readable protocol diagnostics for the Debug tab.
  void Function(String message)? onDiagnostic;

  /// Fired with the node currently being called / in a call, or null.
  void Function(AllStarNode? node)? onConnectedNode;

  AllStarClient({required this.network});

  AllStarClientState _state = AllStarClientState.offline;
  AllStarClientState get state => _state;

  StreamSubscription<Iax2Datagram>? _rxSub;
  Iax2Call? _call;
  AllStarNode? _node;
  bool _opened = false;
  final Random _rand = Random();

  // Outbound PCM accumulated into whole 160-sample (20 ms) voice frames.
  final List<int> _txBuffer = <int>[];

  AllStarNode? get connectedNode =>
      (_state == AllStarClientState.inCall || _state == AllStarClientState.connecting)
          ? _node
          : null;

  void _setState(AllStarClientState s) {
    if (_state == s) return;
    _state = s;
    onStateChanged?.call(s);
  }

  /// Opens the UDP transport and moves to the online (ready) state.
  Future<void> open() async {
    if (_opened) return;
    await network.open();
    _rxSub = network.datagramsIn.listen(_onDatagram);
    _opened = true;
    _setState(AllStarClientState.online);
  }

  /// Places an outbound IAX2 call to [node]. Any existing call is dropped first.
  /// For account (Web Transceiver) nodes, [wtToken] is the portal token sent as
  /// the CallerID name for the node to validate.
  void connectTo(AllStarNode node, {String? wtToken}) {
    if (!_opened) return;
    _endCall();
    _node = node;
    _txBuffer.clear();

    final bool account = node.authMode == AllStarAuthMode.account;
    final String host = node.effectiveHost;
    final int port = node.effectivePort;

    final Iax2Call call = Iax2Call(
      username: account ? allStarPublicUser : node.iaxUser,
      secret: account ? allStarPublicSecret : node.iaxSecret,
      calledNumber: node.nodeNumber,
      callingNumber: account ? node.nodeNumber : null,
      callingName: account ? wtToken : null,
      onSend: (Uint8List d) => network.send(host, port, d),
      onAudio: (Int16List pcm) => onAudio?.call(pcm),
      onStateChanged: _onCallState,
      onDiagnostic: onDiagnostic,
      onHangupCause: (String cause) =>
          onDiagnostic?.call('Node responded: $cause'),
    );
    _call = call;
    _setState(AllStarClientState.connecting);
    onConnectedNode?.call(node);
    call.connect(srcCallNumber: 1 + _rand.nextInt(0x7FFE));
  }

  /// Ends the active call but stays online (ready to place another).
  void disconnect() {
    _endCall();
    if (_opened) _setState(AllStarClientState.online);
  }

  /// Sends outbound 8 kHz mono PCM to the node, framing it into 20 ms frames.
  void sendAudio(Int16List pcm8k) {
    final Iax2Call? call = _call;
    if (call == null || call.state != Iax2CallState.up) return;
    for (final int s in pcm8k) {
      _txBuffer.add(s);
    }
    while (_txBuffer.length >= allStarGsmFrameSamples) {
      final Int16List frame = Int16List(allStarGsmFrameSamples);
      for (int i = 0; i < allStarGsmFrameSamples; i++) {
        frame[i] = _txBuffer[i];
      }
      _txBuffer.removeRange(0, allStarGsmFrameSamples);
      call.sendVoiceFrame(frame);
    }
  }

  /// Drops any partial outbound voice buffer (end of a PTT burst).
  void flushAudio() => _txBuffer.clear();

  /// Closes the transport and releases resources.
  Future<void> close() async {
    _endCall();
    await _rxSub?.cancel();
    _rxSub = null;
    _opened = false;
    _setState(AllStarClientState.offline);
    await network.close();
  }

  void _endCall() {
    _call?.disconnect();
    _call = null;
    _txBuffer.clear();
    if (_node != null) {
      _node = null;
      onConnectedNode?.call(null);
    }
  }

  void _onCallState(Iax2CallState s) {
    switch (s) {
      case Iax2CallState.up:
        _setState(AllStarClientState.inCall);
        onConnectedNode?.call(_node);
        break;
      case Iax2CallState.hungUp:
        // The call ended on its own (remote hangup, reject, timeout).
        _call = null;
        _txBuffer.clear();
        if (_node != null) {
          _node = null;
          onConnectedNode?.call(null);
        }
        if (_opened) _setState(AllStarClientState.online);
        break;
      case Iax2CallState.connecting:
      case Iax2CallState.idle:
        break;
    }
  }

  void _onDatagram(Iax2Datagram dg) {
    // Single active call: forward everything to it. Media from an unexpected
    // host is dropped implicitly because the call ignores unknown call numbers
    // for signaling, but stray audio is harmless with one call in flight.
    _call?.handleDatagram(dg.data);
  }
}
