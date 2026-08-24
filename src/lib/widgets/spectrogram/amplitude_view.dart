/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

//
// amplitude_view.dart - A scrolling amplitude (level) graph, an alternative to
// the spectrograph for setting the radio's volume. It consumes the same PCM
// stream and advances one column per [stepSize] samples, matching the
// spectrogram's horizontal scroll rate so the two can be toggled interchangeably.
//

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Buffers PCM and, on a timer, reduces each [stepSize]-sample hop to one
/// peak/RMS amplitude column, keeping the most recent [columnCount] columns.
class AmplitudeController extends ChangeNotifier {
  AmplitudeController({
    int sampleRate = 32000,
    int fftSize = 512,
    int? stepSize,
    this.updateInterval = const Duration(milliseconds: 50),
    int columnCount = 480,
  })  : // Matches SpectrogramGenerator's default step so both graphs scroll at
        // the same rate for a given source.
        _stepSize = (stepSize ?? (fftSize ~/ 20)).clamp(1, fftSize),
        _columnCount = columnCount.clamp(16, 8192) {
    _sampleRate = sampleRate;
    _startTimer();
  }

  late int _sampleRate;
  final int _stepSize;
  final Duration updateInterval;
  int _columnCount;
  Timer? _timer;
  bool _disposed = false;

  // Rolling amplitude columns (0..1), oldest first, newest last.
  final List<double> _peaks = <double>[];
  final List<double> _rms = <double>[];

  Float64List _buf = Float64List(0);
  int _bufLen = 0;

  int get sampleRate => _sampleRate;
  List<double> get peaks => _peaks;
  List<double> get rms => _rms;

  int get columnCount => _columnCount;
  set columnCount(int value) {
    final int c = value.clamp(16, 8192);
    if (c == _columnCount) return;
    _columnCount = c;
    _trim();
  }

  /// Reconfigure for a new sample rate (the time scale changes, so history is
  /// discarded). The step size is unchanged so the pixel scroll rate tracks the
  /// spectrogram for the same source.
  void reconfigure({int? sampleRate}) {
    if (sampleRate != null && sampleRate != _sampleRate) {
      _sampleRate = sampleRate;
      clear();
    }
  }

  void feedPcm16(Uint8List bytes, [int offset = 0, int? length]) {
    if (_disposed) return;
    final int len = length ?? (bytes.lengthInBytes - offset);
    final int n = len ~/ 2;
    if (n <= 0) return;
    _ensureCapacity(_bufLen + n);
    final ByteData bd = ByteData.sublistView(bytes, offset, offset + n * 2);
    for (int i = 0; i < n; i++) {
      _buf[_bufLen++] = bd.getInt16(i * 2, Endian.little) / 32768.0;
    }
  }

  void _ensureCapacity(int needed) {
    if (_buf.length >= needed) return;
    int cap = _buf.isEmpty ? 8192 : _buf.length;
    while (cap < needed) {
      cap *= 2;
    }
    final Float64List grown = Float64List(cap);
    grown.setRange(0, _bufLen, _buf);
    _buf = grown;
  }

  void _startTimer() {
    _timer = Timer.periodic(updateInterval, (_) => _tick());
  }

  void _tick() {
    if (_disposed || _bufLen < _stepSize) return;
    int consumed = 0;
    while (_bufLen - consumed >= _stepSize) {
      double peak = 0, sumSq = 0;
      for (int i = 0; i < _stepSize; i++) {
        final double v = _buf[consumed + i];
        final double a = v.abs();
        if (a > peak) peak = a;
        sumSq += v * v;
      }
      _peaks.add(peak);
      _rms.add(math.sqrt(sumSq / _stepSize));
      consumed += _stepSize;
    }
    final int remaining = _bufLen - consumed;
    if (remaining > 0) _buf.setRange(0, remaining, _buf, consumed);
    _bufLen = remaining;
    _trim();
    notifyListeners();
  }

  void _trim() {
    if (_peaks.length > _columnCount) {
      _peaks.removeRange(0, _peaks.length - _columnCount);
    }
    if (_rms.length > _columnCount) {
      _rms.removeRange(0, _rms.length - _columnCount);
    }
  }

  void clear() {
    _peaks.clear();
    _rms.clear();
    _bufLen = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}

/// Paints an [AmplitudeController]'s rolling level history: a centre-mirrored
/// peak envelope (with a brighter RMS core) that turns amber then red as the
/// level approaches clipping, so the user can set the radio volume to sit high
/// but out of the red.
class AmplitudeView extends StatelessWidget {
  const AmplitudeView({
    super.key,
    required this.controller,
    this.backgroundColor = Colors.black,
  });

  final AmplitudeController controller;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth.isFinite && constraints.maxWidth > 0) {
          final int targetWidth = constraints.maxWidth.round();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            controller.columnCount = targetWidth;
          });
        }
        return CustomPaint(
          painter: _AmplitudePainter(controller, backgroundColor),
          size: Size.infinite,
        );
      },
    );
  }
}

class _AmplitudePainter extends CustomPainter {
  _AmplitudePainter(this.controller, this.backgroundColor)
      : super(repaint: controller);

  final AmplitudeController controller;
  final Color backgroundColor;

  // Level thresholds (fraction of full scale) for the colour zones.
  static const double _amber = 0.7;
  static const double _red = 0.95;

  @override
  void paint(Canvas canvas, Size size) {
    if (backgroundColor.a > 0) {
      canvas.drawRect(Offset.zero & size, Paint()..color = backgroundColor);
    }
    final double mid = size.height / 2;

    // Reference gridlines: centre plus the amber and near-clip levels.
    final Paint grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), grid);
    for (final double lvl in <double>[_amber, _red]) {
      canvas.drawLine(Offset(0, mid - mid * lvl),
          Offset(size.width, mid - mid * lvl), grid);
      canvas.drawLine(Offset(0, mid + mid * lvl),
          Offset(size.width, mid + mid * lvl), grid);
    }

    final List<double> peaks = controller.peaks;
    final List<double> rms = controller.rms;
    final int len = peaks.length;
    if (len == 0) return;

    final Paint peakPaint = Paint()..strokeWidth = 1;
    final Paint rmsPaint = Paint()..strokeWidth = 1;
    // Right-align the newest column so the graph scrolls left as it fills.
    final double x0 = size.width - len;
    for (int i = 0; i < len; i++) {
      final double x = x0 + i;
      if (x < 0) continue;
      final double p = peaks[i].clamp(0.0, 1.0);
      final double r = (i < rms.length ? rms[i] : 0.0).clamp(0.0, 1.0);
      peakPaint.color = _colorFor(p);
      canvas.drawLine(Offset(x, mid - mid * p), Offset(x, mid + mid * p), peakPaint);
      rmsPaint.color = _colorFor(p).withValues(alpha: 0.55);
      canvas.drawLine(Offset(x, mid - mid * r), Offset(x, mid + mid * r), rmsPaint);
    }
  }

  Color _colorFor(double level) {
    if (level >= _red) return const Color(0xFFFF5252); // clipping
    if (level >= _amber) return const Color(0xFFFFC107); // hot
    return const Color(0xFF4CAF50); // good
  }

  @override
  bool shouldRepaint(covariant _AmplitudePainter old) =>
      old.controller != controller || old.backgroundColor != backgroundColor;
}
