/*
SSTV Encoder

Generates audio samples for SSTV transmission.
Supports all modes present in the decoder.

Ported to Dart from C# (HTCommander SSTV Encoder).
*/

import 'dart:math' as math;
import 'dart:typed_data';
import 'sstv_round.dart';

/// Encodes pixel data into SSTV audio samples using frequency modulation.
/// Supports Robot 36, Robot 72, Martin 1/2, Scottie 1/2/DX,
/// Wraase SC2-180, PD 50/90/120/160/180/240/290, and HF Fax modes.
class Encoder {
  final int _sampleRate;
  double _phase = 0;

  // SSTV standard frequencies
  static const double syncPulseFrequency = 1200.0;
  static const double syncPorchFrequency = 1500.0;
  static const double blackFrequency = 1500.0;
  static const double whiteFrequency = 2300.0;
  static const double leaderToneFrequency = 1900.0;
  static const double visBitOneFrequency = 1100.0;
  static const double visBitZeroFrequency = 1300.0;

  Encoder(int sampleRate) : _sampleRate = sampleRate;

  /// Reset the oscillator phase.
  void reset() {
    _phase = 0;
  }

  /// Generate a tone at the given frequency for the given duration and append
  /// samples to the list.
  void _addTone(
    List<double> samples,
    double frequency,
    double durationSeconds,
  ) {
    final count = sstvRound(durationSeconds * _sampleRate);
    final delta = 2.0 * math.pi * frequency / _sampleRate;
    for (int i = 0; i < count; i++) {
      samples.add(math.sin(_phase));
      _phase += delta;
      if (_phase > 2.0 * math.pi) _phase -= 2.0 * math.pi;
    }
  }

  /// Convert a pixel luminance/color level [0..1] to SSTV frequency.
  static double _levelToFrequency(double level) {
    level = level.clamp(0.0, 1.0);
    return blackFrequency + level * (whiteFrequency - blackFrequency);
  }

  /// Add a single sample at the given frequency.
  void _addSample(List<double> samples, double frequency) {
    final delta = 2.0 * math.pi * frequency / _sampleRate;
    samples.add(math.sin(_phase));
    _phase += delta;
    if (_phase > 2.0 * math.pi) _phase -= 2.0 * math.pi;
  }

  /// Add a scan line of pixels as frequency-modulated samples.
  void _addPixelLine(
    List<double> samples,
    Float64List levels,
    double durationSeconds,
  ) {
    final count = sstvRound(durationSeconds * _sampleRate);
    for (int i = 0; i < count; i++) {
      int pixelIndex = (i * levels.length) ~/ count;
      pixelIndex = math.min(pixelIndex, levels.length - 1);
      final freq = _levelToFrequency(levels[pixelIndex]);
      _addSample(samples, freq);
    }
  }

  /// Generate the SSTV VIS header (leader tone + break + VIS code + sync).
  void _addVISHeader(List<double> samples, int visCode) {
    // Leader tone (300ms)
    _addTone(samples, leaderToneFrequency, 0.3);
    // Break (10ms at 1200Hz)
    _addTone(samples, syncPulseFrequency, 0.01);
    // Leader tone (300ms)
    _addTone(samples, leaderToneFrequency, 0.3);

    // VIS start bit (30ms at 1200Hz)
    _addTone(samples, syncPulseFrequency, 0.03);

    // Compute even parity for bit 7 over the lower 7 data bits
    int parity = 0;
    for (int i = 0; i < 7; i++) {
      parity ^= (visCode >> i) & 1;
    }
    final visCodeWithParity = (visCode & 0x7F) | (parity << 7);

    // 8 VIS bits (7 data + 1 parity, LSB first), 30ms each
    for (int i = 0; i < 8; i++) {
      final bit = (visCodeWithParity & (1 << i)) != 0;
      _addTone(samples, bit ? visBitOneFrequency : visBitZeroFrequency, 0.03);
    }

    // VIS stop bit (30ms at 1200Hz)
    _addTone(samples, syncPulseFrequency, 0.03);
  }

  /// Extract RGB from a packed ARGB int.
  static (double, double, double) _unpackRGB(int argb) {
    final r = ((argb >> 16) & 0xFF) / 255.0;
    final g = ((argb >> 8) & 0xFF) / 255.0;
    final b = (argb & 0xFF) / 255.0;
    return (r, g, b);
  }

