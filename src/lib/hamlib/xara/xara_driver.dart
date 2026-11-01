/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Host driver for the XARA FM station. HTCommander delivers radio audio in
squelch-gated runs at the host sample rate and transmits whole PCM buffers, while
the station expects a continuous 48 kHz timeline with sample-accurate transmit
timing. The driver keeps the station clock a fixed jitter delay behind the wall
clock, fills silent gaps with zeros, and renders each transmission ahead of time
as one PCM burst, preceded by an optional key-up pre-roll of silence.
*/

import 'dart:math' as math;
import 'dart:typed_data';

import 'fm_station.dart';
import 'resample.dart';
import 'station.dart';

const int stationRate = 48000;

class XaraDriver {
  final FmStation station;
  final int hostRate;

  /// Samples (48 kHz) the station runs behind the wall clock to absorb audio jitter.
  final int delay;

  /// Longest wait (48 kHz samples) for late audio during an active receive run.
  final int maxWait;

  /// A receive run counts as active this long (48 kHz samples) after the last audio.
  final int runGap;

  final int block;

  /// Silence (48 kHz samples) prepended to every transmission. The radio keys up
  /// on the arriving audio, so the first part of each burst is lost to key-up and
  /// the far end's squelch opening (whose noise burst would otherwise land on the
  /// frame); this pre-roll absorbs that ahead of the protocol's own lead-in.
  final int keyUp;
  final Resampler _in;
  final List<double> _rx = <double>[];
  int _rxHead = 0;
  int _lastRx = -(1 << 40);

  XaraDriver(
    this.station, {
    this.hostRate = 32000,
    this.delay = 12000,
    this.maxWait = 24000,
    this.runGap = 9600,
    this.block = 480,
    this.keyUp = 0,
  }) : _in = Resampler(hostRate.toDouble(), stationRate.toDouble());

  int get _queued => _rx.length - _rxHead;

  /// Adds received host-rate PCM that arrived at wall time [wall] (48 kHz samples).
  void pushRx(Int16List pcm, int wall) {
    _rx.addAll(_in.process(<double>[for (final int v in pcm) v / 32768.0]));
    _lastRx = wall;
    final int excess = _queued - 4 * stationRate;
    if (excess > 0) _rxHead += excess;
  }

  /// Advances the station to wall time [wall] (48 kHz samples since start) and
  /// returns any transmissions rendered as host-rate PCM.
  List<Int16List> tick(int wall) {
    final List<Int16List> bursts = <Int16List>[];
    final int target = wall - delay;
    while (station.now + block <= target) {
      final int avail = _queued;
      if (avail < block && wall - _lastRx < runGap && target - station.now < maxWait) break;
      final List<double> input = List<double>.filled(block, 0.0);
      final int n = math.min(avail, block);
      for (int i = 0; i < n; i++) {
        input[i] = _rx[_rxHead + i];
      }
      _rxHead += n;
      final List<double> output = List<double>.filled(block, 0.0);
      station.process(input, output);
      if (station.keyedFirst >= 0) bursts.add(_render(output));
    }
    if (_rxHead > 1 << 16) {
      _rx.removeRange(0, _rxHead);
      _rxHead = 0;
    }
    return bursts;
  }

  /// Runs the station ahead until the burst that started in [first] is done.
  Int16List _render(List<double> first) {
    final List<double> burst = List<double>.filled(keyUp, 0.0, growable: true);
    List<double> out = first;
    int from = station.keyedFirst;
    while (true) {
      final int to = station.keyedLast + 1;
      if (!station.transmitting) {
        if (station.keyedFirst >= 0) burst.addAll(out.sublist(from, to));
        break;
      }
      burst.addAll(out.sublist(from));
      out = List<double>.filled(block, 0.0);
      station.process(List<double>.filled(block, 0.0), out);
      from = 0;
    }
    final Resampler r = Resampler(stationRate.toDouble(), hostRate.toDouble());
    final List<double> y = <double>[...r.process(burst), ...r.flush()];
    final Int16List pcm = Int16List(y.length);
    for (int i = 0; i < y.length; i++) {
      pcm[i] = (y[i] * 32767.0).round().clamp(-32768, 32767);
    }
    return pcm;
  }

  Report? pop() => station.pop();
}
