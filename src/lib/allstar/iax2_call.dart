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
// iax2_call.dart - IAX2 outbound call state machine (client to an AllStarLink
// node). Handles the NEW / AUTHREQ / AUTHREP / ACCEPT / ANSWER handshake, ACK
// reliability with retransmission, PING/PONG and LAGRQ/LAGRP keepalives, and
// GSM / mu-law voice media over mini and full frames.
//
// The call is transport-agnostic: it emits datagrams through [onSend] (the
// caller routes them to the node's single UDP host:port) and receives them via
// [handleDatagram]. Timers are internal but always cancelled on teardown.
//

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'allstar_audio.dart';
import 'iax2_constants.dart';
import 'iax2_frame.dart';
import 'iax2_ie.dart';

/// High-level call state exposed to the client.
enum Iax2CallState { idle, connecting, up, hungUp }

/// Manages one outbound IAX2 call. Not reusable after [disconnect].
class Iax2Call {
  /// Sends an encoded datagram to the remote node.
  final void Function(Uint8List datagram) onSend;

  /// Delivers decoded 8 kHz mono PCM received from the node.
  final void Function(Int16List pcm8k) onAudio;

  /// Reports call-state transitions.
  final void Function(Iax2CallState state) onStateChanged;

  /// Optional callback for text messages received from the node (IAX2 TEXT
  /// frames, e.g. app_rpt node status / connection announcements).
  final void Function(String text)? onText;

  /// Optional human-readable protocol diagnostics (routed to the Debug tab).
  final void Function(String message)? onDiagnostic;

  /// Called with the Q.931 cause text when the call is rejected/hung up.
  final void Function(String cause)? onHangupCause;

  final String username;
  final String secret;
  final String calledNumber;

  /// CallerID number sent in the NEW frame. Defaults to [username] (iaxRPT
  /// style); account (Web Transceiver) calls set it to the target node number.
  final String? callingNumber;

  /// CallerID name sent in the NEW frame. For account (Web Transceiver) auth
  /// this carries the portal token the node validates; null otherwise.
  final String? callingName;

  /// Codecs we can decode/encode, advertised in CAPABILITY.
  final int capability;

  /// Codec we prefer, advertised in FORMAT.
  final int preferredFormat;

  Iax2Call({
    required this.onSend,
    required this.onAudio,
    required this.onStateChanged,
    required this.username,
    required this.secret,
    required this.calledNumber,
    this.callingNumber,
    this.callingName,
    this.capability = Iax2Format.gsm | Iax2Format.ulaw,
    this.preferredFormat = Iax2Format.gsm,
    this.onDiagnostic,
    this.onHangupCause,
    this.onText,
  });

  // Timing.
  static const int _pingIntervalMs = 20000;
  static const int _retransmitMs = 1000;
  static const int _maxRetransmits = 5;
  static const int _connectTimeoutMs = 10000;
  static const int _fullVoiceResyncMs = 0x8000; // 32768 ms.

  Iax2CallState _state = Iax2CallState.idle;
  Iax2CallState get state => _state;

  int _srcCall = 0;
  int _dstCall = 0;
  int _oSeqno = 0;
  int _iSeqno = 0;
  int _format = Iax2Format.gsm; // Negotiated media format (from ACCEPT).

  final Stopwatch _clock = Stopwatch();
  bool _authSent = false;
  bool _acceptReceived = false;

  final AllStarAudioEncoder _encoder =
      AllStarAudioEncoder(format: Iax2Format.gsm);
  final AllStarAudioDecoder _decoder =
      AllStarAudioDecoder(format: Iax2Format.gsm);
  int _lastFullVoiceTs = -_fullVoiceResyncMs;
  bool _voiceStreamStarted = false;

  // Reliable frames awaiting ACK: oSeqno -> (bytes, retries).
  final Map<int, _Pending> _pending = <int, _Pending>{};

