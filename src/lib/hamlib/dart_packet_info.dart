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
// dart_packet_info.dart - Per-packet metadata for the DART modem.
//
// Captures how each packet was sent or received so the Flutter packet-capture
// tab can display rich diagnostics (mode, rate, signal quality, ARQ state).
//

import 'dart_constellation.dart';
import 'dart_ldpc.dart';

/// Whether a packet was transmitted or received.
enum DartDirection { transmit, receive }

/// The role a frame plays in the link layer.
enum DartFrameType {
  /// User data, connected (ARQ) mode — expects an ACK.
  data,

  /// User data, connectionless (multicast / broadcast / chat) — no ACK.
  datagram,

  /// Positive acknowledgement of a received data frame.
  ack,

  /// Negative acknowledgement (CRC failed) — requests retransmission.
  nack,
}

/// Header flag bit definitions (mirror of the on-air header flags byte).
class DartFlags {
  DartFlags._();

  static const int ack = 0x01;
  static const int nack = 0x02;
  static const int data = 0x04;
  static const int broadcast = 0x08;

  /// Derive a [DartFrameType] from a raw flags byte.
  static DartFrameType frameType(int flags) {
    if (flags & ack != 0) return DartFrameType.ack;
    if (flags & nack != 0) return DartFrameType.nack;
    if (flags & broadcast != 0) return DartFrameType.datagram;
    return DartFrameType.data;
  }
}

/// Measured signal-quality metrics for a received packet.
///
/// All fields are receive-side only; a transmitted packet has no quality data.
class DartSignalQuality {
  /// Error Vector Magnitude (%) of the payload constellation after
  /// equalization — the primary channel-quality indicator. Lower is better.
  final double evmPercent;

  /// SNR (dB) estimated from the EVM (`SNR ≈ -20·log10(EVM)`).
  final double snrDb;

  /// Preamble cross-correlation peak (0..1) — detection confidence.
  final double preambleCorrelation;

  /// Average channel gain |H| across active subcarriers, in dB (relative).
  final double channelGainDb;

  const DartSignalQuality({
    required this.evmPercent,
    required this.snrDb,
    required this.preambleCorrelation,
    required this.channelGainDb,
  });

  @override
  String toString() =>
      'EVM ${evmPercent.toStringAsFixed(1)}%, '
      'SNR ${snrDb.toStringAsFixed(1)} dB, '
      'corr ${preambleCorrelation.toStringAsFixed(2)}, '
      'gain ${channelGainDb.toStringAsFixed(1)} dB';
}

/// Complete metadata describing how a single DART packet was sent or received.
///
/// This is the object the Flutter packet-capture tab consumes to render a row
/// of diagnostics for each packet.
class DartPacketInfo {
  /// Transmit or receive.
  final DartDirection direction;

  /// When the packet was processed.
  final DateTime timestamp;

  /// Payload modulation/coding mode index (0–5).
  final int modeIndex;

  /// Constellation used for the payload.
  final ConstellationType constellation;

  /// LDPC code rate used for the payload.
  final LdpcRate ldpcRate;

  /// Human-readable mode description, e.g. "16QAM R3/4 (~5 kbps)".
  final String modeDescription;

  /// Link-layer role of the frame.
  final DartFrameType frameType;

  /// Source callsign.
  final String source;

  /// Destination callsign (or "*" / empty for broadcast).
  final String destination;

  /// Sequence number (identifies the frame, or the frame being ACK/NACK'd).
  final int seqNum;

  /// Payload length in bytes (0 for ACK/NACK).
  final int payloadLength;

  /// Whether this was a connectionless (multicast/broadcast) transmission.
  final bool broadcast;

  /// On-air duration of the frame in milliseconds.
  final double durationMs;

  /// Number of times this frame had been retransmitted (0 = first attempt).
  final int retransmitCount;

  /// True when the payload CRC verified (receive side). Always true for TX.
  final bool crcOk;

  /// Signal-quality metrics (receive side only; null for transmit).
  final DartSignalQuality? quality;

  const DartPacketInfo({
    required this.direction,
    required this.timestamp,
    required this.modeIndex,
    required this.constellation,
    required this.ldpcRate,
    required this.modeDescription,
    required this.frameType,
    required this.source,
    required this.destination,
    required this.seqNum,
    required this.payloadLength,
    required this.broadcast,
    required this.durationMs,
    this.retransmitCount = 0,
    this.crcOk = true,
    this.quality,
  });

  /// A compact one-line summary suitable for a capture-log row.
  String summary() {
    final dir = direction == DartDirection.transmit ? 'TX' : 'RX';
    final buf = StringBuffer()
      ..write('$dir ')
      ..write(frameType.name.toUpperCase().padRight(8))
      ..write('$source→$destination ')
      ..write('seq=$seqNum ')
      ..write('mode=$modeIndex ($modeDescription) ')
      ..write('${payloadLength}B ')
      ..write('${durationMs.toStringAsFixed(0)}ms');
    if (retransmitCount > 0) buf.write(' rtx=$retransmitCount');
    if (direction == DartDirection.receive) {
      buf.write(crcOk ? ' CRC=OK' : ' CRC=FAIL');
      if (quality != null) buf.write(' [$quality]');
    }
    return buf.toString();
  }

  @override
  String toString() => summary();
}
