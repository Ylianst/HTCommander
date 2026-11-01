/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:convert';
import 'dart:typed_data';

import '../hamlib/xara/fm_ctrl.dart' show FmCode;
import '../hamlib/xara/fm_frame.dart' show Kind, Record0, parseData;
import '../hamlib/xara/fm_level.dart';
import 'utils.dart';

/// A XARA (VARA FM) session frame or control code as stored in the packet
/// capture, with the details needed to debug a link: bandwidth, level,
/// modulation, LDPC rate, bit rate, frame position in its burst, lead-in and
/// burst airtime (sent), SNR / LDPC iterations / coherence (received), and the
/// session state at the time.
///
/// Packed as `[record][flags][metaLen hi][metaLen lo][meta JSON][payload]`.
/// `record` is the FM record index (0 = connect, 1..13 = data levels,
/// 14 = short, 15 = start) or [controlRecord] for a control code, whose payload
/// is the code byte. The meta block is present when flag bit 7 is set; older
/// captures without it still parse.
class XaraCapture {
  static const int controlRecord = 0xFF;
  static const int _flagOk = 0x01;
  static const int _flagMeta = 0x80;

  final int record;
  final bool ok;
  final Uint8List payload;
  final Map<String, Object?> meta;

  const XaraCapture(
    this.record,
    this.ok,
    this.payload, [
    this.meta = const <String, Object?>{},
  ]);

  bool get isControl => record == controlRecord;

  int get code => isControl && payload.isNotEmpty ? payload[0] : -1;

  static Uint8List encode({
    required int record,
    required int code,
    required bool ok,
    required Uint8List data,
    Map<String, Object?> meta = const <String, Object?>{},
  }) {
    final List<int> body = record < 0 ? <int>[code & 0xFF] : data;
    final Map<String, Object?> clean = {
      for (final e in meta.entries)
        if (e.value != null)
          e.key: e.value is double
              ? double.parse((e.value! as double).toStringAsFixed(2))
              : e.value,
    };
    final Uint8List json = clean.isEmpty
        ? Uint8List(0)
        : Uint8List.fromList(utf8.encode(jsonEncode(clean)));
    final int flags =
        (record < 0 || ok ? _flagOk : 0) | (json.isEmpty ? 0 : _flagMeta);
    return Uint8List.fromList([
      record < 0 ? controlRecord : record & 0xFF,
      flags,
      if (json.isNotEmpty) ...[json.length >> 8, json.length & 0xFF, ...json],
      ...body,
    ]);
  }

  static XaraCapture? parse(Uint8List b) {
    if (b.length < 2) return null;
    final int flags = b[1];
    int p = 2;
    Map<String, Object?> meta = const <String, Object?>{};
    if ((flags & _flagMeta) != 0) {
      if (b.length < 4) return null;
      final int len = (b[2] << 8) | b[3];
      p = 4 + len;
      if (b.length < p) return null;
      try {
        final Object? m = jsonDecode(utf8.decode(b.sublist(4, p)));
        if (m is Map) meta = m.cast<String, Object?>();
      } on FormatException {
        return null;
      }
    }
    return XaraCapture(
      b[0],
      (flags & _flagOk) != 0,
      Uint8List.sublistView(b, p),
      meta,
    );
  }

  // ---- protocol tables ------------------------------------------------------

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

  static const List<String> _modulations = [
    '',
    'BPSK',
    '4-DPSK',
    '8PSK',
    '16QAM',
    '32QAM',
    '64QAM',
    '128QAM',
    '256QAM',
  ];

  static const Map<int, String> _ldpcRates = {
    2: '1/3',
    3: '1/2',
    4: '2/3',
    5: '3/4',
  };

  String get recordName => switch (record) {
    controlRecord => 'Control',
    0 => 'Connect',
    14 => 'Short',
    15 => 'Start',
    16 => 'Broadcast',
    _ => 'Level $record',
  };

  String get codeName => _codeNames[code] ?? 'Code $code';

  FmBandwidth? get bandwidth => switch (meta['bw']) {
    'narrow' => FmBandwidth.narrow,
    'wide' => FmBandwidth.wide,
    _ => null,
  };

