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
// echolink_audio_test.dart - Verifies EchoLink GSM voice-packet framing.
//
// Uses the same libgsm golden vectors as gsm_bit_exact_test.dart: the packet
// payloads must equal the golden GSM frames, and decoded audio must match the
// golden decoded PCM. Run reference/libgsm/build_golden.sh first.
//

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/echolink/echolink_audio.dart';
import 'package:htcommander/echolink/rtp_voice_packet.dart';

Directory _vectorsDir() {
  for (final String p in <String>['test/gsm_vectors', 'src/test/gsm_vectors']) {
    final Directory d = Directory(p);
    if (d.existsSync()) return d;
  }
  final String here = File.fromUri(Platform.script).parent.path;
  return Directory('$here/gsm_vectors');
}

Int16List _readPcm(File f) {
  final Uint8List bytes = f.readAsBytesSync();
  final ByteData bd = ByteData.sublistView(bytes);
  final Int16List out = Int16List(bytes.length ~/ 2);
  for (int i = 0; i < out.length; i++) {
    out[i] = bd.getInt16(i * 2, Endian.little);
  }
  return out;
}

void main() {
  final Directory vdir = _vectorsDir();
  final File inputFile = File('${vdir.path}/input.pcm');
  final File goldenGsm = File('${vdir.path}/golden.gsm');
  final File goldenDec = File('${vdir.path}/golden_dec.pcm');
  final bool haveVectors = inputFile.existsSync() &&
      goldenGsm.existsSync() &&
      goldenDec.existsSync();
  final String? skip =
      haveVectors ? null : 'reference vectors not generated yet';

  const int samplesPerPacket = RtpVoicePacket.gsmSamplesPerPacket; // 640
  const int payloadBytes = RtpVoicePacket.gsmPayloadBytes; // 132

  group('EchoLink voice packet framing', () {
    test('encoded packets carry golden GSM payload with correct header', () {
      final Int16List pcm = _readPcm(inputFile);
      final Uint8List gsm = goldenGsm.readAsBytesSync();

      final int packets = pcm.length ~/ samplesPerPacket;
      final EchoLinkAudioEncoder enc = EchoLinkAudioEncoder(ssrc: 0);

      for (int p = 0; p < packets; p++) {
        final Uint8List dg = enc.encodePacket(pcm, pcmOff: p * samplesPerPacket);
        expect(dg.length, RtpVoicePacket.headerSize + payloadBytes); // 144

        final ByteData bd = ByteData.sublistView(dg);
        expect(bd.getUint8(0), RtpVoicePacket.audioVersion, reason: 'version');
        expect(bd.getUint8(1), RtpVoicePacket.ptGsm, reason: 'pt');
        expect(bd.getUint16(2, Endian.big), p & 0xFFFF, reason: 'seqNum');
        expect(bd.getUint32(4, Endian.big), 0, reason: 'timestamp');
        expect(bd.getUint32(8, Endian.big), 0, reason: 'ssrc');

        for (int i = 0; i < payloadBytes; i++) {
          final int actual = dg[RtpVoicePacket.headerSize + i];
          final int expected = gsm[p * payloadBytes + i];
          if (actual != expected) {
            fail('packet $p payload byte $i: got $actual want $expected');
          }
        }
      }
    }, skip: skip);

    test('decoded packets match golden decoded PCM', () {
      final Uint8List gsm = goldenGsm.readAsBytesSync();
      final Int16List expected = _readPcm(goldenDec);
      final int packets = gsm.length ~/ payloadBytes;

      final EchoLinkAudioDecoder dec = EchoLinkAudioDecoder();
      for (int p = 0; p < packets; p++) {
        final RtpVoicePacket pkt = RtpVoicePacket(
          pt: RtpVoicePacket.ptGsm,
          seqNum: p,
          payload: Uint8List.sublistView(gsm, p * payloadBytes, (p + 1) * payloadBytes),
        );
        final Int16List? out = dec.decodePacket(pkt.toBytes());
        expect(out, isNotNull);
        for (int i = 0; i < samplesPerPacket; i++) {
          final int a = out![i];
          final int e = expected[p * samplesPerPacket + i];
          if (a != e) {
            fail('packet $p sample $i: got $a want $e');
          }
        }
      }
    }, skip: skip);
  });

  group('RtpVoicePacket', () {
    test('toBytes/parse round-trip', () {
      final Uint8List payload = Uint8List.fromList(
          List<int>.generate(payloadBytes, (int i) => (i * 7) & 0xFF));
      final RtpVoicePacket p = RtpVoicePacket(
        pt: RtpVoicePacket.ptGsm,
        seqNum: 0xBEEF,
        timestamp: 0x11223344,
        ssrc: 0x55667788,
        payload: payload,
      );
      final RtpVoicePacket? r = RtpVoicePacket.parse(p.toBytes());
      expect(r, isNotNull);
      expect(r!.version, RtpVoicePacket.audioVersion);
      expect(r.pt, RtpVoicePacket.ptGsm);
      expect(r.seqNum, 0xBEEF);
      expect(r.timestamp, 0x11223344);
      expect(r.ssrc, 0x55667788);
      expect(r.isAudio, isTrue);
      expect(r.isGsm, isTrue);
      expect(r.payload, orderedEquals(payload));
    });

    test('sequence numbers increment and wrap at 16 bits', () {
      final EchoLinkAudioEncoder enc = EchoLinkAudioEncoder(initialSeq: 0xFFFF);
      final Int16List pcm = Int16List(samplesPerPacket);
      final ByteData a = ByteData.sublistView(enc.encodePacket(pcm));
      final ByteData b = ByteData.sublistView(enc.encodePacket(pcm));
      expect(a.getUint16(2, Endian.big), 0xFFFF);
      expect(b.getUint16(2, Endian.big), 0x0000);
    });

    test('non-audio datagram is rejected', () {
      final Uint8List notAudio = Uint8List(RtpVoicePacket.headerSize + payloadBytes)
        ..[0] = 0x00; // wrong version
      final EchoLinkAudioDecoder dec = EchoLinkAudioDecoder();
      expect(dec.decodePacket(notAudio), isNull);
    });

    test('too-short datagram parses to null', () {
      expect(RtpVoicePacket.parse(Uint8List(4)), isNull);
    });
  });
}
