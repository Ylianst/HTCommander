/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported to Dart. The original C# version produced System.Drawing.Bitmap
instances; this port produces dependency-free [SstvImage] objects holding the
decoded ARGB pixel data (which can be turned into a ui.Image or written out by
the caller), and exposes the lifecycle events as broadcast streams instead of
C# events.
*/

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'decoder.dart';
import 'pixel_buffer.dart';

/// A decoded SSTV image as a flat ARGB pixel array.
class SstvImage {
  final int width;
  final int height;

  /// Pixels packed as 32-bit ARGB values, row-major (width * height entries).
  final Int32List pixels;

  SstvImage(this.width, this.height, this.pixels);
}

/// Event payload for SSTV decoding start.
class SstvDecodingStarted {
  final String modeName;
  final int width;
  final int height;

  SstvDecodingStarted({
    required this.modeName,
    required this.width,
    required this.height,
  });
}

/// Event payload for SSTV decoding progress.
class SstvDecodingProgress {
  final String modeName;
  final int currentLine;
  final int totalLines;

  SstvDecodingProgress({
    required this.modeName,
    required this.currentLine,
    required this.totalLines,
  });

  double get percentComplete =>
      totalLines > 0 ? (currentLine / totalLines) * 100.0 : 0.0;
}

/// Event payload for SSTV decoding completion.
class SstvDecodingComplete {
  final String modeName;
  final int width;
  final int height;

  /// The decoded image, or null on failure.
  final SstvImage? image;

  SstvDecodingComplete({
    required this.modeName,
    required this.width,
    required this.height,
    required this.image,
  });
}

/// Wraps the SSTV [Decoder] to provide event-driven notifications for
/// auto-detection, progress, and completion of SSTV image decoding.
/// Feed it received PCM audio and it will emit events as images are detected
/// and decoded.
class SstvMonitor {
  late Decoder _decoder;
  late PixelBuffer _imageBuffer;
  final int sampleRate;
  bool _disposed = false;

  // State tracking for event detection
  int _previousLine = -1;
  bool _isDecoding = false;
  String? _currentModeName;
  int _lastProgressLine = -1;
  static const int _progressLineInterval = 10; // Fire progress every N lines

  final StreamController<SstvDecodingStarted> _startedController =
      StreamController<SstvDecodingStarted>.broadcast();
  final StreamController<SstvDecodingProgress> _progressController =
      StreamController<SstvDecodingProgress>.broadcast();
  final StreamController<SstvDecodingComplete> _completeController =
      StreamController<SstvDecodingComplete>.broadcast();

  /// Fired when SSTV decoding starts (VIS header detected, mode identified).
  Stream<SstvDecodingStarted> get onDecodingStarted =>
      _startedController.stream;

  /// Fired when new scan lines have been decoded (progress update).
  Stream<SstvDecodingProgress> get onDecodingProgress =>
      _progressController.stream;

  /// Fired when a complete SSTV image has been decoded.
  Stream<SstvDecodingComplete> get onDecodingComplete =>
      _completeController.stream;

  /// Creates a new SstvMonitor.
  ///
  /// [sampleRate] is the audio sample rate in Hz (must match the PCM data fed
  /// in). Default 32000.
  SstvMonitor({this.sampleRate = 32000}) {
    _initialize();
  }

  /// Initializes the decoder for detecting a new image.
  void _initialize() {
    _imageBuffer = PixelBuffer(0, 0);
    _imageBuffer.line = -1;

    _decoder = Decoder(null, _imageBuffer, 'Raw', sampleRate);
    _previousLine = -1;
    _isDecoding = false;
    _currentModeName = null;
    _lastProgressLine = -1;
  }

  /// Resets the decoder to prepare for detecting a new image.
  void reset() {
    if (_disposed) return;
    _decoder.dispose();
    _initialize();
  }

  /// Feeds 16-bit signed PCM audio data (little-endian) to the SSTV decoder.
  /// Events will fire as images are detected and decoded.
  ///
  /// [pcmData] is a byte array containing 16-bit signed PCM samples.
  /// [offset] is the offset into the byte array.
  /// [length] is the number of bytes to process (must be even).
  void processPcm16(Uint8List pcmData, int offset, int length) {
    if (_disposed) return;
    if (length <= 1) return;

    _updateEvents(_decoder.processPcm16(pcmData, offset, length));
  }

  /// Feeds float audio samples (normalized -1..1) to the SSTV decoder.
  void processFloatSamples(Float64List samples) {
    if (_disposed) return;
    if (samples.isEmpty) return;

    _updateEvents(_decoder.process(samples, 0));
  }

