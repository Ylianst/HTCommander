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
// allstar_call_test.dart - IAX2 outbound call state machine: the NEW / AUTHREQ /
// AUTHREP / ACCEPT / ANSWER handshake, MD5 authentication, media exchange and
// hangup, driven entirely by crafted server frames against a fake transport.
//

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/allstar/allstar_audio.dart';
import 'package:htcommander/allstar/iax2_call.dart';
import 'package:htcommander/allstar/iax2_constants.dart';
import 'package:htcommander/allstar/iax2_frame.dart';
import 'package:htcommander/allstar/iax2_ie.dart';

/// Builds a full frame as if sent by the node (server) to the client.
Uint8List _serverFull(int subclass,
    {int srcCall = 1000,
    int dstCall = 1,
    int oSeqno = 0,
    int iSeqno = 0,
    int frameType = Iax2FrameType.iax,
    Iax2IeSet? ies,
    Uint8List? payload}) {
  return Iax2FullFrame(
    sourceCallNumber: srcCall,
    destCallNumber: dstCall,
    timestamp: 100,
    oSeqno: oSeqno,
    iSeqno: iSeqno,
    frameType: frameType,
    subclass: subclass,
    payload: payload,
  ).toBytes(ies: ies);
}

void main() {
  late List<Iax2FullFrame> sentFull;
  late List<Iax2MiniFrame> sentMini;
  late List<Iax2CallState> states;
  late List<Int16List> audio;
  late Iax2Call call;

  void makeCall() {
    sentFull = <Iax2FullFrame>[];
    sentMini = <Iax2MiniFrame>[];
    states = <Iax2CallState>[];
    audio = <Int16List>[];
    call = Iax2Call(
      username: '54321',
      secret: 'hunter2',
      calledNumber: '2000',
      onSend: (Uint8List d) {
        if (iax2IsFullFrame(d)) {
          sentFull.add(Iax2FullFrame.parse(d)!);
        } else {
          sentMini.add(Iax2MiniFrame.parse(d)!);
        }
      },
      onAudio: audio.add,
      onStateChanged: states.add,
    );
  }

  Iax2FullFrame lastOfSubclass(int subclass, int frameType) => sentFull.lastWhere(
      (Iax2FullFrame f) => f.frameType == frameType && f.subclass == subclass);

  setUp(makeCall);
  tearDown(() => call.disconnect());

  test('connect sends a NEW frame with the required IEs', () {
    call.connect(srcCallNumber: 1);
    expect(call.state, Iax2CallState.connecting);
    final Iax2FullFrame newFrame =
        lastOfSubclass(Iax2Subclass.newCall, Iax2FrameType.iax);
    final Iax2IeSet ies = newFrame.parseIes();
    expect(ies.getUint(Iax2Ie.version), iax2ProtocolVersion);
    expect(ies.getString(Iax2Ie.calledNumber), '2000');
    expect(ies.getString(Iax2Ie.username), '54321');
    expect(ies.getUint(Iax2Ie.capability), Iax2Format.gsm | Iax2Format.ulaw);
    expect(ies.getUint(Iax2Ie.format), Iax2Format.gsm);
    expect(newFrame.oSeqno, 0);
  });

  test('AUTHREQ triggers an AUTHREP with the correct MD5 response', () {
    call.connect(srcCallNumber: 1);
    final Iax2IeSet auth = Iax2IeSet();
    auth.addUint16(Iax2Ie.authMethods, Iax2AuthMethod.md5);
    auth.addString(Iax2Ie.challenge, '135792468');
    call.handleDatagram(
        _serverFull(Iax2Subclass.authReq, oSeqno: 0, iSeqno: 1, ies: auth));

    final Iax2FullFrame rep =
        lastOfSubclass(Iax2Subclass.authRep, Iax2FrameType.iax);
    expect(rep.destCallNumber, 1000); // Learned the node's call number.
    expect(rep.parseIes().getString(Iax2Ie.md5Result),
        iax2Md5Response('135792468', 'hunter2'));
  });

  test('ACCEPT then ANSWER brings the call up and negotiates the format', () {
    call.connect(srcCallNumber: 1);
    // AUTHREQ -> AUTHREP.
    final Iax2IeSet auth = Iax2IeSet()
      ..addUint16(Iax2Ie.authMethods, Iax2AuthMethod.md5)
      ..addString(Iax2Ie.challenge, 'abc');
    call.handleDatagram(
        _serverFull(Iax2Subclass.authReq, oSeqno: 0, iSeqno: 1, ies: auth));
    // ACCEPT (mu-law).
    final Iax2IeSet accept = Iax2IeSet()..addUint32(Iax2Ie.format, Iax2Format.ulaw);
    call.handleDatagram(
        _serverFull(Iax2Subclass.accept, oSeqno: 1, iSeqno: 2, ies: accept));
    expect(call.isAccepted, isTrue);
    expect(call.state, Iax2CallState.connecting);
    // ANSWER (control).
    call.handleDatagram(_serverFull(Iax2Control.answer,
        oSeqno: 2, iSeqno: 2, frameType: Iax2FrameType.control));
    expect(call.state, Iax2CallState.up);
    expect(states, contains(Iax2CallState.up));
  });

  test('received voice frame is decoded to PCM', () {
    _bringUp(call);
    final AllStarAudioEncoder enc = AllStarAudioEncoder(format: Iax2Format.gsm);
    final Uint8List gsm = enc.encodeFrame(Int16List(allStarGsmFrameSamples));
    call.handleDatagram(_serverFull(Iax2Format.gsm,
        oSeqno: 3, iSeqno: 3, frameType: Iax2FrameType.voice, payload: gsm));
    expect(audio, isNotEmpty);
    expect(audio.first.length, allStarGsmFrameSamples);
  });

  test('sendVoiceFrame emits a full voice frame first, then mini frames', () {
    _bringUp(call);
    call.sendVoiceFrame(Int16List(allStarGsmFrameSamples));
    expect(
        sentFull.where((Iax2FullFrame f) => f.frameType == Iax2FrameType.voice),
        isNotEmpty);
    call.sendVoiceFrame(Int16List(allStarGsmFrameSamples));
    expect(sentMini, isNotEmpty);
  });

  test('HANGUP from the node tears the call down', () {
    _bringUp(call);
    final Iax2IeSet hup = Iax2IeSet()..addString(Iax2Ie.cause, 'Normal Clearing');
    call.handleDatagram(
        _serverFull(Iax2Subclass.hangup, oSeqno: 3, iSeqno: 3, ies: hup));
    expect(call.state, Iax2CallState.hungUp);
  });

  test('REJECT from the node fails the call', () {
    call.connect(srcCallNumber: 1);
    final Iax2IeSet rej = Iax2IeSet()..addString(Iax2Ie.cause, 'Call rejected');
    call.handleDatagram(
        _serverFull(Iax2Subclass.reject, oSeqno: 0, iSeqno: 1, ies: rej));
    expect(call.state, Iax2CallState.hungUp);
  });

  test('PING from the node is answered with PONG', () {
    _bringUp(call);
    call.handleDatagram(_serverFull(Iax2Subclass.ping, oSeqno: 3, iSeqno: 3));
    expect(
        sentFull.any((Iax2FullFrame f) =>
            f.frameType == Iax2FrameType.iax && f.subclass == Iax2Subclass.pong),
        isTrue);
  });
}

/// Drives a fresh call through the full handshake to the "up" state.
void _bringUp(Iax2Call call) {
  call.connect(srcCallNumber: 1);
  final Iax2IeSet auth = Iax2IeSet()
    ..addUint16(Iax2Ie.authMethods, Iax2AuthMethod.md5)
    ..addString(Iax2Ie.challenge, 'abc');
  call.handleDatagram(
      _serverFull(Iax2Subclass.authReq, oSeqno: 0, iSeqno: 1, ies: auth));
  final Iax2IeSet accept = Iax2IeSet()..addUint32(Iax2Ie.format, Iax2Format.gsm);
  call.handleDatagram(
      _serverFull(Iax2Subclass.accept, oSeqno: 1, iSeqno: 2, ies: accept));
  call.handleDatagram(_serverFull(Iax2Control.answer,
      oSeqno: 2, iSeqno: 2, frameType: Iax2FrameType.control));
}
