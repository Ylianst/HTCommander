/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Event wrapper around the SARSAT 406 v1g demodulator/decoder. Received PCM is
buffered for the length of a burst and decoded on [flush] (end of the audio
run), emitting a [Sarsat1gFrame] for every valid beacon message found. Mirrors
the shape of CwMonitor/SstvMonitor so it can be wired into the audio pipeline
the same way.
*/

import 'dart:async';
import 'dart:typed_data';

import 'sarsat_1g_decoder.dart';
import 'sarsat_1g_demodulator.dart';

/// Monitors received audio for 406 MHz v1g distress beacons.
class SarsatMonitor {
  SarsatMonitor({int sampleRate = 32000, double carrierHz = 1400})
    : _demod = Sarsat1gDemodulator(sampleRate, nominalCarrierHz: carrierHz),
      _sampleRate = sampleRate;

  final Sarsat1gDemodulator _demod;
  final int _sampleRate;
  bool _disposed = false;

  // Accumulated 16-bit LE PCM for the current burst.
  final BytesBuilder _buffer = BytesBuilder(copy: false);

  final StreamController<Sarsat1gFrame> _decodedController =
      StreamController<Sarsat1gFrame>.broadcast();

  /// Fired for every valid 406 v1g frame decoded from a burst.
  Stream<Sarsat1gFrame> get onDecoded => _decodedController.stream;

  // Skip decoding bursts shorter than one message (~0.5 s); saves work on the
  // constant stream of short noise fragments.
  int get _minBytes => (_sampleRate * 0.35).round() * 2;
  // Bound the buffer so a continuous stream is decoded periodically rather than
  // growing without limit.
  int get _maxBytes => _sampleRate * 5 * 2;

  /// Feeds 16-bit signed little-endian PCM. [offset]/[length] are in bytes.
  void processPcm16(Uint8List pcm, int offset, int length) {
    if (_disposed || length <= 1) return;
    // Copy the slice since the source buffer is reused by the audio engine.
    _buffer.add(Uint8List.sublistView(pcm, offset, offset + length));
    if (_buffer.length >= _maxBytes) {
      _decodeBuffer(reset: true);
    }
  }

  /// Decodes and emits any pending burst; call at the end of an audio run.
  void flush() {
    if (_disposed) return;
    _decodeBuffer(reset: true);
  }

  void _decodeBuffer({required bool reset}) {
    final len = _buffer.length;
    if (len < _minBytes) {
      if (reset) _buffer.clear();
      return;
    }
    final bytes = _buffer.toBytes();
    if (reset) _buffer.clear();
    final samples = bytes.buffer.asInt16List(
      bytes.offsetInBytes,
      bytes.lengthInBytes ~/ 2,
    );
    final frames = _demod.decode(samples);
    for (final f in frames) {
      if (_disposed) return;
      _decodedController.add(f);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _buffer.clear();
    _decodedController.close();
  }
}
