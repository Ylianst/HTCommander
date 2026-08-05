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
// allstar_server_test.dart - Inbound IAX2 node server: NEW -> AUTHREQ ->
// AUTHREP -> ACCEPT/ANSWER handshake, authentication rejection, media bridging
// and hangup, driven through the transport-agnostic frame callbacks.
//

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/allstar/iax2_constants.dart';
import 'package:htcommander/allstar/iax2_frame.dart';
import 'package:htcommander/allstar/iax2_ie.dart';
import 'package:htcommander/allstar/iax2_server.dart';
import 'package:htcommander/allstar/ulaw_codec.dart';

const String _secret = 'VerySecret';
const int _peerCall = 100;

/// Captures outbound datagrams and decodes them as full frames for assertions.
class _Sink {
  final List<Iax2FullFrame> full = <Iax2FullFrame>[];
  final List<Iax2MiniFrame> mini = <Iax2MiniFrame>[];

  void onSend(String host, int port, Uint8List d) {
    if (iax2IsFullFrame(d)) {
      final Iax2FullFrame? f = Iax2FullFrame.parse(d);
      if (f != null) full.add(f);
    } else {
      final Iax2MiniFrame? m = Iax2MiniFrame.parse(d);
      if (m != null) mini.add(m);
    }
  }

  Iax2FullFrame? firstWith(int subclass) {
    for (final Iax2FullFrame f in full) {
      if (f.frameType == Iax2FrameType.iax && f.subclass == subclass) return f;
    }
    return null;
  }

  Iax2FullFrame? firstControl(int subclass) {
    for (final Iax2FullFrame f in full) {
      if (f.frameType == Iax2FrameType.control && f.subclass == subclass) {
        return f;
      }
    }
    return null;
  }
}

Uint8List _newFrame({int oSeqno = 0, String? username}) {
  final Iax2IeSet ies = Iax2IeSet();
  ies.addUint16(Iax2Ie.version, iax2ProtocolVersion);
  ies.addString(Iax2Ie.callingNumber, '1234');
  ies.addString(Iax2Ie.callingName, 'TESTNODE');
  if (username != null) ies.addString(Iax2Ie.username, username);
  ies.addUint32(Iax2Ie.capability, Iax2Format.gsm | Iax2Format.ulaw);
  ies.addUint32(Iax2Ie.format, Iax2Format.ulaw);
  return Iax2FullFrame(
    sourceCallNumber: _peerCall,
    destCallNumber: 0,
    timestamp: 0,
    oSeqno: oSeqno,
    iSeqno: 0,
    frameType: Iax2FrameType.iax,
    subclass: Iax2Subclass.newCall,
  ).toBytes(ies: ies);
}

Uint8List _authRep(int serverCall, String challenge, String secret,
    {int oSeqno = 1}) {
  final Iax2IeSet ies = Iax2IeSet();
  ies.addString(Iax2Ie.md5Result, iax2Md5Response(challenge, secret));
  return Iax2FullFrame(
    sourceCallNumber: _peerCall,
    destCallNumber: serverCall,
    timestamp: 0,
    oSeqno: oSeqno,
    iSeqno: 1,
    frameType: Iax2FrameType.iax,
    subclass: Iax2Subclass.authRep,
  ).toBytes(ies: ies);
}

