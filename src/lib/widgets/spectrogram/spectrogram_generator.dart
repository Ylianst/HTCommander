/*
SpectrogramGenerator - Dart port of the C# Spectrogram component.

Equivalent of reference/Spectrogram/src/Spectrogram/{SpectrogramGenerator,
Settings,ImageMaker}.cs. It maintains a sliding-window FFT over an incoming
stream of audio samples and renders the accumulated FFT columns into an RGBA
pixel buffer that a widget can turn into a `ui.Image`.

Design notes for efficiency:
  * Audio is buffered in a compacting Float64List ring (no per-sample boxing).
  * The FFT uses preallocated scratch buffers and a reusable twiddle table.
  * A Hann window and the dB/log10 constant are precomputed once.
  * The RGBA render buffer is supplied by the caller and reused frame to frame.
*/

import 'dart:math' as math;
import 'dart:typed_data';

import 'spectrogram_colormap.dart';
import 'spectrogram_fft.dart';

class SpectrogramGenerator {
  /// Samples per second.
  final int sampleRate;

  /// FFT window length in samples (power of two).
  final int fftSize;

  /// Samples to advance between successive FFTs (controls horizontal/time
  /// resolution).
  final int stepSize;

  /// Lowest stored frequency bin (Hz) and the bin index it maps to.
  final double minFreq;

  /// Highest stored frequency bin (Hz).
  final double maxFreq;

  /// Frequency resolution (Hz per vertical pixel).
  late final double hzPerPixel;

  /// Index of the first stored FFT bin (inclusive).
  late final int fftIndex1;

  /// Index of the last stored FFT bin (exclusive).
  late final int fftIndex2;

  /// Number of frequency bins (vertical pixels) in the output image.
  late final int height;

  final SpectrogramFft _fft;
  final Float64List _window;
  final Float64List _re;
  final Float64List _im;
  final _SampleBuffer _buffer = _SampleBuffer();

  /// One Float64List per spectrogram column; length is the image width.
  final List<Float64List> _ffts = [];

  int _fftsProcessed = 0;
  int _rollOffset = 0;
  int _fixedWidth = 0;

  /// Cached empty column reused when padding to the fixed width.
  late final Float64List _emptyColumn;

  static const double _log10Mul = 20.0 / math.ln10;

  SpectrogramGenerator({
    this.sampleRate = 32000,
    this.fftSize = 512,
    int? stepSize,
    this.minFreq = 0,
    this.maxFreq = double.infinity,
  }) : stepSize = (stepSize ?? (fftSize ~/ 20)).clamp(1, fftSize),
       _fft = SpectrogramFft(fftSize),
       _window = Float64List(fftSize),
       _re = Float64List(fftSize),
       _im = Float64List(fftSize) {
    if (fftSize < 2 || (fftSize & (fftSize - 1)) != 0) {
      throw ArgumentError('fftSize must be a power of two (was $fftSize)');
    }

    final clampedMin = minFreq < 0 ? 0.0 : minFreq;
    final nyquist = sampleRate / 2.0;
    hzPerPixel = sampleRate / fftSize;
    fftIndex1 = clampedMin == 0 ? 0 : (clampedMin / hzPerPixel).floor();
    fftIndex2 = maxFreq >= nyquist
        ? fftSize ~/ 2
        : (maxFreq / hzPerPixel).floor();
    height = fftIndex2 - fftIndex1;
    _emptyColumn = Float64List(height);

    // Hann window.
    if (fftSize == 1) {
      _window[0] = 1.0;
    } else {
      for (int i = 0; i < fftSize; i++) {
        _window[i] = 0.5 * (1.0 - math.cos(2.0 * math.pi * i / (fftSize - 1)));
      }
    }
  }

  /// Number of FFT columns currently stored (the image width).
  int get width => _ffts.length;

  /// Number of complete FFT windows waiting to be processed.
  int get fftsToProcess => (_buffer.length - fftSize) ~/ stepSize;

  /// Column index that will be written next (used for the roll-mode marker).
  int get nextColumnIndex =>
      width > 0 ? (_fftsProcessed + _rollOffset) % width : 0;

  /// Append raw audio samples (already converted to doubles).
  void addSamples(Float64List samples, [int offset = 0, int? length]) {
    final count = length ?? (samples.length - offset);
    if (count <= 0) return;
    _buffer.addAll(samples, offset, count);
  }

  /// Append 16-bit little-endian PCM audio (as delivered by the radio/mic).
  void addPcm16(Uint8List bytes, [int offset = 0, int? length]) {
    final count = length ?? (bytes.length - offset);
    final sampleCount = count ~/ 2;
    if (sampleCount <= 0) return;
    final data = ByteData.sublistView(bytes, offset, offset + sampleCount * 2);
    final samples = Float64List(sampleCount);
    for (int i = 0; i < sampleCount; i++) {
      samples[i] = data.getInt16(i * 2, Endian.little).toDouble();
    }
    _buffer.addAll(samples, 0, sampleCount);
  }

  /// Reset the next-column marker so the next processed FFT lands at the far
  /// left (used when starting a fresh roll-mode sweep).
  void rollReset([int offset = 0]) {
    _rollOffset = -_fftsProcessed + offset;
  }