  /// Convert RGB [0..1] to YUV [0..1] (BT.601).
  static (double, double, double) _rgbToYUV(double r, double g, double b) {
    final y = 0.299 * r + 0.587 * g + 0.114 * b;
    final u = -0.169 * r - 0.331 * g + 0.500 * b + 0.5;
    final v = 0.500 * r - 0.419 * g - 0.081 * b + 0.5;
    return (y, u, v);
  }

  /// Encode a full image using Robot 36 Color mode.
  /// Image is expected as a flat ARGB int array, width x height.
  Float64List encodeRobot36(Int32List pixels, int width, int height) {
    const visCode = 8;
    const double syncPulseSeconds = 0.009;
    const double syncPorchSeconds = 0.003;
    const double luminanceSeconds = 0.088;
    const double separatorSeconds = 0.0045;
    const double porchSeconds = 0.0015;
    const double chrominanceSeconds = 0.044;
    const horizontalPixels = 320;
    const verticalPixels = 240;

    final samples = <double>[];
    _addVISHeader(samples, visCode);

    for (int line = 0; line < verticalPixels; line += 2) {
      final yEven = Float64List(horizontalPixels);
      final yOdd = Float64List(horizontalPixels);
      final uAvg = Float64List(horizontalPixels);
      final vAvg = Float64List(horizontalPixels);

      for (int x = 0; x < horizontalPixels; x++) {
        final srcXEven = (x * width) ~/ horizontalPixels;
        final srcYEven = (line * height) ~/ verticalPixels;
        final srcXOdd = srcXEven;
        int srcYOdd = ((line + 1) * height) ~/ verticalPixels;
        srcYOdd = math.min(srcYOdd, height - 1);

        final (rE, gE, bE) = _unpackRGB(pixels[srcYEven * width + srcXEven]);
        final (yE, uE, vE) = _rgbToYUV(rE, gE, bE);
        final (rO, gO, bO) = _unpackRGB(pixels[srcYOdd * width + srcXOdd]);
        final (yO, uO, vO) = _rgbToYUV(rO, gO, bO);

        yEven[x] = yE;
        yOdd[x] = yO;
        uAvg[x] = (uE + uO) / 2;
        vAvg[x] = (vE + vO) / 2;
      }

      // Even line: sync + porch + Y + separator(even=1500Hz) + porch + V
      _addTone(samples, syncPulseFrequency, syncPulseSeconds);
      _addTone(samples, syncPorchFrequency, syncPorchSeconds);
      _addPixelLine(samples, yEven, luminanceSeconds);
      _addTone(samples, syncPorchFrequency, separatorSeconds); // even separator
      _addTone(samples, syncPorchFrequency, porchSeconds);
      _addPixelLine(samples, vAvg, chrominanceSeconds);

      // Odd line: sync + porch + Y + separator(odd=2300Hz) + porch + U
      _addTone(samples, syncPulseFrequency, syncPulseSeconds);
      _addTone(samples, syncPorchFrequency, syncPorchSeconds);
      _addPixelLine(samples, yOdd, luminanceSeconds);
      _addTone(samples, whiteFrequency, separatorSeconds); // odd separator
      _addTone(samples, syncPorchFrequency, porchSeconds);
      _addPixelLine(samples, uAvg, chrominanceSeconds);
    }

    return Float64List.fromList(samples);
  }

