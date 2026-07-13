/*
Copyright 2026 Ylian Saint-Hilaire

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

//
// dart_modem.dart - DART modem: complete TX/RX frame encoder and decoder.
//
// Implements the full signal chain:
// TX: payload → CRC → LDPC → interleave → map → SC-FDMA → preamble + PCM
// RX: PCM → preamble detect → channel est → equalize → demap → LDPC → CRC
//

import 'dart:math' as math;
import 'dart:typed_data';

import 'dart_constellation.dart';
import 'dart_fsk.dart';
import 'dart_ldpc.dart';
import 'dart_ofdm.dart';
import 'dart_packet_info.dart';
import 'dart_preamble.dart';

/// DART modem mode (from the mode table).
///
/// Modes 0–5 are OFDM (increasing throughput). Mode F is the constant-envelope
/// 4-FSK fallback for amplitude-hostile radios.
enum DartMode { mode0, mode1, mode2, mode3, mode4, mode5, modeF }

/// DART mode parameters.
class DartModeParams {
  final DartMode mode;
  final ConstellationType constellation;
  final LdpcRate ldpcRate;
  final int bitsPerSymbol;
  final String description;

  /// True for the constant-envelope 4-FSK fallback (Mode F). When true, the
  /// [constellation] field is a placeholder and the FSK modem is used instead.
  final bool isFsk;

  const DartModeParams._({
    required this.mode,
    required this.constellation,
    required this.ldpcRate,
    required this.bitsPerSymbol,
    required this.description,
    this.isFsk = false,
  });

  static const mode0 = DartModeParams._(
    mode: DartMode.mode0,
    constellation: ConstellationType.bpsk,
    ldpcRate: LdpcRate.r1_2,
    bitsPerSymbol: 1,
    description: 'BPSK R1/2 (~1 kbps)',
  );

  static const mode1 = DartModeParams._(
    mode: DartMode.mode1,
    constellation: ConstellationType.qpsk,
    ldpcRate: LdpcRate.r1_2,
    bitsPerSymbol: 2,
    description: 'QPSK R1/2 (~2 kbps)',
  );

  static const mode2 = DartModeParams._(
    mode: DartMode.mode2,
    constellation: ConstellationType.qpsk,
    ldpcRate: LdpcRate.r2_3,
    bitsPerSymbol: 2,
    description: 'QPSK R2/3 (~3 kbps)',
  );

  static const mode3 = DartModeParams._(
    mode: DartMode.mode3,
    constellation: ConstellationType.psk8,
    ldpcRate: LdpcRate.r2_3,
    bitsPerSymbol: 3,
    description: '8PSK R2/3 (~4 kbps)',
  );

  static const mode4 = DartModeParams._(
    mode: DartMode.mode4,
    constellation: ConstellationType.qam16,
    ldpcRate: LdpcRate.r3_4,
    bitsPerSymbol: 4,
    description: '16QAM R3/4 (~5 kbps)',
  );

  static const mode5 = DartModeParams._(
    mode: DartMode.mode5,
    constellation: ConstellationType.qam16,
    ldpcRate: LdpcRate.r5_6,
    bitsPerSymbol: 4,
    description: '16QAM R5/6 (~6 kbps)',
  );

  /// Constant-envelope 4-FSK fallback. Amplitude-immune; lowest throughput.
  static const modeF = DartModeParams._(
    mode: DartMode.modeF,
    constellation: ConstellationType.bpsk, // placeholder (FSK has no constellation)
    ldpcRate: LdpcRate.r1_2,
    bitsPerSymbol: 2,
    description: '4-FSK R1/2 (fallback)',
    isFsk: true,
  );

  static DartModeParams fromMode(DartMode mode) {
    switch (mode) {
      case DartMode.mode0: return mode0;
      case DartMode.mode1: return mode1;
      case DartMode.mode2: return mode2;
      case DartMode.mode3: return mode3;
      case DartMode.mode4: return mode4;
      case DartMode.mode5: return mode5;
      case DartMode.modeF: return modeF;
    }
  }

  static const allModes = [mode0, mode1, mode2, mode3, mode4, mode5];
}

/// DART frame header (always sent at mode 0).
class DartHeader {
  /// Payload mode index (0–5).
  final int modeIndex;

  /// Payload length in bytes.
  final int payloadLength;

  /// Sequence number (0–255).
  final int seqNum;

  /// Flags: bit 0 = ACK, bit 1 = NACK, bit 2 = data, bit 3 = broadcast.
  final int flags;

  /// Source callsign (up to 6 chars + SSID).
  final String source;

  /// Destination callsign.
  final String destination;

  const DartHeader({
    required this.modeIndex,
    required this.payloadLength,
    required this.seqNum,
    this.flags = 0x04, // data frame
    this.source = '',
    this.destination = '',
  });

  /// Serialize header to bits.
  Uint8List toBits() {
    final bits = Uint8List(144);
    int pos = 0;

    // Mode index: 4 bits
    for (int b = 3; b >= 0; b--) {
      bits[pos++] = (modeIndex >> b) & 1;
    }

    // Payload length: 12 bits
    for (int b = 11; b >= 0; b--) {
      bits[pos++] = (payloadLength >> b) & 1;
    }

    // Source address: 48 bits (6 bytes, padded with spaces)
    final srcBytes = _callsignToBytes(source);
    for (int i = 0; i < 6; i++) {
      for (int b = 7; b >= 0; b--) {
        bits[pos++] = (srcBytes[i] >> b) & 1;
      }
    }

    // Destination address: 48 bits
    final dstBytes = _callsignToBytes(destination);
    for (int i = 0; i < 6; i++) {
      for (int b = 7; b >= 0; b--) {
        bits[pos++] = (dstBytes[i] >> b) & 1;
      }
    }

    // Sequence number: 8 bits
    for (int b = 7; b >= 0; b--) {
      bits[pos++] = (seqNum >> b) & 1;
    }

    // Flags: 8 bits
    for (int b = 7; b >= 0; b--) {
      bits[pos++] = (flags >> b) & 1;
    }

    // CRC-16 over the preceding 128 bits
    final int crc = _crc16(bits, 0, 128);
    for (int b = 15; b >= 0; b--) {
      bits[pos++] = (crc >> b) & 1;
    }

    return bits;
  }

  /// Deserialize header from bits. Returns null if CRC fails.
  static DartHeader? fromBits(Uint8List bits) {
    if (bits.length < 144) return null;

    // Verify CRC
    final int expectedCrc = _extractInt(bits, 128, 16);
    final int computedCrc = _crc16(bits, 0, 128);
    if (expectedCrc != computedCrc) return null;

    int pos = 0;
    final int modeIndex = _extractInt(bits, pos, 4);
    pos += 4;
    final int payloadLength = _extractInt(bits, pos, 12);
    pos += 12;

    // Source: 6 bytes
    final srcBytes = Uint8List(6);
    for (int i = 0; i < 6; i++) {
      srcBytes[i] = _extractInt(bits, pos, 8);
      pos += 8;
    }

    // Destination: 6 bytes
    final dstBytes = Uint8List(6);
    for (int i = 0; i < 6; i++) {
      dstBytes[i] = _extractInt(bits, pos, 8);
      pos += 8;
    }

    final int seqNum = _extractInt(bits, pos, 8);
    pos += 8;
    final int flags = _extractInt(bits, pos, 8);

    return DartHeader(
      modeIndex: modeIndex,
      payloadLength: payloadLength,
      seqNum: seqNum,
      flags: flags,
      source: _bytesToCallsign(srcBytes),
      destination: _bytesToCallsign(dstBytes),
    );
  }

  static int _extractInt(Uint8List bits, int start, int length) {
    int value = 0;
    for (int i = 0; i < length; i++) {
      value = (value << 1) | bits[start + i];
    }
    return value;
  }

  static Uint8List _callsignToBytes(String call) {
    final bytes = Uint8List(6);
    for (int i = 0; i < 6; i++) {
      bytes[i] = i < call.length ? call.codeUnitAt(i) & 0x7F : 0x20;
    }
    return bytes;
  }

  static String _bytesToCallsign(Uint8List bytes) {
    final buf = StringBuffer();
    for (int i = 0; i < 6; i++) {
      if (bytes[i] != 0x20 && bytes[i] != 0) {
        buf.writeCharCode(bytes[i]);
      }
    }
    return buf.toString();
  }

  /// CRC-16/CCITT over a bit array.
  static int _crc16(Uint8List bits, int start, int length) {
    int crc = 0xFFFF;
    for (int i = start; i < start + length; i++) {
      final int bit = bits[i];
      final int xorBit = ((crc >> 15) ^ bit) & 1;
      crc = (crc << 1) & 0xFFFF;
      if (xorBit == 1) crc ^= 0x1021;
    }
    return crc;
  }
}

/// Result of decoding a DART frame.
class DartDecodeResult {
  final DartHeader header;
  final Uint8List payload;
  final bool crcOk;

  /// Measured signal quality for this received frame.
  final DartSignalQuality quality;

  /// On-air duration of the decoded frame in milliseconds.
  final double durationMs;

  /// Sample index in the decoded buffer just past the end of this frame.
  /// Lets a streaming receiver consume the frame and keep the remaining audio.
  final int endSample;

  /// Number of payload bit errors the LDPC decoder corrected.
  final int ldpcCorrections;

  /// Equalized payload constellation symbols (I/Q), captured only when the
  /// decoder is asked to (`captureConstellation: true`). Null otherwise, so the
  /// live radio path carries no extra overhead. Empty for the FSK fallback,
  /// which has no constellation.
  final List<Complex>? constellation;

  /// Measured carrier phase drift in degrees per OFDM symbol, derived from the
  /// payload pilots (decision-independent). Small (<~3°) means slow/decision-
  /// limited phase noise (pilots help); large (>~10°) means fast/ICI-limited
  /// (irreducible). Null when pilots are disabled or unavailable.
  final double? phaseDriftDeg;

  const DartDecodeResult({
    required this.header,
    required this.payload,
    required this.crcOk,
    required this.quality,
    required this.durationMs,
    this.endSample = 0,
    this.ldpcCorrections = 0,
    this.constellation,
    this.phaseDriftDeg,
  });

  /// Link-layer frame type derived from the header flags.
  DartFrameType get frameType => DartFlags.frameType(header.flags);

  /// Build a [DartPacketInfo] describing this received frame.
  DartPacketInfo toPacketInfo() {
    final mode = DartMode.values[header.modeIndex.clamp(0, DartMode.modeF.index)];
    final modeParams = DartModeParams.fromMode(mode);
    return DartPacketInfo(
      direction: DartDirection.receive,
      timestamp: DateTime.now(),
      modeIndex: header.modeIndex,
      constellation: modeParams.constellation,
      ldpcRate: modeParams.ldpcRate,
      modeDescription: modeParams.description,
      frameType: frameType,
      source: header.source,
      destination: header.destination,
      seqNum: header.seqNum,
      payloadLength: payload.length,
      broadcast: header.flags & DartFlags.broadcast != 0,
      durationMs: durationMs,
      crcOk: crcOk,
      quality: quality,
    );
  }
}

/// DART modem - complete TX/RX implementation.
class DartModem {
  /// OFDM parameters.
  final DartOfdmParams ofdmParams;

  /// Preamble generator/detector.
  late final DartPreamble preamble;

  /// OFDM modulator/demodulator.
  late final DartOfdm ofdm;

  /// Constant-envelope 4-FSK modem for Mode F (amplitude-hostile fallback).
  late final DartFsk fsk;

  /// Guard interval (samples) before the preamble and after the payload.
  /// Lets the SBC codec filterbank warm up / flush so the frame survives the
  /// Bluetooth audio round-trip. ~2 SBC frames (128 samples each).
  static const int _guardSamples = 256;

  /// Payload pilot spacing: one known pilot OFDM symbol is inserted before every
  /// [_pilotInterval] data symbols (plus a trailing pilot), giving the receiver
  /// a *decision-independent* phase reference to track carrier phase noise — the
  /// dominant real-world impairment. Costs ~1/interval of payload throughput.
  static const int _pilotInterval = 8;

  /// When true, the payload carries interspersed pilot symbols for
  /// decision-independent phase tracking. Off = the previous decision-directed-
  /// only path (useful for A/B testing the pilot benefit).
  final bool pilotsEnabled;

  DartModem({
    DartOfdmParams? params,
    DartFskParams? fskParams,
    this.pilotsEnabled = true,
  }) : ofdmParams = params ?? DartOfdmParams() {
    preamble = DartPreamble(ofdmParams: ofdmParams);
    ofdm = DartOfdm(ofdmParams);
    fsk = DartFsk(fskParams ?? DartFskParams());
  }

  /// Known pilot data symbols (reuse the preamble's BPSK PN — known to both
  /// ends), and the corresponding modulated (DFT-spread) pilot OFDM symbol.
  late final List<Complex> _pilotSymbols = preamble.channelEstSymbols;
  late final Float64List _pilotOfdm = ofdm.modulateSymbol(_pilotSymbols);

  /// On-air payload layout for [numData] data OFDM symbols: each entry is a data
  /// index, or -1 for a pilot slot. Shared by the encoder and decoder so both
  /// agree on where the pilots sit.
  static List<int> _pilotLayout(int numData, int interval) {
    final layout = <int>[];
    for (int i = 0; i < numData; i++) {
      if (i % interval == 0) layout.add(-1); // pilot before each group
      layout.add(i);
    }
    layout.add(-1); // trailing pilot so every data symbol is bracketed
    return layout;
  }

  /// Encode a frame: payload bytes → PCM audio samples.
  /// The header is sent at mode 0 (OFDM) or Mode F (FSK); the payload at [mode].
  Int16List encode({
    required Uint8List payload,
    required DartMode mode,
    String source = '',
    String destination = '',
    int seqNum = 0,
    int flags = 0x04,
  }) {
    if (mode == DartMode.modeF) {
      return _encodeFsk(
        payload: payload,
        source: source,
        destination: destination,
        seqNum: seqNum,
        flags: flags,
      );
    }
    final modeParams = DartModeParams.fromMode(mode);

    // --- Build header ---
    final header = DartHeader(
      modeIndex: mode.index,
      payloadLength: payload.length,
      seqNum: seqNum,
      flags: flags,
      source: source,
      destination: destination,
    );

    // --- Encode header (mode 0: BPSK, LDPC 1/2) ---
    final headerBits = header.toBits(); // 144 bits
    final headerCodedBits = _ldpcEncodeBlock(headerBits, LdpcRate.r1_2);
    final headerSymbols = _mapToSymbols(headerCodedBits, ConstellationType.bpsk);
    final headerOfdmSymbols = _modulateSymbols(headerSymbols);

    // --- Encode payload ---
    // Prepend CRC-32 to payload
    final payloadWithCrc = _appendCrc32(payload);
    // Convert to bits
    final payloadBits = _bytesToBits(payloadWithCrc);
    // LDPC encode (pad to block boundaries)
    final payloadCodedBits = _ldpcEncodeStream(payloadBits, modeParams.ldpcRate);
    // Interleave
    final interleavedBits = _interleave(payloadCodedBits);
    // Map to symbols
    final payloadSymbols = _mapToSymbols(interleavedBits, modeParams.constellation);
    // Modulate to OFDM symbols, then (optionally) intersperse known pilot
    // symbols so the receiver can track carrier phase noise independently of
    // its decisions.
    final payloadDataOfdm = _modulateSymbols(payloadSymbols);
    final payloadOfdmSymbols =
        pilotsEnabled ? _insertPayloadPilots(payloadDataOfdm) : payloadDataOfdm;

    // --- Assemble frame ---
    // Lead-in silence lets the SBC filterbank warm up before the preamble,
    // and a short tail flushes the codec's group delay so the last OFDM
    // symbol survives the round-trip.
    final preambleSamples = preamble.generate();
    final leadIn = Float64List(_guardSamples);
    final tail = Float64List(_guardSamples);

    final allSymbols = <Float64List>[
      leadIn,
      preambleSamples,
      ...headerOfdmSymbols,
      ...payloadOfdmSymbols,
      tail,
    ];

    return DartOfdm.toPcm(allSymbols);
  }

  /// Encode a Mode F (constant-envelope 4-FSK) frame. Header and payload are
  /// both FSK so the entire frame is amplitude-immune. Shares the same header
  /// format, LDPC, interleaving, and CRC as the OFDM path.
  Int16List _encodeFsk({
    required Uint8List payload,
    required String source,
    required String destination,
    required int seqNum,
    required int flags,
  }) {
    // Header carries the Mode F index so the receiver knows the format.
    final header = DartHeader(
      modeIndex: DartMode.modeF.index,
      payloadLength: payload.length,
      seqNum: seqNum,
      flags: flags,
      source: source,
      destination: destination,
    );

    // Header: 144 bits → LDPC R1/2 → 648 coded bits → FSK.
    final headerCodedBits = _ldpcEncodeBlock(header.toBits(), LdpcRate.r1_2);
    final headerFsk = fsk.modulate(headerCodedBits);

    // Payload: CRC-32 → bits → LDPC R1/2 → interleave → FSK.
    final payloadWithCrc = _appendCrc32(payload);
    final payloadBits = _bytesToBits(payloadWithCrc);
    final payloadCodedBits = _ldpcEncodeStream(payloadBits, LdpcRate.r1_2);
    final interleavedBits = _interleave(payloadCodedBits);
    final payloadFsk = fsk.modulate(interleavedBits);

    // Assemble: guard + preamble + FSK header + FSK payload + guard.
    final preambleSamples = preamble.generate();

    // The FSK header/payload are constant-envelope (amplitude 1.0, RMS ~0.707).
    // The preamble was scaled for the *OFDM* data path, whose per-symbol RMS is
    // far lower (high-PAPR IFFT output). Left as-is, the preamble is much
    // quieter than the FSK payload it precedes, so in a Mode F frame it becomes
    // the first casualty of channel noise — detection fails at the very SNR the
    // amplitude-immune FSK payload is designed to survive. Scale the preamble
    // up to match the FSK payload RMS so the whole frame is uniform amplitude
    // and the preamble is as robust as the payload (correlation detection is
    // energy-normalized, so only the relative level matters).
    final double fskRms = _rmsOf(headerFsk);
    final double preRms = _rmsOf(preambleSamples);
    if (preRms > 1e-12 && fskRms > 1e-12) {
      final double preScale = fskRms / preRms;
      for (int i = 0; i < preambleSamples.length; i++) {
        preambleSamples[i] *= preScale;
      }
    }

    final parts = <Float64List>[
      Float64List(_guardSamples),
      preambleSamples,
      headerFsk,
      payloadFsk,
      Float64List(_guardSamples),
    ];
    return DartOfdm.toPcm(parts);
  }

  /// Root-mean-square amplitude of a real signal (0 for an empty buffer).
  static double _rmsOf(Float64List x) {
    if (x.isEmpty) return 0;
    double sumSq = 0;
    for (final v in x) {
      sumSq += v * v;
    }
    return math.sqrt(sumSq / x.length);
  }

  /// Decode a frame from PCM audio samples.
  /// Returns null if no valid frame found. Tries the OFDM path (modes 0–5)
  /// first, then the constant-envelope Mode F (FSK) fallback.
  /// When [captureConstellation] is true, the result includes the equalized
  /// payload symbols (for constellation plots / diagnostics).
  DartDecodeResult? decode(Int16List pcm, {bool captureConstellation = false}) {
    final rxSamples = DartOfdm.fromPcm(pcm);
    final double durationMs = pcm.length * 1000.0 / ofdmParams.sampleRate;

    // Detect preamble (shared by both waveforms).
    final detection = preamble.detectDetailed(rxSamples);
    if (detection.position < 0) return null;

    // Try OFDM first; fall back to Mode F (FSK).
    return _decodeOfdm(rxSamples, detection, durationMs,
            captureConstellation: captureConstellation) ??
        _decodeFsk(rxSamples, detection, durationMs);
  }

  /// Decode an OFDM frame (modes 0–5). Returns null if it does not decode as a
  /// valid OFDM frame.
  DartDecodeResult? _decodeOfdm(
    Float64List rxSamples,
    PreambleDetection detection,
    double durationMs, {
    bool captureConstellation = false,
  }) {
    final int preambleStart = detection.position;

    // --- Channel estimation ---
    final preambleSlice = Float64List.sublistView(
      rxSamples,
      preambleStart,
      math.min(preambleStart + preamble.preambleSamples, rxSamples.length),
    );
    if (preambleSlice.length < preamble.preambleSamples) return null;
    final channelEst = preamble.estimateChannel(preambleSlice);

    // --- Decode header (mode 0: BPSK, LDPC R1/2) ---
    final int headerStart = preambleStart + preamble.preambleSamples;
    // Header: 144 info bits → 1 LDPC block (K=324, N=648) → 648 BPSK symbols
    final headerLdpcCode = DartLdpc.getCode(LdpcRate.r1_2);
    final int headerSymbolCount = headerLdpcCode.n; // 648 coded BPSK symbols
    final int headerOfdmCount =
        (headerSymbolCount + ofdmParams.numDataCarriers - 1) ~/
        ofdmParams.numDataCarriers;

    final headerRxSymbols = _demodulateOfdmSymbols(
      rxSamples, headerStart, headerOfdmCount, channelEst,
    );
    if (headerRxSymbols == null) return null;

    // Soft-demap header (BPSK)
    final constellation = Constellation.get(ConstellationType.bpsk);
    final headerLlrs = Float64List(headerSymbolCount);
    final double noiseVar = _estimateNoiseVariance(headerRxSymbols);
    for (int i = 0; i < headerSymbolCount && i < headerRxSymbols.length; i++) {
      final softBits = constellation.softDemap(headerRxSymbols[i], noiseVar);
      headerLlrs[i] = softBits[0];
    }

    // LDPC decode header blocks
    final headerDecodedBits = _ldpcDecodeStream(headerLlrs, LdpcRate.r1_2, 144);
    if (headerDecodedBits == null) return null;

    // Parse header
    final header = DartHeader.fromBits(headerDecodedBits);
    if (header == null) return null;

    // If the header announces Mode F, this isn't an OFDM frame — let the FSK
    // path handle it.
    if (header.modeIndex == DartMode.modeF.index) return null;

    // --- Decision-directed channel refinement ---
    // The header decoded correctly, so we know the transmitted header symbols
    // exactly. Re-encode them and use them as an extended pilot to refine the
    // channel estimate (especially phase), averaged over all header OFDM
    // symbols. This corrects residual SBC phase drift that a single preamble
    // snapshot misses — critical for QPSK/8PSK/QAM payloads.
    final refinedChannel = _refineChannelFromHeader(
      rxSamples,
      headerStart,
      headerOfdmCount,
      headerDecodedBits,
      channelEst,
    );

    // --- Decode payload ---
    final payloadMode = DartMode.values[header.modeIndex.clamp(0, 5)];
    final modeParams = DartModeParams.fromMode(payloadMode);
    final payloadConst = Constellation.get(modeParams.constellation);
    // Compute expected payload size
    final int payloadBytesWithCrc = header.payloadLength + 4; // +4 for CRC32
    final int payloadBitsNeeded = payloadBytesWithCrc * 8;
    final ldpcCode = DartLdpc.getCode(modeParams.ldpcRate);
    final int numLdpcBlocks =
        (payloadBitsNeeded + ldpcCode.k - 1) ~/ ldpcCode.k;
    final int totalCodedBits = numLdpcBlocks * ldpcCode.n;
    final int totalSymbols =
        (totalCodedBits + modeParams.bitsPerSymbol - 1) ~/
        modeParams.bitsPerSymbol;
    final int payloadOfdmCount =
        (totalSymbols + ofdmParams.numDataCarriers - 1) ~/
        ofdmParams.numDataCarriers;

    final int payloadStart =
        headerStart + headerOfdmCount * ofdmParams.symbolLength;
    // The payload may carry interspersed pilot symbols; account for them in the
    // on-air span and use them to track carrier phase noise.
    final int payloadOnAir = pilotsEnabled
        ? _pilotLayout(payloadOfdmCount, _pilotInterval).length
        : payloadOfdmCount;
    final Float64List driftHolder = Float64List(1);
    final payloadRxSymbols = pilotsEnabled
        ? _demodulateOfdmSymbolsPilots(
            rxSamples, payloadStart, payloadOfdmCount, refinedChannel,
            payloadConst,
            noiseVar: noiseVar,
            driftOut: driftHolder,
          )
        : _demodulateOfdmSymbolsTracked(
            rxSamples, payloadStart, payloadOfdmCount, refinedChannel,
            payloadConst,
            noiseVar: noiseVar,
          );
    if (payloadRxSymbols == null) return null;

    // Soft-demap payload
    final payloadLlrs = Float64List(totalCodedBits);
    int llrIdx = 0;
    for (int i = 0; i < payloadRxSymbols.length && llrIdx < totalCodedBits; i++) {
      final softBits = payloadConst.softDemap(payloadRxSymbols[i], noiseVar);
      for (int b = 0; b < softBits.length && llrIdx < totalCodedBits; b++) {
        payloadLlrs[llrIdx++] = softBits[b];
      }
    }

    // Deinterleave
    final deinterleavedLlrs = _deinterleave(payloadLlrs);

    // LDPC decode (counting the bit errors corrected)
    final corrections = Int32List(1);
    final payloadBits = _ldpcDecodeStream(
      deinterleavedLlrs, modeParams.ldpcRate, payloadBitsNeeded,
      corrOut: corrections,
    );
    if (payloadBits == null) return null;

    // Convert bits to bytes and verify CRC-32
    final payloadBytes = _bitsToBytes(payloadBits);
    if (payloadBytes.length < 4) return null;

    final dataBytes = Uint8List.sublistView(
      payloadBytes, 0, payloadBytes.length - 4,
    );
    final int rxCrc = _extractCrc32(payloadBytes);
    final int computedCrc = _computeCrc32(dataBytes);

    // --- Signal quality metrics ---
    final quality = _measureQuality(
      payloadRxSymbols,
      payloadConst,
      refinedChannel,
      detection.correlation,
    );

    return DartDecodeResult(
      header: header,
      payload: dataBytes.sublist(0, header.payloadLength.clamp(0, dataBytes.length)),
      crcOk: rxCrc == computedCrc,
      quality: quality,
      durationMs: durationMs,
      endSample: payloadStart + payloadOnAir * ofdmParams.symbolLength,
      ldpcCorrections: corrections[0],
      constellation: captureConstellation ? payloadRxSymbols : null,
      phaseDriftDeg: pilotsEnabled ? driftHolder[0] : null,
    );
  }

  /// Decode a Mode F (constant-envelope 4-FSK) frame. Returns null if the
  /// header/payload does not decode as a valid Mode F frame.
  DartDecodeResult? _decodeFsk(
    Float64List rxSamples,
    PreambleDetection detection,
    double durationMs,
  ) {
    final int headerStart = detection.position + preamble.preambleSamples;

    // Header: 648 coded bits (LDPC R1/2 of 144 info bits).
    final headerCode = DartLdpc.getCode(LdpcRate.r1_2);
    final int headerCodedBits = headerCode.n; // 648
    if (headerStart + fsk.samplesForBits(headerCodedBits) > rxSamples.length) {
      return null;
    }

    final headerLlrs = fsk.demodulateSoft(rxSamples, headerStart, headerCodedBits);
    final headerBits = _ldpcDecodeStream(headerLlrs, LdpcRate.r1_2, 144);
    if (headerBits == null) return null;

    final header = DartHeader.fromBits(headerBits);
    if (header == null) return null;
    // Only accept frames that actually announce Mode F.
    if (header.modeIndex != DartMode.modeF.index) return null;

    // Payload layout mirrors the OFDM path but uses LDPC R1/2 + FSK.
    final int payloadBytesWithCrc = header.payloadLength + 4;
    final int payloadBitsNeeded = payloadBytesWithCrc * 8;
    final ldpcCode = DartLdpc.getCode(LdpcRate.r1_2);
    final int numLdpcBlocks =
        (payloadBitsNeeded + ldpcCode.k - 1) ~/ ldpcCode.k;
    final int totalCodedBits = numLdpcBlocks * ldpcCode.n;

    final int payloadStart = headerStart + fsk.samplesForBits(headerCodedBits);
    if (payloadStart + fsk.samplesForBits(totalCodedBits) > rxSamples.length) {
      return null;
    }

    final payloadLlrs =
        fsk.demodulateSoft(rxSamples, payloadStart, totalCodedBits);
    final deinterleavedLlrs = _deinterleave(payloadLlrs);
    final corrections = Int32List(1);
    final payloadBits = _ldpcDecodeStream(
      deinterleavedLlrs, LdpcRate.r1_2, payloadBitsNeeded,
      corrOut: corrections,
    );
    if (payloadBits == null) return null;

    final payloadBytes = _bitsToBytes(payloadBits);
    if (payloadBytes.length < 4) return null;
    final dataBytes = Uint8List.sublistView(
      payloadBytes, 0, payloadBytes.length - 4,
    );
    final int rxCrc = _extractCrc32(payloadBytes);
    final int computedCrc = _computeCrc32(dataBytes);

    // Quality: FSK has no constellation EVM, so derive SNR from tone
    // separation and report the preamble correlation.
    final int numSymbols = (totalCodedBits + 1) ~/ 2;
    final double snrDb = fsk.estimateSnrDb(rxSamples, payloadStart, numSymbols);
    final quality = DartSignalQuality(
      evmPercent: snrDb > 0 ? (100.0 / (1 + snrDb)) : 99.0,
      snrDb: snrDb,
      preambleCorrelation: detection.correlation,
      channelGainDb: 0.0, // not measured for non-coherent FSK
    );

    return DartDecodeResult(
      header: header,
      payload: dataBytes.sublist(0, header.payloadLength.clamp(0, dataBytes.length)),
      crcOk: rxCrc == computedCrc,
      quality: quality,
      durationMs: durationMs,
      endSample: payloadStart + fsk.samplesForBits(totalCodedBits),
      ldpcCorrections: corrections[0],
    );
  }

  /// Measure signal-quality metrics from the equalized payload symbols.
  DartSignalQuality _measureQuality(
    List<Complex> rxSymbols,
    Constellation constellation,
    List<Complex> channelEst,
    double preambleCorrelation,
  ) {
    // EVM: RMS error to the nearest constellation point, normalized to the
    // reference RMS amplitude (which is ~1.0 for our unit-power constellations).
    double errPow = 0;
    double refPow = 0;
    int count = 0;
    for (final rx in rxSymbols) {
      final Complex ref = constellation.nearestPoint(rx);
      final double di = rx.i - ref.i;
      final double dq = rx.q - ref.q;
      errPow += di * di + dq * dq;
      refPow += ref.magnitudeSquared;
      count++;
    }
    double evm = 1.0;
    if (count > 0 && refPow > 1e-12) {
      evm = math.sqrt(errPow / refPow);
    }
    final double evmPercent = (evm * 100).clamp(0.0, 999.0);

    // SNR (dB) estimated from EVM: SNR ≈ -20·log10(EVM)
    final double snrDb = evm > 1e-6 ? -20 * _log10(evm) : 60.0;

    // Average channel gain |H| across active subcarriers, in dB.
    double gainSum = 0;
    for (final h in channelEst) {
      gainSum += h.magnitude;
    }
    final double avgGain = channelEst.isEmpty ? 0 : gainSum / channelEst.length;
    final double channelGainDb = avgGain > 1e-9 ? 20 * _log10(avgGain) : -60.0;

    return DartSignalQuality(
      evmPercent: evmPercent,
      snrDb: snrDb,
      preambleCorrelation: preambleCorrelation,
      channelGainDb: channelGainDb,
    );
  }

  static double _log10(double x) => math.log(x) / math.ln10;

  // --- Private TX helpers ---

  /// LDPC-encode a single block (pad if needed).
  Uint8List _ldpcEncodeBlock(Uint8List infoBits, LdpcRate rate) {
    final code = DartLdpc.getCode(rate);
    // Pad info bits to code.k
    final padded = Uint8List(code.k);
    padded.setRange(0, math.min(infoBits.length, code.k), infoBits);
    return DartLdpc.encode(code, padded);
  }

  /// LDPC-encode a bit stream (multiple blocks, padded).
  Uint8List _ldpcEncodeStream(Uint8List bits, LdpcRate rate) {
    final code = DartLdpc.getCode(rate);
    final int numBlocks = (bits.length + code.k - 1) ~/ code.k;
    final output = Uint8List(numBlocks * code.n);

    for (int b = 0; b < numBlocks; b++) {
      final int start = b * code.k;
      final block = Uint8List(code.k);
      final int copyLen = math.min(code.k, bits.length - start);
      if (copyLen > 0) {
        block.setRange(0, copyLen, bits, start);
      }
      final coded = DartLdpc.encode(code, block);
      output.setRange(b * code.n, (b + 1) * code.n, coded);
    }
    return output;
  }

  /// Map coded bits to constellation symbols.
  List<Complex> _mapToSymbols(Uint8List bits, ConstellationType type) {
    final constellation = Constellation.get(type);
    final int bps = constellation.bitsPerSymbol;
    // Pad bits to multiple of bps
    final int paddedLen = ((bits.length + bps - 1) ~/ bps) * bps;
    final padded = Uint8List(paddedLen);
    padded.setRange(0, bits.length, bits);
    return constellation.mapBits(padded);
  }

  /// Modulate a list of data symbols into OFDM symbols (time-domain).
  List<Float64List> _modulateSymbols(List<Complex> symbols) {
    final int carriersPerSymbol = ofdmParams.numDataCarriers;
    final int numOfdmSymbols =
        (symbols.length + carriersPerSymbol - 1) ~/ carriersPerSymbol;
    final ofdmSymbols = <Float64List>[];

    for (int s = 0; s < numOfdmSymbols; s++) {
      final int start = s * carriersPerSymbol;
      final block = List<Complex>.filled(carriersPerSymbol, const Complex(0, 0));
      for (int i = 0; i < carriersPerSymbol && start + i < symbols.length; i++) {
        block[i] = symbols[start + i];
      }
      ofdmSymbols.add(ofdm.modulateSymbol(block));
    }
    return ofdmSymbols;
  }

  /// Block bit interleaver.
  Uint8List _interleave(Uint8List bits) {
    if (bits.isEmpty) return bits;
    // Interleave with a stride that spreads adjacent bits apart.
    // Block size = 648 (matches LDPC block). Write columns, read rows.
    const int blockSize = 648;
    final int numBlocks = (bits.length + blockSize - 1) ~/ blockSize;
    final output = Uint8List(numBlocks * blockSize);

    // Number of columns in the interleaver matrix
    const int numCols = 24; // chosen to break SBC frame-boundary bursts
    final int numRows = (blockSize + numCols - 1) ~/ numCols;

    for (int blk = 0; blk < numBlocks; blk++) {
      final int base = blk * blockSize;
      // Write row-by-row, read column-by-column
      for (int col = 0; col < numCols; col++) {
        for (int row = 0; row < numRows; row++) {
          final int readIdx = base + row * numCols + col;
          final int writeIdx = base + col * numRows + row;
          if (writeIdx < output.length && readIdx < bits.length) {
            output[writeIdx] = bits[readIdx];
          }
        }
      }
    }
    return Uint8List.fromList(output.sublist(0, bits.length));
  }

  // --- Private RX helpers ---

  /// Demodulate a sequence of OFDM symbols from the received signal.
  List<Complex>? _demodulateOfdmSymbols(
    Float64List rxSamples,
    int startSample,
    int numOfdmSymbols,
    List<Complex> channelEst,
  ) {
    final int symbolLen = ofdmParams.symbolLength;
    final int needed = startSample + numOfdmSymbols * symbolLen;
    if (rxSamples.length < needed) return null;

    final allSymbols = <Complex>[];
    for (int s = 0; s < numOfdmSymbols; s++) {
      final int offset = startSample + s * symbolLen;
      final slice = Float64List.sublistView(rxSamples, offset, offset + symbolLen);
      final symbols = ofdm.demodulateSymbol(slice, channelEst);
      allSymbols.addAll(symbols);
    }
    return allSymbols;
  }

  /// Demodulate OFDM symbols with decision-directed common-phase-error (CPE)
  /// tracking.
  ///
  /// The refined channel estimate captures only the *average* phase over the
  /// header. Over a real radio/SBC link the receive and transmit sample clocks
  /// differ slightly, so the constellation slowly rotates as the payload
  /// progresses (a residual carrier-frequency offset). A single static channel
  /// estimate cannot follow that drift, which shows up as a sheared/rotated
  /// constellation and lost QPSK/8PSK/QAM frames.
  ///
  /// This tracker runs a first-order phase-locked loop across the OFDM symbols:
  /// for each symbol it de-rotates by the running phase estimate, measures the
  /// residual common phase from decisions against [constellation] (a
  /// pilot-less, decision-directed error), removes it from the current symbol,
  /// and carries the accumulated phase forward to predict the next symbol. This
  /// follows a linear phase ramp (constant CFO) with a one-symbol lag and
  /// recovers the modes that a static estimate loses.
  List<Complex>? _demodulateOfdmSymbolsTracked(
    Float64List rxSamples,
    int startSample,
    int numOfdmSymbols,
    List<Complex> channelEst,
    Constellation constellation, {
    double noiseVar = 0.0,
  }) {
    final int symbolLen = ofdmParams.symbolLength;
    final int needed = startSample + numOfdmSymbols * symbolLen;
    if (rxSamples.length < needed) return null;

    final allSymbols = <Complex>[];
    // Running accumulated phase estimate (radians), tracking the drift.
    double phaseAccum = 0.0;
    for (int s = 0; s < numOfdmSymbols; s++) {
      final int offset = startSample + s * symbolLen;
      final slice =
          Float64List.sublistView(rxSamples, offset, offset + symbolLen);
      final symbols = ofdm.demodulateSymbol(slice, channelEst, noiseVar: noiseVar);

      // Predict this symbol's phase from the running estimate and de-rotate.
      final double cosP = math.cos(-phaseAccum);
      final double sinP = math.sin(-phaseAccum);
      for (int i = 0; i < symbols.length; i++) {
        final Complex c = symbols[i];
        symbols[i] =
            Complex(c.i * cosP - c.q * sinP, c.i * sinP + c.q * cosP);
      }

      // Measure the residual common phase error from decisions on the
      // predicted symbols: e = angle( Σ y · conj(x_hat) ).
      double sumRe = 0, sumIm = 0;
      for (final c in symbols) {
        final Complex ref = constellation.nearestPoint(c);
        sumRe += c.i * ref.i + c.q * ref.q; // Re(y · conj(ref))
        sumIm += c.q * ref.i - c.i * ref.q; // Im(y · conj(ref))
      }
      if (sumRe != 0 || sumIm != 0) {
        final double residual = math.atan2(sumIm, sumRe);
        // Remove the residual from the current symbol.
        final double cosR = math.cos(-residual);
        final double sinR = math.sin(-residual);
        for (int i = 0; i < symbols.length; i++) {
          final Complex c = symbols[i];
          symbols[i] =
              Complex(c.i * cosR - c.q * sinR, c.i * sinR + c.q * cosR);
        }
        // Carry the correction forward so the next symbol is predicted at the
        // updated absolute phase (first-order ramp tracking).
        phaseAccum += residual;
      }

      allSymbols.addAll(symbols);
    }
    return allSymbols;
  }

  /// Insert known pilot OFDM symbols into a payload data-symbol stream.
  List<Float64List> _insertPayloadPilots(List<Float64List> dataOfdm) {
    final layout = _pilotLayout(dataOfdm.length, _pilotInterval);
    final out = <Float64List>[];
    for (final slot in layout) {
      out.add(slot < 0 ? _pilotOfdm : dataOfdm[slot]);
    }
    return out;
  }

  /// Demodulate a pilot-interspersed payload, tracking carrier phase noise from
  /// the known pilot symbols (decision-independent) and interpolating the phase
  /// correction across the data symbols between pilots. Returns the equalized,
  /// phase-corrected data symbols (pilots consumed). This is the primary defense
  /// against the FM audio path's carrier phase noise.
  List<Complex>? _demodulateOfdmSymbolsPilots(
    Float64List rxSamples,
    int startSample,
    int numData,
    List<Complex> channelEst,
    Constellation constellation, {
    double noiseVar = 0.0,
    Float64List? driftOut,
  }) {
    final int symbolLen = ofdmParams.symbolLength;
    final layout = _pilotLayout(numData, _pilotInterval);
    final int total = layout.length;
    if (rxSamples.length < startSample + total * symbolLen) return null;

    // Pass 1: demodulate every on-air symbol (equalized + de-spread).
    final raw = List<List<Complex>>.filled(total, const <Complex>[]);
    for (int p = 0; p < total; p++) {
      final int offset = startSample + p * symbolLen;
      final slice =
          Float64List.sublistView(rxSamples, offset, offset + symbolLen);
      raw[p] = ofdm.demodulateSymbol(slice, channelEst, noiseVar: noiseVar);
    }

    // Pass 2: single forward sweep. At each pilot, measure the absolute phase
    // from the known symbols and *anchor* the running estimate to it
    // (decision-independent — this bounds drift and bootstraps the high-order
    // modes where decision-directed tracking alone fails). Between pilots, track
    // per-symbol with decision direction for fine, fast correction.
    final out = <Complex>[];
    double phaseAccum = 0.0;
    bool anchored = false;
    // Collect (position, unwrapped absolute phase) at pilots to measure the
    // carrier phase-drift rate (a decision-independent diagnostic).
    final pilotPos = <int>[];
    final pilotAbsPhase = <double>[];
    for (int p = 0; p < total; p++) {
      if (layout[p] == -1) {
        // Pilot: measure θ = angle( Σ y · conj(pilot) ) and anchor to it.
        double sumRe = 0, sumIm = 0;
        for (int m = 0; m < _pilotSymbols.length && m < raw[p].length; m++) {
          final Complex c = raw[p][m];
          final Complex ref = _pilotSymbols[m];
          sumRe += c.i * ref.i + c.q * ref.q;
          sumIm += c.q * ref.i - c.i * ref.q;
        }
        final double theta = math.atan2(sumIm, sumRe);
        if (!anchored) {
          phaseAccum = theta;
          anchored = true;
        } else {
          // Unwrap toward the running estimate.
          phaseAccum +=
              math.atan2(math.sin(theta - phaseAccum), math.cos(theta - phaseAccum));
        }
        pilotPos.add(p);
        pilotAbsPhase.add(phaseAccum);
        continue;
      }

      // Data: de-rotate by the running phase estimate, then refine per-symbol
      // with a decision-directed residual.
      final syms = raw[p];
      final double cosP = math.cos(-phaseAccum);
      final double sinP = math.sin(-phaseAccum);
      for (int i = 0; i < syms.length; i++) {
        final Complex c = syms[i];
        syms[i] = Complex(c.i * cosP - c.q * sinP, c.i * sinP + c.q * cosP);
      }
      double sumRe = 0, sumIm = 0;
      for (final c in syms) {
        final Complex ref = constellation.nearestPoint(c);
        sumRe += c.i * ref.i + c.q * ref.q;
        sumIm += c.q * ref.i - c.i * ref.q;
      }
      if (sumRe != 0 || sumIm != 0) {
        final double residual = math.atan2(sumIm, sumRe);
        final double cosR = math.cos(-residual);
        final double sinR = math.sin(-residual);
        for (int i = 0; i < syms.length; i++) {
          final Complex c = syms[i];
          syms[i] = Complex(c.i * cosR - c.q * sinR, c.i * sinR + c.q * cosR);
        }
        phaseAccum += residual;
      }
      out.addAll(syms);
    }

    // Estimate the per-symbol carrier phase-drift rate from the pilot phases.
    // For a random-walk phase, the drift over a g-symbol gap has std
    // proportional to sqrt(g); normalizing each gap by sqrt(g) yields the
    // per-symbol RMS drift, which distinguishes slow/decision-limited phase
    // noise (small) from fast/ICI-limited (large).
    if (driftOut != null && driftOut.isNotEmpty) {
      double sumSq = 0;
      int cnt = 0;
      for (int i = 1; i < pilotPos.length; i++) {
        final int g = pilotPos[i] - pilotPos[i - 1];
        if (g <= 0) continue;
        final double perSym =
            (pilotAbsPhase[i] - pilotAbsPhase[i - 1]) / math.sqrt(g);
        sumSq += perSym * perSym;
        cnt++;
      }
      driftOut[0] = cnt > 0 ? math.sqrt(sumSq / cnt) * 180.0 / math.pi : 0.0;
    }
    return out;
  }

  /// Refine the channel estimate using the known (decoded) header symbols.
  ///
  /// Because the header decoded correctly, the transmitted header constellation
  /// symbols are known exactly. Averaging Y[k]/X[k] over all header OFDM symbols
  /// yields a much more accurate H[k] (in particular its phase) than a single
  /// preamble snapshot — this is what makes QPSK/8PSK/QAM survive the SBC codec's
  /// residual phase drift.
  List<Complex> _refineChannelFromHeader(
    Float64List rxSamples,
    int headerStart,
    int headerOfdmCount,
    Uint8List headerInfoBits,
    List<Complex> fallbackChannel,
  ) {
    // Re-encode the header exactly as the transmitter did.
    final headerCodedBits = _ldpcEncodeBlock(headerInfoBits, LdpcRate.r1_2);
    final txSymbols = _mapToSymbols(headerCodedBits, ConstellationType.bpsk);

    final int nc = ofdmParams.numDataCarriers;
    final int symbolLen = ofdmParams.symbolLength;

    // Accumulate Y[k] * conj(X[k]) and |X[k]|^2 per carrier across all symbols.
    final accIQ = List<Complex>.filled(nc, const Complex(0, 0));
    final accPow = Float64List(nc);

    int symIdx = 0; // index into txSymbols (nc per OFDM symbol)
    for (int s = 0; s < headerOfdmCount; s++) {
      final int offset = headerStart + s * symbolLen;
      if (offset + symbolLen > rxSamples.length) break;
      final slice =
          Float64List.sublistView(rxSamples, offset, offset + symbolLen);
      // Raw FFT bins (no equalization).
      final rawBins = ofdm.demodulateSymbolRaw(slice);

      // Reconstruct the transmitted subcarrier values X[k]. The header is
      // DFT-spread, so the tones are the DFT-spread of this OFDM symbol's data
      // symbols — not the data symbols themselves.
      final block = List<Complex>.filled(nc, const Complex(0, 0));
      for (int i = 0; i < nc; i++) {
        block[i] = symIdx + i < txSymbols.length
            ? txSymbols[symIdx + i]
            : const Complex(0, 0);
      }
      final tones = ofdm.dftSpread(block, inverse: false);
      symIdx += nc;

      for (int i = 0; i < nc; i++) {
        final Complex x = tones[i];
        final Complex y = rawBins[i];
        // Y * conj(X)
        accIQ[i] = accIQ[i] +
            Complex(
              y.i * x.i + y.q * x.q,
              y.q * x.i - y.i * x.q,
            );
        accPow[i] += x.magnitudeSquared;
      }
    }

    // H[k] = sum(Y * conj(X)) / sum(|X|^2)
    final refined = List<Complex>.filled(nc, const Complex(0, 0));
    for (int i = 0; i < nc; i++) {
      if (accPow[i] > 1e-9) {
        refined[i] = accIQ[i] / accPow[i];
      } else {
        refined[i] = fallbackChannel[i];
      }
    }
    return refined;
  }

  /// Deinterleave LLRs (inverse of _interleave).
  Float64List _deinterleave(Float64List llrs) {
    if (llrs.isEmpty) return llrs;
    const int blockSize = 648;
    final int numBlocks = (llrs.length + blockSize - 1) ~/ blockSize;
    final padded = Float64List(numBlocks * blockSize);
    padded.setRange(0, llrs.length, llrs);
    final output = Float64List(padded.length);

    const int numCols = 24;
    final int numRows = (blockSize + numCols - 1) ~/ numCols;

    for (int blk = 0; blk < numBlocks; blk++) {
      final int base = blk * blockSize;
      // Inverse: read column-by-column (interleaved order), write row-by-row
      for (int col = 0; col < numCols; col++) {
        for (int row = 0; row < numRows; row++) {
          final int readIdx = base + col * numRows + row;
          final int writeIdx = base + row * numCols + col;
          if (readIdx < padded.length && writeIdx < output.length) {
            output[writeIdx] = padded[readIdx];
          }
        }
      }
    }
    return Float64List.fromList(output.sublist(0, llrs.length));
  }

  /// LDPC decode a stream of LLRs, return decoded info bits.
  /// If [corrOut] (a 1-element array) is provided, the total number of LDPC bit
  /// errors corrected across all blocks is added to `corrOut[0]`.
  Uint8List? _ldpcDecodeStream(
    Float64List llrs,
    LdpcRate rate,
    int infoBitsNeeded, {
    Int32List? corrOut,
  }) {
    final code = DartLdpc.getCode(rate);
    final int numBlocks = (infoBitsNeeded + code.k - 1) ~/ code.k;
    final output = Uint8List(numBlocks * code.k);

    for (int b = 0; b < numBlocks; b++) {
      final int start = b * code.n;
      final blockLlr = Float64List(code.n);
      final int copyLen = math.min(code.n, llrs.length - start);
      if (copyLen > 0) {
        blockLlr.setRange(0, copyLen, llrs, start);
      }
      // Code shortening: any info bits beyond the real payload are known-zero
      // padding (the encoder zero-fills each block to K). Pin their LLRs to a
      // strong positive value (LLR>0 = bit 0) so the belief-propagation decoder
      // treats them as known. Known bits constrain the codeword and improve
      // decoding — the gain is largest for short frames, where padding
      // dominates the block.
      final int realInBlock =
          (infoBitsNeeded - b * code.k).clamp(0, code.k);
      const double knownLlr = 1e6;
      for (int i = realInBlock; i < code.k; i++) {
        blockLlr[i] = knownLlr;
      }
      final decoded = DartLdpc.decode(code, blockLlr, corrOut: corrOut);
      if (decoded == null) return null;
      output.setRange(b * code.k, (b + 1) * code.k, decoded);
    }
    return Uint8List.fromList(output.sublist(0, infoBitsNeeded));
  }

  /// Estimate noise variance from received symbols (for LLR computation).
  double _estimateNoiseVariance(List<Complex> symbols) {
    if (symbols.isEmpty) return 1.0;
    // Estimate from scatter around unit-power constellation points.
    // Use the variance of the magnitude as a rough proxy.
    double sumMagSq = 0;
    for (final s in symbols) {
      sumMagSq += s.magnitudeSquared;
    }
    final double avgPower = sumMagSq / symbols.length;
    // Noise variance ≈ deviation from expected unit power
    // For low SNR this underestimates, but it's a reasonable starting point.
    return math.max(0.01, (avgPower - 1.0).abs() + 0.05);
  }

  // --- Utility functions ---

  /// Append CRC-32 to payload bytes.
  Uint8List _appendCrc32(Uint8List data) {
    final int crc = _computeCrc32(data);
    final output = Uint8List(data.length + 4);
    output.setRange(0, data.length, data);
    output[data.length + 0] = (crc >> 24) & 0xFF;
    output[data.length + 1] = (crc >> 16) & 0xFF;
    output[data.length + 2] = (crc >> 8) & 0xFF;
    output[data.length + 3] = crc & 0xFF;
    return output;
  }

  /// Extract CRC-32 from the last 4 bytes.
  int _extractCrc32(Uint8List data) {
    final int len = data.length;
    return (data[len - 4] << 24) |
        (data[len - 3] << 16) |
        (data[len - 2] << 8) |
        data[len - 1];
  }

  /// Compute CRC-32 (ISO 3309 / ITU-T V.42).
  static int _computeCrc32(Uint8List data) {
    int crc = 0xFFFFFFFF;
    for (int i = 0; i < data.length; i++) {
      crc ^= data[i];
      for (int bit = 0; bit < 8; bit++) {
        if (crc & 1 != 0) {
          crc = (crc >> 1) ^ 0xEDB88320;
        } else {
          crc >>= 1;
        }
      }
    }
    return crc ^ 0xFFFFFFFF;
  }

  /// Convert bytes to a bit array (MSB first).
  static Uint8List _bytesToBits(Uint8List bytes) {
    final bits = Uint8List(bytes.length * 8);
    for (int i = 0; i < bytes.length; i++) {
      for (int b = 7; b >= 0; b--) {
        bits[i * 8 + (7 - b)] = (bytes[i] >> b) & 1;
      }
    }
    return bits;
  }

  /// Convert a bit array back to bytes (MSB first).
  static Uint8List _bitsToBytes(Uint8List bits) {
    final int numBytes = bits.length ~/ 8;
    final bytes = Uint8List(numBytes);
    for (int i = 0; i < numBytes; i++) {
      int val = 0;
      for (int b = 0; b < 8; b++) {
        val = (val << 1) | bits[i * 8 + b];
      }
      bytes[i] = val;
    }
    return bytes;
  }
}
