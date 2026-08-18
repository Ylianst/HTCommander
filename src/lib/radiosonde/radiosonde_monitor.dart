/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Event wrapper around the radiosonde demodulators/decoders. Received PCM is
buffered for the length of a receive run and decoded on [flush], emitting a
[RadiosondeFix] for every complete fix found. Each sonde family has its own
demodulator + stateful decoder, all fed the same audio; a single decoder
instance per family is kept for the monitor's lifetime so serial numbers and
calibration that span many frames accumulate. Mirrors the shape of
[SarsatMonitor] so it wires into the audio pipeline the same way.
*/

import 'dart:async';
import 'dart:typed_data';

import 'dfm_decoder.dart';
import 'dfm_demodulator.dart';
import 'imet_decoder.dart';
import 'imet_demodulator.dart';
import 'lms6_decoder.dart';
import 'lms6_demodulator.dart';
import 'm10_decoder.dart';
import 'm10_demodulator.dart';
import 'm20_decoder.dart';
import 'radiosonde_fix.dart';
import 'rs41_decoder.dart';
import 'rs41_demodulator.dart';

/// Monitors received audio for supported radiosonde telemetry
/// (DFM, RS41, M10, M20, iMet, LMS6).
class RadiosondeMonitor {
  RadiosondeMonitor({int sampleRate = 48000})
    : _dfmDemod = DfmDemodulator(sampleRate),
      _rs41Demod = Rs41Demodulator(sampleRate),
      _m10Demod = M10Demodulator(sampleRate),
      _m20Demod = M10Demodulator(sampleRate,
          chipRate: 9600, frameBytes: 70, sync0: 0x45, sync1: 0x20),
      _imetDemod = ImetDemodulator(sampleRate),
      _lms6Demod = Lms6Demodulator(sampleRate),
      _sampleRate = sampleRate;

  final DfmDemodulator _dfmDemod;
  final DfmDecoder _dfmDecoder = DfmDecoder();
  final Rs41Demodulator _rs41Demod;
  final Rs41Decoder _rs41Decoder = Rs41Decoder();
  final M10Demodulator _m10Demod;
  final M10Decoder _m10Decoder = M10Decoder();
  final M10Demodulator _m20Demod;
  final M20Decoder _m20Decoder = M20Decoder();
  final ImetDemodulator _imetDemod;
  final ImetDecoder _imetDecoder = ImetDecoder();
  final Lms6Demodulator _lms6Demod;
  final Lms6Decoder _lms6Decoder = Lms6Decoder();
  final int _sampleRate;
  bool _disposed = false;

  // Accumulated 16-bit LE PCM for the current run.
  final BytesBuilder _buffer = BytesBuilder(copy: false);

  final StreamController<RadiosondeFix> _decodedController =
      StreamController<RadiosondeFix>.broadcast();

  /// Fired for every complete radiosonde fix decoded from a run.
  Stream<RadiosondeFix> get onDecoded => _decodedController.stream;

  // The shortest sonde frame is ~0.22 s; skip runs too short for a few frames.
  int get _minBytes => (_sampleRate * 0.5).round() * 2;
  // Bound the buffer so a continuous stream is decoded periodically.
  int get _maxBytes => _sampleRate * 6 * 2;

  /// Feeds 16-bit signed little-endian PCM. [offset]/[length] are in bytes.
  void processPcm16(Uint8List pcm, int offset, int length) {
    if (_disposed || length <= 1) return;
    _buffer.add(Uint8List.sublistView(pcm, offset, offset + length));
    if (_buffer.length >= _maxBytes) {
      _decodeBuffer(reset: true);
    }
  }

  /// Decodes and emits any pending run; call at the end of an audio run.
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

    // DFM.
    for (final bits in _dfmDemod.demodulate(samples)) {
      if (_disposed) return;
      final fix = _dfmDecoder.decodeFrame(bits);
      if (fix != null) {
        _decodedController.add(
          RadiosondeFix(
            sondeType: fix.dfmType.isNotEmpty ? fix.dfmType : 'DFM',
            id: fix.sondeId,
            frameNumber: fix.frameNumber,
            latitude: fix.latitude,
            longitude: fix.longitude,
            altitude: fix.altitude,
            horizontalSpeed: fix.horizontalSpeed,
            verticalSpeed: fix.verticalSpeed,
            heading: fix.heading,
            satellites: fix.satellites,
            dateTimeUtc: fix.dateTimeUtc,
            temperatureC: fix.temperatureC,
          ),
        );
      }
    }

