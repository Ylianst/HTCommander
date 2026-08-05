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
// iax2_registrar.dart - IAX2 registration client for an AllStarLink node.
//
// Periodically registers this node's number + password with the AllStarLink
// registration server so the network DNS (<node>.nodes.allstarlink.org)
// publishes our current public address and other nodes can link to us. The
// exchange is REGREQ -> REGAUTH -> REGREQ(md5) -> REGACK (RFC 5456 section 6.9).
//
// Transport-agnostic: datagrams to the registration server leave via [onSend]
// and replies arrive via [handleDatagram]. It shares the node's UDP socket so
// the address the server perceives (and publishes) is the node's inbound port.
//

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'iax2_constants.dart';
import 'iax2_frame.dart';
import 'iax2_ie.dart';

/// Registration lifecycle state.
enum Iax2RegState { idle, registering, registered, failed }

/// Registers a node with the AllStarLink registration server and keeps the
/// registration refreshed. Reusable across restarts via [start] / [stop].
class Iax2Registrar {
  /// Sends an encoded datagram to the registration server.
  final void Function(Uint8List datagram) onSend;

  /// Node number registered (IAX2 USERNAME).
  final String nodeNumber;

  /// Node password (shared secret for MD5 registration auth).
  final String secret;

  /// Requested refresh interval in seconds (the server may shorten it).
  final int refreshSeconds;

  void Function(Iax2RegState state, {String? detail})? onStateChanged;
  void Function(String message)? onDiagnostic;

  final Random _rng = Random.secure();
  int _srcCall = 0;
  int _dstCall = 0;
  int _oSeqno = 0;
  int _iSeqno = 0;
  int _authSent = 0;
  Iax2RegState _state = Iax2RegState.idle;

  Timer? _retransmitTimer;
  Timer? _refreshTimer;
  Uint8List? _pending;
  int _retries = 0;
  bool _stopped = true;

  static const int _retransmitMs = 1000;
  static const int _maxRetransmits = 4;

  Iax2Registrar({
    required this.onSend,
    required this.nodeNumber,
    required this.secret,
    this.refreshSeconds = 60,
    this.onStateChanged,
    this.onDiagnostic,
  });

  Iax2RegState get state => _state;

  /// This registration leg's local call number. Lives in the 0x4000+ range so a
  /// shared node socket can route replies to the registrar vs. inbound sessions.
  int get localCall => _srcCall;

  /// Begins (or restarts) registration.
  void start() {
    _stopped = false;
    _sendRegReq(withAuth: false);
  }

  /// Stops registering (optionally sending REGREL to deregister).
  void stop({bool release = true}) {
    _stopped = true;
    _retransmitTimer?.cancel();
    _refreshTimer?.cancel();
    _retransmitTimer = null;
    _refreshTimer = null;
    _pending = null;
    if (release && _state == Iax2RegState.registered && _dstCall != 0) {
      _send(Iax2Subclass.regRel, _regReqIes(withAuth: true));
    }
    _setState(Iax2RegState.idle);
  }

  void _setState(Iax2RegState s, {String? detail}) {
    if (_state == s && detail == null) return;
    _state = s;
    onStateChanged?.call(s, detail: detail);
  }

  // --- Outbound --------------------------------------------------------------

  Iax2IeSet _regReqIes({required bool withAuth}) {
    final Iax2IeSet ies = Iax2IeSet();
    ies.addString(Iax2Ie.username, nodeNumber);
    if (withAuth && _challenge != null) {
      ies.addString(Iax2Ie.md5Result, iax2Md5Response(_challenge!, secret));
    }
    ies.addUint16(Iax2Ie.refresh, refreshSeconds);
    return ies;
  }

  String? _challenge;

  void _sendRegReq({required bool withAuth}) {
    if (!withAuth) {
      _srcCall = 0x4000 + _rng.nextInt(0x3FFD);
      _dstCall = 0;
      _oSeqno = 0;
      _iSeqno = 0;
      _challenge = null;
    }
    _authSent = withAuth ? _authSent + 1 : 0;
    _setState(Iax2RegState.registering);
    _send(Iax2Subclass.regReq, _regReqIes(withAuth: withAuth));
  }

  void _send(int subclass, Iax2IeSet ies) {
    final Iax2FullFrame frame = Iax2FullFrame(
      sourceCallNumber: _srcCall,
      destCallNumber: _dstCall,
      timestamp: 0,
      oSeqno: _oSeqno,
      iSeqno: _iSeqno,
      frameType: Iax2FrameType.iax,
      subclass: subclass,
    );
    final Uint8List bytes = frame.toBytes(ies: ies);
    _oSeqno = (_oSeqno + 1) & 0xFF;
    _pending = bytes;
    _retries = 0;
    _retransmitTimer?.cancel();
    _retransmitTimer = Timer.periodic(
        const Duration(milliseconds: _retransmitMs), (_) => _onRetransmit());
    onSend(bytes);
  }

