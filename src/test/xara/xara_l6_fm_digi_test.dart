/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Layer 6 tests: the FM digipeater. Ports the unit tests in XARA's
`fm/digi.rs` and the randomized golden transcript in `tests/fm_digi.rs`
(`golden/fm_digi.txt`, compared byte for byte).
*/

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/hamlib/xara/arq_host.dart';
import 'package:htcommander/hamlib/xara/arq_time.dart';
import 'package:htcommander/hamlib/xara/call.dart';
import 'package:htcommander/hamlib/xara/fm_adapt.dart' show snrOffsetDb;
import 'package:htcommander/hamlib/xara/fm_ctrl.dart';
import 'package:htcommander/hamlib/xara/fm_digi.dart';
import 'package:htcommander/hamlib/xara/fm_frame.dart';
import 'package:htcommander/hamlib/xara/fm_level.dart';
import 'package:htcommander/hamlib/xara/xorshift.dart';

import 'xara_arq_sim.dart' show digest;

FmRecord rec(int i) => FmRecord.fromIndex(i)!;

Uint8List connect(String src, String via1, String via2, String dst, int hop) =>
    Record0.connect(src, dst, via1, via2, true, false).copyWith(hop: hop).toBytes()!;

List<DigiOutput> drain(Digi d) {
  final List<DigiOutput> out = <DigiOutput>[];
  while (true) {
    final DigiOutput? o = d.pop();
    if (o == null) return out;
    out.add(o);
  }
}

List<DigiTx> txs(List<DigiOutput> o) => <DigiTx>[for (final DigiOutput x in o) if (x is DigiOutTx) x.tx];

String hostDebug(HostEvent e) => e.debug;

String outLine(DigiOutput o) => switch (o) {
      DigiOutTx(tx: DigiTxData(:final FmRecord record, :final Uint8List frame, :final int lead, :final Side side)) =>
        'Tx(Data { record: ${record.index}, frame: ${digest(frame)}, lead: $lead, side: ${side.idx} })',
      DigiOutTx(:final DigiTx tx) => 'Tx(${tx.debug})',
      DigiOutListen(:final DigiListen listen) => 'Listen(DigiListen { bw: ${fmBwDebug(listen.bw)}, '
          'data_key: ${listen.dataKey}, records: [${listen.records.map((r) => r.index).join(', ')}], '
          'ctrl: [${listen.ctrl.map((c) => '(${c.keyD}, ${c.keyU}, [${c.codes.join(', ')}])').join(', ')}] })',
      DigiOutHost(:final HostEvent event) => 'Host(${hostDebug(event)})',
      DigiOutDone() => 'Done',
    };

void drainTo(Digi d, String tag, StringBuffer out) {
  while (true) {
    final DigiOutput? o = d.pop();
    if (o == null) return;
    out.write('$tag ${outLine(o)}\n');
  }
}

const List<(String, String, int)> paths = <(String, String, int)>[
  ('N2CALL', '', 0),
  ('N3CALL', 'N2CALL', 1),
  ('N2CALL', 'N3CALL', 0),
  ('N2CALL', 'N0CALL', 0),
];

Uint8List record0(XorShift r) {
  final (String via1, String via2, int hop) = paths[r.below(paths.length)];
  final bool registered = r.below(4) != 0;
  final bool wide = r.below(2) == 0;
  final Record0 rec = Record0.connect('N0CALL', 'N1CALL', via1, via2, registered, wide);
  final int compression = r.below(3);
  final int chain = r.below(200);
  return rec.copyWith(hop: hop, compression: compression, chainSnr: chain).toBytes()!;
}

Uint8List dataFrame(FmRecord record, int levelByte) {
  final Trailer t = Trailer(leadReport: 3, level: levelByte, chainSnr: 100);
  return buildData(record, FmBandwidth.narrow.level(record).frameBytes, 'data'.codeUnits, false, 2, false, t);
}