  Timer? _retransmitTimer;
  Timer? _pingTimer;
  Timer? _connectTimer;

  int _timestamp() => _clock.elapsedMilliseconds & 0xFFFFFFFF;

  void _setState(Iax2CallState s) {
    if (_state == s) return;
    _state = s;
    onStateChanged(s);
  }

  /// Starts the outbound call by sending a NEW frame. [srcCallNumber] must be a
  /// non-zero 15-bit value unique on this transport.
  void connect({required int srcCallNumber}) {
    _srcCall = srcCallNumber & 0x7FFF;
    if (_srcCall == 0) _srcCall = 1;
    _clock.start();
    _setState(Iax2CallState.connecting);

    final Iax2IeSet ies = Iax2IeSet();
    ies.addUint16(Iax2Ie.version, iax2ProtocolVersion); // Must be first.
    ies.addString(Iax2Ie.calledNumber, calledNumber);
    ies.addString(Iax2Ie.callingNumber, callingNumber ?? username);
    if (callingName != null && callingName!.isNotEmpty) {
      ies.addString(Iax2Ie.callingName, callingName!);
    }
    ies.addRaw(Iax2Ie.callingPres, Uint8List(1)); // Allowed, not screened.
    ies.addRaw(Iax2Ie.callingTon, Uint8List(1)); // Unknown.
    ies.addUint16(Iax2Ie.callingTns, 0);
    ies.addString(Iax2Ie.username, username);
    ies.addUint32(Iax2Ie.capability, capability);
    ies.addUint32(Iax2Ie.format, preferredFormat);
    _sendReliable(Iax2FrameType.iax, Iax2Subclass.newCall, ies: ies);

    _retransmitTimer =
        Timer.periodic(const Duration(milliseconds: _retransmitMs), (_) => _onRetransmit());
    _connectTimer = Timer(const Duration(milliseconds: _connectTimeoutMs), () {
      if (_state == Iax2CallState.connecting) {
        _diag('Connect timed out (no ACCEPT/ANSWER)');
        _teardown(Iax2CallState.hungUp);
      }
    });
  }

  /// Ends the call, sending HANGUP if it had progressed past idle.
  void disconnect() {
    if (_state == Iax2CallState.connecting || _state == Iax2CallState.up) {
      final Iax2IeSet ies = Iax2IeSet();
      ies.addString(Iax2Ie.cause, 'Normal Clearing');
      ies.addRaw(Iax2Ie.causeCode,
          Uint8List.fromList(<int>[Iax2Cause.normalClearing]));
      _sendReliable(Iax2FrameType.iax, Iax2Subclass.hangup, ies: ies);
    }
    _teardown(Iax2CallState.hungUp);
  }

  void _teardown(Iax2CallState finalState) {
    _retransmitTimer?.cancel();
    _pingTimer?.cancel();
    _connectTimer?.cancel();
    _retransmitTimer = null;
    _pingTimer = null;
    _connectTimer = null;
    _pending.clear();
    _clock.stop();
    _setState(finalState);
  }

  // --- Sending ---------------------------------------------------------------

  void _sendReliable(int frameType, int subclass,
      {Iax2IeSet? ies, Uint8List? payload}) {
    final Iax2FullFrame frame = Iax2FullFrame(
      sourceCallNumber: _srcCall,
      destCallNumber: _dstCall,
      timestamp: _timestamp(),
      oSeqno: _oSeqno,
      iSeqno: _iSeqno,
      frameType: frameType,
      subclass: subclass,
      payload: payload,
    );
    final Uint8List bytes = frame.toBytes(ies: ies);
    _pending[_oSeqno] = _Pending(bytes);
    _oSeqno = (_oSeqno + 1) & 0xFF;
    onSend(bytes);
  }

