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
// dart_link.dart - DART link layer: connectionless datagrams + ARQ.
//
// Two modes of operation:
//
// 1. Connectionless (multicast / broadcast / chat) — fire-and-forget. No ACK is
//    expected. Rate is fixed or set manually. This matches common ham usage
//    where packets go out to everyone (APRS-style, group chat, beacons).
//
// 2. Connected (ARQ) — reliable delivery with a sliding send/receive window
//    (selective repeat). Up to `windowSize` frames may be in flight at once;
//    each is ACK'd or NACK'd individually by sequence number, and only the lost
//    frames are retransmitted. The receiver buffers out-of-order frames and
//    delivers payloads to the application strictly in order. Rate adapts up on
//    a run of clean ACKs and down on any NACK.
//
// Every transmitted and received packet carries a DartPacketInfo describing how
// it was sent/received (mode, rate, signal quality, ARQ state) so the Flutter
// packet-capture tab can display it.
//

import 'dart:typed_data';

import 'dart_modem.dart';
import 'dart_packet_info.dart';

/// A frame ready to transmit, plus its descriptive metadata.
class DartTxFrame {
  /// PCM audio samples to play out to the radio.
  final Int16List pcm;

  /// Metadata describing this transmission (for the capture log).
  final DartPacketInfo info;

  const DartTxFrame({required this.pcm, required this.info});
}

/// The outcome of feeding a received PCM buffer to [DartLink.receive].
class DartRxEvent {
  /// Metadata about the received frame.
  final DartPacketInfo info;

  /// User payloads delivered to the application, strictly in order. Usually
  /// empty (ACK/NACK) or a single element; may contain several when a buffered
  /// gap is filled and multiple queued frames become deliverable at once.
  final List<Uint8List> deliveredPayloads;

  /// A frame the link layer wants transmitted in response — an ACK/NACK (when
  /// we received data) or a selective retransmission (when we received a NACK).
  /// Null if nothing needs to be sent.
  final DartTxFrame? response;

  /// True if this frame was an ACK for one of our outstanding frames.
  final bool ackReceived;

  /// True if this frame was a NACK for one of our outstanding frames.
  final bool nackReceived;

  const DartRxEvent({
    required this.info,
    this.deliveredPayloads = const [],
    this.response,
    this.ackReceived = false,
    this.nackReceived = false,
  });

  /// The first delivered payload, or null if none.
  Uint8List? get payload =>
      deliveredPayloads.isEmpty ? null : deliveredPayloads.first;

  /// Whether any user payload was delivered.
  bool get delivered => deliveredPayloads.isNotEmpty;
}

/// Configuration for a [DartLink] endpoint.
class DartLinkConfig {
  /// This station's callsign.
  final String callsign;

  /// Starting payload mode for connected/adaptive sessions.
  final DartMode initialMode;

  /// When true, connected transmissions adapt their rate from ACK/NACK.
  /// When false, the mode is fixed (manual control).
  final bool adaptive;

  /// Consecutive clean ACKs required before bumping the rate up.
  final int rateUpThreshold;

  /// Maximum retransmission attempts per frame before giving up.
  final int maxRetransmits;

  /// Sliding-window size — the maximum number of unacknowledged frames that
  /// may be in flight at once. 1 = stop-and-wait.
  final int windowSize;

  /// When true, the constant-envelope Mode F fallback sits at the bottom of the
  /// rate ladder, so a link that keeps failing at mode 0 automatically drops to
  /// the amplitude-immune waveform.
  final bool allowModeF;

  const DartLinkConfig({
    required this.callsign,
    this.initialMode = DartMode.mode1,
    this.adaptive = true,
    this.rateUpThreshold = 3,
    this.maxRetransmits = 5,
    this.windowSize = 4,
    this.allowModeF = true,
  });
}

/// An outstanding reliable frame in the send window.
class _SendSlot {
  final Uint8List payload;
  final String destination;
  final int seqNum;
  int retransmits = 0;
  bool acked = false;

  _SendSlot({
    required this.payload,
    required this.destination,
    required this.seqNum,
  });
}