  /// Encode a full image using Robot 72 Color mode.
  Float64List encodeRobot72(Int32List pixels, int width, int height) {
    const visCode = 12;
    const double syncPulseSeconds = 0.009;
    const double syncPorchSeconds = 0.003;
    const double luminanceSeconds = 0.138;
    const double separatorSeconds = 0.0045;
    const double porchSeconds = 0.0015;
    const double chrominanceSeconds = 0.069;
    const horizontalPixels = 320;
    const verticalPixels = 240;

    final samples = <double>[];
    _addVISHeader(samples, visCode);

    for (int line = 0; line < verticalPixels; line++) {
      final yLine = Float64List(horizontalPixels);
      final uLine = Float64List(horizontalPixels);
      final vLine = Float64List(horizontalPixels);

      for (int x = 0; x < horizontalPixels; x++) {
        final srcX = (x * width) ~/ horizontalPixels;
        final srcY = (line * height) ~/ verticalPixels;
        final (r, g, b) = _unpackRGB(pixels[srcY * width + srcX]);
        final (y, u, v) = _rgbToYUV(r, g, b);
        yLine[x] = y;
        uLine[x] = u;
        vLine[x] = v;
      }

      _addTone(samples, syncPulseFrequency, syncPulseSeconds);
      _addTone(samples, syncPorchFrequency, syncPorchSeconds);
      _addPixelLine(samples, yLine, luminanceSeconds);
      _addTone(samples, syncPorchFrequency, separatorSeconds);
      _addTone(samples, syncPorchFrequency, porchSeconds);
      _addPixelLine(samples, vLine, chrominanceSeconds);
      _addTone(samples, syncPorchFrequency, separatorSeconds);
      _addTone(samples, syncPorchFrequency, porchSeconds);
      _addPixelLine(samples, uLine, chrominanceSeconds);
    }

    return Float64List.fromList(samples);
  }

  /// Encode a full image using a Martin mode (Martin 1 or Martin 2).
  Float64List encodeMartin(
    Int32List pixels,
    int width,
    int height,
    String variant,
  ) {
    int visCode;
    double channelSeconds;
    if (variant == '1') {
      visCode = 44;
      channelSeconds = 0.146432;
    } else {
      visCode = 40;
      channelSeconds = 0.073216;
    }

    const double syncPulseSeconds = 0.004862;
    const double separatorSeconds = 0.000572;
    const horizontalPixels = 320;
    const verticalPixels = 256;

    final samples = <double>[];
    _addVISHeader(samples, visCode);

    for (int line = 0; line < verticalPixels; line++) {
      final red = Float64List(horizontalPixels);
      final green = Float64List(horizontalPixels);
      final blue = Float64List(horizontalPixels);

      for (int x = 0; x < horizontalPixels; x++) {
        final srcX = (x * width) ~/ horizontalPixels;
        final srcY = (line * height) ~/ verticalPixels;
        final (r, g, b) = _unpackRGB(pixels[srcY * width + srcX]);
        red[x] = r;
        green[x] = g;
        blue[x] = b;
      }

      _addTone(samples, syncPulseFrequency, syncPulseSeconds);
      _addTone(samples, syncPorchFrequency, separatorSeconds);
      _addPixelLine(samples, green, channelSeconds);
      _addTone(samples, syncPorchFrequency, separatorSeconds);
      _addPixelLine(samples, blue, channelSeconds);
      _addTone(samples, syncPorchFrequency, separatorSeconds);
      _addPixelLine(samples, red, channelSeconds);
    }

    return Float64List.fromList(samples);
  }

  /// Encode a full image using a Scottie mode (Scottie 1, 2, or DX).
  Float64List encodeScottie(
    Int32List pixels,
    int width,
    int height,
    String variant,
  ) {
    int visCode;
    double channelSeconds;
    if (variant == '1') {
      visCode = 60;
      channelSeconds = 0.138240;
    } else if (variant == '2') {
      visCode = 56;
      channelSeconds = 0.088064;
    } else {
      visCode = 76;
      channelSeconds = 0.3456;
    }

    const double syncPulseSeconds = 0.009;
    const double separatorSeconds = 0.0015;
    const horizontalPixels = 320;
    const verticalPixels = 256;

    final samples = <double>[];
    _addVISHeader(samples, visCode);

    for (int line = 0; line < verticalPixels; line++) {
      final red = Float64List(horizontalPixels);
      final green = Float64List(horizontalPixels);
      final blue = Float64List(horizontalPixels);

      for (int x = 0; x < horizontalPixels; x++) {
        final srcX = (x * width) ~/ horizontalPixels;
        final srcY = (line * height) ~/ verticalPixels;
        final (r, g, b) = _unpackRGB(pixels[srcY * width + srcX]);
        red[x] = r;
        green[x] = g;
        blue[x] = b;
      }

      // Scottie order: separator + green + separator + blue + sync + separator + red
      _addTone(samples, syncPorchFrequency, separatorSeconds);
      _addPixelLine(samples, green, channelSeconds);
      _addTone(samples, syncPorchFrequency, separatorSeconds);
      _addPixelLine(samples, blue, channelSeconds);
      _addTone(samples, syncPulseFrequency, syncPulseSeconds);
      _addTone(samples, syncPorchFrequency, separatorSeconds);
      _addPixelLine(samples, red, channelSeconds);
    }

    return Float64List.fromList(samples);
  }