  void _sendAck(int subclass, int timestampEcho) {
    // ACK/PONG/etc. do not increment the outbound sequence number.
    final Iax2FullFrame frame = Iax2FullFrame(
      sourceCallNumber: _srcCall,
      destCallNumber: _dstCall,
      timestamp: timestampEcho,
      oSeqno: _oSeqno,
      iSeqno: _iSeqno,
      frameType: Iax2FrameType.iax,
      subclass: subclass,
    );
    onSend(frame.toBytes());
  }

  void _onRetransmit() {
    if (_pending.isEmpty) return;
    final List<int> drop = <int>[];
    _pending.forEach((int seq, _Pending p) {
      if (p.retries >= _maxRetransmits) {
        drop.add(seq);
        return;
      }
      p.retries++;
      // Set the R (retransmit) bit on resend.
      final Uint8List b = Uint8List.fromList(p.bytes);
      b[2] = b[2] | 0x80;
      onSend(b);
    });
    if (drop.isNotEmpty) {
      _diag('No ACK after $_maxRetransmits retries; dropping call');
      _teardown(Iax2CallState.hungUp);
    }
  }

  // --- Receiving -------------------------------------------------------------

  /// Processes a datagram received from the node.
  void handleDatagram(Uint8List data) {
    if (_state == Iax2CallState.idle || _state == Iax2CallState.hungUp) return;
    if (iax2IsFullFrame(data)) {
      final Iax2FullFrame? f = Iax2FullFrame.parse(data);
      if (f != null) _handleFullFrame(f);
    } else {
      final Iax2MiniFrame? m = Iax2MiniFrame.parse(data);
      if (m != null) _handleMiniFrame(m);
    }
  }

  void _handleFullFrame(Iax2FullFrame f) {
    // Learn the peer's call number from its first reply.
    if (_dstCall == 0 && f.sourceCallNumber != 0) {
      _dstCall = f.sourceCallNumber;
    }

    // Clear pending frames the peer has acknowledged.
    _ackPendingUpTo(f.iSeqno);

    final bool counts = _frameCountsForSeq(f);
    if (counts) {
      _iSeqno = (f.oSeqno + 1) & 0xFF;
    }

    if (f.frameType == Iax2FrameType.iax) {
      _handleIaxCommand(f);
    } else if (f.frameType == Iax2FrameType.control) {
      _handleControl(f);
      _sendAck(Iax2Subclass.ack, f.timestamp);
    } else if (f.frameType == Iax2FrameType.voice) {
      _voiceStreamStarted = true;
      _decodeAndEmit(f.subclass, f.payload);
      _sendAck(Iax2Subclass.ack, f.timestamp);
    } else if (f.frameType == Iax2FrameType.text) {
      _handleText(f.payload);
      _sendAck(Iax2Subclass.ack, f.timestamp);
    } else {
      // Other reliable frames: acknowledge and ignore.
      _sendAck(Iax2Subclass.ack, f.timestamp);
    }
  }

  void _handleIaxCommand(Iax2FullFrame f) {
    switch (f.subclass) {
      case Iax2Subclass.authReq:
        _onAuthReq(f);
        break;
      case Iax2Subclass.accept:
        _onAccept(f);
        break;
      case Iax2Subclass.ack:
        break; // Pure acknowledgement; already processed via iSeqno.
      case Iax2Subclass.ping:
      case Iax2Subclass.poke:
        _sendAck(Iax2Subclass.pong, f.timestamp);
        break;
      case Iax2Subclass.pong:
        _sendAck(Iax2Subclass.ack, f.timestamp);
        break;
      case Iax2Subclass.lagRq:
        _sendAck(Iax2Subclass.lagRp, f.timestamp);
        break;
      case Iax2Subclass.lagRp:
        _sendAck(Iax2Subclass.ack, f.timestamp);
        break;
      case Iax2Subclass.hangup:
        _onHangup(f);
        break;
      case Iax2Subclass.reject:
        _onReject(f);
        break;
      case Iax2Subclass.inval:
        _diag('Received INVAL; call no longer valid');
        _teardown(Iax2CallState.hungUp);
        break;
      default:
        // Unknown reliable IAX command: acknowledge to keep the peer happy.
        _sendAck(Iax2Subclass.ack, f.timestamp);
    }
  }

