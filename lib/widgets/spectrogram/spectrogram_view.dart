/*
Spectrogram widget for Flutter.

Provides a [SpectrogramController] that buffers incoming PCM audio, periodically
runs the sliding-window FFT and rasterizes the result to a `ui.Image`, and a
[SpectrogramView] widget that paints that image scaled to fill its bounds.

This is the Flutter equivalent of the C# SpectrogramForm's drawing surface
(a PictureBox fed by a SpectrogramGenerator on a timer). Feeding audio and
selecting a source (radio/microphone) is left to the caller so the widget stays
decoupled from the rest of the app.

Usage:
  final controller = SpectrogramController(sampleRate: 32000, maxFrequency: 16000);
  // From your audio stream:
  controller.feedPcm16(bytes, offset, length);
  // In the tree:
  SpectrogramView(controller: controller);
  // When done:
  controller.dispose();
*/

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'spectrogram_colormap.dart';
import 'spectrogram_generator.dart';

export 'spectrogram_colormap.dart' show SpectrogramColormap;

/// Owns a [SpectrogramGenerator], drives it on a timer and exposes the latest
/// rendered [ui.Image]. Notifies listeners whenever a new frame is ready.
class SpectrogramController extends ChangeNotifier {
  SpectrogramGenerator _generator;

  /// Brightness multiplier applied before the colormap (C# default was 5).
  double intensity;

  /// Apply a dB/log10 transform before scaling (C# default was true).
  bool decibel;

  /// Multiplier applied before the dB log transform.
  double dbScale;

  /// Roll mode wraps new columns around; otherwise the image scrolls left.
  bool roll;

  /// How often to process buffered audio and regenerate the image.
  Duration updateInterval;

  SpectrogramColormap _colormap;
  int _columnCount;
  Timer? _timer;
  ui.Image? _image;
  Uint8List? _rgba;
  bool _generating = false;
  bool _disposed = false;

  SpectrogramController({
    int sampleRate = 32000,
    int fftSize = 512,
    int? stepSize,
    double minFrequency = 0,
    double maxFrequency = 16000,
    this.intensity = 5,
    this.decibel = true,
    this.dbScale = 1,
    this.roll = false,
    SpectrogramColormap? colormap,
    this.updateInterval = const Duration(milliseconds: 50),
    int columnCount = 480,
  }) : _columnCount = columnCount.clamp(16, 4096),
       _colormap = colormap ?? SpectrogramColormap.viridis,
       _generator = SpectrogramGenerator(
         sampleRate: sampleRate,
         fftSize: fftSize,
         stepSize: stepSize,
         minFreq: minFrequency,
         maxFreq: maxFrequency,
       ) {
    _generator.setFixedWidth(_columnCount);
    _startTimer();
  }

  /// The most recent rendered spectrogram image (null until the first frame).
  ui.Image? get image => _image;

  /// Number of frequency bins in the generated image (its native height).
  int get imageHeight => _generator.height;

  /// Number of FFT columns in the generated image (its native width).
  int get imageWidth => _generator.width;

  /// Active colormap.
  SpectrogramColormap get colormap => _colormap;
  set colormap(SpectrogramColormap value) {
    if (_colormap == value) return;
    _colormap = value;
    // Re-render on the next tick using existing FFT data.
  }

  /// Number of pixel columns to keep (the image's native width). The
  /// [SpectrogramView] sets this from its layout width.
  int get columnCount => _columnCount;
  set columnCount(int value) {
    final clamped = value.clamp(16, 4096);
    if (clamped == _columnCount) return;
    _columnCount = clamped;
    _generator.setFixedWidth(_columnCount);
    _rgba = null; // size changed; reallocate on next render
  }

  /// Feed 16-bit little-endian PCM audio (e.g. radio or microphone data).
  void feedPcm16(Uint8List bytes, [int offset = 0, int? length]) {
    if (_disposed) return;
    _generator.addPcm16(bytes, offset, length);
  }

  /// Feed raw audio samples already converted to doubles.
  void feedSamples(Float64List samples, [int offset = 0, int? length]) {
    if (_disposed) return;
    _generator.addSamples(samples, offset, length);
  }

  /// Column index where the roll-mode marker should be drawn, or -1 when not
  /// in roll mode.
  int get rollColumn => roll ? _generator.nextColumnIndex : -1;

