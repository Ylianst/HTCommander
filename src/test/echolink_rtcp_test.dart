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
// echolink_rtcp_test.dart - Verifies the EchoLink signaling layer: RTCP
// SDES/BYE (bit-exact vs EchoLib rtpacket.cpp), the "oNDATA" info/chat packets,
// and the QSO connection state machine.
//
// Generate RTCP vectors first:
//   wsl bash reference/svxlink/src/echolib/build_echolink_golden.sh
//

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/echolink/echolink_audio.dart';
import 'package:htcommander/echolink/echolink_data_packet.dart';
import 'package:htcommander/echolink/echolink_qso.dart';
import 'package:htcommander/echolink/rtcp_packet.dart';

Directory _vectorsDir() {
  for (final String p in <String>[
    'test/echolink_vectors',
    'src/test/echolink_vectors',
  ]) {
    final Directory d = Directory(p);
    if (d.existsSync()) return d;
  }
  final String here = File.fromUri(Platform.script).parent.path;
  return Directory('$here/echolink_vectors');
}

void _expectBytes(Uint8List a, Uint8List b, String what) {
  expect(a.length, b.length, reason: '$what length');
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      fail('$what differ at byte $i: Dart=0x${a[i].toRadixString(16)} '
          'C=0x${b[i].toRadixString(16)}');
    }
  }
}