  void _onAuthReq(Iax2FullFrame f) {
    final Iax2IeSet ies = f.parseIes();
    final int methods = ies.getUint(Iax2Ie.authMethods) ?? 0;
    final String? challenge = ies.getString(Iax2Ie.challenge);
    if ((methods & Iax2AuthMethod.md5) == 0 || challenge == null) {
      _diag('AUTHREQ without MD5 support (methods=$methods)');
      _sendReject('Unsupported auth method');
      return;
    }
    final Iax2IeSet rep = Iax2IeSet();
    rep.addString(Iax2Ie.md5Result, iax2Md5Response(challenge, secret));
    _authSent = true;
    _sendReliable(Iax2FrameType.iax, Iax2Subclass.authRep, ies: rep);
    _diag('Sent AUTHREP (MD5)');
  }

  void _onAccept(Iax2FullFrame f) {
    final Iax2IeSet ies = f.parseIes();
    final int fmt = ies.getUint(Iax2Ie.format) ?? preferredFormat;
    _format = _pickSupportedFormat(fmt);
    _encoder.format = _format;
    _decoder.format = _format;
    _acceptReceived = true;
    _sendAck(Iax2Subclass.ack, f.timestamp);
    _diag('Call accepted, format=${Iax2Format.name(_format)}');
    // Some nodes answer immediately; treat ACCEPT as enough to start media if
    // ANSWER is slow, but only mark "up" on ANSWER.
    _startPingKeepalive();
  }

  void _handleControl(Iax2FullFrame f) {
    switch (f.subclass) {
      case Iax2Control.answer:
        _diag('Node answered');
        _connectTimer?.cancel();
        _setState(Iax2CallState.up);
        break;
      case Iax2Control.hangup:
        _onHangup(f);
        break;
      case Iax2Control.busy:
        _diag('Node busy');
        _teardown(Iax2CallState.hungUp);
        break;
      case Iax2Control.congestion:
        _diag('Network congestion');
        _teardown(Iax2CallState.hungUp);
        break;
      default:
        break; // Ringing / proceeding / key-radio: informational.
    }
  }

  void _onHangup(Iax2FullFrame f) {
    final String? cause = f.parseIes().getString(Iax2Ie.cause);
    _sendAck(Iax2Subclass.ack, f.timestamp);
    if (cause != null) onHangupCause?.call(cause);
    _diag('Node hung up${cause != null ? ' ($cause)' : ''}');
    _teardown(Iax2CallState.hungUp);
  }

  void _onReject(Iax2FullFrame f) {
    final String? cause = f.parseIes().getString(Iax2Ie.cause);
    _sendAck(Iax2Subclass.ack, f.timestamp);
    if (cause != null) onHangupCause?.call(cause);
    _diag('Call rejected${cause != null ? ' ($cause)' : ''}');
    // A "No such context/extension" reject means auth succeeded but the node
    // has no dialplan route for us: Web Transceiver access is not enabled there.
    if (cause != null && cause.toLowerCase().contains('no such context')) {
      _diag('This node has not enabled Web Transceiver access; try a node you '
          'own with WT enabled in your AllStarLink portal.');
    }
    _teardown(Iax2CallState.hungUp);
  }

  void _sendReject(String cause) {
    final Iax2IeSet ies = Iax2IeSet();
    ies.addString(Iax2Ie.cause, cause);
    _sendReliable(Iax2FrameType.iax, Iax2Subclass.reject, ies: ies);
    _teardown(Iax2CallState.hungUp);
  }

  // --- Media -----------------------------------------------------------------

  void _handleMiniFrame(Iax2MiniFrame m) {
    if (!_voiceStreamStarted) return; // No full voice frame seen yet.
    _decodeAndEmit(_format, m.payload);
  }

