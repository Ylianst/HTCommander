/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:typed_data';

import '../hamlib/xara/fm_ctrl.dart' show FmCode;
import '../hamlib/xara/fm_frame.dart' show Kind, Record0;
import 'utils.dart';

/// A XARA (VARA FM) session frame or control code as stored in the packet
/// capture. Captured data is packed as `[record][flags][payload]`, where record
/// is the FM record index (0 = connect, 1..13 = data levels, 14 = short,
/// 15 = start) or [controlRecord] for a control code (the payload is the code).
class XaraCapture {
  static const int controlRecord = 0xFF;
  static const int _flagOk = 0x01;

  final int record;
  final bool ok;
  final Uint8List payload;

  const XaraCapture(this.record, this.ok, this.payload);

  bool get isControl => record == controlRecord;

  int get code => isControl && payload.isNotEmpty ? payload[0] : -1;

  static Uint8List encode({
    required int record,
    required int code,
    required bool ok,
    required Uint8List data,
  }) {
    if (record < 0) {
      return Uint8List.fromList([controlRecord, _flagOk, code & 0xFF]);
    }
    return Uint8List.fromList([record & 0xFF, ok ? _flagOk : 0, ...data]);
  }

  static XaraCapture? parse(Uint8List b) {
    if (b.length < 2) return null;
    return XaraCapture(
      b[0],
      (b[1] & _flagOk) != 0,
      Uint8List.sublistView(b, 2),
    );
  }

  static const Map<int, String> _codeNames = {
    FmCode.ackStay: 'ACK',
    FmCode.nack: 'NACK',
    FmCode.qrt: 'QRT (disconnect)',
    FmCode.brk: 'BREAK',
    FmCode.ackUp2: 'ACK, speed up 2',
    FmCode.ackDown: 'ACK, slow down',
    FmCode.ackUp1: 'ACK, speed up 1',
    FmCode.ackUp3: 'ACK, speed up 3',
    FmCode.ackUp6: 'ACK, speed up 6',
    FmCode.ackSecondOnly: 'ACK second frame only',
    FmCode.ackFirstOnly: 'ACK first frame only',
    FmCode.ackReq0: 'ACK request 0',
    FmCode.ackReq1: 'ACK request 1',
    FmCode.goAhead: 'Go ahead',
    FmCode.idle: 'Idle',
    FmCode.noTraffic: 'No traffic',
    FmCode.relayFailed: 'Relay failed',
    FmCode.connectReplyNarrow: 'Connect reply (narrow)',
    FmCode.connectReplyWide: 'Connect reply (wide)',
  };

  String get recordName => switch (record) {
    controlRecord => 'Control',
    0 => 'Connect',
    14 => 'Short',
    15 => 'Start',
    16 => 'Broadcast',
    _ => 'Data level $record',
  };

  String get codeName => _codeNames[code] ?? 'Code $code';

  Record0? get connect => record == 0 && ok ? Record0.parse(payload) : null;

  static String _route(Record0 r) {
    final vias = [r.via1, r.via2].where((v) => v.isNotEmpty).join(',');
    return '${r.source}>${r.target}${vias.isEmpty ? '' : ',$vias'}';
  }

  /// Single-line summary for the packet list.
  String get summary {
    if (isControl) return 'XARA control: $codeName';
    if (!ok) return 'XARA $recordName: CRC failed';
    final r = connect;
    if (r != null) {
      final what = r.kind == Kind.connect
          ? 'connect request (${r.wide ? 'wide' : 'narrow'})'
          : r.kind.name;
      return '${_route(r)}: XARA $what';
    }
    return 'XARA $recordName: ${payload.length} bytes: '
        '${RadioUtils.bytesToHex(payload)}';
  }

  /// Detail lines for the packet decode panel.
  List<MapEntry<String, String>> get details {
    final lines = <MapEntry<String, String>>[
      MapEntry('Record', isControl ? 'Control' : '$record ($recordName)'),
    ];
    if (isControl) {
      lines.add(MapEntry('Code', '$code ($codeName)'));
      return lines;
    }
    lines.add(MapEntry('CRC', ok ? 'OK' : 'Failed'));
    final r = connect;
    if (r != null) {
      lines.add(MapEntry('Kind', r.kind.name));
      lines.add(MapEntry('Source', r.source));
      lines.add(MapEntry('Target', r.target));
      if (r.via1.isNotEmpty) lines.add(MapEntry('Via 1', r.via1));
      if (r.via2.isNotEmpty) lines.add(MapEntry('Via 2', r.via2));
      lines.add(MapEntry('Bandwidth', r.wide ? 'Wide' : 'Narrow'));
      lines.add(MapEntry('Registered', r.registered ? 'Yes' : 'No'));
      lines.add(MapEntry('Hop', '${r.hop}'));
    } else if (payload.isNotEmpty) {
      lines.add(MapEntry('Payload HEX', RadioUtils.bytesToHex(payload)));
    }
    return lines;
  }
}
