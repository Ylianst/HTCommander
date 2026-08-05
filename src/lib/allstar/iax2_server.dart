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
// iax2_server.dart - Inbound IAX2 server for hosting an AllStarLink node.
//
// Accepts NEW calls from remote nodes, performs the AUTHREQ / AUTHREP MD5
// handshake against the node password, answers the call (ACCEPT + ANSWER), and
// bridges GSM / mu-law voice both ways. Unlike [Iax2Call] (a single outbound
// call) this manages many concurrent inbound sessions keyed by peer address and
// call number. It is transport-agnostic: datagrams arrive via [handleDatagram]
// and leave via the [onSend] callback (the caller owns the UDP socket).
//

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'allstar_audio.dart';
import 'iax2_constants.dart';
import 'iax2_frame.dart';
import 'iax2_ie.dart';

/// State of one inbound session.
enum Iax2ServerSessionState { authenticating, up, hungUp }

/// Multi-session inbound IAX2 endpoint (an AllStarLink node). Not reusable after
/// [close]; create a new instance to restart hosting.
class Iax2Server {
  /// Sends an encoded datagram to a peer.
  final void Function(String host, int port, Uint8List datagram) onSend;

  /// This node's number (used as CALLERID / for logging).
  final String nodeNumber;

  /// Shared IAX2 secret used to authenticate inbound peers (the node password).
  final String secret;

  /// When true (default) inbound calls must pass MD5 authentication.
  final bool requireAuth;

  /// When true, callers using the AllStarLink public Web Transceiver username
  /// ([webTransceiverUsername]) are authenticated against [webTransceiverSecret]
  /// instead of the node password, so anyone with the WT client can connect.
  final bool allowWebTransceiver;

  /// IAX2 username a Web Transceiver client presents ('allstar-public').
  final String webTransceiverUsername;

  /// Shared MD5 secret satisfying the public Web Transceiver context ('allstar').
  final String webTransceiverSecret;

  /// Optional async check that a Web Transceiver caller's portal token (its IAX2
  /// CallerID name) is valid. Invoked after MD5 auth for WT sessions; the call
  /// is accepted only when it completes with true.
  final Future<bool> Function(String token)? webTransceiverValidator;

  /// Codecs we can decode/encode, advertised in ACCEPT.
  final int capability;

  /// Codec we prefer when the peer supports several.
  final int preferredFormat;

  /// Optional allow-list of peer node numbers (CALLERID). When non-empty, calls
  /// from numbers not in the list are rejected.
  final Set<String> allowList;

  /// Optional deny-list of peer node numbers (CALLERID). Calls from numbers in
  /// the list are always rejected.
  final Set<String> denyList;

  /// Maximum number of concurrent inbound sessions (flood protection).
  final int maxSessions;

  void Function(Iax2ServerSession session)? onSessionConnected;
  void Function(Iax2ServerSession session)? onSessionEnded;
  void Function(Iax2ServerSession session, Int16List pcm8k)? onAudio;
  void Function(Iax2ServerSession session, bool keyed)? onKeyed;
  void Function(Iax2ServerSession session, String text)? onText;
  void Function(String message)? onDiagnostic;

  final Map<int, Iax2ServerSession> _byLocalCall = <int, Iax2ServerSession>{};
  final Map<String, Iax2ServerSession> _byPeer = <String, Iax2ServerSession>{};
  final Random _rng = Random.secure();
  int _nextCall = 1;
  bool _closed = false;

  Iax2Server({
    required this.onSend,
    required this.nodeNumber,
    required this.secret,
    this.requireAuth = true,
    this.allowWebTransceiver = false,
    this.webTransceiverUsername = 'allstar-public',
    this.webTransceiverSecret = 'allstar',
    this.webTransceiverValidator,
    this.capability = Iax2Format.gsm | Iax2Format.ulaw,
    this.preferredFormat = Iax2Format.ulaw,
    Set<String>? allowList,
    Set<String>? denyList,
    this.maxSessions = 16,
    this.onSessionConnected,
    this.onSessionEnded,
    this.onAudio,
    this.onKeyed,
    this.onText,
    this.onDiagnostic,
  })  : allowList = allowList ?? <String>{},
        denyList = denyList ?? <String>{};

