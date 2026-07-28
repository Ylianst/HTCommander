/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Event wrapper around [CwDecoder]. Feed it received PCM and it emits a
[CwDecoded] event on its broadcast stream each time a complete CW (Morse)
transmission is decoded to text. Mirrors the shape of SstvMonitor so it can be
wired into the audio pipeline the same way.
*/

import 'dart:async';
import 'dart:typed_data';

import 'cw_decoder.dart';

/// A decoded CW transmission.
class CwDecoded {
  final String text;
  final int wpm;
  final double toneHz;

  CwDecoded({required this.text, required this.wpm, required this.toneHz});
}

/// Monitors received audio for on/off-keyed CW tones and reports decoded text.
class CwMonitor {
  CwMonitor({int sampleRate = 32000}) {
    _decoder = CwDecoder(
      sampleRate: sampleRate,
      onDecoded: _onDecoded,
    );
  }

  late final CwDecoder _decoder;
  bool _disposed = false;

  final StreamController<CwDecoded> _decodedController =
      StreamController<CwDecoded>.broadcast();

  /// Fired when a complete CW transmission has been decoded.
  Stream<CwDecoded> get onDecoded => _decodedController.stream;

  void _onDecoded(String text, int wpm) {
    if (_disposed) return;
    _decodedController.add(
      CwDecoded(text: text, wpm: wpm, toneHz: _decoder.lastToneHz),
    );
  }

  /// Feeds 16-bit signed little-endian PCM. [offset]/[length] are in bytes.
  void processPcm16(Uint8List pcm, int offset, int length) {
    if (_disposed) return;
    _decoder.processPcm16(pcm, offset, length);
  }

  /// Finalizes and emits any pending transmission (call at the end of a burst).
  void flush() {
    if (_disposed) return;
    _decoder.flush();
  }

  /// Clears decoder state without emitting.
  void reset() {
    if (_disposed) return;
    _decoder.reset();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _decodedController.close();
  }
}