  /// The modem level this frame was sent with, when the bandwidth is known.
  FmLevel? get level {
    final bw = bandwidth;
    if (bw == null || isControl || record > 16) return null;
    return bw.level(FmRecord(record));
  }

  String _modulation(FmLevel l) {
    final int bps = l.layout.bps;
    return bps < _modulations.length ? _modulations[bps] : '$bps bits/symbol';
  }

  /// Mode description, e.g. "8PSK, 58 carriers, LDPC 2/3, 4252 bps".
  String? get modeDescription {
    final l = level;
    if (l == null) return null;
    final rate =
        _ldpcRates[l.rate] ?? 'rate ${(l.layout.k / l.n).toStringAsFixed(2)}';
    return '${_modulation(l)}, ${l.nc} carriers, LDPC $rate, '
        '${l.netBps.round()} bps';
  }

  double? _num(String k) => (meta[k] as num?)?.toDouble();
  int? _int(String k) => (meta[k] as num?)?.toInt();

  bool get _vias => meta['vias'] == true;

  /// Parsed control byte and trailer of a data frame, when it decodes.
  ({
    Uint8List data,
    bool compressed,
    int hint,
    bool last,
    bool full,
    int leadReport,
    int offer,
    int? chainSnr,
  })?
  get dataFrame {
    if (isControl || record == 0 || !ok || payload.isEmpty) return null;
    final d = parseData(FmRecord(record), payload, _vias);
    if (d == null) return null;
    return (
      data: d.data,
      compressed: d.control.compressed,
      hint: d.control.hint,
      last: d.control.last,
      full: d.control.full,
      leadReport: d.trailer.leadReport,
      offer: d.trailer.level,
      chainSnr: d.trailer.chainSnr,
    );
  }

  Record0? get connect => record == 0 && ok ? Record0.parse(payload) : null;

  static String _route(Record0 r) {
    final vias = [r.via1, r.via2].where((v) => v.isNotEmpty).join(',');
    return '${r.source}>${r.target}${vias.isEmpty ? '' : ',$vias'}';
  }

  String get _position {
    final i = _int('i'), n = _int('n');
    return (i != null && n != null && n > 1) ? ' [$i/$n]' : '';
  }

  // ---- display --------------------------------------------------------------

  /// Encoding label for the capture list and clipboard, in the style of DART,
  /// e.g. "Software XARA FM Narrow Level 5 (8PSK, 58 carriers, LDPC 2/3,
  /// 4252 bps), Session, SNR 18.4 dB, 3 LDPC iterations".
  String get encodingLabel {
    final sb = StringBuffer('Software XARA FM');
    final bw = bandwidth;
    if (isControl) {
      sb.write(', Session control');
    } else {
      if (bw != null) {
        sb.write(' ${bw == FmBandwidth.wide ? 'Wide' : 'Narrow'}');
      }
      sb.write(' $recordName');
      final mode = modeDescription;
      if (mode != null) sb.write(' ($mode)');
      sb.write(', Session');
    }
    if (!ok) sb.write(', CRC failed');
    final snr = _num('snr');
    if (snr != null) sb.write(', SNR ${snr.toStringAsFixed(1)} dB');
    final iter = _int('iter');
    if (iter != null && !isControl) {
      sb.write(', $iter LDPC iteration${iter == 1 ? '' : 's'}');
    }
    return sb.toString();
  }

  /// Single-line summary for the packet list.
  String get summary {
    if (isControl) {
      final hits = _int('hits');
      return 'XARA control: $codeName${hits == null ? '' : ' ($hits hits)'}';
    }
    if (!ok) {
      return 'XARA $recordName$_position: '
          '${meta['missing'] == true ? 'missing' : 'CRC failed'}';
    }
    final r = connect;
    if (r != null) {
      final what = r.kind == Kind.connect
          ? 'connect request (${r.wide ? 'wide' : 'narrow'})'
          : r.kind.name;
      return '${_route(r)}: XARA $what';
    }
    final d = dataFrame;
    if (d != null) {
      final flags = [if (d.compressed) 'compressed', if (d.last) 'last'];
      final body = d.compressed
          ? RadioUtils.bytesToHex(d.data)
          : _ascii(d.data);
      return 'XARA $recordName$_position: ${d.data.length} bytes'
          '${flags.isEmpty ? '' : ' (${flags.join(', ')})'}'
          '${d.data.isEmpty ? '' : ': $body'}';
    }
    return 'XARA $recordName$_position: ${payload.length} bytes: '
        '${RadioUtils.bytesToHex(payload)}';
  }

