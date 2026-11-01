/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/hamlib/xara/fm_ctrl.dart' show FmCode;
import 'package:htcommander/hamlib/xara/fm_frame.dart' show Record0;
import 'package:htcommander/radio/ax25_packet.dart';
import 'package:htcommander/radio/packet_decoder.dart';
import 'package:htcommander/radio/tnc_data_fragment.dart';
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
      'Software XARA FM, Session',
    );
    expect(sections.any((s) => s.title == 'AX.25'), isFalse);
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
      'XARA Data level 5: CRC failed',
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
