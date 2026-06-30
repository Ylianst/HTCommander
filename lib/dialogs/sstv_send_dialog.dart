import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Result returned by [SstvSendDialog] when the user confirms a transmission.
class SstvSendResult {
  /// Selected SSTV mode name (e.g. "Robot 36 Color").
  final String modeName;

  /// Width of the scaled image in pixels.
  final int width;

  /// Height of the scaled image in pixels.
  final int height;

  /// Scaled image pixels packed as ARGB (0xAARRGGBB), row-major.
  final Int32List pixels;

  /// PNG-encoded bytes of the scaled image, ready to be saved to disk.
  final Uint8List pngBytes;

  const SstvSendResult({
    required this.modeName,
    required this.width,
    required this.height,
    required this.pixels,
    required this.pngBytes,
  });
}

/// SSTV mode definition with name, native resolution and approximate
/// transmit time.
class _SstvModeInfo {
  final String name;
  final int width;
  final int height;
  final int transmitSeconds;

  const _SstvModeInfo(this.name, this.width, this.height, this.transmitSeconds);

  String get transmitTimeString {
    if (transmitSeconds < 60) return '${transmitSeconds}s';
    final min = transmitSeconds ~/ 60;
    final sec = transmitSeconds % 60;
    return sec > 0 ? '${min}m ${sec}s' : '${min}m';
  }

  @override
  String toString() => '$name  ($width x $height)';
}

/// All supported SSTV modes with their native resolutions and approximate
/// transmit times (computed from the encoder timing constants).
const List<_SstvModeInfo> _sstvModes = <_SstvModeInfo>[
  _SstvModeInfo('Robot 36 Color', 320, 240, 36),
  _SstvModeInfo('Robot 72 Color', 320, 240, 73),
  _SstvModeInfo('Martin 1', 320, 256, 115),
  _SstvModeInfo('Martin 2', 320, 256, 59),
  _SstvModeInfo('Scottie 1', 320, 256, 110),
  _SstvModeInfo('Scottie 2', 320, 256, 72),
  _SstvModeInfo('Scottie DX', 320, 256, 270),
  _SstvModeInfo('Wraase SC2\u2013180', 320, 256, 183),
  _SstvModeInfo('PD 50', 320, 256, 51),
  _SstvModeInfo('PD 90', 320, 256, 91),
  _SstvModeInfo('PD 120', 640, 496, 127),
  _SstvModeInfo('PD 160', 512, 400, 162),
  _SstvModeInfo('PD 180', 640, 496, 188),
  _SstvModeInfo('PD 240', 640, 496, 249),
  _SstvModeInfo('PD 290', 800, 616, 290),
];

/// A dialog that previews how an image will be transmitted over SSTV.
///
/// The user selects an SSTV mode; the image is center-cropped and scaled to
/// the mode's native resolution and shown alongside the estimated transmit
/// time. Confirming returns the scaled pixels and PNG bytes via [SstvSendResult].
class SstvSendDialog extends StatefulWidget {
  /// Source image to be transmitted. The dialog does not dispose it.
  final ui.Image sourceImage;

  /// Optional source file name shown in the dialog header.
  final String? sourceName;

  const SstvSendDialog({super.key, required this.sourceImage, this.sourceName});

  @override
  State<SstvSendDialog> createState() => _SstvSendDialogState();
}

class _SstvSendDialogState extends State<SstvSendDialog> {
  int _modeIndex = 0;
  bool _busy = false;
  Uint8List? _previewPng;

  @override
  void initState() {
    super.initState();
    // Default to Robot 36 Color when present.
    final idx = _sstvModes.indexWhere((m) => m.name == 'Robot 36 Color');
    _modeIndex = idx >= 0 ? idx : 0;
    _updatePreview();
  }

