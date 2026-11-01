/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
Host-facing ARQ types (settings, events), the session output queue and
numeric helpers. `debug` getters render Rust's `{:?}` format so transcripts
can be compared with upstream golden files.
*/

import 'dart:collection';
import 'dart:typed_data';

import 'arq_link.dart';
import 'compression.dart';
import 'fm_level.dart';
import 'hf_level.dart';
import 'numeric.dart';
import 'xorshift.dart';

final double noSnr = toF32(1e35);

int rint(double x) => asI64(roundTiesEven(x));

double dec1(double x) => (x * 10.0).roundToDouble() / 10.0;

/// Rust `{:?}` of an f64.
String rustF64(double x) {
  if (x.isNaN) return 'NaN';
  if (x.isInfinite) return x > 0 ? 'inf' : '-inf';
  if (x == x.truncateToDouble() && x.abs() < 1e16) {
    final String s = x.toInt().toString();
    return x == 0 && x.isNegative ? '-0.0' : '$s.0';
  }
  return x.toString();
}

/// Rust `{:?}` of a string.
String rustStr(String s) {
  final StringBuffer b = StringBuffer('"');
  for (final int c in s.runes) {
    switch (c) {
      case 0x22:
        b.write(r'\"');
      case 0x5C:
        b.write(r'\\');
      case 0x0A:
        b.write(r'\n');
      case 0x0D:
        b.write(r'\r');
      case 0x09:
        b.write(r'\t');
      case 0x00:
        b.write(r'\0');
      default:
        if (c < 0x20 || c == 0x7F) {
          b.write('\\u{${c.toRadixString(16)}}');
        } else {
          b.writeCharCode(c);
        }
    }
  }
  b.write('"');
  return b.toString();
}

String _cap(String s) => s[0].toUpperCase() + s.substring(1);

/// Rust Debug name of an [FmBandwidth] ("Narrow"/"Wide").
String fmBwDebug(FmBandwidth bw) => _cap(bw.name);

String hfBwDebug(HfBandwidth bw) => 'Hz${bw.hz}';

sealed class LinkBw {
  const LinkBw();

  String get debug;
}

class LinkBwHf extends LinkBw {
  final HfBandwidth bw;

  const LinkBwHf(this.bw);

  @override
  String get debug => 'Hf(${hfBwDebug(bw)})';

  @override
  bool operator ==(Object other) => other is LinkBwHf && other.bw == bw;

  @override
  int get hashCode => bw.hashCode;
}

class LinkBwFm extends LinkBw {
  final FmBandwidth bw;

  const LinkBwFm(this.bw);

  @override
  String get debug => 'Fm(${fmBwDebug(bw)})';

  @override
  bool operator ==(Object other) => other is LinkBwFm && other.bw == bw;

  @override
  int get hashCode => bw.hashCode;
}

class HostSettings {
  final List<String> mycalls;
  bool chat;
  bool registered;
  int retries;
  Compression compression;

  HostSettings(String mycall, this.retries)
      : mycalls = <String>[mycall],
        chat = false,
        registered = false,
        compression = Compression.text;

  HostSettings._copy(HostSettings o)
      : mycalls = List<String>.of(o.mycalls),
        chat = o.chat,
        registered = o.registered,
        retries = o.retries,
        compression = o.compression;

  HostSettings copy() => HostSettings._copy(this);

  String get primaryCall => mycalls.isEmpty ? '' : mycalls.first;
}

const String qrtReceived = 'QRT Received';

sealed class HostEvent {
  const HostEvent();

  String get debug;

  @override
  String toString() => debug;
}

class _Unit extends HostEvent {
  final String name;

  const _Unit(this.name);

  @override
  String get debug => name;