  /// Encode a full image using Wraase SC2-180 mode.
  Float64List encodeWraaseSc2180(Int32List pixels, int width, int height) {
    const visCode = 55;
    const double syncPulseSeconds = 0.0055225;
    const double syncPorchSeconds = 0.0005;
    const double channelSeconds = 0.235;
    const horizontalPixels = 320;
    const verticalPixels = 256;

    final samples = <double>[];
    _addVISHeader(samples, visCode);

    for (int line = 0; line < verticalPixels; line++) {
      final red = Float64List(horizontalPixels);
      final green = Float64List(horizontalPixels);
      final blue = Float64List(horizontalPixels);

      for (int x = 0; x < horizontalPixels; x++) {
        final srcX = (x * width) ~/ horizontalPixels;
        final srcY = (line * height) ~/ verticalPixels;
        final (r, g, b) = _unpackRGB(pixels[srcY * width + srcX]);
        red[x] = r;
        green[x] = g;
        blue[x] = b;
      }

      _addTone(samples, syncPulseFrequency, syncPulseSeconds);
      _addTone(samples, syncPorchFrequency, syncPorchSeconds);
      _addPixelLine(samples, red, channelSeconds);
      _addPixelLine(samples, green, channelSeconds);
      _addPixelLine(samples, blue, channelSeconds);
    }

    return Float64List.fromList(samples);
  }

  /// Encode a full image using a PD (PaulDon) mode.
  /// Valid variants: "50", "90", "120", "160", "180", "240", "290"
  Float64List encodePaulDon(
    Int32List pixels,
    int width,
    int height,
    String variant,
  ) {
    int visCode;
    int horizontalPixels;
    int verticalPixels;
    double channelSeconds;

    switch (variant) {
      case '50':
        visCode = 93;
        horizontalPixels = 320;
        verticalPixels = 256;
        channelSeconds = 0.09152;
        break;
      case '90':
        visCode = 99;
        horizontalPixels = 320;
        verticalPixels = 256;
        channelSeconds = 0.17024;
        break;
      case '120':
        visCode = 95;
        horizontalPixels = 640;
        verticalPixels = 496;
        channelSeconds = 0.1216;
        break;
      case '160':
        visCode = 98;
        horizontalPixels = 512;
        verticalPixels = 400;
        channelSeconds = 0.195584;
        break;
      case '180':
        visCode = 96;
        horizontalPixels = 640;
        verticalPixels = 496;
        channelSeconds = 0.18304;
        break;
      case '240':
        visCode = 97;
        horizontalPixels = 640;
        verticalPixels = 496;
        channelSeconds = 0.24448;
        break;
      case '290':
        visCode = 94;
        horizontalPixels = 800;
        verticalPixels = 616;
        channelSeconds = 0.2288;
        break;
      default:
        throw ArgumentError('Unknown PD variant: $variant');
    }

    const double syncPulseSeconds = 0.02;
    const double syncPorchSeconds = 0.00208;

    final samples = <double>[];
    _addVISHeader(samples, visCode);

    for (int line = 0; line < verticalPixels; line += 2) {
      final yEven = Float64List(horizontalPixels);
      final yOdd = Float64List(horizontalPixels);
      final uAvg = Float64List(horizontalPixels);
      final vAvg = Float64List(horizontalPixels);

      for (int x = 0; x < horizontalPixels; x++) {
        final srcXEven = (x * width) ~/ horizontalPixels;
        final srcYEven = (line * height) ~/ verticalPixels;
        final srcXOdd = srcXEven;
        int srcYOdd = ((line + 1) * height) ~/ verticalPixels;
        srcYOdd = math.min(srcYOdd, height - 1);

        final (rE, gE, bE) = _unpackRGB(pixels[srcYEven * width + srcXEven]);
        final (yE, uE, vE) = _rgbToYUV(rE, gE, bE);
        final (rO, gO, bO) = _unpackRGB(pixels[srcYOdd * width + srcXOdd]);
        final (yO, uO, vO) = _rgbToYUV(rO, gO, bO);

        yEven[x] = yE;
        yOdd[x] = yO;
        uAvg[x] = (uE + uO) / 2;
        vAvg[x] = (vE + vO) / 2;
      }

      _addTone(samples, syncPulseFrequency, syncPulseSeconds);
      _addTone(samples, syncPorchFrequency, syncPorchSeconds);
      _addPixelLine(samples, yEven, channelSeconds);
      _addPixelLine(samples, vAvg, channelSeconds);
      _addPixelLine(samples, uAvg, channelSeconds);
      _addPixelLine(samples, yOdd, channelSeconds);
    }

    return Float64List.fromList(samples);
  }

