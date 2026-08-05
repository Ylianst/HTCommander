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
// allstar_registrar_test.dart - IAX2 node registration: REGREQ -> REGAUTH ->
// REGREQ(md5) -> REGACK, and REGREJ handling, driven through the frame
// callbacks (no real socket).
//

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/allstar/iax2_constants.dart';
import 'package:htcommander/allstar/iax2_frame.dart';
import 'package:htcommander/allstar/iax2_ie.dart';
import 'package:htcommander/allstar/iax2_registrar.dart';

const String _secret = 'NodePass';
const int _serverCall = 55;

class _Sink {
  final List<Iax2FullFrame> full = <Iax2FullFrame>[];
  void onSend(Uint8List d) {
    final Iax2FullFrame? f = Iax2FullFrame.parse(d);
    if (f != null) full.add(f);
  }

  Iax2FullFrame? lastWith(int subclass) {
    Iax2FullFrame? found;
    for (final Iax2FullFrame f in full) {
      if (f.frameType == Iax2FrameType.iax && f.subclass == subclass) found = f;
    }
    return found;
  }
}

Uint8List _regAuth(int registrarCall, String challenge) {
  final Iax2IeSet ies = Iax2IeSet();
  ies.addUint16(Iax2Ie.authMethods, Iax2AuthMethod.md5);
  ies.addString(Iax2Ie.challenge, challenge);
  return Iax2FullFrame(
    sourceCallNumber: _serverCall,
    destCallNumber: registrarCall,
    timestamp: 0,
    oSeqno: 0,
    iSeqno: 1,
    frameType: Iax2FrameType.iax,
    subclass: Iax2Subclass.regAuth,
  ).toBytes(ies: ies);
}

Uint8List _regAck(int registrarCall) {
  final Iax2IeSet ies = Iax2IeSet();
  ies.addUint16(Iax2Ie.refresh, 60);
  // APPARENTADDR sockaddr_in: family(2) port(2) ip(4) zero(8).
  ies.addRaw(Iax2Ie.apparentAddr,
      Uint8List.fromList(<int>[2, 0, 0x11, 0xD9, 8, 8, 8, 8, 0, 0, 0, 0, 0, 0, 0, 0]));
  return Iax2FullFrame(
    sourceCallNumber: _serverCall,
    destCallNumber: registrarCall,
    timestamp: 0,
    oSeqno: 1,
    iSeqno: 2,
    frameType: Iax2FrameType.iax,
    subclass: Iax2Subclass.regAck,
  ).toBytes(ies: ies);
}

void main() {
  test('REGREQ -> REGAUTH -> REGREQ(md5) -> REGACK reaches Registered', () {
    final _Sink sink = _Sink();
    final List<Iax2RegState> states = <Iax2RegState>[];
    final Iax2Registrar reg = Iax2Registrar(
      onSend: sink.onSend,
      nodeNumber: '2000',
      secret: _secret,
      onStateChanged: (Iax2RegState s, {String? detail}) => states.add(s),
    );

    reg.start();
    final Iax2FullFrame first = sink.lastWith(Iax2Subclass.regReq)!;
    expect(first.parseIes().getString(Iax2Ie.username), '2000');
    final int registrarCall = reg.localCall;
    expect(registrarCall >= 0x4000, isTrue);

    reg.handleDatagram(_regAuth(registrarCall, 'challenge123'));
    final Iax2FullFrame authed = sink.lastWith(Iax2Subclass.regReq)!;
    expect(authed.parseIes().getString(Iax2Ie.md5Result),
        iax2Md5Response('challenge123', _secret));

    reg.handleDatagram(_regAck(registrarCall));
    expect(reg.state, Iax2RegState.registered);
    expect(states.contains(Iax2RegState.registered), isTrue);
    reg.stop(release: false);
  });

  test('REGREJ moves to failed', () {
    final _Sink sink = _Sink();
    final Iax2Registrar reg = Iax2Registrar(
      onSend: sink.onSend,
      nodeNumber: '2000',
      secret: _secret,
    );
    reg.start();
    final int registrarCall = reg.localCall;
    reg.handleDatagram(_regAuth(registrarCall, 'ch'));

    final Iax2IeSet ies = Iax2IeSet();
    ies.addString(Iax2Ie.cause, 'Bad password');
    final Uint8List rej = Iax2FullFrame(
      sourceCallNumber: _serverCall,
      destCallNumber: registrarCall,
      timestamp: 0,
      oSeqno: 1,
      iSeqno: 2,
      frameType: Iax2FrameType.iax,
      subclass: Iax2Subclass.regRej,
    ).toBytes(ies: ies);
    reg.handleDatagram(rej);
    expect(reg.state, Iax2RegState.failed);
    reg.stop(release: false);
  });
}