/// DART link layer providing connectionless and selective-repeat ARQ delivery.
class DartLink {
  /// The underlying modem (encode/decode).
  final DartModem modem;

  /// Link configuration.
  final DartLinkConfig config;

  /// Current payload mode used for connected/adaptive transmissions.
  DartMode currentMode;

  // --- Send-side window state ---
  final Map<int, _SendSlot> _sendWindow = {};
  int _sendBase = 0; // lowest unacknowledged sequence number
  int _nextSeq = 0; // next reliable sequence number to assign
  int _datagramSeq = 0; // independent sequence space for connectionless frames
  int _ackStreak = 0;

  // --- Receive-side window state ---
  int _recvBase = 0; // next in-order sequence number expected
  final Map<int, Uint8List> _recvBuffer = {}; // buffered out-of-order frames

  DartLink({DartModem? modem, required this.config})
      : modem = modem ?? DartModem(),
        currentMode = config.initialMode;

  /// The mode currently selected for connected transmissions.
  DartMode get mode => currentMode;

  /// Number of unacknowledged frames currently in flight.
  int get inFlight => _seqDiff(_sendBase, _nextSeq);

  /// Whether the send window has room for another reliable frame.
  bool get canSend => inFlight < config.windowSize;

  /// Whether any reliable frame is awaiting acknowledgement.
  bool get hasPending => inFlight > 0;

  /// Sequence number of the oldest unacknowledged frame, or null if none.
  int? get pendingSeq => hasPending ? _sendBase : null;

  /// Manually set the transmission mode. Resets the ACK streak.
  void setMode(DartMode mode) {
    currentMode = mode;
    _ackStreak = 0;
  }

  /// Send a connectionless datagram (multicast / broadcast / chat). No ACK is
  /// expected. [mode] overrides the current mode for this frame only.
  DartTxFrame sendDatagram(
    Uint8List payload, {
    String destination = '*',
    DartMode? mode,
  }) {
    final useMode = mode ?? currentMode;
    final int seq = _datagramSeq & 0xFF;
    _datagramSeq = _seqAdd(_datagramSeq, 1);
    final pcm = modem.encode(
      payload: payload,
      mode: useMode,
      source: config.callsign,
      destination: destination,
      seqNum: seq,
      flags: DartFlags.data | DartFlags.broadcast,
    );
    return _txFrame(
      pcm: pcm,
      mode: useMode,
      frameType: DartFrameType.datagram,
      destination: destination,
      seqNum: seq,
      payloadLength: payload.length,
      broadcast: true,
    );
  }

  /// Queue and send a reliable (connected) data frame. Returns the frame to
  /// transmit, or null if the send window is full (call again after ACKs
  /// arrive). [mode] sets the current mode for this and subsequent frames.
  DartTxFrame? sendReliable(
    Uint8List payload, {
    required String destination,
    DartMode? mode,
  }) {
    if (mode != null) currentMode = mode;
    if (!canSend) return null;

    final int seq = _nextSeq & 0xFF;
    _nextSeq = _seqAdd(_nextSeq, 1);
    final slot = _SendSlot(
      payload: payload,
      destination: destination,
      seqNum: seq,
    );
    _sendWindow[seq] = slot;
    return _encodeData(slot);
  }

  /// Retransmit outstanding frames after a timeout (no ACK received). Returns a
  /// frame for every un-acked slot still within the retransmit budget.
  List<DartTxFrame> retransmitTimedOut() {
    final out = <DartTxFrame>[];
    int seq = _sendBase;
    final int count = inFlight;
    for (int i = 0; i < count; i++) {
      final frame = _retransmitSlot(seq);
      if (frame != null) out.add(frame);
      seq = _seqAdd(seq, 1);
    }
    return out;
  }

  /// Retransmit a specific outstanding frame (or the oldest if [seq] is null).
  /// Returns null if there is nothing to send or the retransmit budget is spent.
  DartTxFrame? retransmit({int? seq}) {
    final target = seq ?? (hasPending ? _sendBase : null);
    if (target == null) return null;
    return _retransmitSlot(target);
  }