  void _decodeAndEmit(int format, Uint8List payload) {
    if (format != _decoder.format) {
      _decoder.format = _pickSupportedFormat(format);
      _decoder.reset();
    }
    final Int16List? pcm = _decoder.decode(payload);
    if (pcm != null && pcm.isNotEmpty) onAudio(pcm);
  }

  void _handleText(Uint8List payload) {
    if (payload.isEmpty) return;
    String text;
    try {
      text = utf8.decode(payload, allowMalformed: true);
    } catch (_) {
      text = String.fromCharCodes(payload);
    }
    // IAX2 text frames may be null-terminated; trim trailing NULs/whitespace.
    text = text.replaceAll('\u0000', '').trim();
    if (text.isEmpty) return;
    onText?.call(text);
  }

  /// Sends one 20 ms (160-sample) frame of outbound 8 kHz PCM. Uses a full voice
  /// frame to (re)establish the codec, then mini frames.
  void sendVoiceFrame(Int16List pcm160) {
    if (_state != Iax2CallState.up) return;
    final Uint8List payload = _encoder.encodeFrame(pcm160);
    final int ts = _timestamp();
    final bool needFull = !_voiceStreamStarted ||
        (ts - _lastFullVoiceTs) >= _fullVoiceResyncMs ||
        (ts & 0xFFFF) < (_lastFullVoiceTs & 0xFFFF);
    if (needFull) {
      _lastFullVoiceTs = ts;
      _voiceStreamStarted = true;
      final Iax2FullFrame frame = Iax2FullFrame(
        sourceCallNumber: _srcCall,
        destCallNumber: _dstCall,
        timestamp: ts,
        oSeqno: _oSeqno,
        iSeqno: _iSeqno,
        frameType: Iax2FrameType.voice,
        subclass: _format,
        payload: payload,
      );
      _pending[_oSeqno] = _Pending(frame.toBytes());
      _oSeqno = (_oSeqno + 1) & 0xFF;
      onSend(frame.toBytes());
    } else {
      final Iax2MiniFrame mini = Iax2MiniFrame(
        sourceCallNumber: _srcCall,
        timestamp: ts & 0xFFFF,
        payload: payload,
      );
      onSend(mini.toBytes());
    }
  }

  // --- Keepalive & reliability helpers --------------------------------------

  void _startPingKeepalive() {
    _pingTimer ??= Timer.periodic(
        const Duration(milliseconds: _pingIntervalMs), (_) => _sendPing());
  }

  void _sendPing() {
    if (_state == Iax2CallState.hungUp || _state == Iax2CallState.idle) return;
    _sendReliable(Iax2FrameType.iax, Iax2Subclass.ping);
  }

  void _ackPendingUpTo(int peerISeqno) {
    // Remove pending frames whose oSeqno is below the peer's next-expected.
    _pending.removeWhere((int seq, _Pending p) => _seqBefore(seq, peerISeqno));
  }

  // True if [a] is before [b] in 8-bit wrapping sequence space.
  bool _seqBefore(int a, int b) => ((b - a) & 0xFF) != 0 && ((b - a) & 0xFF) < 128;

  // Frames that advance the inbound sequence counter (RFC 5456 section 7).
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

  int _pickSupportedFormat(int fmt) {
    if (fmt == Iax2Format.gsm || fmt == Iax2Format.ulaw) return fmt;
    // Fall back to our preferred format if the peer named one we can't do.
    return preferredFormat;
  }

  void _diag(String msg) => onDiagnostic?.call(msg);

  /// Whether the call has completed the ACCEPT handshake (for diagnostics/UI).
  bool get isAccepted => _acceptReceived;

  /// Whether an AUTHREP has been sent (for diagnostics).
  bool get authSent => _authSent;
}

class _Pending {
  final Uint8List bytes;
  int retries = 0;
  _Pending(this.bytes);
}