  void _updateEvents(bool newLines) {
    SstvDecodingStarted? startedArgs;
    SstvDecodingProgress? progressArgs;
    SstvDecodingComplete? completeArgs;

    final currentLine = _imageBuffer.line;
    final height = _imageBuffer.height;

    // Detect decoding START: line transitions from negative to 0+ with a mode.
    if (!_isDecoding && currentLine >= 0 && currentLine < height) {
      _isDecoding = true;
      _currentModeName = _decoder.currentMode.getName();
      _lastProgressLine = 0;

      startedArgs = SstvDecodingStarted(
        modeName: _currentModeName!,
        width: _decoder.currentMode.getWidth(),
        height: _decoder.currentMode.getHeight(),
      );
    }

    // Detect PROGRESS: new lines were decoded, throttled by interval.
    if (_isDecoding &&
        newLines &&
        currentLine > _previousLine &&
        currentLine < height) {
      if (currentLine - _lastProgressLine >= _progressLineInterval) {
        _lastProgressLine = currentLine;
        progressArgs = SstvDecodingProgress(
          modeName: _currentModeName!,
          currentLine: currentLine,
          totalLines: height,
        );
      }
    }

    // Detect COMPLETION: line reached or exceeded height.
    if (_isDecoding && currentLine >= height && _previousLine < height) {
      final image = _extractImage();

      completeArgs = SstvDecodingComplete(
        modeName: _currentModeName ?? '',
        width: image?.width ?? 0,
        height: image?.height ?? 0,
        image: image,
      );

      // Reset for next image
      _isDecoding = false;
      _currentModeName = null;
      _previousLine = -1;
      _lastProgressLine = -1;

      // Re-initialize decoder for the next potential image
      _decoder.dispose();
      _initialize();
    } else {
      _previousLine = currentLine;
    }

    if (startedArgs != null) _startedController.add(startedArgs);
    if (progressArgs != null) _progressController.add(progressArgs);
    if (completeArgs != null) _completeController.add(completeArgs);
  }

  /// Extracts the decoded image from the pixel buffer.
  /// Returns null on failure.
  SstvImage? _extractImage() {
    final width = _imageBuffer.width;
    final height = _imageBuffer.height;
    final pixels = _imageBuffer.pixels;

    if (width <= 0 || height <= 0 || pixels.length < width * height) {
      return null;
    }

    // Apply post-processing if the mode supports it (e.g. HF Fax shift).
    Int32List finalPixels = pixels;
    int finalWidth = width;
    final finalHeight = height;

    finalPixels = _decoder.currentMode.postProcessScopeImage(
      pixels,
      width,
      height,
    );
    final modeWidth = _decoder.currentMode.getWidth();
    if (finalPixels.length != width * height &&
        modeWidth > 0 &&
        finalPixels.length == modeWidth * height) {
      finalWidth = modeWidth;
    }

    final n = finalWidth * finalHeight;
    // Completion replaces the decoder before publishing this image, so an
    // exactly-sized buffer can be transferred without a defensive copy.
    if (finalPixels.length == n) {
      return SstvImage(finalWidth, finalHeight, finalPixels);
    }
    final out = Int32List(n);
    out.setRange(0, math.min(n, finalPixels.length), finalPixels);
    return SstvImage(finalWidth, finalHeight, out);
  }

  /// Extracts a partial image from the pixel buffer at full resolution.
  /// Decoded lines are filled in; remaining lines are opaque black.
  /// Returns null if no lines have been decoded yet.
  SstvImage? getPartialImage() {
    if (_imageBuffer.line <= 0) return null;

    final width = _imageBuffer.width;
    final fullHeight = _imageBuffer.height;
    final decodedLines = math.min(_imageBuffer.line, fullHeight);
    final pixels = _imageBuffer.pixels;

    if (width <= 0 || fullHeight <= 0 || pixels.length < width * decodedLines) {
      return null;
    }

    // Create a full-size pixel array initialized to opaque black.
    final totalPixels = width * fullHeight;
    final fullPixels = Int32List(totalPixels);
    const opaqueBlack = 0xFF000000;
    for (int i = width * decodedLines; i < totalPixels; i++) {
      fullPixels[i] = opaqueBlack;
    }

    // Copy decoded lines into the full-size array.
    fullPixels.setRange(0, width * decodedLines, pixels);

    return SstvImage(width, fullHeight, fullPixels);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _decoder.dispose();
    _startedController.close();
    _progressController.close();
    _completeController.close();
  }
}