  /// Process a received PCM buffer. Returns a [DartRxEvent], or null if no
  /// valid frame was detected.
  DartRxEvent? receive(Int16List pcm) {
    final result = modem.decode(pcm);
    if (result == null) return null;

    final info = result.toPacketInfo();
    final type = result.frameType;
    final int seq = result.header.seqNum;

    switch (type) {
      case DartFrameType.ack:
        final bool forUs =
            _addressedToUs(result.header.destination) &&
            _sendWindow.containsKey(seq) &&
            !_sendWindow[seq]!.acked;
        if (forUs) {
          _sendWindow[seq]!.acked = true;
          _slideSendWindow();
          _adaptUp();
        }
        return DartRxEvent(info: info, ackReceived: forUs);

      case DartFrameType.nack:
        final bool forUs =
            _addressedToUs(result.header.destination) &&
            _sendWindow.containsKey(seq);
        DartTxFrame? resp;
        if (forUs) {
          _adaptDown();
          resp = _retransmitSlot(seq); // selective: resend only this frame
        }
        return DartRxEvent(info: info, nackReceived: forUs, response: resp);

      case DartFrameType.datagram:
        return DartRxEvent(
          info: info,
          deliveredPayloads: result.crcOk ? [result.payload] : const [],
        );

      case DartFrameType.data:
        if (!_addressedToUs(result.header.destination)) {
          // Not for us — report it for monitoring, no delivery/response.
          return DartRxEvent(info: info);
        }
        if (!result.crcOk) {
          // Payload failed — ask for a retransmission of this sequence.
          final nack = _encodeControl(
            DartFrameType.nack,
            destination: result.header.source,
            seqNum: seq,
          );
          return DartRxEvent(info: info, response: nack);
        }
        // Valid frame — accept into the receive window (in-order delivery) and
        // acknowledge it.
        final delivered = _acceptData(seq, result.payload);
        final ack = _encodeControl(
          DartFrameType.ack,
          destination: result.header.source,
          seqNum: seq,
        );
        return DartRxEvent(
          info: info,
          deliveredPayloads: delivered,
          response: ack,
        );
    }
  }

  // --- Receive-window logic (selective repeat, in-order delivery) ---

  /// Accept a valid data frame with sequence [seq]; return payloads that became
  /// deliverable in order (possibly several if this filled a buffered gap).
  List<Uint8List> _acceptData(int seq, Uint8List payload) {
    final int dist = _seqDiff(_recvBase, seq); // forward distance from base
    final delivered = <Uint8List>[];

    if (dist == 0) {
      // The next expected frame — deliver it, then drain any buffered run.
      delivered.add(payload);
      _recvBase = _seqAdd(_recvBase, 1);
      while (_recvBuffer.containsKey(_recvBase)) {
        delivered.add(_recvBuffer.remove(_recvBase)!);
        _recvBase = _seqAdd(_recvBase, 1);
      }
    } else if (dist < config.windowSize) {
      // A future frame within the window — buffer it (unless already buffered).
      _recvBuffer.putIfAbsent(seq, () => payload);
    } else {
      // A frame at or behind the base (already delivered) — duplicate.
      // Re-ACK only (handled by caller); do not deliver again.
    }
    return delivered;
  }

  // --- Send-window logic ---

  void _slideSendWindow() {
    while (_sendWindow[_sendBase]?.acked == true) {
      _sendWindow.remove(_sendBase);
      _sendBase = _seqAdd(_sendBase, 1);
    }
  }

  DartTxFrame? _retransmitSlot(int seq) {
    final slot = _sendWindow[seq];
    if (slot == null || slot.acked) return null;
    if (slot.retransmits >= config.maxRetransmits) return null;
    slot.retransmits++;
    return _encodeData(slot);
  }

  // --- Rate adaptation ---

