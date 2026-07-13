/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

DART reception-quality analysis widgets for the Audio tab. Renders the last
received DART packet's signal metrics (SNR, EVM, correlation, gain, phase drift,
LDPC corrections) and an I/Q constellation scatter diagram (ideal points in
blue, received symbols in red) — the same picture the DART test tool produces,
so the user can watch reception quality change as they tweak radio settings.
*/

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Immutable view model for one received DART packet's reception analysis.
///
/// Built from the JSON-safe map published by the software modem on device 1
/// under 'DartAnalysis' (see SoftwareModem._onDartAnalysis).
class DartReceptionAnalysis {
  final int modeIndex;
  final String modeDescription;
  final bool isFsk;
  final bool crcOk;
  final double evmPercent;
  final double snrDb;
  final double preambleCorrelation;
  final double channelGainDb;
  final double? phaseDriftDeg;
  final int ldpcCorrections;
  final int payloadLength;
  final double durationMs;

  /// Received (equalized) constellation symbols. Empty for Mode F (FSK).
  final List<Offset> received;

  /// Ideal constellation points for the mode. Empty for Mode F (FSK).
  final List<Offset> reference;

  final DateTime time;

  const DartReceptionAnalysis({
    required this.modeIndex,
    required this.modeDescription,
    required this.isFsk,
    required this.crcOk,
    required this.evmPercent,
    required this.snrDb,
    required this.preambleCorrelation,
    required this.channelGainDb,
    required this.phaseDriftDeg,
    required this.ldpcCorrections,
    required this.payloadLength,
    required this.durationMs,
    required this.received,
    required this.reference,
    required this.time,
  });

