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
// echolink_qso.dart - Transport-agnostic EchoLink connection state machine.
//
// Models the connection handshake and framing of a single EchoLink QSO,
// mirroring reference/svxlink/src/echolib/EchoLinkQso.cpp but without any
// sockets or timers: outgoing packets are handed to injected sinks and the
// keep-alive / timeout timers are driven by the host via [onKeepAliveTick] and
// [onConnectionTimeout]. The UDP transport (ports 5198 audio / 5199 control)
// and directory/proxy layers are wired in separately.
//

import 'dart:typed_data';

import 'echolink_audio.dart';
import 'echolink_data_packet.dart';
import 'rtcp_packet.dart';

/// Default UDP port for audio and info/chat data.
const int echoLinkAudioPort = 5198;

/// Default UDP port for RTCP control (SDES/BYE).
const int echoLinkControlPort = 5199;

/// Connection state of a QSO (Qso::State).
enum QsoState { disconnected, connecting, connected, byeReceived }

/// A single EchoLink peer connection. Not tied to any I/O; the host wires the
/// [sendControl] / [sendAudio] sinks to UDP sockets and calls the handle* and
/// timer methods.
class EchoLinkQso {
  /// SDES keep-alive interval in milliseconds (KEEP_ALIVE_TIME).
  static const int keepAliveMs = 10000;

  /// Connection inactivity timeout in milliseconds (CON_TIMEOUT_TIME).
  static const int connectionTimeoutMs = 50000;

  final String localCallsign;
  final String localName;
  String localInfo;

  /// Sends a control-port datagram (RTCP SDES/BYE) to the remote station.
  final void Function(Uint8List packet) sendControl;

  /// Sends an audio-port datagram (voice or info/chat) to the remote station.
  final void Function(Uint8List packet) sendAudio;

  /// Fired when the connection state changes.
  void Function(QsoState state)? onStateChanged;

  /// Fired with 640 decoded samples for each received voice packet.
  void Function(Int16List pcm)? onAudio;

  /// Fired when a station-info message is received.
  void Function(String info)? onInfo;

  /// Fired when a chat message is received.
  void Function(EchoLinkChat chat)? onChat;

  /// Fired when the remote station's callsign/name is learned from SDES.
  void Function(SdesStation station)? onRemoteStation;

  /// Fired whenever a valid keep-alive (SDES) is received while connecting or
  /// connected; the host should reset its inactivity timeout on this.
  void Function()? onKeepAlive;

  final Uint8List _sdes;
  final EchoLinkAudioEncoder _encoder;
  final EchoLinkAudioDecoder _decoder = EchoLinkAudioDecoder();

  QsoState _state = QsoState.disconnected;
  bool _remoteInitiated = false;

  EchoLinkQso({
    required this.localCallsign,
    this.localName = '',
    this.localInfo = '',
    int ssrc = 0,
    required this.sendControl,
    required this.sendAudio,
  })  : _sdes = buildSdes(callsign: localCallsign, name: localName),
        _encoder = EchoLinkAudioEncoder(ssrc: ssrc);

  QsoState get state => _state;

  /// True if the connection was initiated by the remote station.
  bool get isRemoteInitiated => _remoteInitiated;

  void _setState(QsoState s) {
    if (_state != s) {
      _state = s;
      onStateChanged?.call(s);
    }
  }

  // ---- Local actions ------------------------------------------------------

  /// Initiates an outgoing connection: sends the initial SDES and enters the
  /// connecting state. Returns false if already connecting/connected.
  bool connect() {
    if (_state != QsoState.disconnected) return false;
    _remoteInitiated = false;
    _encoder.reset();
    sendControl(_sdes);
    _openAudioPath();
    _setState(QsoState.connecting);
    return true;
  }

