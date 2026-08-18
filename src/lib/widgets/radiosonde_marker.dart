/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A radiosonde marker: a circular light-blue badge with a treasure-map style
/// "X", sitting on a downward spike whose tip marks the exact landing/position.
/// Shares the shape of [SarsatMarker] so map and dialog render consistently.
class RadiosondeMarker extends StatelessWidget {
  const RadiosondeMarker({super.key, this.size = 30, this.spikeHeight});

  final double size;

  /// Height of the spike below the badge; defaults to 55% of [size].
  final double? spikeHeight;

  double get _spike => spikeHeight ?? size * 0.55;

  /// Total marker height (badge + spike), for sizing the enclosing Marker.
  double get totalHeight => size + _spike;

  @override
  Widget build(BuildContext context) {
    const Color color = Color(0xFF0277BD); // light-blue 800
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
          child: const Center(
            child: Icon(Icons.close, color: Colors.white, size: 18),
          ),
        ),
        CustomPaint(
          size: Size(size * 0.5, _spike),
          painter: RadiosondeMarkerSpikePainter(color),
        ),
      ],
    );
  }
}

/// Paints the downward triangular spike beneath a [RadiosondeMarker] badge,
/// whose tip marks the exact geographic position.
class RadiosondeMarkerSpikePainter extends CustomPainter {
  RadiosondeMarkerSpikePainter(this.color);

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
  bool shouldRepaint(RadiosondeMarkerSpikePainter oldDelegate) =>
      color != oldDelegate.color;
}