  /// Active sessions (any state).
  Iterable<Iax2ServerSession> get sessions => _byLocalCall.values;

  /// Sessions that have completed the handshake and are exchanging media.
  Iterable<Iax2ServerSession> get connectedSessions =>
      _byLocalCall.values.where((Iax2ServerSession s) => s.isUp);

  int get sessionCount => _byLocalCall.length;

  /// The MD5 secret an inbound caller with [username] is authenticated against:
  /// the public Web Transceiver secret when enabled and the caller is a WT
  /// client, otherwise the node password.
  String _secretForUser(String username) {
    if (allowWebTransceiver && username == webTransceiverUsername) {
      return webTransceiverSecret;
    }
    return secret;
  }

  /// Sends one 20 ms (160-sample) 8 kHz PCM frame to every connected peer.
  void broadcastVoiceFrame(Int16List pcm160) {
    for (final Iax2ServerSession s in _byLocalCall.values) {
      s.sendVoiceFrame(pcm160);
    }
  }

  /// Signals key/unkey (COS) state to every connected peer via app_rpt control
  /// frames so linked nodes reflect our radio's carrier.
  void broadcastKey(bool keyed) {
    for (final Iax2ServerSession s in _byLocalCall.values) {
      s.sendKey(keyed);
    }
  }

  /// Routes a received datagram to the owning session, creating one for a NEW.
  void handleDatagram(String host, int port, Uint8List data) {
    if (_closed) return;
    if (iax2IsFullFrame(data)) {
      final Iax2FullFrame? f = Iax2FullFrame.parse(data);
      if (f == null) return;
      _routeFullFrame(host, port, f);
    } else {
      final Iax2MiniFrame? m = Iax2MiniFrame.parse(data);
      if (m == null) return;
      final Iax2ServerSession? s = _byPeer[_peerKey(host, port, m.sourceCallNumber)];
      s?.handleMiniFrame(m);
    }
  }

  void _routeFullFrame(String host, int port, Iax2FullFrame f) {
    // Established frames carry our local call number as the destination.
    if (f.destCallNumber != 0) {
      final Iax2ServerSession? s = _byLocalCall[f.destCallNumber];
      if (s != null && s.host == host && s.port == port) {
        s.handleFullFrame(f);
        return;
      }
    }
    final bool isNew =
        f.frameType == Iax2FrameType.iax && f.subclass == Iax2Subclass.newCall;
    if (isNew) {
      _onNew(host, port, f);
      return;
    }
    // Unknown call. If it looks like a keepalive probe (POKE), answer politely.
    if (f.frameType == Iax2FrameType.iax && f.subclass == Iax2Subclass.poke) {
      _sendBarePong(host, port, f);
    }
  }

  void _onNew(String host, int port, Iax2FullFrame f) {
    final String peerKey = _peerKey(host, port, f.sourceCallNumber);
    final Iax2ServerSession? existing = _byPeer[peerKey];
    if (existing != null) {
      // Retransmitted NEW; let the session re-drive its handshake response.
      existing.handleFullFrame(f);
      return;
    }
    if (_byLocalCall.length >= maxSessions) {
      _rejectBare(host, port, f, 'Too many sessions');
      return;
    }
    final Iax2IeSet ies = f.parseIes();
    final String callerNum = ies.getString(Iax2Ie.callingNumber) ?? '';
    final String callerName = ies.getString(Iax2Ie.callingName) ?? '';
    final String username = ies.getString(Iax2Ie.username) ?? '';
    if (denyList.contains(callerNum) ||
        (allowList.isNotEmpty && !allowList.contains(callerNum))) {
      onDiagnostic?.call('Rejected inbound call from node '
          '${callerNum.isEmpty ? '?' : callerNum} ($host): not permitted');
      _rejectBare(host, port, f, 'Not permitted');
      return;
    }
    final bool viaWt =
        allowWebTransceiver && username == webTransceiverUsername;
    final int localCall = _allocCall();
    final Iax2ServerSession s = Iax2ServerSession._(
      this,
      host: host,
      port: port,
      localCall: localCall,
      peerCall: f.sourceCallNumber,
      callerIdNumber: callerNum,
      callerIdName: callerName,
      authSecret: _secretForUser(username),
      viaWebTransceiver: viaWt,
      peerCapability: ies.getUint(Iax2Ie.capability) ?? Iax2Format.gsm,
      peerFormat: ies.getUint(Iax2Ie.format) ?? Iax2Format.gsm,
      challenge: _newChallenge(),
    );
    _byLocalCall[localCall] = s;
    _byPeer[peerKey] = s;
    onDiagnostic?.call('Inbound IAX2 ${viaWt ? 'Web Transceiver ' : ''}call from '
        'node ${callerNum.isEmpty ? '?' : callerNum} ($host:$port)');
    s._start(f);
  }