  /// Process every complete FFT window currently buffered.
  void process() {
    final count = fftsToProcess;
    if (count < 1) return;

    for (int f = 0; f < count; f++) {
      final srcIndex = f * stepSize;
      for (int i = 0; i < fftSize; i++) {
        _re[i] = _buffer[srcIndex + i] * _window[i];
        _im[i] = 0.0;
      }

      _fft.forward(_re, _im);

      final column = Float64List(height);
      for (int i = 0; i < height; i++) {
        final idx = fftIndex1 + i;
        final re = _re[idx];
        final im = _im[idx];
        column[i] = math.sqrt(re * re + im * im) / fftSize;
      }
      _ffts.add(column);
    }

    _fftsProcessed += count;
    _buffer.removeFront(count * stepSize);
    _padOrTrimForFixedWidth();
  }

  /// Keep exactly [columns] FFT columns in memory, padding the left with blank
  /// columns or trimming the oldest ones.
  void setFixedWidth(int columns) {
    _fixedWidth = columns;
    _padOrTrimForFixedWidth();
  }

  void _padOrTrimForFixedWidth() {
    if (_fixedWidth <= 0) return;
    final overhang = _ffts.length - _fixedWidth;
    if (overhang > 0) {
      _ffts.removeRange(0, overhang);
    }
    while (_ffts.length < _fixedWidth) {
      _ffts.insert(0, _emptyColumn);
    }
  }

  /// Render the stored FFT columns into [rgba] (length must be
  /// `width * height * 4`, RGBA8888 order).
  ///
  /// Mirrors the C# ImageMaker: optional dB/log transform, intensity scaling,
  /// clamping to 0..255, then colormap lookup. Low frequencies are drawn at the
  /// bottom of the image. When [roll] is true new columns wrap around starting
  /// at [nextColumnIndex] instead of scrolling.
  void renderInto(
    Uint8List rgba, {
    required SpectrogramColormap colormap,
    double intensity = 1,
    bool decibel = false,
    double dbScale = 1,
    bool roll = false,
  }) {
    final w = width;
    final h = height;
    if (w <= 0 || h <= 0) return;

    final r = colormap.r;
    final g = colormap.g;
    final b = colormap.b;
    final rollOffset = nextColumnIndex;

    for (int col = 0; col < w; col++) {
      int sourceCol = col;
      if (roll) {
        sourceCol += w - (rollOffset % w);
        if (sourceCol >= w) sourceCol -= w;
      }
      final column = _ffts[sourceCol];

      for (int row = 0; row < h; row++) {
        double value = column[row];
        if (decibel) {
          value = _log10Mul * math.log(value * dbScale + 1.0);
        }
        value *= intensity;
        if (value > 255.0) value = 255.0;
        if (value < 0.0) value = 0.0;
        final v = value.toInt();

        // Low-frequency bin (row 0) is drawn at the bottom of the image.
        final pixel = ((h - 1 - row) * w + col) * 4;
        rgba[pixel] = r[v];
        rgba[pixel + 1] = g[v];
        rgba[pixel + 2] = b[v];
        rgba[pixel + 3] = 255;
      }
    }
  }

  /// Discard all stored audio and FFT columns.
  void clear() {
    _ffts.clear();
    _buffer.clear();
    _fftsProcessed = 0;
    _rollOffset = 0;
    _padOrTrimForFixedWidth();
  }

  /// Frequency (Hz) and magnitude of the dominant bin in the most recent FFT.
  ({double freqHz, double magnitude}) getPeak() {
    if (_ffts.isEmpty) {
      return (freqHz: double.nan, magnitude: double.nan);
    }
    final freqs = _ffts.last;
    int peakIndex = 0;
    double peakMagnitude = 0;
    for (int i = 0; i < freqs.length; i++) {
      if (freqs[i] > peakMagnitude) {
        peakMagnitude = freqs[i];
        peakIndex = i;
      }
    }
    final freqHz = (fftIndex1 + peakIndex) * hzPerPixel;
    return (freqHz: freqHz, magnitude: peakMagnitude);
  }
}

/// A compacting growable buffer of doubles backed by a Float64List. Avoids the
/// boxing overhead of `List<double>` and the O(n) shift of List.removeRange when
/// consuming from the front.
class _SampleBuffer {
  Float64List _data = Float64List(0);
  int _start = 0;
  int _end = 0;

  int get length => _end - _start;

  double operator [](int i) => _data[_start + i];

  void addAll(Float64List src, int srcOffset, int count) {
    _ensureTail(count);
    _data.setRange(_end, _end + count, src, srcOffset);
    _end += count;
  }

  void removeFront(int n) {
    _start += n;
    if (_start >= _end) {
      _start = 0;
      _end = 0;
    }
  }

  void clear() {
    _start = 0;
    _end = 0;
  }

  void _ensureTail(int count) {
    if (_end + count <= _data.length) return;
    final len = length;
    if (len + count <= _data.length) {
      // Enough total capacity: compact toward the start.
      _data.setRange(0, len, _data, _start);
      _start = 0;
      _end = len;
      return;
    }
    var newCap = _data.isEmpty ? 1024 : _data.length;
    while (newCap < len + count) {
      newCap <<= 1;
    }
    final grown = Float64List(newCap);
    grown.setRange(0, len, _data, _start);
    _data = grown;
    _start = 0;
    _end = len;
  }
}
