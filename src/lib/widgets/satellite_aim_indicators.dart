/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Compass dial showing the azimuth (direction) to aim an antenna.
/// 0 degrees = North, increasing clockwise.
class CompassIndicator extends StatelessWidget {
  final double azimuthDeg;
  final double size;

  const CompassIndicator({
    super.key,
    required this.azimuthDeg,
    this.size = 76,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CompassPainter(
          azimuthDeg: azimuthDeg,
          needleColor: scheme.primary,
          tickColor: scheme.onSurfaceVariant,
          dialColor: scheme.outlineVariant,
          labelColor: scheme.onSurface,
        ),
      ),
    );
  }
}

class _CompassPainter extends CustomPainter {
  final double azimuthDeg;
  final Color needleColor;
  final Color tickColor;
  final Color dialColor;
  final Color labelColor;

  _CompassPainter({
    required this.azimuthDeg,
    required this.needleColor,
    required this.tickColor,
    required this.dialColor,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 1;

    final dialPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = dialColor;
    canvas.drawCircle(center, radius, dialPaint);

    // Cardinal ticks.
    final tickPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = tickColor;
    for (var i = 0; i < 360; i += 30) {
      final major = i % 90 == 0;
      final a = (i - 90) * math.pi / 180; // 0 deg at top (North).
      final outer = center + Offset(math.cos(a), math.sin(a)) * radius;
      final inner = center +
          Offset(math.cos(a), math.sin(a)) * (radius - (major ? 6 : 3));
      canvas.drawLine(inner, outer, tickPaint);
    }

    // Cardinal letters.
    const letters = ['N', 'E', 'S', 'W'];
    for (var i = 0; i < 4; i++) {
      final a = (i * 90 - 90) * math.pi / 180;
      final p = center + Offset(math.cos(a), math.sin(a)) * (radius - 14);
      final tp = TextPainter(
        text: TextSpan(
          text: letters[i],
          style: TextStyle(
            color: i == 0 ? needleColor : labelColor.withValues(alpha: 0.7),
            fontSize: 9,
            fontWeight: i == 0 ? FontWeight.bold : FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    }

    // Needle pointing at the azimuth.
    final a = (azimuthDeg - 90) * math.pi / 180;
    final dir = Offset(math.cos(a), math.sin(a));
    final tip = center + dir * (radius - 8);
    final tail = center - dir * (radius * 0.45);
    final perp = Offset(-dir.dy, dir.dx);

    final needlePaint = Paint()..color = needleColor;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo((center + perp * 4).dx, (center + perp * 4).dy)
      ..lineTo(tail.dx, tail.dy)
      ..lineTo((center - perp * 4).dx, (center - perp * 4).dy)
      ..close();
    canvas.drawPath(path, needlePaint);

    // Center hub.
    canvas.drawCircle(
      center,
      2.5,
      Paint()..color = labelColor.withValues(alpha: 0.8),
    );
  }

  @override
  bool shouldRepaint(covariant _CompassPainter old) =>
      old.azimuthDeg != azimuthDeg ||
      old.needleColor != needleColor ||
      old.tickColor != tickColor ||
      old.dialColor != dialColor ||
      old.labelColor != labelColor;
}

/// Elevation gauge showing the up-angle (0 = horizon, 90 = straight up).
/// Dimmed when the satellite is below the horizon (negative elevation).
class ElevationIndicator extends StatelessWidget {
  final double elevationDeg;
  final double size;

  const ElevationIndicator({
    super.key,
    required this.elevationDeg,
    this.size = 76,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final belowHorizon = elevationDeg < 0;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ElevationPainter(
          elevationDeg: elevationDeg,
          needleColor: belowHorizon
              ? scheme.onSurfaceVariant.withValues(alpha: 0.5)
              : scheme.primary,
          arcColor: scheme.outlineVariant,
          tickColor: scheme.onSurfaceVariant,
          labelColor: scheme.onSurface,
        ),
      ),
    );
  }
}

class _ElevationPainter extends CustomPainter {
  final double elevationDeg;
  final Color needleColor;
  final Color arcColor;
  final Color tickColor;
  final Color labelColor;

  _ElevationPainter({
    required this.elevationDeg,
    required this.needleColor,
    required this.arcColor,
    required this.tickColor,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Pivot at bottom-left; quarter arc sweeping up to the right.
    final pivot = Offset(size.width * 0.16, size.height * 0.86);
    final radius = math.min(size.width, size.height) * 0.72;

    // Quarter-circle arc from 0 (horizon, right) up to 90 (zenith, up).
    final rect = Rect.fromCircle(center: pivot, radius: radius);
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = arcColor;
    canvas.drawArc(rect, -math.pi / 2, math.pi / 2, false, arcPaint);

    // Horizon baseline.
    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = tickColor;
    canvas.drawLine(pivot, pivot + Offset(radius, 0), basePaint);

    // Tick marks every 30 degrees with 0/90 labels.
    for (final deg in [0, 30, 60, 90]) {
      final a = -deg * math.pi / 180;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        pivot + dir * (radius - 5),
        pivot + dir * radius,
        basePaint,
      );
    }
    for (final deg in [0, 90]) {
      final a = -deg * math.pi / 180;
      final dir = Offset(math.cos(a), math.sin(a));
      final p = pivot + dir * (radius + 8);
      final tp = TextPainter(
        text: TextSpan(
          text: '$deg\u00b0',
          style: TextStyle(
            color: labelColor.withValues(alpha: 0.7),
            fontSize: 8,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    }

    // Needle at the elevation angle (clamped to the gauge range).
    final clamped = elevationDeg.clamp(0.0, 90.0);
    final a = -clamped * math.pi / 180;
    final dir = Offset(math.cos(a), math.sin(a));
    final needlePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..color = needleColor;
    canvas.drawLine(pivot, pivot + dir * (radius - 4), needlePaint);

    // Pivot hub.
    canvas.drawCircle(pivot, 2.8, Paint()..color = needleColor);
  }

  @override
  bool shouldRepaint(covariant _ElevationPainter old) =>
      old.elevationDeg != elevationDeg ||
      old.needleColor != needleColor ||
      old.arcColor != arcColor ||
      old.tickColor != tickColor ||
      old.labelColor != labelColor;
}