    // RS41.
    for (final frame in _rs41Demod.demodulate(samples)) {
      if (_disposed) return;
      final fix = _rs41Decoder.decodeFrame(frame);
      if (fix != null) {
        _decodedController.add(
          RadiosondeFix(
            sondeType: 'RS41',
            id: fix.id,
            frameNumber: fix.frameNumber,
            latitude: fix.latitude,
            longitude: fix.longitude,
            altitude: fix.altitude,
            horizontalSpeed: fix.horizontalSpeed,
            verticalSpeed: fix.verticalSpeed,
            heading: fix.heading,
            satellites: fix.satellites,
            dateTimeUtc: fix.dateTimeUtc,
          ),
        );
      }
    }

    // M10.
    for (final frame in _m10Demod.demodulate(samples)) {
      if (_disposed) return;
      final fix = _m10Decoder.decodeFrame(frame);
      if (fix != null) {
        _decodedController.add(
          RadiosondeFix(
            sondeType: 'M10',
            id: fix.id,
            frameNumber: 0,
            latitude: fix.latitude,
            longitude: fix.longitude,
            altitude: fix.altitude,
            horizontalSpeed: fix.horizontalSpeed,
            verticalSpeed: fix.verticalSpeed,
            heading: fix.heading,
            satellites: fix.satellites,
            dateTimeUtc: fix.dateTimeUtc,
          ),
        );
      }
    }

    // M20.
    for (final frame in _m20Demod.demodulate(samples)) {
      if (_disposed) return;
      final fix = _m20Decoder.decodeFrame(frame);
      if (fix != null) {
        _decodedController.add(
          RadiosondeFix(
            sondeType: 'M20',
            id: fix.id,
            frameNumber: 0,
            latitude: fix.latitude,
            longitude: fix.longitude,
            altitude: fix.altitude,
            horizontalSpeed: fix.horizontalSpeed,
            verticalSpeed: fix.verticalSpeed,
            heading: fix.heading,
            satellites: 0,
            dateTimeUtc: fix.dateTimeUtc,
          ),
        );
      }
    }

    // iMet (Bell-202 AFSK byte stream).
    final imetBytes = _imetDemod.demodulate(samples);
    if (imetBytes.isNotEmpty) {
      final now = DateTime.now().toUtc();
      for (final fix in _imetDecoder.decodeStream(imetBytes)) {
        if (_disposed) return;
        // iMet frames carry only a time-of-day; anchor to today's UTC date.
        DateTime dt;
        try {
          dt = DateTime.utc(
              now.year, now.month, now.day, fix.hour, fix.minute, fix.second);
        } catch (_) {
          dt = now;
        }
        _decodedController.add(
          RadiosondeFix(
            sondeType: 'iMet',
            id: '',
            frameNumber: 0,
            latitude: fix.latitude,
            longitude: fix.longitude,
            altitude: fix.altitude.toDouble(),
            horizontalSpeed: fix.horizontalSpeed,
            verticalSpeed: fix.verticalSpeed,
            heading: fix.heading,
            satellites: fix.satellites,
            dateTimeUtc: dt,
          ),
        );
      }
    }

    // LMS6 (NRZ 4800, convolutional + RS).
    final lms6Blocks = _lms6Demod.demodulate(samples);
    if (lms6Blocks.isNotEmpty) {
      final now = DateTime.now().toUtc();
      for (final block in lms6Blocks) {
        if (_disposed) return;
        final fix = _lms6Decoder.decodeRawBits(block);
        if (fix == null) continue;
        // LMS6 frames carry only a time-of-day; anchor to today's UTC date.
        DateTime dt;
        try {
          dt = DateTime.utc(
              now.year, now.month, now.day, fix.hour, fix.minute, fix.second);
        } catch (_) {
          dt = now;
        }
        _decodedController.add(
          RadiosondeFix(
            sondeType: 'LMS6',
            id: fix.serial != 0 ? '${fix.serial}' : '',
            frameNumber: fix.frameNumber,
            latitude: fix.latitude,
            longitude: fix.longitude,
            altitude: fix.altitude,
            horizontalSpeed: fix.horizontalSpeed,
            verticalSpeed: fix.verticalSpeed,
            heading: fix.heading,
            satellites: 0,
            dateTimeUtc: dt,
          ),
        );
      }
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _buffer.clear();
    _decodedController.close();
  }
}
