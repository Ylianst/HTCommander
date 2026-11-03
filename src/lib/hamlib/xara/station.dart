/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/xara-modem/xara), crates/xara/src/station/mod.rs
and crates/xara/src/station/scheduler.rs. Copyright (c) the XARA authors, MIT License.

Shared station pieces: options, host-facing reports and the sample-timed
transmit scheduler that keys PTT around queued bursts.
*/

import 'dart:typed_data';

import 'arq_host.dart';
import 'arq_time.dart';
import 'kiss_command.dart';

const double defaultDriveDb = -5.0;
const int txRingBytes = 600000;
const int minGap = 4000;

double secsOf(int t) => t / second;

class StationOptions {
  double driveDb;
  int txLatency;
  int rxLag;
  int pttTail;

  StationOptions({this.driveDb = defaultDriveDb, this.txLatency = 0, this.rxLag = 0, this.pttTail = 0});
}

sealed class Report {
  const Report();
}

class ReportHost extends Report {
  final HostEvent event;

  const ReportHost(this.event);

  @override
  bool operator ==(Object other) => other is ReportHost && other.event == event;

  @override
  int get hashCode => event.hashCode;

  @override
  String toString() => 'Host(${event.debug})';
}

class ReportPtt extends Report {
  final bool on;

  const ReportPtt(this.on);

  @override
  bool operator ==(Object other) => other is ReportPtt && other.on == on;

  @override
  int get hashCode => on.hashCode;

  @override
  String toString() => 'Ptt($on)';
}

class ReportBitrate extends Report {
  final int level;
  final int bps;
  final bool tx;

  const ReportBitrate(this.level, this.bps, this.tx);

  @override
  bool operator ==(Object other) =>
      other is ReportBitrate && other.level == level && other.bps == bps && other.tx == tx;

  @override
  int get hashCode => Object.hash(level, bps, tx);

  @override
  String toString() => 'Bitrate { level: $level, bps: $bps, tx: $tx }';
}

class ReportBusy extends Report {
  final bool on;

  const ReportBusy(this.on);

  @override
  bool operator ==(Object other) => other is ReportBusy && other.on == on;

  @override
  int get hashCode => on.hashCode;

  @override
  String toString() => 'Busy($on)';
}

class ReportUnencryptedLink extends Report {
  const ReportUnencryptedLink();

  @override
  bool operator ==(Object other) => other is ReportUnencryptedLink;

  @override
  int get hashCode => 1;

  @override
  String toString() => 'UnencryptedLink';
}

class ReportTrace extends Report {
  final String text;

  const ReportTrace(this.text);

  @override
  bool operator ==(Object other) => other is ReportTrace && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'Trace(${rustStr(text)})';
}

class ReportLine extends Report {
  final String text;

  const ReportLine(this.text);

  @override
  bool operator ==(Object other) => other is ReportLine && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'Line(${rustStr(text)})';
}

class ReportKiss extends Report {
  final KissCommand cmd;
  final Uint8List data;

  const ReportKiss(this.cmd, this.data);