void main() {
  final Directory vdir = _vectorsDir();
  final File sdesFile = File('${vdir.path}/sdes.bin');
  final File byeFile = File('${vdir.path}/bye.bin');
  final bool haveVectors = sdesFile.existsSync() && byeFile.existsSync();
  final String? skip =
      haveVectors ? null : 'RTCP reference vectors not generated yet';

  group('RTCP SDES/BYE bit-exact vs EchoLib', () {
    test('buildSdes matches rtp_make_sdes', () {
      final Uint8List expected = sdesFile.readAsBytesSync();
      final Uint8List actual =
          buildSdes(callsign: 'N0CALL', name: 'Test Name');
      _expectBytes(actual, expected, 'SDES');
    }, skip: skip);

    test('buildBye matches rtp_make_bye', () {
      final Uint8List expected = byeFile.readAsBytesSync();
      final Uint8List actual = buildBye();
      _expectBytes(actual, expected, 'BYE');
    }, skip: skip);

    test('parses NAME/station out of the golden SDES', () {
      final Uint8List sdes = sdesFile.readAsBytesSync();
      expect(parseSdesItem(sdes, sdesName), 'N0CALL         Test Name');
      final SdesStation? st = parseSdesStation(sdes);
      expect(st, isNotNull);
      expect(st!.callsign, 'N0CALL');
      expect(st.name, 'Test Name');
    }, skip: skip);

    test('classifies golden SDES and BYE', () {
      final Uint8List sdes = sdesFile.readAsBytesSync();
      final Uint8List bye = byeFile.readAsBytesSync();
      expect(isSdesPacket(sdes), isTrue);
      expect(isByePacket(sdes), isFalse);
      expect(isByePacket(bye), isTrue);
      expect(isSdesPacket(bye), isFalse);
    }, skip: skip);
  });

  group('RTCP SDES round-trip (no C required)', () {
    test('build then parse recovers callsign and name', () {
      final Uint8List sdes = buildSdes(callsign: 'AB1CDE', name: 'Jane Doe');
      final SdesStation? st = parseSdesStation(sdes);
      expect(st!.callsign, 'AB1CDE');
      expect(st.name, 'Jane Doe');
      expect(isSdesPacket(sdes), isTrue);
    });
  });

  group('EchoLink info/chat packets', () {
    test('info packet build/classify/parse', () {
      final Uint8List pkt = buildInfoPacket('Station online\nline2');
      expect(classifyAudioPortPacket(pkt), EchoLinkAudioPortPacket.info);
      expect(pkt.last, 0); // null terminated
      expect(parseInfoPacket(pkt), 'Station online\nline2');
    });

    test('chat packet build/classify/parse', () {
      final Uint8List pkt = buildChatPacket('N0CALL', 'hello there');
      expect(classifyAudioPortPacket(pkt), EchoLinkAudioPortPacket.chat);
      final EchoLinkChat chat = parseChatPacket(pkt);
      expect(chat.callsign, 'N0CALL');
      expect(chat.message, 'hello there');
    });

    test('voice packet classifies as audio', () {
      final EchoLinkAudioEncoder enc = EchoLinkAudioEncoder();
      final Uint8List pkt = enc.encodePacket(Int16List(640));
      expect(classifyAudioPortPacket(pkt), EchoLinkAudioPortPacket.audio);
    });
  });

  group('EchoLinkQso state machine', () {
    late List<Uint8List> ctrlOut;
    late List<Uint8List> audioOut;
    late EchoLinkQso qso;
    late List<QsoState> states;

    setUp(() {
      ctrlOut = <Uint8List>[];
      audioOut = <Uint8List>[];
      states = <QsoState>[];
      qso = EchoLinkQso(
        localCallsign: 'N0CALL',
        localName: 'Tester',
        localInfo: 'HTCommander',
        sendControl: ctrlOut.add,
        sendAudio: audioOut.add,
      )..onStateChanged = states.add;
    });

    test('connect sends SDES and enters connecting', () {
      expect(qso.connect(), isTrue);
      expect(qso.state, QsoState.connecting);
      expect(ctrlOut.length, 1);
      expect(isSdesPacket(ctrlOut.single), isTrue);
      expect(states, <QsoState>[QsoState.connecting]);
    });

    test('remote SDES completes the handshake', () {
      bool keepAlive = false;
      SdesStation? remote;
      qso.onKeepAlive = () => keepAlive = true;
      qso.onRemoteStation = (SdesStation s) => remote = s;

      qso.connect();
      qso.handleControlPacket(buildSdes(callsign: 'W1AW', name: 'Hiram'));

      expect(qso.state, QsoState.connected);
      expect(keepAlive, isTrue);
      expect(remote?.callsign, 'W1AW');
    });

    test('audio/info/chat only sent when connected', () {
      qso.sendChat('nope'); // disconnected -> ignored
      expect(audioOut, isEmpty);

      qso.connect();
      qso.handleControlPacket(buildSdes(callsign: 'W1AW'));
      audioOut.clear();

      qso.sendChat('hi');
      qso.sendInfo();
      qso.sendAudioFrame(Int16List(640));
      expect(audioOut.length, 3);
      expect(classifyAudioPortPacket(audioOut[0]), EchoLinkAudioPortPacket.chat);
      expect(classifyAudioPortPacket(audioOut[1]), EchoLinkAudioPortPacket.info);
      expect(classifyAudioPortPacket(audioOut[2]), EchoLinkAudioPortPacket.audio);
    });

    test('incoming voice/info/chat fire callbacks', () {
      Int16List? gotAudio;
      String? gotInfo;
      EchoLinkChat? gotChat;
      qso.onAudio = (Int16List p) => gotAudio = p;
      qso.onInfo = (String s) => gotInfo = s;
      qso.onChat = (EchoLinkChat c) => gotChat = c;

      qso.accept();
      final EchoLinkAudioEncoder enc = EchoLinkAudioEncoder();
      qso.handleAudioPacket(enc.encodePacket(Int16List(640)));
      qso.handleAudioPacket(buildInfoPacket('remote info'));
      qso.handleAudioPacket(buildChatPacket('W1AW', 'yo'));

      expect(gotAudio?.length, 640);
      expect(gotInfo, 'remote info');
      expect(gotChat?.callsign, 'W1AW');
      expect(gotChat?.message, 'yo');
    });

    test('receiving BYE disconnects without sending BYE back', () {
      qso.accept();
      ctrlOut.clear();
      qso.handleControlPacket(buildBye());
      expect(qso.state, QsoState.disconnected);
      expect(ctrlOut, isEmpty);
    });

    test('local disconnect sends BYE', () {
      qso.accept();
      ctrlOut.clear();
      expect(qso.disconnect(), isTrue);
      expect(qso.state, QsoState.disconnected);
      expect(ctrlOut.length, 1);
      expect(isByePacket(ctrlOut.single), isTrue);
    });

    test('keep-alive tick resends SDES while connected', () {
      qso.accept();
      ctrlOut.clear();
      qso.onKeepAliveTick();
      expect(ctrlOut.length, 1);
      expect(isSdesPacket(ctrlOut.single), isTrue);
    });
  });
}
