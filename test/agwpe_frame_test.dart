import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/services/agwpe/agwpe_frame.dart';

void main() {
  test('AgwpeFrame round-trips header and payload', () {
    final original = AgwpeFrame(
      port: 0,
      dataKind: AgwpeDataKind.connectedData,
      pid: 240,
      callFrom: 'K7VZT-5',
      callTo: 'N0CALL-1',
      user: 0x12345678,
      data: Uint8List.fromList(<int>[1, 2, 3, 4, 5]),
    );

    final bytes = original.toBytes();
    expect(bytes.length, AgwpeFrame.headerLength + 5);

    final parsed = AgwpeFrame.tryParse(bytes);
    expect(parsed, isNotNull);
    expect(parsed!.consumed, bytes.length);

    final frame = parsed.frame;
    expect(frame.port, original.port);
    expect(frame.dataKind, original.dataKind);
    expect(frame.pid, original.pid);
    expect(frame.callFrom, original.callFrom);
    expect(frame.callTo, original.callTo);
    expect(frame.user, original.user);
    expect(frame.data, original.data);
  });

  test('AgwpeFrame DataLen is little-endian at offset 28', () {
    final frame = AgwpeFrame(
      dataKind: AgwpeDataKind.monitorUnproto,
      data: Uint8List.fromList(List<int>.filled(260, 0x41)),
    );
    final bytes = frame.toBytes();
    // 260 = 0x0104 -> little-endian bytes 0x04, 0x01, 0x00, 0x00.
    expect(bytes[28], 0x04);
    expect(bytes[29], 0x01);
    expect(bytes[30], 0x00);
    expect(bytes[31], 0x00);
  });

  test('AgwpeFrame.tryParse returns null on incomplete data', () {
    // A complete header that declares a 10-byte payload but supplies none.
    final frame = AgwpeFrame(
      dataKind: AgwpeDataKind.connectedData,
      data: Uint8List.fromList(List<int>.filled(10, 0)),
    );
    final full = frame.toBytes();
    final truncated = Uint8List.sublistView(full, 0, full.length - 5);
    expect(AgwpeFrame.tryParse(truncated), isNull);

    // Fewer bytes than even the header.
    expect(AgwpeFrame.tryParse(Uint8List(10)), isNull);
  });

  test('AgwpeFrame.tryParse reports consumed bytes for streamed frames', () {
    final a = AgwpeFrame(
      dataKind: AgwpeDataKind.registerCallsign,
      callFrom: 'AAA',
      data: Uint8List.fromList(<int>[9]),
    ).toBytes();
    final b = AgwpeFrame(
      dataKind: AgwpeDataKind.disconnect,
      callFrom: 'BBB',
    ).toBytes();

    final combined = Uint8List(a.length + b.length)
      ..setRange(0, a.length, a)
      ..setRange(a.length, a.length + b.length, b);

    final first = AgwpeFrame.tryParse(combined);
    expect(first, isNotNull);
    expect(first!.consumed, a.length);
    expect(first.frame.dataKind, AgwpeDataKind.registerCallsign);

    final rest = Uint8List.sublistView(combined, first.consumed);
    final second = AgwpeFrame.tryParse(rest);
    expect(second, isNotNull);
    expect(second!.consumed, b.length);
    expect(second.frame.dataKind, AgwpeDataKind.disconnect);
    expect(second.frame.callFrom, 'BBB');
  });
}
