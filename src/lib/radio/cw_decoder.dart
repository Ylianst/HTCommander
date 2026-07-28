/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Pure-Dart receive-side CW (Morse) decoder for FM audio. It listens for a keyed
tone in a narrow band (default 600-800 Hz), converts the tone on/off envelope
into mark/space durations, and feeds them to the shared [MorseDecoder] for
text. To avoid false positives on voice, each analysis frame is scored for
spectral purity (how much of the frame's energy sits in the single CW peak): a
frame is only treated as a tone when its energy is concentrated, so broadband
speech is rejected. Kept free of Flutter/dart:io so it can be unit-tested.
*/

import 'dart:math' as math;
import 'dart:typed_data';

import 'morse_keyer.dart';

/// Called when a complete CW transmission has been decoded to [text]. [wpm] is
/// the decoder's estimated sending speed.
typedef CwDecodedCallback = void Function(String text, int wpm);

/// Detects and decodes on/off-keyed CW tones in received FM audio.
///
/// Feed received PCM with [processPcm16] (or [addSamples]); completed
/// transmissions are reported through [onDecoded]. A transmission is considered
/// finished after [idleFinishMs] of silence, or when [flush] is called (e.g. at
/// the end of a receive burst).
class CwDecoder {
  CwDecoder({
    this.sampleRate = 32000,
    this.bandLowHz = 600,
    this.bandHighHz = 800,
    this.probeStepHz = 25,
    this.windowSize = 512,
    this.hopSize = 128,
    this.purityThreshold = 0.5,
    this.snrFactor = 4.0,
    this.absFloor = 0.01,
    this.debounceMs = 15,
    this.idleFinishMs = 1500,
    this.minChars = 2,
    this.onDecoded,
  }) {
    // Pre-compute one Goertzel coefficient per probe frequency spanning the CW
    // band. The peak across these probes estimates the tone regardless of its
    // exact pitch inside the band.
    final probes = <double>[];
    for (int f = bandLowHz; f <= bandHighHz; f += probeStepHz) {
      probes.add(2.0 * math.cos(2.0 * math.pi * f / sampleRate));
      _probeFreqs.add(f.toDouble());
    }
    _coeffs = Float64List.fromList(probes);
    _halfN = windowSize / 2.0;
  }

  final int sampleRate;
  final int bandLowHz;
  final int bandHighHz;
  final int probeStepHz;
  final int windowSize;
  final int hopSize;

  /// Minimum fraction of a frame's energy that must sit in the CW peak for the
  /// frame to count as a tone (0..1). Higher rejects voice more aggressively.
  final double purityThreshold;

  /// Tone amplitude must exceed the tracked noise floor by this factor.
  final double snrFactor;

  /// Absolute minimum tone amplitude (0..1 full scale) below which nothing is
  /// ever treated as a tone, so pure silence/noise never decodes.
  final double absFloor;

  /// A tone edge must persist this long before it is accepted, rejecting clicks.
  final int debounceMs;

  /// Silence longer than this ends a transmission and emits the decoded text.
  final int idleFinishMs;

  /// A decoded transmission must contain at least this many letters (spaces
  /// excluded) to be emitted, so stray one-character noise is dropped. A
  /// two-letter result made only of the single-element characters E (dit) and
  /// T (dah) is also rejected, as that is almost always noise.
  final int minChars;

  CwDecodedCallback? onDecoded;

  late final Float64List _coeffs;
  final List<double> _probeFreqs = <double>[];
  late final double _halfN;

  // Elements of the current transmission, in order, as (durationMs, isTone).
  final List<_Seg> _segments = <_Seg>[];
  double _lastUnitMs = 80.0;

  // Sample buffer with overlapping windows.
  final List<double> _buffer = <double>[];
  int _readPos = 0;
  int _absBase = 0; // absolute sample index of _buffer[0]

  // Adaptive noise floor (tone amplitude, 0..1) tracked during non-tone frames.
  double _noiseFloor = 0.0;

  // Envelope / debounce state.
  bool _committedTone = false;
  double _lastEdgeMs = 0.0;
  bool _haveCandidate = false;
  bool _candidateState = false;
  double _candidateMs = 0.0;
  bool _hasContent = false;
  double _lastFrameMs = 0.0;

  /// The tone frequency (Hz) of the most recent strong frame, for diagnostics.
  double get lastToneHz => _lastToneHz;
  double _lastToneHz = 0.0;

  /// Feeds 16-bit signed little-endian PCM. [offset]/[length] are in bytes.
  void processPcm16(Uint8List pcm, int offset, int length) {
    if (length <= 1) return;
    final count = length ~/ 2;
    final samples = Float64List(count);
    for (int i = 0; i < count; i++) {
      final b = offset + i * 2;
      int raw = pcm[b] | (pcm[b + 1] << 8);
      if (raw >= 0x8000) raw -= 0x10000;
      samples[i] = raw / 32768.0;
    }
    addSamples(samples);
  }

  /// Feeds float audio samples normalized to -1..1.
  void addSamples(Float64List samples) {
    if (samples.isEmpty) return;
    _buffer.addAll(samples);
    while (_buffer.length - _readPos >= windowSize) {
      _processWindow(_readPos);
      _readPos += hopSize;
    }
    // Drop consumed samples, keeping the tail still needed by future windows.
    if (_readPos > 0) {
      _buffer.removeRange(0, _readPos);
      _absBase += _readPos;
      _readPos = 0;
    }
  }

  void _processWindow(int start) {
    final n = windowSize;
    final probeCount = _coeffs.length;
    // Per-probe Goertzel recurrences plus the frame energy.
    final s1 = Float64List(probeCount);
    final s2 = Float64List(probeCount);
    double energy = 0.0;
    for (int i = 0; i < n; i++) {
      final x = _buffer[start + i];
      energy += x * x;
      for (int p = 0; p < probeCount; p++) {
        final s = x + _coeffs[p] * s1[p] - s2[p];
        s2[p] = s1[p];
        s1[p] = s;
      }
    }

    double maxPower = 0.0;
    double peakFreq = 0.0;
    for (int p = 0; p < probeCount; p++) {
      final power = s1[p] * s1[p] + s2[p] * s2[p] - _coeffs[p] * s1[p] * s2[p];
      if (power > maxPower) {
        maxPower = power;
        peakFreq = _probeFreqs[p];
      }
    }

    // Amplitude estimate of the peak tone (0..1) and its spectral purity: the
    // fraction of frame energy concentrated in the single CW peak. A pure tone
    // approaches 1.0; broadband voice spreads energy and stays well below.
    final toneLevel = math.sqrt(maxPower) / _halfN;
    final purity = energy > 0.0
        ? (maxPower / (energy * _halfN)).clamp(0.0, 1.0)
        : 0.0;

    final threshold = math.max(absFloor, _noiseFloor * snrFactor);
    final toneOn = toneLevel > threshold && purity >= purityThreshold;

    if (toneOn) {
      _lastToneHz = peakFreq;
    } else {
      // Track the background level from non-tone frames.
      _noiseFloor += (toneLevel - _noiseFloor) * 0.01;
      if (_noiseFloor < 0.0) _noiseFloor = 0.0;
    }

    final frameMs = (_absBase + start + n / 2.0) / sampleRate * 1000.0;
    _lastFrameMs = frameMs;
    _updateEnvelope(frameMs, toneOn);

    if (!_committedTone && _hasContent && frameMs - _lastEdgeMs >= idleFinishMs) {
      _finish(frameMs);
    }
  }

  void _updateEnvelope(double frameMs, bool rawOn) {
    if (rawOn == _committedTone) {
      _haveCandidate = false;
      return;
    }
    if (!_haveCandidate || _candidateState != rawOn) {
      _haveCandidate = true;
      _candidateState = rawOn;
      _candidateMs = frameMs; // time the change was first observed
    }
    if (frameMs - _candidateMs >= debounceMs) {
      _commitEdge(_candidateState, _candidateMs);
      _haveCandidate = false;
    }
  }

  void _commitEdge(bool newState, double edgeMs) {
    final durMs = edgeMs - _lastEdgeMs;
    if (_committedTone) {
      _segments.add(_Seg(durMs, true));
      _hasContent = true;
    } else if (_hasContent) {
      // Ignore the leading silence before the first mark.
      _segments.add(_Seg(durMs, false));
    }
    _committedTone = newState;
    _lastEdgeMs = edgeMs;
  }

  void _finish(double nowMs) {
    final text = _decodeSegments();
    final wpm = (1200.0 / _lastUnitMs).round().clamp(1, 100);
    _segments.clear();
    _committedTone = false;
    _haveCandidate = false;
    _hasContent = false;
    _lastEdgeMs = nowMs;
    if (_acceptable(text)) onDecoded?.call(text, wpm);
  }

  /// Whether a decoded [text] is worth surfacing. Requires at least [minChars]
  /// letters (spaces excluded) and rejects a bare two-character E/T result.
  bool _acceptable(String text) {
    final letters = text.replaceAll(' ', '');
    if (letters.length < minChars) return false;
    if (letters.length == 2 && RegExp(r'^[ET]{2}$').hasMatch(letters)) {
      return false;
    }
    return true;
  }

  /// Decodes the buffered elements. The dit length is estimated from the marks
  /// themselves (a 2-means split of short vs long tones) so a transmission at
  /// any speed is classified against its own timing rather than a fixed guess.
  String _decodeSegments() {
    final marks = <double>[
      for (final s in _segments)
        if (s.tone) s.ms
    ];
    if (marks.isEmpty) return '';
    final unit = _estimateUnit(marks);
    _lastUnitMs = unit;
    final dec = MorseDecoder(fixedUnitMs: unit.round().clamp(10, 2000));
    final dahThreshold = 2.0 * unit;
    for (final s in _segments) {
      if (s.tone) {
        dec.onMark(((s.ms >= dahThreshold ? 3.0 : 1.0) * unit).round());
      } else if (s.ms >= 5.0 * unit) {
        dec.onSpace((7.0 * unit).round()); // word gap
      } else if (s.ms >= dahThreshold) {
        dec.onSpace((3.0 * unit).round()); // letter gap
      }
      // Shorter gaps are intra-element and simply continue the symbol.
    }
    return dec.finish();
  }

  /// Estimates the dit (unit) length in ms from the observed mark durations by
  /// splitting them into a short (dit) and long (dah) cluster.
  double _estimateUnit(List<double> marks) {
    double lo = marks[0];
    double hi = marks[0];
    for (final m in marks) {
      if (m < lo) lo = m;
      if (m > hi) hi = m;
    }
    double c1 = lo;
    double c2 = hi > lo * 1.5 ? hi : lo * 3.0;
    for (int it = 0; it < 8; it++) {
      double s1 = 0, s2 = 0;
      int n1 = 0, n2 = 0;
      for (final m in marks) {
        if ((m - c1).abs() <= (m - c2).abs()) {
          s1 += m;
          n1++;
        } else {
          s2 += m;
          n2++;
        }
      }
      if (n1 > 0) c1 = s1 / n1;
      if (n2 > 0) c2 = s2 / n2;
    }
    return math.min(c1, c2);
  }

  /// Forces any pending transmission to be finalized and emitted. Call at the
  /// end of a receive burst so the last characters aren't held back.
  void flush() {
    final now = _lastFrameMs;
    if (_committedTone) {
      _segments.add(_Seg(now - _lastEdgeMs, true));
      _hasContent = true;
      _committedTone = false;
      _lastEdgeMs = now;
    }
    if (_hasContent) _finish(now);
  }

  /// Clears all state without emitting, e.g. when switching radios or modes.
  void reset() {
    _buffer.clear();
    _readPos = 0;
    _absBase = 0;
    _noiseFloor = 0.0;
    _committedTone = false;
    _haveCandidate = false;
    _hasContent = false;
    _lastEdgeMs = 0.0;
    _lastFrameMs = 0.0;
    _lastToneHz = 0.0;
    _segments.clear();
  }
}

class _Seg {
  _Seg(this.ms, this.tone);
  final double ms;
  final bool tone;
}