  /// Encode a grayscale image using HF Fax mode (IOC 576, 120 LPM).
  /// Pixels should be ARGB packed ints.
  Float64List encodeHFFax(Int32List pixels, int width, int height) {
    const horizontalPixels = 640;
    const totalLines = 1200;
    const double scanLineSeconds = 0.5; // 120 LPM = 0.5s per line

    final samples = <double>[];

    // HF Fax has no VIS header; just encode scan lines
    for (int line = 0; line < totalLines; line++) {
      final gray = Float64List(horizontalPixels);
      int srcY = (line * height) ~/ totalLines;
      srcY = math.min(srcY, height - 1);

      for (int x = 0; x < horizontalPixels; x++) {
        int srcX = (x * width) ~/ horizontalPixels;
        srcX = math.min(srcX, width - 1);
        final argb = pixels[srcY * width + srcX];
        final r = ((argb >> 16) & 0xFF) / 255.0;
        final g = ((argb >> 8) & 0xFF) / 255.0;
        final b = (argb & 0xFF) / 255.0;
        gray[x] = 0.299 * r + 0.587 * g + 0.114 * b;
      }

      _addPixelLine(samples, gray, scanLineSeconds);
    }

    return Float64List.fromList(samples);
  }

  /// Convenience method to encode any supported mode by name.
  Float64List encode(Int32List pixels, int width, int height, String modeName) {
    switch (modeName) {
      case 'Robot 36 Color':
        return encodeRobot36(pixels, width, height);
      case 'Robot 72 Color':
        return encodeRobot72(pixels, width, height);
      case 'Martin 1':
        return encodeMartin(pixels, width, height, '1');
      case 'Martin 2':
        return encodeMartin(pixels, width, height, '2');
      case 'Scottie 1':
        return encodeScottie(pixels, width, height, '1');
      case 'Scottie 2':
        return encodeScottie(pixels, width, height, '2');
      case 'Scottie DX':
        return encodeScottie(pixels, width, height, 'DX');
      case 'Wraase SC2\u2013180':
        return encodeWraaseSc2180(pixels, width, height);
      case 'PD 50':
        return encodePaulDon(pixels, width, height, '50');
      case 'PD 90':
        return encodePaulDon(pixels, width, height, '90');
      case 'PD 120':
        return encodePaulDon(pixels, width, height, '120');
      case 'PD 160':
        return encodePaulDon(pixels, width, height, '160');
      case 'PD 180':
        return encodePaulDon(pixels, width, height, '180');
      case 'PD 240':
        return encodePaulDon(pixels, width, height, '240');
      case 'PD 290':
        return encodePaulDon(pixels, width, height, '290');
      case 'HF Fax':
        return encodeHFFax(pixels, width, height);
      default:
        throw ArgumentError('Unknown mode: $modeName');
    }
  }

  /// Get the list of all supported mode names.
  static List<String> getSupportedModes() => const [
    'Robot 36 Color',
    'Robot 72 Color',
    'Martin 1',
    'Martin 2',
    'Scottie 1',
    'Scottie 2',
    'Scottie DX',
    'Wraase SC2\u2013180',
    'PD 50',
    'PD 90',
    'PD 120',
    'PD 160',
    'PD 180',
    'PD 240',
    'PD 290',
    'HF Fax',
  ];
}