  // --- Bare (session-less) responses ----------------------------------------

  void _sendBarePong(String host, int port, Iax2FullFrame f) {
    final Iax2FullFrame pong = Iax2FullFrame(
      sourceCallNumber: 0,
      destCallNumber: f.sourceCallNumber,
      timestamp: f.timestamp,
      oSeqno: 0,
      iSeqno: (f.oSeqno + 1) & 0xFF,
      frameType: Iax2FrameType.iax,
      subclass: Iax2Subclass.pong,
    );
    onSend(host, port, pong.toBytes());
  }

  void _rejectBare(String host, int port, Iax2FullFrame f, String cause) {
    final Iax2IeSet ies = Iax2IeSet();
    ies.addString(Iax2Ie.cause, cause);
    final Iax2FullFrame rej = Iax2FullFrame(
      sourceCallNumber: 0,
      destCallNumber: f.sourceCallNumber,
      timestamp: f.timestamp,
      oSeqno: 0,
      iSeqno: (f.oSeqno + 1) & 0xFF,
      frameType: Iax2FrameType.iax,
      subclass: Iax2Subclass.reject,
    );
    onSend(host, port, rej.toBytes(ies: ies));
  }

  // --- Session bookkeeping ---------------------------------------------------

  int _allocCall() {
    for (int i = 0; i < 0x3FFE; i++) {
      final int c = _nextCall;
      // Server call numbers live in 1..0x3FFE; the registrar uses 0x4000+ so a
      // shared node socket can route replies by destination call number.
      _nextCall = (_nextCall % 0x3FFD) + 1;
      if (!_byLocalCall.containsKey(c)) return c;
    }
    return _nextCall;
  }

  String _newChallenge() => (100000000 + _rng.nextInt(899999999)).toString();

  String _peerKey(String host, int port, int peerCall) => '$host:$port:$peerCall';

  void _removeSession(Iax2ServerSession s) {
    _byLocalCall.remove(s.localCall);
    _byPeer.remove(_peerKey(s.host, s.port, s.peerCall));
    onSessionEnded?.call(s);
  }

  /// Hangs up every session and stops the server.
  void close() {
    if (_closed) return;
    _closed = true;
    for (final Iax2ServerSession s in _byLocalCall.values.toList()) {
      s._teardown(sendHangup: true, notify: false);
    }
    _byLocalCall.clear();
    _byPeer.clear();
  }
}

/// One inbound IAX2 session (a linked remote node). Handles the server-side
/// handshake, ACK reliability, keepalives and per-call media codec state.
class Iax2ServerSession {
  final Iax2Server _server;
  final String host;
  final int port;
  final int localCall;
  int peerCall;

  /// Remote node number (CALLERID number from the NEW frame).
  final String callerIdNumber;

  /// Remote node CALLERID name (often the callsign / description).
  final String callerIdName;

  /// MD5 secret this caller is authenticated against (node password, or the
  /// public Web Transceiver secret for WT clients).
  final String authSecret;

  /// Whether this caller connected as a public Web Transceiver client (and so
  /// its CallerID name carries a portal token to validate).
  final bool viaWebTransceiver;

  /// Codecs the peer advertised in its NEW frame (CAPABILITY bitmask).
  final int peerCapability;

  /// Codec the peer requested in its NEW frame (FORMAT).
  final int peerFormat;

  /// MD5 challenge string issued to authenticate this peer.
  final String challenge;

