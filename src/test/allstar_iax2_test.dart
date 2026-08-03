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
// allstar_iax2_test.dart - IAX2 protocol core: information elements, full/mini
// frame encode-decode round trips, MD5 challenge response, and the mu-law /
// GSM media codecs used by AllStarLink.
//

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/allstar/allstar_audio.dart';
import 'package:htcommander/allstar/iax2_constants.dart';
import 'package:htcommander/allstar/iax2_frame.dart';
import 'package:htcommander/allstar/iax2_ie.dart';
import 'package:htcommander/allstar/ulaw_codec.dart';

void main() {
  group('Iax2IeSet', () {
    test('string / uint round trip preserves order and values', () {
      final Iax2IeSet ies = Iax2IeSet();
      ies.addUint16(Iax2Ie.version, iax2ProtocolVersion);
      ies.addString(Iax2Ie.calledNumber, '2000');
      ies.addString(Iax2Ie.username, 'N0CALL');
      ies.addUint32(Iax2Ie.capability, Iax2Format.gsm | Iax2Format.ulaw);
      ies.addUint32(Iax2Ie.format, Iax2Format.gsm);

      final Iax2IeSet parsed = Iax2IeSet.parse(ies.toBytes());
      expect(parsed.getUint(Iax2Ie.version), iax2ProtocolVersion);
      expect(parsed.getString(Iax2Ie.calledNumber), '2000');
      expect(parsed.getString(Iax2Ie.username), 'N0CALL');
      expect(parsed.getUint(Iax2Ie.capability), Iax2Format.gsm | Iax2Format.ulaw);
      expect(parsed.getUint(Iax2Ie.format), Iax2Format.gsm);
    });

    test('flag IE has zero-length data', () {
      final Iax2IeSet ies = Iax2IeSet();
      ies.addFlag(Iax2Ie.autoAnswer);
      final Uint8List bytes = ies.toBytes();
      expect(bytes, <int>[Iax2Ie.autoAnswer, 0]);
      expect(Iax2IeSet.parse(bytes).has(Iax2Ie.autoAnswer), isTrue);
    });

    test('parse ignores truncated trailing IE', () {
      // Valid VERSION IE followed by a truncated header.
      final Uint8List bytes =
          Uint8List.fromList(<int>[Iax2Ie.version, 2, 0, 2, Iax2Ie.username, 5]);
      final Iax2IeSet parsed = Iax2IeSet.parse(bytes);
      expect(parsed.getUint(Iax2Ie.version), 2);
      expect(parsed.has(Iax2Ie.username), isFalse);
    });
  });

  group('iax2Md5Response', () {
    test('matches known MD5 vectors (challenge + secret)', () {
      // md5("") = d41d8cd9...
      expect(iax2Md5Response('', ''), 'd41d8cd98f00b204e9800998ecf8427e');
      // md5("abc") = 900150983cd24fb0d6963f7d28e17f72; split across args.
      expect(iax2Md5Response('a', 'bc'), '900150983cd24fb0d6963f7d28e17f72');
      expect(iax2Md5Response('ab', 'c'), '900150983cd24fb0d6963f7d28e17f72');
    });
  });

  group('Iax2FullFrame', () {
    test('IAX signaling frame round trips with IEs', () {
      final Iax2IeSet ies = Iax2IeSet();
      ies.addUint16(Iax2Ie.version, iax2ProtocolVersion);
      ies.addString(Iax2Ie.calledNumber, '1998');

      final Iax2FullFrame frame = Iax2FullFrame(
        sourceCallNumber: 5,
        destCallNumber: 0,
        timestamp: 123,
        oSeqno: 0,
        iSeqno: 0,
        frameType: Iax2FrameType.iax,
        subclass: Iax2Subclass.newCall,
      );
      final Uint8List bytes = frame.toBytes(ies: ies);
      // F bit must be set on a full frame.
      expect(bytes[0] & 0x80, 0x80);

      final Iax2FullFrame? p = Iax2FullFrame.parse(bytes);
      expect(p, isNotNull);
      expect(p!.sourceCallNumber, 5);
      expect(p.destCallNumber, 0);
      expect(p.timestamp, 123);
      expect(p.frameType, Iax2FrameType.iax);
      expect(p.subclass, Iax2Subclass.newCall);
      final Iax2IeSet pies = p.parseIes();
      expect(pies.getUint(Iax2Ie.version), iax2ProtocolVersion);
      expect(pies.getString(Iax2Ie.calledNumber), '1998');
    });

    test('retransmit bit and dest call number survive round trip', () {
      final Iax2FullFrame frame = Iax2FullFrame(
        sourceCallNumber: 0x1234,
        destCallNumber: 0x0ABC,
        retransmit: true,
        timestamp: 0xDEADBEEF,
        oSeqno: 3,
        iSeqno: 7,
        frameType: Iax2FrameType.iax,
        subclass: Iax2Subclass.ack,
      );
      final Iax2FullFrame p = Iax2FullFrame.parse(frame.toBytes())!;
      expect(p.sourceCallNumber, 0x1234 & 0x7FFF);
      expect(p.destCallNumber, 0x0ABC);
      expect(p.retransmit, isTrue);
      expect(p.timestamp, 0xDEADBEEF);
      expect(p.oSeqno, 3);
      expect(p.iSeqno, 7);
      expect(p.subclass, Iax2Subclass.ack);
    });

    test('voice frame carries a power-of-two media subclass', () {
      final Iax2FullFrame frame = Iax2FullFrame(
        sourceCallNumber: 9,
        destCallNumber: 4,
        timestamp: 0x8000,
        oSeqno: 1,
        iSeqno: 1,
        frameType: Iax2FrameType.voice,
        subclass: Iax2Format.gsm,
        payload: Uint8List(allStarGsmFrameBytes),
      );
      final Iax2FullFrame p = Iax2FullFrame.parse(frame.toBytes())!;
      expect(p.frameType, Iax2FrameType.voice);
      expect(p.subclass, Iax2Format.gsm);
      expect(p.payload.length, allStarGsmFrameBytes);
    });

    test('parse rejects a mini frame', () {
      final Uint8List mini =
          Iax2MiniFrame(sourceCallNumber: 3, timestamp: 10, payload: Uint8List(2))
              .toBytes();
      expect(Iax2FullFrame.parse(mini), isNull);
      expect(iax2IsFullFrame(mini), isFalse);
    });
  });

  group('Iax2MiniFrame', () {
    test('round trips and rejects full frames', () {
      final Uint8List payload = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);
      final Iax2MiniFrame mini =
          Iax2MiniFrame(sourceCallNumber: 42, timestamp: 0x1234, payload: payload);
      final Uint8List bytes = mini.toBytes();
      expect(bytes[0] & 0x80, 0); // F bit clear.

      final Iax2MiniFrame? p = Iax2MiniFrame.parse(bytes);
      expect(p, isNotNull);
      expect(p!.sourceCallNumber, 42);
      expect(p.timestamp, 0x1234);
      expect(p.payload, payload);
      expect(iax2IsFullFrame(bytes), isFalse);

      final Iax2FullFrame full = Iax2FullFrame(
        sourceCallNumber: 1,
        destCallNumber: 1,
        timestamp: 0,
        oSeqno: 0,
        iSeqno: 0,
        frameType: Iax2FrameType.iax,
        subclass: Iax2Subclass.ping,
      );
      expect(Iax2MiniFrame.parse(full.toBytes()), isNull);
    });
  });

  group('UlawCodec', () {
    final UlawCodec codec = UlawCodec();

    test('known G.711 endpoints', () {
      expect(codec.encode(Int16List.fromList(<int>[0]))[0], 0xFF);
      expect(codec.decode(Uint8List.fromList(<int>[0xFF]))[0], 0);
    });

    test('decode(encode(x)) preserves sign and stays close', () {
      final List<int> samples = <int>[
        -32000, -8000, -1000, -100, -1, 0, 1, 100, 1000, 8000, 32000
      ];
      for (final int s in samples) {
        final int r = codec
            .decode(codec.encode(Int16List.fromList(<int>[s])))[0];
        // mu-law has a dead zone near zero; sign is only guaranteed for
        // samples above the smallest quantisation step.
        if (s.abs() >= 100) {
          expect(r.sign, s.sign, reason: 'sign for $s');
        }
        // mu-law quantisation error grows with amplitude but stays bounded.
        expect((r - s).abs(), lessThan((s.abs() >> 3) + 300),
            reason: 'quantisation error for $s (got $r)');
      }
    });
  });

  group('AllStarAudio', () {
    test('GSM frame encodes to 33 bytes and decodes to 160 samples', () {
      final AllStarAudioEncoder enc = AllStarAudioEncoder(format: Iax2Format.gsm);
      final AllStarAudioDecoder dec = AllStarAudioDecoder(format: Iax2Format.gsm);
      final Int16List pcm = Int16List(allStarGsmFrameSamples);
      for (int i = 0; i < pcm.length; i++) {
        pcm[i] = (2000 * (i.isEven ? 1 : -1));
      }
      final Uint8List payload = enc.encodeFrame(pcm);
      expect(payload.length, allStarGsmFrameBytes);
      final Int16List? out = dec.decode(payload);
      expect(out, isNotNull);
      expect(out!.length, allStarGsmFrameSamples);
    });

    test('mu-law frame encodes one byte per sample', () {
      final AllStarAudioEncoder enc = AllStarAudioEncoder(format: Iax2Format.ulaw);
      final AllStarAudioDecoder dec = AllStarAudioDecoder(format: Iax2Format.ulaw);
      final Int16List pcm = Int16List(allStarGsmFrameSamples);
      final Uint8List payload = enc.encodeFrame(pcm);
      expect(payload.length, allStarGsmFrameSamples);
      expect(dec.decode(payload)!.length, allStarGsmFrameSamples);
    });

    test('GSM decode rejects a non-frame-aligned payload', () {
      final AllStarAudioDecoder dec = AllStarAudioDecoder(format: Iax2Format.gsm);
      expect(dec.decode(Uint8List(10)), isNull);
      expect(dec.decode(Uint8List(0)), isNull);
    });
  });
}