  static String _ascii(Uint8List data) =>
      String.fromCharCodes(data.map((b) => (b >= 32 && b < 127) ? b : 46));

  /// Detail lines for the packet decode panel.
  List<MapEntry<String, String>> get details {
    final lines = <MapEntry<String, String>>[];
    void add(String k, Object? v) {
      if (v != null) lines.add(MapEntry(k, v.toString()));
    }

    String db(String k) => '${_num(k)!.toStringAsFixed(1)} dB';
    String ms(String k) => '${_num(k)!.toStringAsFixed(0)} ms';

    if (isControl) {
      add('Type', 'Control code');
      add('Code', '$code ($codeName)');
      if (meta['hits'] != null) add('Detection hits', _int('hits'));
      if (meta['row'] != null) add('Lead row', _int('row'));
      if (meta['side'] != null) add('Side', meta['side']);
    } else {
      add('Record', '$record ($recordName)');
      final bw = bandwidth;
      if (bw != null) {
        add('Bandwidth', bw == FmBandwidth.wide ? 'Wide' : 'Narrow');
      }
      final l = level;
      if (l != null) {
        add('Modulation', _modulation(l));
        add('Carriers', l.nc);
        add(
          'LDPC rate',
          _ldpcRates[l.rate] ?? (l.layout.k / l.n).toStringAsFixed(2),
        );
        add('Net rate', '${l.netBps.round()} bps');
        add('Frame size', '${l.frameBytes} bytes');
      }
      final i = _int('i'), n = _int('n');
      if (i != null && n != null) add('Frame', '$i of $n');
      add('CRC', ok ? 'OK' : (meta['missing'] == true ? 'Missing' : 'Failed'));
    }

    // Reception quality (received frames).
    if (meta['snr'] != null) add('SNR', db('snr'));
    if (meta['esn0'] != null) add('Es/N0', db('esn0'));
    if (meta['iter'] != null) add('LDPC iterations', _int('iter'));
    if (meta['coh'] != null) add('Coherence', _num('coh')!.toStringAsFixed(2));
    if (meta['ms'] != null) add('Frame airtime', ms('ms'));

    // Transmission (sent frames).
    if (meta['lead'] != null) add('Lead-in', _int('lead'));
    if (meta['burstMs'] != null) add('Burst airtime', ms('burstMs'));
    if (meta['drive'] != null) add('Drive', db('drive'));

    if (meta['vias'] == true) add('Digipeated', 'Yes');
    if (meta['state'] != null) add('Session state', meta['state']);

    final r = connect;
    if (r != null) {
      add('Kind', r.kind.name);
      add('Source', r.source);
      add('Target', r.target);
      if (r.via1.isNotEmpty) add('Via 1', r.via1);
      if (r.via2.isNotEmpty) add('Via 2', r.via2);
      add('Requested bandwidth', r.wide ? 'Wide' : 'Narrow');
      add('Registered', r.registered ? 'Yes' : 'No');
      add('Hop', r.hop);
      return lines;
    }

    final d = dataFrame;
    if (d != null) {
      add('Payload', '${d.data.length} bytes');
      add('Compressed', d.compressed ? 'Yes' : 'No');
      add('Last frame', d.last ? 'Yes' : 'No');
      add('Full frame', d.full ? 'Yes' : 'No');
      add('Queue hint', d.hint);
      add('Lead report', d.leadReport);
      if (record == 15) add('Level offer', d.offer == 0 ? 'None' : d.offer);
      if (d.chainSnr != null) {
        add('Chain SNR', '${(d.chainSnr! / 7.0).toStringAsFixed(1)} dB');
      }
      if (d.data.isNotEmpty) {
        if (!d.compressed) add('Payload text', _ascii(d.data));
        add('Payload HEX', RadioUtils.bytesToHex(d.data));
      }
    } else if (!isControl && payload.isNotEmpty) {
      add('Frame HEX', RadioUtils.bytesToHex(payload));
    }
    return lines;
  }
}