  Iax2ServerSessionState _state = Iax2ServerSessionState.authenticating;
  int _oSeqno = 0;
  int _iSeqno = 0;
  int _format = Iax2Format.ulaw;
  bool _voiceStreamStarted = false;
  bool _keyed = false;
  bool _validating = false;

  final Stopwatch _clock = Stopwatch()..start();
  final AllStarAudioEncoder _encoder =
      AllStarAudioEncoder(format: Iax2Format.ulaw);
  final AllStarAudioDecoder _decoder =
      AllStarAudioDecoder(format: Iax2Format.ulaw);
  int _lastFullVoiceTs = -_fullVoiceResyncMs;

  final Map<int, _PendingTx> _pending = <int, _PendingTx>{};
  Timer? _retransmitTimer;
  Timer? _inactivityTimer;
  DateTime _lastRx = DateTime.now();

  static const int _retransmitMs = 1000;
  static const int _maxRetransmits = 5;
  static const int _inactivityMs = 60000;
  static const int _fullVoiceResyncMs = 0x8000;

  Iax2ServerSession._(
    this._server, {
    required this.host,
    required this.port,
    required this.localCall,
    required this.peerCall,
    required this.callerIdNumber,
    required this.callerIdName,
    required this.authSecret,
    required this.viaWebTransceiver,
    required this.peerCapability,
    required this.peerFormat,
    required this.challenge,
  });


  bool get isUp => _state == Iax2ServerSessionState.up;
  bool get keyed => _keyed;
  int get negotiatedFormat => _format;

  int _timestamp() => _clock.elapsedMilliseconds & 0xFFFFFFFF;

  void _start(Iax2FullFrame newFrame) {
    _iSeqno = (newFrame.oSeqno + 1) & 0xFF;
    _retransmitTimer = Timer.periodic(
        const Duration(milliseconds: _retransmitMs), (_) => _onRetransmit());
    _inactivityTimer = Timer.periodic(
        const Duration(milliseconds: _inactivityMs ~/ 2), (_) => _checkAlive());
    if (_server.requireAuth) {
      _sendAuthReq();
    } else {
      _accept();
    }
  }

  // --- Inbound ---------------------------------------------------------------

  void handleFullFrame(Iax2FullFrame f) {
    _lastRx = DateTime.now();
    _ackPendingUpTo(f.iSeqno);
    if (_frameCountsForSeq(f)) _iSeqno = (f.oSeqno + 1) & 0xFF;

    switch (f.frameType) {
      case Iax2FrameType.iax:
        _handleIaxCommand(f);
        break;
      case Iax2FrameType.control:
        _handleControl(f);
        _sendAck(f.timestamp);
        break;
      case Iax2FrameType.voice:
        _voiceStreamStarted = true;
        _decodeAndEmit(f.subclass, f.payload);
        _sendAck(f.timestamp);
        break;
      case Iax2FrameType.text:
        _handleText(f.payload);
        _sendAck(f.timestamp);
        break;
      default:
        _sendAck(f.timestamp);
    }
  }

  void handleMiniFrame(Iax2MiniFrame m) {
    if (!_voiceStreamStarted) return;
    _lastRx = DateTime.now();
    _decodeAndEmit(_format, m.payload);
  }

  void _handleIaxCommand(Iax2FullFrame f) {
    switch (f.subclass) {
      case Iax2Subclass.newCall:
        // Retransmitted NEW before we answered: re-drive our response.
        if (_state == Iax2ServerSessionState.authenticating) {
          if (_server.requireAuth) {
            _sendAuthReq();
          } else {
            _accept();
          }
        }
        break;
      case Iax2Subclass.authRep:
        _onAuthRep(f);
        break;
      case Iax2Subclass.ack:
        break;
      case Iax2Subclass.ping:
      case Iax2Subclass.poke:
        _sendCommand(Iax2Subclass.pong, timestampEcho: f.timestamp);
        break;
      case Iax2Subclass.pong:
        _sendAck(f.timestamp);
        break;
      case Iax2Subclass.lagRq:
        _sendCommand(Iax2Subclass.lagRp, timestampEcho: f.timestamp);
        break;
      case Iax2Subclass.lagRp:
        _sendAck(f.timestamp);
        break;
      case Iax2Subclass.hangup:
        _onHangup(f);
        break;
      case Iax2Subclass.reject:
        _sendAck(f.timestamp);
        _teardown(sendHangup: false, notify: true);
        break;
      default:
        _sendAck(f.timestamp);
    }
  }

