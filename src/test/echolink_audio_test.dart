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
import 'package:htcommander/gsm/gsm_codec.dart';

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
    test('header writer preserves payload and typed-data view boundaries', () {
      final storage = Uint8List(25)..fillRange(0, 25, 0xA5);
      final packet = Uint8List.sublistView(storage, 3, 23);
      RtpVoicePacket.writeHeader(packet,
          version: 0xC0, pt: RtpVoicePacket.ptSpeex, seqNum: 0x1234,
          timestamp: 0x56789ABC, ssrc: 0xDEF01234);
      expect(packet.sublist(0, 12), [
        0xC0, 0x96, 0x12, 0x34, 0x56, 0x78,
        0x9A, 0xBC, 0xDE, 0xF0, 0x12, 0x34,
      ]);
      expect(packet.sublist(12), everyElement(0xA5));
      expect(storage.sublist(0, 3), everyElement(0xA5));
      expect(storage.sublist(23), everyElement(0xA5));
    });

    test('unused codecs handle reset, empty TX and rejected RX before first use', () {
      final enc = EchoLinkAudioEncoder(ssrc: 0x87654321);
      final dec = EchoLinkAudioDecoder();
      final pcm = Int16List.fromList(
        List.generate(samplesPerPacket, (i) => (i * 193 % 65536) - 32768),
      );
      try {
        enc.reset(initialSeq: 0xFFFF);
        dec.reset();
        expect(enc.encode(Int16List(0)), isEmpty);
        expect(() => enc.encodePacket(Int16List(639)), throwsArgumentError);
        expect(() => enc.encodePacket(pcm, pcmOff: -1), throwsRangeError);
        expect(dec.decodePacket(Uint8List(4)), isNull);
        expect(dec.decodePacket(Uint8List(144)), isNull);
        expect(enc.nextSeq, 0xFFFF);
        final packet = enc.encodePacket(pcm);
        expect(packet.sublist(0, 12), [
          0xC0, 0x03, 0xFF, 0xFF, 0, 0, 0, 0, 0x87, 0x65, 0x43, 0x21,
        ]);
        final frames = GsmEncoder().encode(pcm);
        expect(packet.sublist(12), frames);
        expect(dec.decodePacket(packet), GsmDecoder().decode(frames));
      } finally {
        enc.dispose();
        dec.dispose();
      }
      final unusedEncoder = EchoLinkAudioEncoder()..reset();
      final unusedDecoder = EchoLinkAudioDecoder()..reset();
      unusedEncoder.dispose();
      unusedDecoder.dispose();
      expect(() => unusedEncoder.encodePacket(pcm), throwsStateError);
      expect(() => unusedDecoder.decodePacket(Uint8List(144)), throwsStateError);
    });

    test('audio buffers survive later calls, offsets, reset and disposal', () {
      final enc = EchoLinkAudioEncoder(initialSeq: 37, ssrc: 73);
      final dec = EchoLinkAudioDecoder();
      final pcm = Int16List.fromList(
        List.generate(samplesPerPacket, (i) => (i * 193 % 65536) - 32768),
      );
      final padded = Int16List(samplesPerPacket + 9)..setAll(5, pcm);
      final first = enc.encodePacket(padded, pcmOff: 5);
      final saved = Uint8List.fromList(first);
      final datagram = Uint8List(first.length + 7)..setAll(3, first);
      final decoded = dec.decodePacket(datagram, 3)!;
      final savedPcm = Int16List.fromList(decoded);
      enc.encodePacket(pcm);
      dec.decodePacket(first);
      enc.reset(initialSeq: 37);
      dec.reset();
      expect(enc.encodePacket(pcm), first);
      expect(dec.decodePacket(first), decoded);
      enc.dispose();
      dec.dispose();
      enc.dispose();
      dec.dispose();
      expect(first, saved);
      expect(decoded, savedPcm);
      expect(() => enc.encodePacket(pcm), throwsStateError);
      expect(enc.reset, throwsStateError);
      expect(() => dec.decodePacket(first), throwsStateError);
      expect(dec.reset, throwsStateError);
    });

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
