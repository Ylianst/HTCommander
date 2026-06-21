import 'dart:io';

import 'package:flutter/material.dart';

/// Simple dialog that displays an image at a larger size, with pinch/scroll
/// zoom and a Close button in the bottom-right (matching the other dialogs).
class ImageViewDialog extends StatelessWidget {
  /// Full path to the image file to display.
  final String filePath;

  /// Optional title shown in the dialog header (e.g. the SSTV mode name).
  final String? title;

  const ImageViewDialog({super.key, required this.filePath, this.title});

  @override
  Widget build(BuildContext context) {
    final fileName = title ?? filePath.split(Platform.pathSeparator).last;
    final media = MediaQuery.of(context).size;

    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.image, size: 20, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    fileName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: media.width * 0.9,
                  maxHeight: media.height * 0.7,
                ),
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 5,
                  child: Image.file(
                    File(filePath),
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    errorBuilder: (context, error, stackTrace) => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'Failed to load image.',
                        style: TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