  @override
  bool operator ==(Object other) {
    if (other is! ReportKiss || other.cmd != cmd || other.data.length != data.length) return false;
    for (int i = 0; i < data.length; i++) {
      if (other.data[i] != data[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(cmd, Object.hashAll(data));

  @override
  String toString() => 'Kiss(${cmd.name}, $data)';
}

/// Link status for the user interface.
class StationLink {
  final String state;
  final int level;
  final String peer;
  final String bw;
  final (double, double) passband;
  final int attempts;
  final double? afcHz;

  const StationLink(this.state, this.level, this.peer, this.bw, this.passband, this.attempts, this.afcHz);
}

enum BurstKind { session, digi, announce, fragment, lastFragment }

class _Burst {
  final List<double> samples;
  final int tail;
  int pos = 0;
  final int earliest;
  final List<Report> keyed;
  final BurstKind kind;

  _Burst(this.samples, this.tail, this.earliest, this.keyed, this.kind);
}

sealed class TxNext {
  const TxNext();
}

class TxIdle extends TxNext {
  const TxIdle();
}

class TxSample extends TxNext {
  final double sample;

  const TxSample(this.sample);
}

class TxLast extends TxNext {
  final double sample;
  final BurstKind kind;
  final int start;
  final int end;

  const TxLast(this.sample, this.kind, this.start, this.end);
}

class _Unkey {
  final int at;
  int ready;

  _Unkey(this.at, this.ready);
}

class TxScheduler {
  final List<_Burst> _bursts = <_Burst>[];
  int _holdUntil = 0;
  bool _ptt = false;
  int _latency;
  int _lag;
  _Unkey? _unkey;
  List<double>? _tune;
  int _tunePos = 0;

  /// While true no new burst starts; one already playing runs to its end. Set
  /// by the host while the radio is receiving, so we never key over a signal.
  bool blocked = false;

  TxScheduler(this._latency, this._lag);

  int get latency => _latency;

  void setLatency(int latency, int lag) {
    _latency = latency;
    _lag = lag;
  }

  bool get ptt => _ptt;

  bool get isEmpty => _bursts.isEmpty && _unkey == null;

  bool get hasBursts => _bursts.isNotEmpty;

  bool get tuning => _tune != null;

  void tune(List<double> tone) {
    _tune = tone;
    _tunePos = 0;
  }

  void retune(List<double> Function() tone) {
    if (_tune != null) _tune = tone();
  }

  void stopTune() => _tune = null;

  void untune(int now, List<Report> reports) {
    if (_tune != null) {
      _tune = null;
      unkeyIfEmpty(now, reports);
    }
  }

  void hold(int until) {
    final int h = until - _latency;
    if (h > _holdUntil) _holdUntil = h;
  }

  int afterHold(int now) => now > _holdUntil ? now : _holdUntil;

  int nextStart(int now) => _bursts.isNotEmpty || (_ptt && _unkey == null) ? now : afterHold(now);

  void push(List<double> samples, int tail, int earliest, List<Report> keyed, BurstKind kind) {
    _bursts.add(_Burst(samples, tail, earliest, keyed, kind));
  }

  void key(List<Report> reports) {
    _unkey = null;
    if (!_ptt) {
      _ptt = true;
      reports.add(const ReportPtt(true));
    }
  }

  void unkeyIfEmpty(int now, List<Report> reports) {
    if (_bursts.isEmpty && _ptt) _unkeyAt(now, reports, reports.length);
  }

  void _unkeyAt(int end, List<Report> reports, int mark) {
    final int h = _latency - _lag;
    if (h <= 0) {
      _ptt = false;
      reports.insert(mark, const ReportPtt(false));
    } else {
      _unkey = _Unkey(end + h, mark);
    }
  }

  Report? pop(List<Report> reports) {
    final _Unkey? u = _unkey;
    if (u != null) {
      if (u.ready == 0) return null;
      u.ready--;
    }
    return reports.isEmpty ? null : reports.removeAt(0);
  }

  TxNext next(int t, List<Report> reports) {
    final _Burst? f = _bursts.isEmpty ? null : _bursts.first;
    if (f == null || !(f.pos > 0 || (t >= f.earliest && !blocked))) {
      final _Unkey? u = _unkey;
      if (u != null && t >= u.at) {
        _unkey = null;
        _ptt = false;
        reports.insert(u.ready, const ReportPtt(false));
      }
      final List<double>? tone = _tune;
      if (tone == null) return const TxIdle();
      final double v = tone[_tunePos];
      _tunePos = (_tunePos + 1) % tone.length;
      key(reports);
      return TxSample(v);
    }
    key(reports);
    final _Burst b = f;
    if (b.pos == 0) {
      reports.addAll(b.keyed);
      b.keyed.clear();
    }
    final double sample = b.pos < b.samples.length ? b.samples[b.pos] : 0.0;
    final int len = b.samples.length + b.tail;
    b.pos++;
    if (b.pos < len) return TxSample(sample);
    _bursts.removeAt(0);
    final int end = t + 1;
    return TxLast(sample, b.kind, end - len, end);
  }

  void release(int end, List<Report> reports, int mark) {
    if (_bursts.isEmpty || _bursts.first.earliest > end) _unkeyAt(end, reports, mark);
  }
}