  void _handleControl(Iax2FullFrame f) {
    switch (f.subclass) {
      case Iax2Control.keyRadio:
        _setKeyed(true);
        break;
      case Iax2Control.unkeyRadio:
        _setKeyed(false);
        break;
      case Iax2Control.hangup:
        _onHangup(f);
        break;
      case Iax2Control.answer:
        // Peer confirms; nothing further required.
        break;
      default:
        break;
    }
  }

  void _onAuthRep(Iax2FullFrame f) {
    final Iax2IeSet ies = f.parseIes();
    final String? md5 = ies.getString(Iax2Ie.md5Result);
    final String expected = iax2Md5Response(challenge, authSecret);
    if (md5 == null || md5.toLowerCase() != expected.toLowerCase()) {
      _server.onDiagnostic?.call(
          'Auth failed for node ${callerIdNumber.isEmpty ? '?' : callerIdNumber}');
      _sendReject('Authentication failed');
      return;
    }
    final Future<bool> Function(String token)? validator =
        _server.webTransceiverValidator;
    if (viaWebTransceiver && validator != null) {
      if (_validating) return;
      _validating = true;
      // Acknowledge the AUTHREP so the peer stops retransmitting while the
      // portal token is validated over the network (may take a moment).
      _sendAck(f.timestamp);
      validator(callerIdName).then((bool ok) {
        _validating = false;
        if (_state != Iax2ServerSessionState.authenticating) return;
        if (ok) {
          _server.onDiagnostic?.call('WT token accepted for '
              '${callerIdNumber.isEmpty ? '?' : callerIdNumber}');
          _accept();
        } else {
          _server.onDiagnostic?.call('WT token rejected for '
              '${callerIdNumber.isEmpty ? '?' : callerIdNumber}');
          _sendReject('Web Transceiver token invalid');
        }
      }).catchError((Object _) {
        _validating = false;
        // Fail open on validator error, matching the node dialplan.
        if (_state == Iax2ServerSessionState.authenticating) _accept();
      });
      return;
    }
    _server.onDiagnostic?.call(
        'Auth OK for node ${callerIdNumber.isEmpty ? '?' : callerIdNumber}');
    _accept();
  }

  void _onHangup(Iax2FullFrame f) {
    _sendAck(f.timestamp);
    _teardown(sendHangup: false, notify: true);
  }

  void _decodeAndEmit(int format, Uint8List payload) {
    if (format != _decoder.format) {
      _decoder.format = _pickSupportedFormat(format);
      _decoder.reset();
    }
    final Int16List? pcm = _decoder.decode(payload);
    if (pcm != null && pcm.isNotEmpty) _server.onAudio?.call(this, pcm);
  }

  void _handleText(Uint8List payload) {
    if (payload.isEmpty) return;
    String text;
    try {
      text = utf8.decode(payload, allowMalformed: true);
    } catch (_) {
      text = String.fromCharCodes(payload);
    }
    text = text.replaceAll('\u0000', '').trim();
    if (text.isEmpty) return;
    _server.onText?.call(this, text);
  }

  void _setKeyed(bool keyed) {
    if (_keyed == keyed) return;
    _keyed = keyed;
    _server.onKeyed?.call(this, keyed);
  }

  // --- Outbound handshake ----------------------------------------------------

  void _sendAuthReq() {
    final Iax2IeSet ies = Iax2IeSet();
    ies.addUint16(Iax2Ie.authMethods, Iax2AuthMethod.md5);
    ies.addString(Iax2Ie.challenge, challenge);
    ies.addString(Iax2Ie.username, _server.nodeNumber);
    _sendReliable(Iax2FrameType.iax, Iax2Subclass.authReq, ies: ies);
  }