void scriptedOpening(Digi d, StringBuffer out) {
  final Uint8List c = Record0.connect('N0CALL', 'N1CALL', 'N2CALL', '', true, false).toBytes()!;
  d.onRecord0(0, c, 20.0);
  drainTo(d, 's0', out);
  // (isCtrl, code-or-record, side-or-levelByte)
  const List<(bool, int, int)> steps = <(bool, int, int)>[
    (true, 23, 1),
    (true, 14, 0),
    (false, 15, 6),
    (true, 1, 0),
    (false, 14, 0),
    (true, 9, 0),
    (false, 7, 0),
    (true, 1, 0),
    (true, 2, 0),
    (true, 2, 0),
    (true, 2, 0),
    (false, 5, 0),
    (true, 6, 0),
    (false, 4, 0),
    (true, 8, 0),
    (true, 4, 0),
    (true, 14, 1),
    (false, 15, 9),
    (true, 4, 1),
    (true, 14, 0),
    (true, 3, 0),
  ];
  for (int i = 0; i < steps.length; i++) {
    final (bool ctrl, int a, int b) = steps[i];
    if (ctrl) {
      d.onCtrl(0, a, 5, Side.values[b]);
    } else {
      final FmRecord record = FmRecord.fromIndex(a)!;
      d.onData(0, record, true, dataFrame(record, b), 20.0);
    }
    drainTo(d, 's${i + 1}', out);
  }
  d.onTxDone();
  drainTo(d, 's-end', out);
}

