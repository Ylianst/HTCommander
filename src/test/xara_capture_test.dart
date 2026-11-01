/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/hamlib/xara/fm_ctrl.dart' show FmCode;
import 'package:htcommander/hamlib/xara/fm_frame.dart'
    show Record0, Trailer, buildData;
import 'package:htcommander/hamlib/xara/fm_level.dart';
import 'package:htcommander/radio/ax25_packet.dart';
import 'package:htcommander/radio/packet_decoder.dart';
import 'package:htcommander/radio/tnc_data_fragment.dart';
import 'package:htcommander/radio/utils.dart';
import 'package:htcommander/radio/xara_capture.dart';

TncDataFragment fragment(Uint8List data, {bool incoming = true}) =>
    TncDataFragment(
      finalFragment: true,
      fragmentId: 0,
      data: data,
      channelId: 2,
      regionId: 0,
      incoming: incoming,
      encoding: FragmentEncodingType.softwareXara,
      frameType: FragmentFrameType.xara,
    );

void main() {
  final connectBytes = Record0.connect(
    'N1ABC',
    'N0CALL-1',
    'N9DIG',
    '',
    false,
    true,
  ).toBytes()!;

  test('connect requests decode with route and bandwidth', () {
    final f = fragment(
      XaraCapture.encode(record: 0, code: -1, ok: true, data: connectBytes),
    );
    expect(
      PacketDecoder.fragmentToShortString(f),
      'N1ABC>N0CALL-1,N9DIG: XARA connect request (wide)',
    );
    final sections = PacketDecoder.decode(f);
    final xara = sections.firstWhere((s) => s.title == 'XARA');
    final details = {for (final e in xara.lines) e.key: e.value};
    expect(details['Target'], 'N0CALL-1');
    expect(details['Via 1'], 'N9DIG');
    expect(
      sections.firstWhere((s) => s.title == 'Frame').lines.single.value,
      'Software XARA FM Connect, Session',
    );
    expect(sections.any((s) => s.title == 'AX.25'), isFalse);
  });

  test('received data frames show mode, burst position and quality', () {
    final frame = buildData(
      FmRecord.start,
      FmBandwidth.narrow.level(FmRecord.start).frameBytes,
      'Hello BBS\r'.codeUnits,
      false,
      2,
      true,
      const Trailer(leadReport: 3, level: 5),
    );
    final f = fragment(
      XaraCapture.encode(
        record: 15,
        code: -1,
        ok: true,
        data: frame,
        meta: {
          'bw': 'narrow',
          'i': 1,
          'n': 2,
          'snr': 18.437,
          'esn0': 12.1,
          'iter': 3,
          'coh': 0.913,
          'ms': 1234.5,
          'vias': false,
          'state': 'AwaitData',
        },
      ),
    );
    expect(
      PacketDecoder.encodingLabel(f),
      'Software XARA FM Narrow Start (4-DPSK, 14 carriers, LDPC 1/2, 566 bps), '
      'Session, SNR 18.4 dB, 3 LDPC iterations',
    );
    expect(
      PacketDecoder.fragmentToShortString(f),
      'XARA Start [1/2]: 10 bytes (last): Hello BBS.',
    );
    final details = {
      for (final e in PacketDecoder.decode(
        f,
      ).firstWhere((s) => s.title == 'XARA').lines)
        e.key: e.value,
    };
    expect(details['Bandwidth'], 'Narrow');
    expect(details['Modulation'], '4-DPSK');
    expect(details['Frame'], '1 of 2');
    expect(details['SNR'], '18.4 dB');
    expect(details['LDPC iterations'], '3');
    expect(details['Coherence'], '0.91');
    expect(details['Frame airtime'], '1235 ms');
    expect(details['Session state'], 'AwaitData');
    expect(details['Level offer'], '5');
    expect(details['Lead report'], '3');
    expect(details['Queue hint'], '2');
    expect(details['Payload text'], 'Hello BBS.');
  });

  test('sent high-level wide frames show modulation, rate and airtime', () {
    final f = fragment(
      XaraCapture.encode(
        record: 9,
        code: -1,
        ok: true,
        data: Uint8List(4),
        meta: {
          'bw': 'wide',
          'i': 2,
          'n': 2,
          'lead': 23,
          'burstMs': 2100.4,
          'drive': -1.5,
        },
      ),
      incoming: false,
    );
    expect(
      PacketDecoder.encodingLabel(f),
      'Software XARA FM Wide Level 9 (32QAM, 116 carriers, LDPC 2/3, '
      '14144 bps), Session',
    );
    final details = {
      for (final e in PacketDecoder.decode(
        f,
      ).firstWhere((s) => s.title == 'XARA').lines)
        e.key: e.value,
    };
    expect(details['Lead-in'], '23');
    expect(details['Burst airtime'], '2100 ms');
    expect(details['Drive'], '-1.5 dB');
    expect(details['Net rate'], '14144 bps');
  });

  test('control codes carry detection details', () {
    final f = fragment(
      XaraCapture.encode(
        record: -1,
        code: FmCode.ackUp1,
        ok: true,
        data: Uint8List(0),
        meta: {'hits': 9, 'row': 2, 'side': 'source', 'state': 'Sending'},
      ),
    );
    expect(
      PacketDecoder.fragmentToShortString(f),
      'XARA control: ACK, speed up 1 (9 hits)',
    );
    expect(
      PacketDecoder.encodingLabel(f),
      'Software XARA FM, Session control (3-tone FSK), 9/10 hits',
    );
  });

  test('dropped control codes say why', () {
    XaraCapture rx(Map<String, Object?> meta) => XaraCapture.parse(
      XaraCapture.encode(
        record: -1,
        code: FmCode.ackStay,
        ok: true,
        data: Uint8List(0),
        meta: meta,
      ),
    )!;
    final late = rx({
      'hits': 8,
      'verdict': 'late',
      'ticks': 600,
      'window': 500,
    });
    expect(late.dropped, isTrue);
    expect(late.verdictText, 'dropped: late, 1600 ms > window 1333 ms');
    expect(
      late.summary,
      endsWith(' - dropped: late, 1600 ms > window 1333 ms'),
    );
    expect(
      late.encodingLabel,
      endsWith(', dropped: late, 1600 ms > window 1333 ms'),
    );
    final details = {for (final e in late.details) e.key: e.value};
    expect(details['Reply delay'], '1600 ms (600 ticks)');
    expect(details['Reply window'], '1333 ms (500 ticks)');

    expect(
      rx({'verdict': 'early', 'ticks': 30}).verdictText,
      'dropped: early, 80 ms < 213 ms',
    );
    expect(
      rx({'verdict': 'transmitting'}).verdictText,
      'dropped: arrived while transmitting',
    );
    final ok = rx({'verdict': 'accepted', 'ticks': 300, 'window': 500});
    expect(ok.dropped, isFalse);
    expect(ok.verdictText, 'accepted, reply after 800 ms (window 1333 ms)');
    expect(ok.summary, isNot(contains('dropped')));
  });

  test('sent connect replies show key, rows, airtime and tones', () {
    final keyD = XaraCapture.callKey('N0CALL-1');
    final keyU = XaraCapture.callKey('N1ABC');
    final f = fragment(
      XaraCapture.encode(
        record: -1,
        code: FmCode.connectReplyNarrow,
        ok: true,
        data: Uint8List(0),
        meta: {
          'lead': 28,
          'rows': 38,
          'burstMs': 810.7,
          'drive': -5.0,
          'keyD': keyD,
          'keyU': keyU,
          'caller': 'N1ABC',
          'answerer': 'N0CALL-1',
          'state': 'AwaitGo',
        },
      ),
      incoming: false,
    );
    final u = XaraCapture.keyHex(keyU);
    expect(
      PacketDecoder.encodingLabel(f),
      'Software XARA FM, Session control (3-tone FSK, 38 rows x 21.3 ms = '
      '811 ms, key U=$u)',
    );
    expect(
      PacketDecoder.fragmentToShortString(f),
      'XARA control: Connect reply (narrow) [U=$u]',
    );
    final details = {
      for (final e in PacketDecoder.decode(
        f,
      ).firstWhere((s) => s.title == 'XARA').lines)
        e.key: e.value,
    };
    expect(details['Coded with'], contains('Caller key U=$u'));
    expect(details['Key D'], XaraCapture.keyHex(keyD));
    expect(details['Lead-in rows'], '28 of 28');
    expect(details['Frame airtime'], '811 ms');
    expect(details['Link caller'], 'N1ABC');
    expect(details['Burst airtime'], '811 ms');
    final tones = details['Code tones (Hz)']!.split(', ');
    expect(tones, hasLength(10));
    expect(tones.every((r) => r.split('/').length == 3), isTrue);
    final ack = XaraCapture.parse(
      XaraCapture.encode(
        record: -1,
        code: FmCode.ackStay,
        ok: true,
        data: Uint8List(0),
        meta: {'keyD': keyD, 'keyU': keyU},
      ),
    )!;
    expect(ack.codeKey, 'D=${XaraCapture.keyHex(keyD)}');
  });

  test('receiver-state entries show what is expected and with which keys', () {
    final keyU = XaraCapture.callKey('N1ABC');
    final f = fragment(
      XaraCapture.encode(
        record: -2,
        code: -1,
        ok: true,
        data: Uint8List(0),
        meta: {
          'bw': 'wide',
          'records': <int>[],
          'codes': [
            FmCode.qrt,
            FmCode.connectReplyNarrow,
            FmCode.connectReplyWide,
          ],
          'keyD': 1,
          'keyU': keyU,
          'n': 1,
          'linked': false,
          'state': 'Calling',
        },
      ),
    );
    expect(
      PacketDecoder.fragmentToShortString(f),
      'XARA listening (Calling): codes QRT (disconnect), '
      'Connect reply (narrow), Connect reply (wide) '
      '[D=0x000001, U=${XaraCapture.keyHex(keyU)}]',
    );
    expect(
      PacketDecoder.encodingLabel(f),
      'Software XARA FM Wide, Receiver state',
    );
    expect(PacketDecoder.frameBytes(f), isEmpty);
    final details = {
      for (final e in PacketDecoder.decode(
        f,
      ).firstWhere((s) => s.title == 'XARA').lines)
        e.key: e.value,
    };
    expect(
      details['Connect replies must use'],
      'U=${XaraCapture.keyHex(keyU)}',
    );
    expect(details['Expected frames'], 'None');
    expect(
      PacketDecoder.decode(
        f,
      ).firstWhere((s) => s.title == 'Packet').lines.map((e) => e.key),
      isNot(contains('Data')),
    );
  });

  test('connect requests show the keys both ends derive', () {
    final f = fragment(
      XaraCapture.encode(record: 0, code: -1, ok: true, data: connectBytes),
    );
    final details = {
      for (final e in PacketDecoder.decode(
        f,
      ).firstWhere((s) => s.title == 'XARA').lines)
        e.key: e.value,
    };
    expect(
      details['Key D (hash of N9DIG)'],
      XaraCapture.keyHex(XaraCapture.callKey('N9DIG')),
    );
    expect(
      details['Expected reply key'],
      'U=${XaraCapture.keyHex(XaraCapture.callKey('N1ABC'))}',
    );
  });

  test(
    'the Packet section shows the over-the-air frame, not capture metadata',
    () {
      final frame = buildData(
        FmRecord.start,
        FmBandwidth.narrow.level(FmRecord.start).frameBytes,
        'BBS>\r'.codeUnits,
        false,
        0,
        true,
        const Trailer(),
      );
      final f = fragment(
        XaraCapture.encode(
          record: 15,
          code: -1,
          ok: true,
          data: frame,
          meta: {
            'bw': 'narrow',
            'i': 1,
            'n': 1,
            'lead': 25,
            'state': 'Sending',
          },
        ),
        incoming: false,
      );
      expect(PacketDecoder.frameBytes(f), frame);
      final packet = {
        for (final e in PacketDecoder.decode(
          f,
        ).firstWhere((s) => s.title == 'Packet').lines)
          e.key: e.value,
      };
      expect(packet['Size'], '${frame.length} bytes');
      expect(packet['Data HEX'], RadioUtils.bytesToHex(frame));
      expect(packet['Data'], startsWith('BBS>.'));
      expect(packet['Data'], isNot(contains('"bw"')));

      final control = fragment(
        XaraCapture.encode(
          record: -1,
          code: FmCode.ackStay,
          ok: true,
          data: Uint8List(0),
          meta: {'hits': 9},
        ),
      );
      expect(PacketDecoder.frameBytes(control), isEmpty);
      final controlPacket = PacketDecoder.decode(
        control,
      ).firstWhere((s) => s.title == 'Packet');
      expect(controlPacket.lines.map((e) => e.key), isNot(contains('Data')));
    },
  );
  test('captures without metadata still parse', () {
    final legacy = Uint8List.fromList([15, 1, 0x41, 0x42]);
    final c = XaraCapture.parse(legacy)!;
    expect(c.record, 15);
    expect(c.payload, [0x41, 0x42]);
    expect(c.meta, isEmpty);
  });

  test('control codes, data records and CRC failures are labelled', () {
    expect(
      PacketDecoder.fragmentToShortString(
        fragment(
          XaraCapture.encode(
            record: -1,
            code: FmCode.connectReplyNarrow,
            ok: true,
            data: Uint8List(0),
          ),
          incoming: false,
        ),
      ),
      'XARA control: Connect reply (narrow)',
    );
    expect(
      PacketDecoder.fragmentToShortString(
        fragment(
          XaraCapture.encode(
            record: 15,
            code: -1,
            ok: true,
            data: Uint8List.fromList([0x41, 0x42]),
          ),
        ),
      ),
      'XARA Start: 2 bytes: 4142',
    );
    expect(
      PacketDecoder.fragmentToShortString(
        fragment(
          XaraCapture.encode(
            record: 5,
            code: -1,
            ok: false,
            data: Uint8List(0),
          ),
        ),
      ),
      'XARA Level 5: CRC failed',
    );
  });

  test('XARA captures survive storage and never decode as AX.25', () {
    final f = fragment(
      XaraCapture.encode(record: 0, code: -1, ok: true, data: connectBytes),
    );
    final restored = TncDataFragment.fromString(f.toString())!;
    expect(restored.frameType, FragmentFrameType.xara);
    expect(restored.data, f.data);
    expect(
      TncDataFragment.fromJson(f.toJson()).frameType,
      FragmentFrameType.xara,
    );
    expect(AX25Packet.decode(f), isNull);
    expect(FragmentFrameType.fx25.index, 2);
  });
}