  /// Accepts an incoming connection: sends SDES and enters the connected state.
  bool accept() {
    if (_state != QsoState.disconnected) return false;
    _remoteInitiated = true;
    _encoder.reset();
    sendControl(_sdes);
    _openAudioPath();
    _setState(QsoState.connected);
    return true;
  }

  /// Sends a station-info packet on the audio port (5198). Besides announcing
  /// our info to the peer (standard EchoLink connect behaviour), this is what
  /// opens and keeps alive the *inbound* NAT/firewall pinhole for the audio
  /// port. A receive-only listener never transmits voice, so without this the
  /// control port (5199) stays reachable via the SDES keep-alives while inbound
  /// voice on 5198 is silently dropped by the NAT — the classic "connected but
  /// no audio" symptom. Sent at connect and on every keep-alive tick.
  void _openAudioPath() {
    sendAudio(buildInfoPacket(localInfo));
  }

  /// Tears down the connection, sending a BYE unless one was just received.
  bool disconnect() {
    if (_state == QsoState.disconnected) return true;
    if (_state != QsoState.byeReceived) {
      sendControl(buildBye());
    }
    _setState(QsoState.disconnected);
    return true;
  }

  /// Encodes and sends one 640-sample (80 ms) voice packet. No-op unless
  /// connected.
  void sendAudioFrame(Int16List pcm640) {
    if (_state != QsoState.connected) return;
    sendAudio(_encoder.encodePacket(pcm640));
  }

  /// Sends a station-info message (defaults to [localInfo]). No-op unless
  /// connected.
  void sendInfo([String? info]) {
    if (_state != QsoState.connected) return;
    sendAudio(buildInfoPacket(info ?? localInfo));
  }

  /// Sends a chat message. No-op unless connected.
  void sendChat(String msg) {
    if (_state != QsoState.connected) return;
    sendAudio(buildChatPacket(localCallsign, msg));
  }

  // ---- Incoming packets ---------------------------------------------------

  /// Handles a datagram received on the control port (RTCP SDES/BYE).
  void handleControlPacket(Uint8List data) {
    if (isByePacket(data)) {
      _handleBye();
    } else if (isSdesPacket(data)) {
      _handleSdes(data);
    }
  }

  void _handleBye() {
    if (_state != QsoState.disconnected) {
      _setState(QsoState.byeReceived);
      disconnect();
    }
  }

  void _handleSdes(Uint8List data) {
    final SdesStation? station = parseSdesStation(data);
    if (station != null) onRemoteStation?.call(station);

    switch (_state) {
      case QsoState.connecting:
        _setState(QsoState.connected);
        onKeepAlive?.call();
        break;
      case QsoState.connected:
        onKeepAlive?.call();
        break;
      case QsoState.disconnected:
      case QsoState.byeReceived:
        break;
    }
  }

  /// Handles a datagram received on the audio port (voice or info/chat).
  void handleAudioPacket(Uint8List data) {
    switch (classifyAudioPortPacket(data)) {
      case EchoLinkAudioPortPacket.audio:
        final Int16List? pcm = _decoder.decodePacket(data);
        if (pcm != null) onAudio?.call(pcm);
        break;
      case EchoLinkAudioPortPacket.info:
        onInfo?.call(parseInfoPacket(data));
        break;
      case EchoLinkAudioPortPacket.chat:
        onChat?.call(parseChatPacket(data));
        break;
      case EchoLinkAudioPortPacket.unknown:
        break;
    }
  }

  // ---- Timer hooks --------------------------------------------------------

  /// Host should call this every [keepAliveMs] to resend SDES while connecting
  /// or connected.
  void onKeepAliveTick() {
    if (_state == QsoState.connecting || _state == QsoState.connected) {
      sendControl(_sdes);
      _openAudioPath();
    }
  }

  /// Host should call this when no packet has been received for
  /// [connectionTimeoutMs]; drops the connection.
  void onConnectionTimeout() {
    if (_state != QsoState.disconnected) {
      _setState(QsoState.disconnected);
    }
  }
}