void main() {
  group('fm digi', () {
    test('via1 forwards record0 with hop and keys', () {
      final Digi d = Digi('N2CALL', FmBandwidth.narrow);
      expect(d.onRecord0(0, connect('N0CALL', 'N2CALL', '', 'N1CALL', 0), 20.0), isTrue);
      final List<DigiOutput> o = drain(d);
      expect(o.any((x) => x is DigiOutHost && x.event == hostPending), isTrue);
      final DigiTx t = txs(o)[0];
      expect(t, isA<DigiTxData>());
      final DigiTxData td = t as DigiTxData;
      expect(td.record, FmRecord.connect);
      expect(td.side, Side.target);
      final Record0 r = Record0.parse(td.frame)!;
      expect((r.hop, r.registered, r.source, r.target), (1, true, 'N0CALL', 'N1CALL'));
      expect(r.chainSnr, snrByte(20.0 + snrOffsetDb));
      expect(d.key(Side.source), callHash('N2CALL'.codeUnits));
      expect(d.key(Side.target), callHash('N1CALL'.codeUnits));
      expect(Digi('N2CALL', FmBandwidth.narrow).onRecord0(0, td.frame, 20.0), isFalse);
      final Digi v2 = Digi('N3CALL', FmBandwidth.narrow);
      expect(v2.onRecord0(0, connect('N0CALL', 'N2CALL', 'N3CALL', 'N1CALL', 0), 20.0), isFalse);
      expect(v2.onRecord0(0, connect('N0CALL', 'N2CALL', 'N3CALL', 'N1CALL', 1), 20.0), isTrue);
      expect((v2.key(Side.source), v2.key(Side.target)), (callHash('N3CALL'.codeUnits), callHash('N1CALL'.codeUnits)));
    });

    test('relays codes and forwards data', () {
      final Digi d = Digi('N2CALL', FmBandwidth.narrow);
      d.onRecord0(0, connect('N0CALL', 'N2CALL', '', 'N1CALL', 0), 20.0);
      drain(d);
      d.onCtrl(1, 23, 1, Side.target);
      expect(txs(drain(d)), <DigiTx>[const DigiTxCtrl(23, 28, Side.source)]);
      d.onCtrl(2, 14, 28, Side.source);
      List<DigiOutput> o = drain(d);
      expect(txs(o)[0], const DigiTxCtrl(14, 28, Side.target));
      DigiListen l = (o.last as DigiOutListen).listen;
      expect(l.records, <FmRecord>[FmRecord.start]);
      expect(l.dataKey, callHash('N1CALL'.codeUnits));
      final int len = FmBandwidth.narrow.level(FmRecord.start).frameBytes;
      final Uint8List f = buildData(FmRecord.start, len, 'hello'.codeUnits, false, 3, false,
          const Trailer(leadReport: 5, level: 4, chainSnr: 0));
      d.onData(3, FmRecord.start, true, f, 15.0);
      final DigiTxData t = txs(drain(d))[0] as DigiTxData;
      expect((t.record, t.side), (FmRecord.start, Side.source));
      final DataFrame p = parseData(FmRecord.start, t.frame, true)!;
      expect(p.data, 'hello'.codeUnits);
      expect(p.trailer, Trailer(leadReport: 28, level: 4, chainSnr: snrByte(15.0 + snrOffsetDb)));
      d.onData(4, FmRecord.start, false, const <int>[], 0.0);
      expect(txs(drain(d)), <DigiTx>[const DigiTxCtrl(22, 28, Side.source)]);
      d.onCtrl(5, 7, 28, Side.source);
      o = drain(d);
      l = (o.last as DigiOutListen).listen;
      expect(l.records, <FmRecord>[rec(2)]);
      d.onCtrl(6, 4, 28, Side.source);
      drain(d);
      d.onCtrl(7, 14, 28, Side.target);
      o = drain(d);
      l = (o.last as DigiOutListen).listen;
      expect(l.dataKey, callHash('N2CALL'.codeUnits));
      expect(l.records, <FmRecord>[rec(4)]);
      d.onCtrl(8, 3, 28, Side.target);
      expect(txs(drain(d)), <DigiTx>[const DigiTxCtrl(3, 28, Side.source)]);
      d.onTxDone();
      expect(d.active, isFalse);
      expect(drain(d).any((x) => x is DigiOutHost && x.event == hostCancelPending), isTrue);
    });

    test('times out', () {
      final Digi d = Digi('N2CALL', FmBandwidth.narrow);
      d.onRecord0(0, connect('N0CALL', 'N2CALL', '', 'N1CALL', 0), 20.0);
      d.poll(22 * second);
      expect(d.active, isTrue);
      d.poll(23 * second);
      expect(d.active, isFalse);
    });

    test('golden transcript', () {
      final XorShift r = XorShift(7);
      final Digi d = Digi('N2CALL', FmBandwidth.narrow);
      int now = 0;
      final StringBuffer out = StringBuffer();
      scriptedOpening(d, out);
      const List<int> codes = <int>[1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 20, 21, 22, 23, 24];
      for (int step = 0; step < 700; step++) {
        now += r.below(3 * second);
        final int ev = d.active ? r.below(100) : 0;
        if (ev <= 2) {
          final Uint8List f = record0(r);
          final double snr = r.below(40).toDouble();
          out.write('$step in record0 ${d.onRecord0(now, f, snr)}\n');
        } else if (ev == 3) {
          d.abort();
        } else if (ev <= 5) {
          now += 20 * second;
          d.poll(now);
        } else if (ev <= 20) {
          d.onTxDone();
        } else if (ev <= 25) {
          d.onSync(now);
        } else if (ev <= 60) {
          final int code = r.below(60) == 0 ? 3 : codes[r.below(18)];
          final int row = r.below(30), side = r.below(2);
          out.write('$step in ctrl $code row $row side $side\n');
          d.onCtrl(now, code, row, Side.values[side]);
        } else {
          final FmBandwidth bw = d.bandwidth;
          final int k = r.below(bw.numLevels + 2);
          final FmRecord record = k == 0 ? FmRecord.start : (k == 1 ? FmRecord.short : FmRecord.fromIndex(k - 1)!);
          final bool ok = r.below(6) != 0;
          Uint8List bytes = Uint8List(0);
          if (ok) {
            final int n = r.below(40);
            final List<int> data = <int>[for (int i = 0; i < n; i++) r.below(256)];
            final int lr = r.below(29), lv = r.below(12), cs = r.below(250);
            final Trailer t = Trailer(leadReport: lr, level: lv, chainSnr: cs);
            final int hint = r.below(8);
            final bool last = r.below(2) == 0;
            bytes = buildData(record, bw.level(record).frameBytes, data, false, hint, last, t);
          }
          final double snr = r.below(40).toDouble();
          out.write('$step in data ${record.index} ok $ok\n');
          d.onData(now, record, ok, bytes, snr);
        }
        drainTo(d, '$step', out);
      }
      final String got = out.toString();
      final String want = File('test/xara/vectors/golden/fm_digi.txt').readAsStringSync().replaceAll('\r', '');
      if (got != want) {
        File('${Directory.systemTemp.path}/fm_digi.txt.new').writeAsStringSync(got);
        final List<String> g = got.split('\n'), w = want.split('\n');
        int i = 0;
        while (i < g.length && i < w.length && g[i] == w[i]) {
          i++;
        }
        fail('fm_digi.txt differs at line ${i + 1}\n got: ${i < g.length ? g[i] : '<end>'}\n'
            'want: ${i < w.length ? w[i] : '<end>'}');
      }
    });
  });
}
