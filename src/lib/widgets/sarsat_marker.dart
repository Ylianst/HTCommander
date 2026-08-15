/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A SARSAT 406 beacon marker: a circular badge sitting on a downward spike
/// whose tip marks the exact position. A real distress beacon is a red "SOS"
/// badge; a self-test beacon is an orange "TEST" badge. Shared by the map tab
/// and the Comms "Show Location" dialog so both render the same marker.
class SarsatMarker extends StatelessWidget {
  const SarsatMarker({
    super.key,
    this.size = 30,
    this.spikeHeight,
    this.isTest = false,
  });

  final double size;

  /// Height of the spike below the badge; defaults to 55% of [size].
  final double? spikeHeight;

  /// True for a self-test beacon (orange "TEST"), false for a real distress
  /// beacon (red "SOS").
  final bool isTest;

  double get _spike => spikeHeight ?? size * 0.55;

  /// Total marker height (badge + spike), for sizing the enclosing Marker.
  double get totalHeight => size + _spike;

  @override
  Widget build(BuildContext context) {
    final Color color = isTest ? Colors.orange.shade800 : Colors.red;
    final String label = isTest ? 'TEST' : 'SOS';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ),
        ),
        CustomPaint(
          size: Size(size * 0.5, _spike),
          painter: SarsatMarkerSpikePainter(color),
        ),
      ],
    );
  }
}

/// Paints the downward triangular spike beneath a [SarsatMarker] badge, whose
/// tip marks the exact geographic position.
class SarsatMarkerSpikePainter extends CustomPainter {
  SarsatMarkerSpikePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final topHalf = w * 0.30;
    final path = ui.Path()
      ..moveTo(w / 2 - topHalf, 0)
      ..lineTo(w / 2 + topHalf, 0)
      ..lineTo(w / 2, h)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = Color.lerp(color, Colors.black, 0.35)!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(SarsatMarkerSpikePainter oldDelegate) =>
      color != oldDelegate.color;
}
