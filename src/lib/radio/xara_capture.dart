/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:convert';
import 'dart:typed_data';

import '../hamlib/xara/call.dart' show callHash;
import '../hamlib/xara/fm_ctrl.dart'
    show Codebook, FmCode, codeRows, ctrlSymbol, leadRows;
import '../hamlib/xara/fm_frame.dart' show Kind, Record0, parseData;
import '../hamlib/xara/fm_level.dart';
import '../hamlib/xara/ofdm_const.dart' as ofdm;
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

  /// A receiver-state entry: what the station now listens for (no payload).
  static const int listenRecord = 0xFE;
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

  bool get isListen => record == listenRecord;

  int get code => isControl && payload.isNotEmpty ? payload[0] : -1;

  /// Packs a capture entry. [record] is the FM record index, -1 for a control
  /// code ([code]) or -2 for a receiver-state entry.
  static Uint8List encode({
    required int record,
    required int code,
    required bool ok,
    required Uint8List data,
    Map<String, Object?> meta = const <String, Object?>{},
  }) {
    final List<int> body = record == -1
        ? <int>[code & 0xFF]
        : (record < 0 ? const <int>[] : data);
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
      record == -1
          ? controlRecord
          : (record < 0 ? listenRecord : record & 0xFF),
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
    listenRecord => 'Listen',
    0 => 'Connect',
    14 => 'Short',
    15 => 'Start',
    16 => 'Broadcast',
    _ => 'Level $record',
  };

  String get codeName => _codeNames[code] ?? 'Code $code';

  static String _codeLabel(int c) => _codeNames[c] ?? 'Code $c';

  /// Control frames are 3-tone FSK rows of [ctrlSymbol] samples.
  static const double rowMs = ctrlSymbol * 1000.0 / ofdm.fs;
  static const double _toneHz = ofdm.fs / ctrlSymbol;

  /// ARQ reply timing is counted in 128-sample ticks.
  static const double tickMs = 128 * 1000.0 / ofdm.fs;

  /// How the session treated a received control code, when known.
  String? get verdict => meta['verdict'] as String?;

  bool get dropped => verdict != null && verdict != 'accepted';

  String _ms(int ticks) => '${(ticks * tickMs).round()} ms';

  /// e.g. "dropped: late, 1650 ms > window 1333 ms".
  String? get verdictText {
    final v = verdict;
    if (v == null) return null;
    final t = _int('ticks'), w = _int('window');
    final delay = t == null ? '' : ', reply after ${_ms(t)}';
    return switch (v) {
      'accepted' => 'accepted$delay${w == null ? '' : ' (window ${_ms(w)})'}',
      'late' => 'dropped: late${t == null || w == null ? '' : ', ${_ms(t)} > window ${_ms(w)}'}',
      'early' => 'dropped: early${t == null ? '' : ', ${_ms(t)} < ${_ms(80)}'}',
      'transmitting' => 'dropped: arrived while transmitting',
      'unexpected' => 'dropped: not expected in this state',
      _ => v,
    };
  }

  static String keyHex(int k) =>
      '0x${k.toRadixString(16).toUpperCase().padLeft(6, '0')}';

  /// Hash a callsign the way XARA keys its control codebook.
  static int callKey(String call) => callHash(utf8.encode(call));

  /// Connect replies are coded with the caller key (U); every other control
  /// code with the downstream key (D).
  static bool usesCallerKey(int c) =>
      c == FmCode.connectReplyNarrow || c == FmCode.connectReplyWide;

  int? get keyD => _int('keyD');
  int? get keyU => _int('keyU');

  /// The key [code] was (or would be) coded with, labelled.
  String? get codeKey {
    final k = usesCallerKey(code) ? keyU : keyD;
    if (k == null) return null;
    return '${usesCallerKey(code) ? 'U' : 'D'}=${keyHex(k)}';
  }

  /// Tone frequencies (Hz) of the 10 code rows, derived from the keys.
  List<List<double>>? get codeTones {
    final d = keyD, u = keyU;
    if (!isControl || d == null || u == null || code < 1 || code > 24) {
      return null;
    }
    return [
      for (final row in Codebook(d, u).code(code))
        [for (final bin in row) bin * _toneHz],
    ];
  }

  FmBandwidth? get bandwidth => switch (meta['bw']) {
    'narrow' => FmBandwidth.narrow,
    'wide' => FmBandwidth.wide,
    _ => null,
  };

  /// The modem level this frame was sent with, when the bandwidth is known.
  FmLevel? get level {
    final bw = bandwidth;
    if (bw == null || isControl || isListen || record > 16) return null;
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
    if (isControl || isListen || record == 0 || !ok || payload.isEmpty) {
      return null;
    }
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
      // Control frames are not OFDM: 3-tone FSK rows, lead-in + 10 code rows.
      sb.write(', Session control (3-tone FSK');
      final rows = _int('rows');
      if (rows != null) {
        sb.write(
          ', $rows rows x ${rowMs.toStringAsFixed(1)} ms = '
          '${(rows * rowMs).round()} ms',
        );
      }
      final k = codeKey;
      if (k != null) sb.write(', key $k');
      sb.write(')');
      final hits = _int('hits');
      if (hits != null) sb.write(', $hits/$codeRows hits');
      if (dropped) sb.write(', ${verdictText!}');
      return sb.toString();
    }
    if (isListen) {
      if (bw != null) {
        sb.write(' ${bw == FmBandwidth.wide ? 'Wide' : 'Narrow'}');
      }
      return '$sb, Receiver state';
    }
    if (bw != null) {
      sb.write(' ${bw == FmBandwidth.wide ? 'Wide' : 'Narrow'}');
    }
    sb.write(' $recordName');
    final mode = modeDescription;
    if (mode != null) sb.write(' ($mode)');
    sb.write(', Session');
    if (!ok) sb.write(', CRC failed');
    final snr = _num('snr');
    if (snr != null) sb.write(', SNR ${snr.toStringAsFixed(1)} dB');
    final iter = _int('iter');
    if (iter != null) {
      sb.write(', $iter LDPC iteration${iter == 1 ? '' : 's'}');
    }
    return sb.toString();
  }

  List<int> _list(String k) => [
    for (final v in (meta[k] as List?) ?? const <Object?>[])
      if (v is num) v.toInt(),
  ];

  String get _listenWhat {
    final records = _list('records');
    final codes = _list('codes');
    final parts = <String>[
      if (records.isNotEmpty)
        'frames ${records.map((r) => XaraCapture(r, true, Uint8List(0)).recordName).join(', ')}',
      if (codes.isNotEmpty) 'codes ${codes.map(_codeLabel).join(', ')}',
    ];
    return parts.isEmpty ? 'nothing' : parts.join('; ');
  }

  /// Single-line summary for the packet list.
  String get summary {
    if (isControl) {
      final hits = _int('hits');
      final k = codeKey;
      return 'XARA control: $codeName'
          '${k == null ? '' : ' [$k]'}'
          '${hits == null ? '' : ' ($hits hits)'}'
          '${dropped ? ' - ${verdictText!}' : ''}';
    }
    if (isListen) {
      final codes = _list('codes');
      final keys = codes.isEmpty || keyD == null
          ? ''
          : ' [D=${keyHex(keyD!)}, U=${keyHex(keyU ?? 0)}]';
      return 'XARA listening (${meta['state'] ?? '?'}): $_listenWhat$keys';
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
      add('Type', 'Control code (3-tone FSK, not OFDM)');
      add('Code', '$code ($codeName)');
      final k = codeKey;
      if (k != null) {
        add(
          'Coded with',
          usesCallerKey(code)
              ? 'Caller key $k (connect replies use the caller hash)'
              : 'Downstream key $k',
        );
      }
      if (keyD != null) add('Key D', keyHex(keyD!));
      if (keyU != null) add('Key U', keyHex(keyU!));
      if (meta['caller'] != null) add('Link caller', meta['caller']);
      if (meta['answerer'] != null) add('Link answerer', meta['answerer']);
      final lead = _int('lead');
      final rows = _int('rows');
      if (lead != null) add('Lead-in rows', '$lead of $leadRows');
      add('Code rows', codeRows);
      add('Row duration', '${rowMs.toStringAsFixed(1)} ms');
      if (rows != null) add('Frame airtime', '${(rows * rowMs).round()} ms');
      if (meta['hits'] != null) {
        add('Detection hits', '${_int('hits')} of $codeRows rows');
      }
      if (meta['row'] != null) add('Lead-in heard from row', _int('row'));
      if (meta['side'] != null) add('Side', meta['side']);
      if (verdict != null) add('Session verdict', verdictText);
      final t = _int('ticks'), w = _int('window');
      if (t != null) add('Reply delay', '${_ms(t)} ($t ticks)');
      if (w != null) add('Reply window', '${_ms(w)} ($w ticks)');
      final tones = codeTones;
      if (tones != null) {
        add(
          'Code tones (Hz)',
          tones.map((r) => r.map((f) => f.round()).join('/')).join(', '),
        );
      }
    } else if (isListen) {
      add('Type', 'Receiver state (what this station now listens for)');
      final bw = bandwidth;
      if (bw != null) {
        add('Bandwidth', bw == FmBandwidth.wide ? 'Wide' : 'Narrow');
      }
      final records = _list('records');
      add(
        'Expected frames',
        records.isEmpty
            ? 'None'
            : records
                  .map(
                    (r) =>
                        '$r (${XaraCapture(r, true, Uint8List(0)).recordName})',
                  )
                  .join(', '),
      );
      final codes = _list('codes');
      add(
        'Expected codes',
        codes.isEmpty
            ? 'None'
            : codes.map((c) => '$c (${_codeLabel(c)})').join(', '),
      );
      if (keyD != null) add('Key D', keyHex(keyD!));
      if (keyU != null) add('Key U', keyHex(keyU!));
      if (codes.any(usesCallerKey) && keyU != null) {
        add('Connect replies must use', 'U=${keyHex(keyU!)}');
      }
      if (meta['n'] != null) add('Frames per burst', _int('n'));
      if (meta['linked'] != null) {
        add('Linked', meta['linked'] == true ? 'Yes' : 'No');
      }
      if (meta['answering'] == false) add('Answering calls', 'No');
      if (meta['caller'] != null) add('Link caller', meta['caller']);
      if (meta['answerer'] != null) add('Link answerer', meta['answerer']);
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
    if (meta['lead'] != null && !isControl) add('Lead-in', _int('lead'));
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
      // The keys both ends derive from these callsigns. The answer must send its
      // connect reply with U, and the caller listens for it with U.
      final down = r.via1.isNotEmpty ? r.via1 : r.target;
      add('Key D (hash of $down)', keyHex(callKey(down)));
      add('Key U (hash of ${r.source})', keyHex(callKey(r.source)));
      add('Expected reply key', 'U=${keyHex(callKey(r.source))}');
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
    } else if (!isControl && !isListen && payload.isNotEmpty) {
      add('Frame HEX', RadioUtils.bytesToHex(payload));
    }
    return lines;
  }
}