void main() {
  test('NEW is answered with an MD5 AUTHREQ', () {
    final _Sink sink = _Sink();
    final Iax2Server server = Iax2Server(
      onSend: sink.onSend,
      nodeNumber: '2000',
      secret: _secret,
    );
    server.handleDatagram('1.2.3.4', 4569, _newFrame());

    final Iax2FullFrame? authReq = sink.firstWith(Iax2Subclass.authReq);
    expect(authReq, isNotNull, reason: 'server should challenge the caller');
    final Iax2IeSet ies = authReq!.parseIes();
    expect((ies.getUint(Iax2Ie.authMethods)! & Iax2AuthMethod.md5) != 0, isTrue);
    expect(ies.getString(Iax2Ie.challenge), isNotNull);
    server.close();
  });

  test('correct AUTHREP is accepted and answered, then media flows', () {
    final _Sink sink = _Sink();
    Iax2ServerSession? connected;
    final List<int> audio = <int>[];
    final Iax2Server server = Iax2Server(
      onSend: sink.onSend,
      nodeNumber: '2000',
      secret: _secret,
      onSessionConnected: (Iax2ServerSession s) => connected = s,
      onAudio: (Iax2ServerSession s, pcm) => audio.addAll(pcm),
    );

    server.handleDatagram('1.2.3.4', 4569, _newFrame());
    final Iax2FullFrame authReq = sink.firstWith(Iax2Subclass.authReq)!;
    final int serverCall = authReq.sourceCallNumber;
    final String challenge = authReq.parseIes().getString(Iax2Ie.challenge)!;

    server.handleDatagram(
        '1.2.3.4', 4569, _authRep(serverCall, challenge, _secret));

    expect(sink.firstWith(Iax2Subclass.accept), isNotNull);
    expect(sink.firstControl(Iax2Control.answer), isNotNull);
    expect(connected, isNotNull);
    expect(server.connectedSessions.length, 1);

    // Peer sends a ulaw voice frame (must be a full frame to start the stream).
    final Uint8List payload = UlawCodec().encode(Int16List(160));
    final Uint8List voice = Iax2FullFrame(
      sourceCallNumber: _peerCall,
      destCallNumber: serverCall,
      timestamp: 20,
      oSeqno: 2,
      iSeqno: 2,
      frameType: Iax2FrameType.voice,
      subclass: Iax2Format.ulaw,
      payload: payload,
    ).toBytes();
    server.handleDatagram('1.2.3.4', 4569, voice);
    expect(audio.length, 160);
    server.close();
  });

  test('wrong AUTHREP secret is rejected and no session remains', () {
    final _Sink sink = _Sink();
    final Iax2Server server = Iax2Server(
      onSend: sink.onSend,
      nodeNumber: '2000',
      secret: _secret,
    );
    server.handleDatagram('1.2.3.4', 4569, _newFrame());
    final Iax2FullFrame authReq = sink.firstWith(Iax2Subclass.authReq)!;
    final int serverCall = authReq.sourceCallNumber;
    final String challenge = authReq.parseIes().getString(Iax2Ie.challenge)!;

    server.handleDatagram(
        '1.2.3.4', 4569, _authRep(serverCall, challenge, 'WrongSecret'));

    expect(sink.firstWith(Iax2Subclass.reject), isNotNull);
    expect(sink.firstWith(Iax2Subclass.accept), isNull);
    expect(server.sessionCount, 0);
    server.close();
  });

  test('broadcastVoiceFrame emits a voice datagram to a connected peer', () {
    final _Sink sink = _Sink();
    final Iax2Server server = Iax2Server(
      onSend: sink.onSend,
      nodeNumber: '2000',
      secret: _secret,
    );
    server.handleDatagram('1.2.3.4', 4569, _newFrame());
    final Iax2FullFrame authReq = sink.firstWith(Iax2Subclass.authReq)!;
    server.handleDatagram(
        '1.2.3.4',
        4569,
        _authRep(authReq.sourceCallNumber,
            authReq.parseIes().getString(Iax2Ie.challenge)!, _secret));

    server.broadcastVoiceFrame(Int16List(160));
    final bool sentVoice = sink.full.any((Iax2FullFrame f) =>
        f.frameType == Iax2FrameType.voice);
    expect(sentVoice, isTrue);
    server.close();
  });

  test('peer HANGUP ends the session', () {
    final _Sink sink = _Sink();
    bool ended = false;
    final Iax2Server server = Iax2Server(
      onSend: sink.onSend,
      nodeNumber: '2000',
      secret: _secret,
      onSessionEnded: (Iax2ServerSession s) => ended = true,
    );
    server.handleDatagram('1.2.3.4', 4569, _newFrame());
    final Iax2FullFrame authReq = sink.firstWith(Iax2Subclass.authReq)!;
    final int serverCall = authReq.sourceCallNumber;
    server.handleDatagram(
        '1.2.3.4',
        4569,
        _authRep(serverCall,
            authReq.parseIes().getString(Iax2Ie.challenge)!, _secret));

    final Uint8List hangup = Iax2FullFrame(
      sourceCallNumber: _peerCall,
      destCallNumber: serverCall,
      timestamp: 40,
      oSeqno: 2,
      iSeqno: 2,
      frameType: Iax2FrameType.iax,
      subclass: Iax2Subclass.hangup,
    ).toBytes();
    server.handleDatagram('1.2.3.4', 4569, hangup);
    expect(ended, isTrue);
    expect(server.sessionCount, 0);
    server.close();
  });

  test('unauthenticated server accepts NEW immediately', () {
    final _Sink sink = _Sink();
    Iax2ServerSession? connected;
    final Iax2Server server = Iax2Server(
      onSend: sink.onSend,
      nodeNumber: '2000',
      secret: _secret,
      requireAuth: false,
      onSessionConnected: (Iax2ServerSession s) => connected = s,
    );
    server.handleDatagram('1.2.3.4', 4569, _newFrame());
    expect(sink.firstWith(Iax2Subclass.authReq), isNull);
    expect(sink.firstWith(Iax2Subclass.accept), isNotNull);
    expect(connected, isNotNull);
    server.close();
  });

  test('Web Transceiver caller is accepted with the public secret when enabled',
      () {
    final _Sink sink = _Sink();
    Iax2ServerSession? connected;
    final Iax2Server server = Iax2Server(
      onSend: sink.onSend,
      nodeNumber: '2000',
      secret: _secret,
      allowWebTransceiver: true,
      onSessionConnected: (Iax2ServerSession s) => connected = s,
    );
    server.handleDatagram(
        '1.2.3.4', 4569, _newFrame(username: 'allstar-public'));
    final Iax2FullFrame authReq = sink.firstWith(Iax2Subclass.authReq)!;
    // The WT client authenticates against the public secret, not the node one.
    server.handleDatagram('1.2.3.4', 4569,
        _authRep(authReq.sourceCallNumber,
            authReq.parseIes().getString(Iax2Ie.challenge)!, 'allstar'));
    expect(sink.firstWith(Iax2Subclass.accept), isNotNull);
    expect(connected, isNotNull);
    server.close();
  });

  test('Web Transceiver caller is rejected when the option is disabled', () {
    final _Sink sink = _Sink();
    final Iax2Server server = Iax2Server(
      onSend: sink.onSend,
      nodeNumber: '2000',
      secret: _secret,
    );
    server.handleDatagram(
        '1.2.3.4', 4569, _newFrame(username: 'allstar-public'));
    final Iax2FullFrame authReq = sink.firstWith(Iax2Subclass.authReq)!;
    // Public secret must fail against the node password.
    server.handleDatagram('1.2.3.4', 4569,
        _authRep(authReq.sourceCallNumber,
            authReq.parseIes().getString(Iax2Ie.challenge)!, 'allstar'));
    expect(sink.firstWith(Iax2Subclass.reject), isNotNull);
    expect(sink.firstWith(Iax2Subclass.accept), isNull);
    expect(server.sessionCount, 0);
    server.close();
  });

  test('WT token validation rejects an invalid token', () async {
    final _Sink sink = _Sink();
    final Iax2Server server = Iax2Server(
      onSend: sink.onSend,
      nodeNumber: '2000',
      secret: _secret,
      allowWebTransceiver: true,
      webTransceiverValidator: (String token) async => false,
    );
    server.handleDatagram(
        '1.2.3.4', 4569, _newFrame(username: 'allstar-public'));
    final Iax2FullFrame authReq = sink.firstWith(Iax2Subclass.authReq)!;
    server.handleDatagram('1.2.3.4', 4569,
        _authRep(authReq.sourceCallNumber,
            authReq.parseIes().getString(Iax2Ie.challenge)!, 'allstar'));
    // MD5 passed but the async token check must complete before ACCEPT/REJECT.
    expect(sink.firstWith(Iax2Subclass.accept), isNull);
    await Future<void>.delayed(Duration.zero);
    expect(sink.firstWith(Iax2Subclass.reject), isNotNull);
    expect(sink.firstWith(Iax2Subclass.accept), isNull);
    expect(server.sessionCount, 0);
    server.close();
  });

  test('WT token validation accepts a valid token', () async {
    final _Sink sink = _Sink();
    Iax2ServerSession? connected;
    final Iax2Server server = Iax2Server(
      onSend: sink.onSend,
      nodeNumber: '2000',
      secret: _secret,
      allowWebTransceiver: true,
      webTransceiverValidator: (String token) async => true,
      onSessionConnected: (Iax2ServerSession s) => connected = s,
    );
    server.handleDatagram(
        '1.2.3.4', 4569, _newFrame(username: 'allstar-public'));
    final Iax2FullFrame authReq = sink.firstWith(Iax2Subclass.authReq)!;
    server.handleDatagram('1.2.3.4', 4569,
        _authRep(authReq.sourceCallNumber,
            authReq.parseIes().getString(Iax2Ie.challenge)!, 'allstar'));
    await Future<void>.delayed(Duration.zero);
    expect(sink.firstWith(Iax2Subclass.accept), isNotNull);
    expect(connected, isNotNull);
    server.close();
  });
}
