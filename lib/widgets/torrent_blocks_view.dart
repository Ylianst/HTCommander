/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A grid visualization of a torrent file's blocks (port of the C#
/// `TorrentBlocksUserControl`).
///
/// Each block is a small square: filled green when received, a grey outline
/// when still missing, each with a soft drop shadow. The grid wraps to the
/// available width and scrolls vertically.
///
/// The UI only knows how many blocks exist ([totalBlocks]) and how many have
/// been received ([receivedBlocks]); the first [receivedBlocks] squares are
/// shown as received (matching the C# placeholder reconstruction in
/// `CreateTorrentFileFromData`).
class TorrentBlocksView extends StatelessWidget {
  const TorrentBlocksView({
    super.key,
    required this.totalBlocks,
    required this.receivedBlocks,
  });

  final int totalBlocks;
  final int receivedBlocks;

  static const double _blockSize = 12;
  static const double _blockMargin = 2;

  @override
  Widget build(BuildContext context) {
    if (totalBlocks <= 0) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const cell = _blockSize + _blockMargin;
        final blocksPerRow = math.max(1, (width / cell).floor());
        final totalRows = (totalBlocks / blocksPerRow).ceil();
        final contentHeight = totalRows * cell;
        return SingleChildScrollView(
          child: SizedBox(
            width: width,
            height: contentHeight,
            child: CustomPaint(
              painter: _BlocksPainter(
                totalBlocks: totalBlocks,
                receivedBlocks: receivedBlocks,
                blocksPerRow: blocksPerRow,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BlocksPainter extends CustomPainter {
  _BlocksPainter({
    required this.totalBlocks,
    required this.receivedBlocks,
    required this.blocksPerRow,
  });

  final int totalBlocks;
  final int receivedBlocks;
  final int blocksPerRow;

  static const double _blockSize = TorrentBlocksView._blockSize;
  static const double _blockMargin = TorrentBlocksView._blockMargin;
  static const double _shadowOffset = 2;

  @override
  void paint(Canvas canvas, Size size) {
    const cell = _blockSize + _blockMargin;

    final receivedPaint = Paint()..color = Colors.green;
    final shadowPaint = Paint()..color = Colors.black.withValues(alpha: 0.25);
    final notReceivedPaint = Paint()
      ..color = Colors.grey
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (var i = 0; i < totalBlocks; i++) {
      final x = (i % blocksPerRow) * cell;
      final y = (i ~/ blocksPerRow) * cell;

      // Drop shadow.
      canvas.drawRect(
        Rect.fromLTWH(
          x + _shadowOffset,
          y + _shadowOffset,
          _blockSize,
          _blockSize,
        ),
        shadowPaint,
      );

      final rect = Rect.fromLTWH(x, y, _blockSize, _blockSize);
      if (i < receivedBlocks) {
        canvas.drawRect(rect, receivedPaint);
      } else {
        canvas.drawRect(rect, notReceivedPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_BlocksPainter old) {
    return old.totalBlocks != totalBlocks ||
        old.receivedBlocks != receivedBlocks ||
        old.blocksPerRow != blocksPerRow;
  }
}