  /// Scales the source image to the selected mode's resolution and refreshes
  /// the preview.
  Future<void> _updatePreview() async {
    setState(() => _busy = true);
    final mode = _sstvModes[_modeIndex];
    try {
      final scaled = await _scaleImageToFill(
        widget.sourceImage,
        mode.width,
        mode.height,
      );
      final png = await _imageToPng(scaled);
      scaled.dispose();
      if (!mounted) return;
      setState(() {
        _previewPng = png;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  Future<void> _onSend() async {
    setState(() => _busy = true);
    final mode = _sstvModes[_modeIndex];
    try {
      final scaled = await _scaleImageToFill(
        widget.sourceImage,
        mode.width,
        mode.height,
      );
      final pixels = await _imageToArgb(scaled);
      final png = await _imageToPng(scaled);
      scaled.dispose();
      if (!mounted) return;
      Navigator.of(context).pop(
        SstvSendResult(
          modeName: mode.name,
          width: mode.width,
          height: mode.height,
          pixels: pixels,
          pngBytes: png,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final mode = _sstvModes[_modeIndex];
    final maxPreviewWidth = (media.size.width * 0.7).clamp(240.0, 520.0);
    final maxPreviewHeight = (media.size.height * 0.5).clamp(180.0, 480.0);

    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxPreviewWidth + 40),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.image, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.sourceName == null
                        ? 'Send SSTV Image'
                        : 'Send SSTV Image - ${widget.sourceName}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Mode selection
            Row(
              children: [
                const Text('Mode:'),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<int>(
                    isExpanded: true,
                    value: _modeIndex,
                    onChanged: _busy
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() => _modeIndex = value);
                            _updatePreview();
                          },
                    items: [
                      for (int i = 0; i < _sstvModes.length; i++)
                        DropdownMenuItem<int>(
                          value: i,
                          child: Text(_sstvModes[i].toString()),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Transmit time: ~${mode.transmitTimeString}',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
            ),
            const SizedBox(height: 12),

            // Preview
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxPreviewWidth,
                maxHeight: maxPreviewHeight,
                minHeight: 160,
              ),
              child: Center(
                child: _previewPng == null
                    ? const SizedBox(
                        height: 160,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                        ),
                        child: Image.memory(
                          _previewPng!,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 16),

            // Buttons (bottom right)
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _busy || _previewPng == null ? null : _onSend,
                    child: const Text('Send'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

/// Scales and center-crops [source] to exactly fill [targetWidth] x
/// [targetHeight], preserving aspect ratio by cropping the excess.
Future<ui.Image> _scaleImageToFill(
  ui.Image source,
  int targetWidth,
  int targetHeight,
) async {
  final sourceAspect = source.width / source.height;
  final targetAspect = targetWidth / targetHeight;

  double srcX, srcY, srcW, srcH;
  if (sourceAspect > targetAspect) {
    // Source is wider - crop left/right.
    srcH = source.height.toDouble();
    srcW = source.height * targetAspect;
    srcX = (source.width - srcW) / 2;
    srcY = 0;
  } else {
    // Source is taller - crop top/bottom.
    srcW = source.width.toDouble();
    srcH = source.width / targetAspect;
    srcX = 0;
    srcY = (source.height - srcH) / 2;
  }

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint()..filterQuality = FilterQuality.high;
  canvas.drawImageRect(
    source,
    Rect.fromLTWH(srcX, srcY, srcW, srcH),
    Rect.fromLTWH(0, 0, targetWidth.toDouble(), targetHeight.toDouble()),
    paint,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(targetWidth, targetHeight);
  picture.dispose();
  return image;
}

/// Extracts the pixels of [image] as packed ARGB (0xAARRGGBB) integers.
Future<Int32List> _imageToArgb(ui.Image image) async {
  final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final rgba = byteData!.buffer.asUint8List();
  final count = image.width * image.height;
  final argb = Int32List(count);
  for (int i = 0; i < count; i++) {
    final o = i * 4;
    final r = rgba[o];
    final g = rgba[o + 1];
    final b = rgba[o + 2];
    final a = rgba[o + 3];
    argb[i] = (a << 24) | (r << 16) | (g << 8) | b;
  }
  return argb;
}

/// Encodes [image] to PNG bytes.
Future<Uint8List> _imageToPng(ui.Image image) async {
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}