  void _accept() {
    _format = _pickFormat(peerCapability, peerFormat);
    _encoder.format = _format;
    _decoder.format = _format;
    final Iax2IeSet ies = Iax2IeSet();
    ies.addUint32(Iax2Ie.format, _format);
    _sendReliable(Iax2FrameType.iax, Iax2Subclass.accept, ies: ies);
    // Answer immediately: HTCommander auto-answers inbound links.
    _sendControl(Iax2Control.answer);
    if (_state != Iax2ServerSessionState.up) {
      _state = Iax2ServerSessionState.up;
      _server.onSessionConnected?.call(this);
    }
  }

  void _sendReject(String cause) {
    final Iax2IeSet ies = Iax2IeSet();
    ies.addString(Iax2Ie.cause, cause);
    _sendReliable(Iax2FrameType.iax, Iax2Subclass.reject, ies: ies);
    _teardown(sendHangup: false, notify: true);
  }

  // --- Outbound media --------------------------------------------------------

  /// Sends one 20 ms (160-sample) 8 kHz PCM frame to the peer.
  void sendVoiceFrame(Int16List pcm160) {
    if (_state != Iax2ServerSessionState.up) return;
    if (pcm160.length < allStarGsmFrameSamples) return;
    final Uint8List payload = _encoder.encodeFrame(pcm160);
    final int ts = _timestamp();
    final bool needFull = !_voiceStreamStarted ||
        (ts - _lastFullVoiceTs) >= _fullVoiceResyncMs ||
        (ts & 0xFFFF) < (_lastFullVoiceTs & 0xFFFF);
    if (needFull) {
      _lastFullVoiceTs = ts;
      _voiceStreamStarted = true;
      final Iax2FullFrame frame = Iax2FullFrame(
        sourceCallNumber: localCall,
        destCallNumber: peerCall,
        timestamp: ts,
        oSeqno: _oSeqno,
        iSeqno: _iSeqno,
        frameType: Iax2FrameType.voice,
        subclass: _format,
        payload: payload,
      );
      _pending[_oSeqno] = _PendingTx(frame.toBytes());
      _oSeqno = (_oSeqno + 1) & 0xFF;
      _server.onSend(host, port, frame.toBytes());
    } else {
      final Iax2MiniFrame mini = Iax2MiniFrame(
        sourceCallNumber: localCall,
        timestamp: ts & 0xFFFF,
        payload: payload,
      );
      _server.onSend(host, port, mini.toBytes());
    }
  }

  /// Sends an app_rpt key/unkey control frame (our radio COS to the peer).
  void sendKey(bool keyed) {
    if (_state != Iax2ServerSessionState.up) return;
    _sendControl(keyed ? Iax2Control.keyRadio : Iax2Control.unkeyRadio);
  }

  // --- Frame plumbing --------------------------------------------------------

  void _sendReliable(int frameType, int subclass,
      {Iax2IeSet? ies, Uint8List? payload}) {
    final Iax2FullFrame frame = Iax2FullFrame(
      sourceCallNumber: localCall,
      destCallNumber: peerCall,
      timestamp: _timestamp(),
      oSeqno: _oSeqno,
      iSeqno: _iSeqno,
      frameType: frameType,
      subclass: subclass,
      payload: payload,
    );
    final Uint8List bytes = frame.toBytes(ies: ies);
    _pending[_oSeqno] = _PendingTx(bytes);
    _oSeqno = (_oSeqno + 1) & 0xFF;
    _server.onSend(host, port, bytes);
  }

  void _sendControl(int subclass) =>
      _sendReliable(Iax2FrameType.control, subclass);

  void _sendCommand(int subclass, {required int timestampEcho}) {
    final Iax2FullFrame frame = Iax2FullFrame(
      sourceCallNumber: localCall,
      destCallNumber: peerCall,
      timestamp: timestampEcho,
      oSeqno: _oSeqno,
      iSeqno: _iSeqno,
      frameType: Iax2FrameType.iax,
      subclass: subclass,
    );
    _server.onSend(host, port, frame.toBytes());
  }

  void _sendAck(int timestampEcho) {
    final Iax2FullFrame frame = Iax2FullFrame(
      sourceCallNumber: localCall,
      destCallNumber: peerCall,
      timestamp: timestampEcho,
      oSeqno: _oSeqno,
      iSeqno: _iSeqno,
      frameType: Iax2FrameType.iax,
      subclass: Iax2Subclass.ack,
    );
    _server.onSend(host, port, frame.toBytes());
  }