  /// Parses the broker map, or returns null if it is malformed.
  static DartReceptionAnalysis? tryParse(Object? data) {
    if (data is! Map) return null;
    double d(Object? v, [double def = 0]) =>
        (v is num) ? v.toDouble() : def;
    int i(Object? v, [int def = 0]) => (v is num) ? v.toInt() : def;

    List<Offset> points(Object? iv, Object? qv) {
      if (iv is! List || qv is! List) return const <Offset>[];
      final n = math.min(iv.length, qv.length);
      final out = <Offset>[];
      for (int k = 0; k < n; k++) {
        final a = iv[k];
        final b = qv[k];
        if (a is num && b is num) {
          out.add(Offset(a.toDouble(), b.toDouble()));
        }
      }
      return out;
    }

    final drift = data['phaseDrift'];
    return DartReceptionAnalysis(
      modeIndex: i(data['mode']),
      modeDescription: data['modeDesc']?.toString() ?? '',
      isFsk: data['isFsk'] == true,
      crcOk: data['crcOk'] == true,
      evmPercent: d(data['evm']),
      snrDb: d(data['snr']),
      preambleCorrelation: d(data['corr']),
      channelGainDb: d(data['gain']),
      phaseDriftDeg: drift is num ? drift.toDouble() : null,
      ldpcCorrections: i(data['ldpc']),
      payloadLength: i(data['payloadLen']),
      durationMs: d(data['durationMs']),
      received: points(data['rxI'], data['rxQ']),
      reference: points(data['refI'], data['refQ']),
      time: DateTime.tryParse(data['time']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

/// Renders the DART reception-quality section: a metrics grid plus the I/Q
/// constellation diagram. Shows a placeholder when no packet has arrived yet.
class DartAnalysisSection extends StatelessWidget {
  final DartReceptionAnalysis? analysis;

  const DartAnalysisSection({super.key, required this.analysis});

  @override
  Widget build(BuildContext context) {
    final a = analysis;
    if (a == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          border: Border.all(color: Colors.grey.shade400),
        ),
        child: const Text(
          'Waiting for a received DART packet…',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade400),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildMetrics(a),
          const SizedBox(height: 12),
          Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final side = math.min(constraints.maxWidth, 280.0);
                  return SizedBox(
                    width: side,
                    height: side,
                    child: a.isFsk || a.received.isEmpty
                        ? _noConstellation(a)
                        : CustomPaint(
                            painter: _ConstellationPainter(
                              received: a.received,
                              reference: a.reference,
                            ),
                          ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _noConstellation(DartReceptionAnalysis a) {
    return Container(
      color: const Color(0xFF0A0A1A),
      alignment: Alignment.center,
      child: Text(
        a.isFsk
            ? 'Mode F (FSK) — no constellation'
            : 'No constellation captured',
        style: const TextStyle(fontSize: 12, color: Colors.white70),
      ),
    );
  }

  Widget _buildMetrics(DartReceptionAnalysis a) {
    final ago = DateTime.now().difference(a.time);
    final agoStr = ago.inSeconds < 1
        ? 'just now'
        : ago.inSeconds < 60
            ? '${ago.inSeconds}s ago'
            : '${ago.inMinutes}m ago';

    final chips = <Widget>[
      _chip('Mode', '${a.modeIndex} — ${a.modeDescription}'),
      _chip('SNR', '${a.snrDb.toStringAsFixed(1)} dB', emphasize: true),
      _chip('EVM', '${a.evmPercent.toStringAsFixed(1)} %'),
      _chip('Preamble corr', a.preambleCorrelation.toStringAsFixed(2)),
      _chip('Channel gain', '${a.channelGainDb.toStringAsFixed(1)} dB'),
      if (a.phaseDriftDeg != null)
        _chip('Phase drift', '${a.phaseDriftDeg!.toStringAsFixed(1)}°/sym'),
      _chip('LDPC fixes', '${a.ldpcCorrections}'),
      _chip('Payload', '${a.payloadLength} B'),
      _chip('Duration', '${a.durationMs.toStringAsFixed(0)} ms'),
      _chip(
        'CRC',
        a.crcOk ? 'OK' : 'FAIL',
        color: a.crcOk ? Colors.green.shade700 : Colors.red.shade700,
      ),
      _chip('Received', agoStr),
    ];

    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }

  Widget _chip(
    String label,
    String value, {
    bool emphasize = false,
    Color? color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(4),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 12, color: Colors.black87),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(color: Colors.black54),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                fontWeight: emphasize ? FontWeight.bold : FontWeight.w500,
                color: color ?? Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints an I/Q constellation scatter: ideal points (blue) and received
/// symbols (red), with axes and a reference grid, on a dark background.
class _ConstellationPainter extends CustomPainter {
  final List<Offset> received;
  final List<Offset> reference;

  _ConstellationPainter({required this.received, required this.reference});

  @override
  void paint(Canvas canvas, Size size) {
    // Clip everything to the diagram's rectangle so outlier symbols (poor SNR)
    // and edge markers never paint beyond its bounds.
    canvas.clipRect(Offset.zero & size);

    final bg = Paint()..color = const Color(0xFF0A0A1A);
    canvas.drawRect(Offset.zero & size, bg);

    final cx = size.width / 2;
    final cy = size.height / 2;

    // Scale so the constellation (unit-power, points near |1|) fits with margin.
    // Use a fixed scale of ~1.6 so most energy stays on-canvas but outliers
    // (poor SNR) still show their spread toward the edges.
    final double scale = math.min(size.width, size.height) / 2 / 1.7;

    Offset toScreen(Offset iq) => Offset(cx + iq.dx * scale, cy - iq.dy * scale);

    // Grid rings at |r| = 0.5, 1.0, 1.5.
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final r in [0.5, 1.0, 1.5]) {
      canvas.drawCircle(Offset(cx, cy), r * scale, gridPaint);
    }

    // Axes.
    final axisPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.20)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), axisPaint);
    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), axisPaint);

    // Received symbols (red).
    final rxPaint = Paint()
      ..color = const Color(0xFFFF4D4D).withValues(alpha: 0.75)
      ..style = PaintingStyle.fill;
    for (final p in received) {
      canvas.drawCircle(toScreen(p), 1.6, rxPaint);
    }

    // Ideal reference points (blue) drawn on top as hollow markers.
    final refFill = Paint()
      ..color = const Color(0xFF5B9BFF)
      ..style = PaintingStyle.fill;
    final refRing = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final p in reference) {
      final s = toScreen(p);
      canvas.drawCircle(s, 3.5, refFill);
      canvas.drawCircle(s, 3.5, refRing);
    }
  }

  @override
  bool shouldRepaint(_ConstellationPainter old) =>
      old.received != received || old.reference != reference;
}