  /// Discard buffered audio and clear the image.
  void clear() {
    _generator.clear();
    _image?.dispose();
    _image = null;
    notifyListeners();
  }

  /// Rebuild the generator with new FFT/frequency parameters, preserving any
  /// unset values. Existing image data is cleared.
  void reconfigure({
    int? sampleRate,
    int? fftSize,
    int? stepSize,
    double? minFrequency,
    double? maxFrequency,
  }) {
    final old = _generator;
    _generator = SpectrogramGenerator(
      sampleRate: sampleRate ?? old.sampleRate,
      fftSize: fftSize ?? old.fftSize,
      stepSize: stepSize,
      minFreq: minFrequency ?? old.minFreq,
      maxFreq: maxFrequency ?? old.maxFreq,
    );
    _generator.setFixedWidth(_columnCount);
    _rgba = null;
    _image?.dispose();
    _image = null;
    notifyListeners();
  }

  void _startTimer() {
    _timer = Timer.periodic(updateInterval, (_) => _tick());
  }

  void _tick() {
    if (_disposed || _generating) return;
    if (_generator.fftsToProcess < 1) return;

    _generator.process();
    _generator.setFixedWidth(_columnCount);

    final w = _generator.width;
    final h = _generator.height;
    if (w <= 0 || h <= 0) return;

    final required = w * h * 4;
    var buffer = _rgba;
    if (buffer == null || buffer.length != required) {
      buffer = Uint8List(required);
      _rgba = buffer;
    }

    _generator.renderInto(
      buffer,
      colormap: _colormap,
      intensity: intensity,
      decibel: decibel,
      dbScale: dbScale,
      roll: roll,
    );

    _generating = true;
    ui.decodeImageFromPixels(buffer, w, h, ui.PixelFormat.rgba8888, (img) {
      _generating = false;
      if (_disposed) {
        img.dispose();
        return;
      }
      _image?.dispose();
      _image = img;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _image?.dispose();
    _image = null;
    super.dispose();
  }
}

/// Paints the spectrogram produced by a [SpectrogramController], scaling the
/// native image to fill the available space.
class SpectrogramView extends StatefulWidget {
  final SpectrogramController controller;

  /// Draw a vertical marker line at the roll position when in roll mode.
  final bool showRollLine;

  /// Sampling quality when the native image is scaled to the widget size.
  final FilterQuality filterQuality;

  /// Color shown before the first frame and behind the image.
  final Color backgroundColor;

  const SpectrogramView({
    super.key,
    required this.controller,
    this.showRollLine = true,
    this.filterQuality = FilterQuality.low,
    this.backgroundColor = Colors.black,
  });

  @override
  State<SpectrogramView> createState() => _SpectrogramViewState();
}

class _SpectrogramViewState extends State<SpectrogramView> {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth.isFinite && constraints.maxWidth > 0) {
          final targetWidth = constraints.maxWidth.round();
          // Update outside the build/layout pass to avoid mutating state mid-build.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.controller.columnCount = targetWidth;
          });
        }
        return CustomPaint(
          painter: _SpectrogramPainter(
            controller: widget.controller,
            showRollLine: widget.showRollLine,
            filterQuality: widget.filterQuality,
            backgroundColor: widget.backgroundColor,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class _SpectrogramPainter extends CustomPainter {
  final SpectrogramController controller;
  final bool showRollLine;
  final FilterQuality filterQuality;
  final Color backgroundColor;

  _SpectrogramPainter({
    required this.controller,
    required this.showRollLine,
    required this.filterQuality,
    required this.backgroundColor,
  }) : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    if (backgroundColor.a > 0) {
      canvas.drawRect(Offset.zero & size, Paint()..color = backgroundColor);
    }

    final image = controller.image;
    if (image == null) return;

    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final dst = Offset.zero & size;
    canvas.drawImageRect(
      image,
      src,
      dst,
      Paint()..filterQuality = filterQuality,
    );

    if (showRollLine && controller.roll) {
      final col = controller.rollColumn;
      final w = controller.imageWidth;
      if (col >= 0 && w > 0) {
        final x = (col / w) * size.width;
        canvas.drawLine(
          Offset(x, 0),
          Offset(x, size.height),
          Paint()
            ..color = Colors.white
            ..strokeWidth = 1,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SpectrogramPainter oldDelegate) {
    return oldDelegate.controller != controller ||
        oldDelegate.showRollLine != showRollLine ||
        oldDelegate.filterQuality != filterQuality ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}