  void _sendAck(int timestampEcho) {
    final Iax2FullFrame frame = Iax2FullFrame(
      sourceCallNumber: _srcCall,
      destCallNumber: _dstCall,
      timestamp: timestampEcho,
      oSeqno: _oSeqno,
      iSeqno: _iSeqno,
      frameType: Iax2FrameType.iax,
      subclass: Iax2Subclass.ack,
    );
    onSend(frame.toBytes());
  }

  void _onRetransmit() {
    final Uint8List? p = _pending;
    if (p == null) return;
    if (_retries >= _maxRetransmits) {
      _retransmitTimer?.cancel();
      _retransmitTimer = null;
      _pending = null;
      onDiagnostic?.call('Registration server did not respond');
      _setState(Iax2RegState.failed, detail: 'No response');
      _scheduleRetry();
      return;
    }
    _retries++;
    final Uint8List b = Uint8List.fromList(p);
    b[2] = b[2] | 0x80;
    onSend(b);
  }

  // --- Inbound ---------------------------------------------------------------

  void handleDatagram(Uint8List data) {
    if (_stopped) return;
    if (!iax2IsFullFrame(data)) return;
    final Iax2FullFrame? f = Iax2FullFrame.parse(data);
    if (f == null || f.frameType != Iax2FrameType.iax) return;
    if (_dstCall == 0 && f.sourceCallNumber != 0) _dstCall = f.sourceCallNumber;
    _iSeqno = (f.oSeqno + 1) & 0xFF;
    switch (f.subclass) {
      case Iax2Subclass.regAuth:
        _pending = null;
        _retransmitTimer?.cancel();
        _onRegAuth(f);
        break;
      case Iax2Subclass.regAck:
        _pending = null;
        _retransmitTimer?.cancel();
        _retransmitTimer = null;
        _onRegAck(f);
        break;
      case Iax2Subclass.regRej:
        _pending = null;
        _retransmitTimer?.cancel();
        _retransmitTimer = null;
        _onRegRej(f);
        break;
      case Iax2Subclass.ack:
        break;
      default:
        break;
    }
  }

  void _onRegAuth(Iax2FullFrame f) {
    final Iax2IeSet ies = f.parseIes();
    final int methods = ies.getUint(Iax2Ie.authMethods) ?? 0;
    _challenge = ies.getString(Iax2Ie.challenge);
    if ((methods & Iax2AuthMethod.md5) == 0 || _challenge == null) {
      onDiagnostic?.call('Registration auth method unsupported');
      _setState(Iax2RegState.failed, detail: 'Unsupported auth');
      _scheduleRetry();
      return;
    }
    if (_authSent >= _maxRetransmits) {
      _setState(Iax2RegState.failed, detail: 'Auth rejected');
      _scheduleRetry();
      return;
    }
    _sendRegReq(withAuth: true);
  }

  void _onRegAck(Iax2FullFrame f) {
    _sendAck(f.timestamp);
    final Iax2IeSet ies = f.parseIes();
    final int? refresh = ies.getUint(Iax2Ie.refresh);
    final String? addr = _formatApparentAddr(ies.raw(Iax2Ie.apparentAddr));
    onDiagnostic?.call(
        'Node $nodeNumber registered${addr != null ? ' (seen as $addr)' : ''}');
    _setState(Iax2RegState.registered, detail: addr);
    final int next = (refresh != null && refresh > 5) ? refresh : refreshSeconds;
    _scheduleRefresh(next);
  }

  void _onRegRej(Iax2FullFrame f) {
    _sendAck(f.timestamp);
    final String? cause = f.parseIes().getString(Iax2Ie.cause);
    onDiagnostic?.call('Registration rejected${cause != null ? ' ($cause)' : ''}');
    _setState(Iax2RegState.failed, detail: cause ?? 'Rejected');
    _scheduleRetry();
  }

  // --- Scheduling ------------------------------------------------------------

  void _scheduleRefresh(int seconds) {
    _refreshTimer?.cancel();
    final int lead = seconds > 15 ? seconds - 10 : seconds;
    _refreshTimer = Timer(Duration(seconds: lead), () {
      if (!_stopped) _sendRegReq(withAuth: false);
    });
  }

  void _scheduleRetry() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(seconds: 30), () {
      if (!_stopped) _sendRegReq(withAuth: false);
    });
  }

  /// Formats an APPARENTADDR IE (sockaddr_in) as "ip:port" for diagnostics.
  static String? _formatApparentAddr(Uint8List? d) {
    if (d == null || d.length < 8) return null;
    final int port = (d[2] << 8) | d[3];
    final String ip = '${d[4]}.${d[5]}.${d[6]}.${d[7]}';
    return '$ip:$port';
  }
}