  @override
  bool operator ==(Object other) => other is _Unit && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

const HostEvent hostDisconnected = _Unit('Disconnected');
const HostEvent hostUnableToConnect = _Unit('UnableToConnect');
const HostEvent hostTimedOut = _Unit('TimedOut');
const HostEvent hostPending = _Unit('Pending');
const HostEvent hostCancelPending = _Unit('CancelPending');
const HostEvent hostUnencrypted = _Unit('Unencrypted');

class HostConnected extends HostEvent {
  final String caller;
  final String answerer;
  final List<String> vias;
  final LinkBw bw;

  const HostConnected(this.caller, this.answerer, this.vias, this.bw);

  @override
  String get debug => 'Connected { caller: ${rustStr(caller)}, answerer: ${rustStr(answerer)}, '
      'vias: [${vias.map(rustStr).join(', ')}], bw: ${bw.debug} }';

  @override
  bool operator ==(Object other) =>
      other is HostConnected &&
      other.caller == caller &&
      other.answerer == answerer &&
      other.bw == bw &&
      other.vias.join('\u0000') == vias.join('\u0000') &&
      other.vias.length == vias.length;

  @override
  int get hashCode => Object.hash(caller, answerer, bw);
}

class HostRegistered extends HostEvent {
  final bool on;

  const HostRegistered(this.on);

  @override
  String get debug => 'Registered($on)';

  @override
  bool operator ==(Object other) => other is HostRegistered && other.on == on;

  @override
  int get hashCode => on.hashCode;
}

class HostBuffer extends HostEvent {
  final int n;

  const HostBuffer(this.n);

  @override
  String get debug => 'Buffer($n)';

  @override
  bool operator ==(Object other) => other is HostBuffer && other.n == n;

  @override
  int get hashCode => n;
}

class HostData extends HostEvent {
  final Uint8List data;

  const HostData(this.data);

  @override
  String get debug => 'Data($data)';

  @override
  bool operator ==(Object other) {
    if (other is! HostData || other.data.length != data.length) return false;
    for (int i = 0; i < data.length; i++) {
      if (other.data[i] != data[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(data);
}

class HostSn extends HostEvent {
  final double db;

  const HostSn(this.db);

  @override
  String get debug => 'Sn(${rustF64(db)})';

  @override
  bool operator ==(Object other) => other is HostSn && other.db == db;

  @override
  int get hashCode => db.hashCode;
}

class HostRxFrame extends HostEvent {
  final FmRecord record;

  const HostRxFrame(this.record);

  @override
  String get debug => 'RxFrame(${record.index})';

  @override
  bool operator ==(Object other) => other is HostRxFrame && other.record == record;

  @override
  int get hashCode => record.index;
}

class HostLog extends HostEvent {
  final String text;

  const HostLog(this.text);

  @override
  String get debug => 'Log(${rustStr(text)})';

  @override
  bool operator ==(Object other) => other is HostLog && other.text == text;

  @override
  int get hashCode => text.hashCode;
}

/// Session output: a transmission, a new receiver configuration, or a host event.
sealed class Output<T, L> {
  const Output();
}

class OutTx<T, L> extends Output<T, L> {
  final T tx;

  const OutTx(this.tx);
}

class OutListen<T, L> extends Output<T, L> {
  final L listen;

  const OutListen(this.listen);
}

class OutHost<T, L> extends Output<T, L> {
  final HostEvent event;

  const OutHost(this.event);
}

class Core<T, L> {
  final ListQueue<Output<T, L>> out = ListQueue<Output<T, L>>();
  final XorShift rng;
  bool transmitting = false;
  int txEnd = 0;

  Core(int seed) : rng = XorShift(seed);

  Output<T, L>? pop() => out.isEmpty ? null : out.removeFirst();

  void host(HostEvent e) => out.add(OutHost<T, L>(e));

  int? nextDeadline(ArqLink link) => transmitting ? null : link.nextDeadline();

  void deliver(ArqLink link, List<int> data, int skip) =>
      link.deliver(data, skip, (d) => out.add(OutHost<T, L>(HostData(d))));
}
