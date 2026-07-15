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
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pasteboard/pasteboard.dart';

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
    final scheme = Theme.of(context).colorScheme;
    final a = analysis;
    if (a == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Waiting for a received DART packet…',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      );
    }

    final Color background = Theme.of(context).scaffoldBackgroundColor;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxW =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 500.0;
        // The constellation diagram is square and never larger than 500x500.
        final double diagramSide = math.min(maxW, 500.0);
        // If there is more than 400px to the right of the diagram, place the
        // metrics beside it instead of stacked above.
        final bool sideBySide = (maxW - diagramSide) > 400;

        final Widget diagram = SizedBox(
          width: diagramSide,
          height: diagramSide,
          child: a.isFsk || a.received.isEmpty
              ? _noConstellation(a, background, scheme)
              : GestureDetector(
                  onSecondaryTapDown: (details) => _showDiagramMenu(
                    context,
                    details.globalPosition,
                    a,
                    background,
                  ),
                  onLongPressStart: (details) => _showDiagramMenu(
                    context,
                    details.globalPosition,
                    a,
                    background,
                  ),
                  child: CustomPaint(
                    painter: _ConstellationPainter(
                      received: a.received,
                      reference: a.reference,
                      background: background,
                    ),
                  ),
                ),
        );

        if (sideBySide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              diagram,
              const SizedBox(width: 16),
              Expanded(child: _buildMetrics(a, scheme)),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildMetrics(a, scheme),
            const SizedBox(height: 12),
            Center(child: diagram),
          ],
        );
      },
    );
  }

  /// Shows a right-click / long-press context menu over the constellation
  /// diagram, offering to copy the rendered diagram to the clipboard.
  Future<void> _showDiagramMenu(
    BuildContext context,
    Offset position,
    DartReceptionAnalysis a,
    Color background,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      items: const [
        PopupMenuItem<String>(
          value: 'copy',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.copy, size: 18),
              SizedBox(width: 8),
              Text('Copy image'),
            ],
          ),
        ),
      ],
    );
    if (selected == 'copy') {
      await _copyDiagramImage(a, background);
    }
  }

  /// Renders the constellation diagram to a PNG and places it on the clipboard.
  Future<void> _copyDiagramImage(
    DartReceptionAnalysis a,
    Color background,
  ) async {
    const double px = 500;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    _ConstellationPainter(
      received: a.received,
      reference: a.reference,
      background: background,
    ).paint(canvas, const Size(px, px));
    final picture = recorder.endRecording();
    final image = await picture.toImage(px.toInt(), px.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    if (byteData == null) return;
    await Pasteboard.writeImage(byteData.buffer.asUint8List());
  }

  Widget _noConstellation(
    DartReceptionAnalysis a,
    Color background,
    ColorScheme scheme,
  ) {
    return Container(
      color: background,
      alignment: Alignment.center,
      child: Text(
        a.isFsk
            ? 'Mode F (FSK) — no constellation'
            : 'No constellation captured',
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      ),
    );
  }

  Widget _buildMetrics(DartReceptionAnalysis a, ColorScheme scheme) {
    final ago = DateTime.now().difference(a.time);
    final agoStr = ago.inSeconds < 1
        ? 'just now'
        : ago.inSeconds < 60
            ? '${ago.inSeconds}s ago'
            : '${ago.inMinutes}m ago';

    final chips = <Widget>[
      _chip(scheme, 'Mode', '${a.modeIndex} — ${a.modeDescription}'),
      _chip(scheme, 'SNR', '${a.snrDb.toStringAsFixed(1)} dB', emphasize: true),
      _chip(scheme, 'EVM', '${a.evmPercent.toStringAsFixed(1)} %'),
      _chip(scheme, 'Preamble corr', a.preambleCorrelation.toStringAsFixed(2)),
      _chip(scheme, 'Channel gain', '${a.channelGainDb.toStringAsFixed(1)} dB'),
      if (a.phaseDriftDeg != null)
        _chip(
          scheme,
          'Phase drift',
          '${a.phaseDriftDeg!.toStringAsFixed(1)}°/sym',
        ),
      _chip(scheme, 'LDPC fixes', '${a.ldpcCorrections}'),
      _chip(scheme, 'Payload', '${a.payloadLength} B'),
      _chip(scheme, 'Duration', '${a.durationMs.toStringAsFixed(0)} ms'),
      _chip(
        scheme,
        'CRC',
        a.crcOk ? 'OK' : 'FAIL',
        color: a.crcOk ? Colors.green.shade700 : Colors.red.shade700,
      ),
      _chip(scheme, 'Received', agoStr),
    ];

    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }

  Widget _chip(
    ColorScheme scheme,
    String label,
    String value, {
    bool emphasize = false,
    Color? color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      child: RichText(
        text: TextSpan(
          style: TextStyle(fontSize: 12, color: scheme.onSurface),
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                fontWeight: emphasize ? FontWeight.bold : FontWeight.w500,
                color: color ?? scheme.onSurface,
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
  final Color background;

  _ConstellationPainter({
    required this.received,
    required this.reference,
    required this.background,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Clip everything to the diagram's rectangle so outlier symbols (poor SNR)
    // and edge markers never paint beyond its bounds.
    canvas.clipRect(Offset.zero & size);

    final bg = Paint()..color = background;
    canvas.drawRect(Offset.zero & size, bg);

    // Line/marker color that contrasts with the background so the grid and
    // axes remain visible in both light and dark themes.
    final Color foreground =
        background.computeLuminance() > 0.5 ? Colors.black : Colors.white;

    final cx = size.width / 2;
    final cy = size.height / 2;

    // Scale so the constellation (unit-power, points near |1|) fits with margin.
    // Use a fixed scale of ~1.6 so most energy stays on-canvas but outliers
    // (poor SNR) still show their spread toward the edges.
    final double scale = math.min(size.width, size.height) / 2 / 1.7;

    Offset toScreen(Offset iq) => Offset(cx + iq.dx * scale, cy - iq.dy * scale);

    // Grid rings at |r| = 0.5, 1.0, 1.5.
    final gridPaint = Paint()
      ..color = foreground.withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final r in [0.5, 1.0, 1.5]) {
      canvas.drawCircle(Offset(cx, cy), r * scale, gridPaint);
    }

    // Axes.
    final axisPaint = Paint()
      ..color = foreground.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), axisPaint);
    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), axisPaint);

    // Received symbols (red).
    final rxPaint = Paint()
      ..color = const Color(0xFFD32F2F).withValues(alpha: 0.75)
      ..style = PaintingStyle.fill;
    for (final p in received) {
      canvas.drawCircle(toScreen(p), 1.6, rxPaint);
    }

    // Ideal reference points (blue) drawn on top as hollow markers.
    final refFill = Paint()
      ..color = const Color(0xFF1565C0)
      ..style = PaintingStyle.fill;
    final refRing = Paint()
      ..color = foreground.withValues(alpha: 0.6)
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
      old.received != received ||
      old.reference != reference ||
      old.background != background;
}