  /// Rate ladder ordered from most robust to highest throughput. Mode F (the
  /// constant-envelope fallback) sits below mode 0 when [DartLinkConfig.allowModeF]
  /// is set, so a link that keeps failing even at mode 0 automatically drops to
  /// the amplitude-immune waveform.
  List<DartMode> get _rateLadder => config.allowModeF
      ? const [
          DartMode.modeF,
          DartMode.mode0,
          DartMode.mode1,
          DartMode.mode2,
          DartMode.mode3,
          DartMode.mode4,
          DartMode.mode5,
        ]
      : const [
          DartMode.mode0,
          DartMode.mode1,
          DartMode.mode2,
          DartMode.mode3,
          DartMode.mode4,
          DartMode.mode5,
        ];

  void _adaptUp() {
    if (!config.adaptive) return;
    _ackStreak++;
    if (_ackStreak >= config.rateUpThreshold) {
      final ladder = _rateLadder;
      final int pos = ladder.indexOf(currentMode);
      if (pos >= 0 && pos < ladder.length - 1) {
        currentMode = ladder[pos + 1];
      }
      _ackStreak = 0;
    }
  }

  void _adaptDown() {
    if (!config.adaptive) return;
    _ackStreak = 0;
    final ladder = _rateLadder;
    final int pos = ladder.indexOf(currentMode);
    if (pos < 0) return;
    final int next = pos - 2;
    currentMode = ladder[next < 0 ? 0 : next];
  }

  // --- Sequence-number arithmetic (8-bit, wraparound) ---

  static int _seqAdd(int a, int b) => (a + b) & 0xFF;

  /// Forward distance from [a] to [b], modulo 256.
  static int _seqDiff(int a, int b) => (b - a) & 0xFF;

  // --- Encoding helpers ---

  bool _addressedToUs(String dest) =>
      dest == config.callsign || dest == '*' || dest.isEmpty;

  DartTxFrame _encodeData(_SendSlot slot) {
    final pcm = modem.encode(
      payload: slot.payload,
      mode: currentMode,
      source: config.callsign,
      destination: slot.destination,
      seqNum: slot.seqNum,
      flags: DartFlags.data,
    );
    return _txFrame(
      pcm: pcm,
      mode: currentMode,
      frameType: DartFrameType.data,
      destination: slot.destination,
      seqNum: slot.seqNum,
      payloadLength: slot.payload.length,
      broadcast: false,
      retransmitCount: slot.retransmits,
    );
  }

  DartTxFrame _encodeControl(
    DartFrameType type, {
    required String destination,
    required int seqNum,
  }) {
    final int flags =
        type == DartFrameType.ack ? DartFlags.ack : DartFlags.nack;
    // Control frames are always sent at the most robust mode (mode 0).
    final pcm = modem.encode(
      payload: Uint8List(0),
      mode: DartMode.mode0,
      source: config.callsign,
      destination: destination,
      seqNum: seqNum,
      flags: flags,
    );
    return _txFrame(
      pcm: pcm,
      mode: DartMode.mode0,
      frameType: type,
      destination: destination,
      seqNum: seqNum,
      payloadLength: 0,
      broadcast: false,
    );
  }

  DartTxFrame _txFrame({
    required Int16List pcm,
    required DartMode mode,
    required DartFrameType frameType,
    required String destination,
    required int seqNum,
    required int payloadLength,
    required bool broadcast,
    int retransmitCount = 0,
  }) {
    final modeParams = DartModeParams.fromMode(mode);
    final double durationMs =
        pcm.length * 1000.0 / modem.ofdmParams.sampleRate;
    final info = DartPacketInfo(
      direction: DartDirection.transmit,
      timestamp: DateTime.now(),
      modeIndex: mode.index,
      constellation: modeParams.constellation,
      ldpcRate: modeParams.ldpcRate,
      modeDescription: modeParams.description,
      frameType: frameType,
      source: config.callsign,
      destination: destination,
      seqNum: seqNum,
      payloadLength: payloadLength,
      broadcast: broadcast,
      durationMs: durationMs,
      retransmitCount: retransmitCount,
    );
    return DartTxFrame(pcm: pcm, info: info);
  }
}
