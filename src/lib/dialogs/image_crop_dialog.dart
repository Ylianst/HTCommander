import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'dialog_utils.dart';

/// Shows a circular pan/zoom crop dialog for [bytes] and returns a base64-encoded
/// [size]x[size] PNG (default 64x64), or null if cancelled.
Future<String?> showImageCropDialog(
  BuildContext context,
  Uint8List bytes, {
  int size = 64,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _ImageCropDialog(bytes: bytes, outputSize: size),
  );
}

class _ImageCropDialog extends StatefulWidget {
  final Uint8List bytes;
  final int outputSize;
  const _ImageCropDialog({required this.bytes, required this.outputSize});

  @override
  State<_ImageCropDialog> createState() => _ImageCropDialogState();
}

class _ImageCropDialogState extends State<_ImageCropDialog> {
  static const double _viewport = 260;

  ui.Image? _image;
  bool _failed = false;

  double _baseScale = 1; // logical px per image px when zoom = 1 (cover)
  double _userScale = 1; // 1..8
  double _panX = 0; // pan in image pixels
  double _panY = 0;
  double _startUserScale = 1;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.bytes);
      final frame = await codec.getNextFrame();
      if (!mounted) return;
      setState(() {
        _image = frame.image;
        final minDim = _image!.width < _image!.height
            ? _image!.width
            : _image!.height;
        _baseScale = _viewport / minDim;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  double get _effScale => _baseScale * _userScale;

  /// The square source rectangle (image pixels) currently framed by the circle.
  Rect _sourceRect() {
    final img = _image!;
    final srcSize = _viewport / _effScale;
    final maxPanX = (img.width - srcSize) / 2;
    final maxPanY = (img.height - srcSize) / 2;
    final px = _panX.clamp(-maxPanX, maxPanX);
    final py = _panY.clamp(-maxPanY, maxPanY);
    final srcX = (img.width - srcSize) / 2 - px;
    final srcY = (img.height - srcSize) / 2 - py;
    return Rect.fromLTWH(srcX, srcY, srcSize, srcSize);
  }

  void _onScaleStart(ScaleStartDetails d) {
    _startUserScale = _userScale;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    setState(() {
      _userScale = (_startUserScale * d.scale).clamp(1, 8);
      _panX += d.focalPointDelta.dx / _effScale;
      _panY += d.focalPointDelta.dy / _effScale;
    });
  }

  Future<void> _confirm() async {
    final img = _image;
    if (img == null) return;
    final n = widget.outputSize;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..filterQuality = FilterQuality.high;
    canvas.drawImageRect(
      img,
      _sourceRect(),
      Rect.fromLTWH(0, 0, n.toDouble(), n.toDouble()),
      paint,
    );
    final picture = recorder.endRecording();
    final out = await picture.toImage(n, n);
    picture.dispose();
    final byteData = await out.toByteData(format: ui.ImageByteFormat.png);
    out.dispose();
    if (byteData == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final b64 = base64Encode(byteData.buffer.asUint8List());
    if (mounted) Navigator.of(context).pop(b64);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(l10n.contactAvatarCropTitle),
      content: SizedBox(
        width: _viewport,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: _viewport,
              height: _viewport,
              child: _failed
                  ? Center(child: Text(l10n.contactAvatarImageError))
                  : _image == null
                      ? const Center(child: CircularProgressIndicator())
                      : GestureDetector(
                          onScaleStart: _onScaleStart,
                          onScaleUpdate: _onScaleUpdate,
                          child: ClipOval(
                            child: CustomPaint(
                              painter: _CropPainter(_image!, _sourceRect()),
                              size: const Size(_viewport, _viewport),
                            ),
                          ),
                        ),
            ),
            if (_image != null && !_failed) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.zoom_out, size: 20, color: scheme.onSurfaceVariant),
                  Expanded(
                    child: Slider(
                      value: _userScale,
                      min: 1,
                      max: 8,
                      onChanged: (v) => setState(() => _userScale = v),
                    ),
                  ),
                  Icon(Icons.zoom_in, size: 20, color: scheme.onSurfaceVariant),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: DialogStyles.secondaryButtonStyle(context),
          child: Text(l10n.commonCancel),
        ),
        ElevatedButton(
          onPressed: (_image != null && !_failed) ? _confirm : null,
          style: DialogStyles.primaryButtonStyle(context),
          child: Text(l10n.commonOk),
        ),
      ],
    );
  }
}

class _CropPainter extends CustomPainter {
  final ui.Image image;
  final Rect src;
  _CropPainter(this.image, this.src);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..filterQuality = FilterQuality.high;
    canvas.drawImageRect(
      image,
      src,
      Rect.fromLTWH(0, 0, size.width, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.image != image || old.src != src;
}