  void _onRetransmit() {
    if (_pending.isEmpty) return;
    final List<int> drop = <int>[];
    _pending.forEach((int seq, _PendingTx p) {
      if (p.retries >= _maxRetransmits) {
        drop.add(seq);
        return;
      }
      p.retries++;
      final Uint8List b = Uint8List.fromList(p.bytes);
      b[2] = b[2] | 0x80; // R (retransmit) bit.
      _server.onSend(host, port, b);
    });
    if (drop.isNotEmpty) {
      _server.onDiagnostic?.call(
          'Peer ${callerIdNumber.isEmpty ? host : callerIdNumber} stopped '
          'acknowledging; dropping');
      _teardown(sendHangup: false, notify: true);
    }
  }

  void _checkAlive() {
    if (DateTime.now().difference(_lastRx).inMilliseconds > _inactivityMs) {
      _server.onDiagnostic?.call(
          'Peer ${callerIdNumber.isEmpty ? host : callerIdNumber} timed out');
      _teardown(sendHangup: true, notify: true);
    }
  }

  void _ackPendingUpTo(int peerISeqno) {
    _pending.removeWhere((int seq, _PendingTx p) => _seqBefore(seq, peerISeqno));
  }

  bool _seqBefore(int a, int b) =>
      ((b - a) & 0xFF) != 0 && ((b - a) & 0xFF) < 128;

  bool _frameCountsForSeq(Iax2FullFrame f) {
    if (f.frameType != Iax2FrameType.iax) return true;
    switch (f.subclass) {
      case Iax2Subclass.ack:
      case Iax2Subclass.inval:
      case Iax2Subclass.txCnt:
      case Iax2Subclass.txAcc:
      case Iax2Subclass.vnak:
        return false;
      default:
        return true;
    }
  }

  int _pickFormat(int peerCap, int peerFmt) {
    // Prefer the peer's requested format if we support it, else our preference.
    const List<int> ours = <int>[Iax2Format.ulaw, Iax2Format.gsm];
    if (ours.contains(peerFmt) && (_server.capability & peerFmt) != 0) {
      return peerFmt;
    }
    for (final int f in ours) {
      if ((_server.capability & f) != 0 && (peerCap & f) != 0) return f;
    }
    return _server.preferredFormat;
  }

  int _pickSupportedFormat(int fmt) {
    if (fmt == Iax2Format.gsm || fmt == Iax2Format.ulaw) return fmt;
    return _format;
  }

  void _teardown({required bool sendHangup, required bool notify}) {
    if (_state == Iax2ServerSessionState.hungUp) return;
    if (sendHangup && _state != Iax2ServerSessionState.hungUp) {
      final Iax2IeSet ies = Iax2IeSet();
      ies.addString(Iax2Ie.cause, 'Normal Clearing');
      ies.addRaw(Iax2Ie.causeCode,
          Uint8List.fromList(<int>[Iax2Cause.normalClearing]));
      // Best-effort; do not track for retransmit since we are tearing down.
      final Iax2FullFrame frame = Iax2FullFrame(
        sourceCallNumber: localCall,
        destCallNumber: peerCall,
        timestamp: _timestamp(),
        oSeqno: _oSeqno,
        iSeqno: _iSeqno,
        frameType: Iax2FrameType.iax,
        subclass: Iax2Subclass.hangup,
      );
      _server.onSend(host, port, frame.toBytes(ies: ies));
    }
    _state = Iax2ServerSessionState.hungUp;
    _retransmitTimer?.cancel();
    _inactivityTimer?.cancel();
    _retransmitTimer = null;
    _inactivityTimer = null;
    _pending.clear();
    _clock.stop();
    if (_keyed) {
      _keyed = false;
      _server.onKeyed?.call(this, false);
    }
    if (notify) _server._removeSession(this);
  }

  /// Hangs up this session (sends HANGUP to the peer).
  void hangup() => _teardown(sendHangup: true, notify: true);
}

class _PendingTx {
  final Uint8List bytes;
  int retries = 0;
  _PendingTx(this.bytes);
}
