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
// echolink_audio.dart - EchoLink audio path: PCM <-> GSM voice packets.
//
// Combines the pure-Dart GSM 06.10 codec with the EchoLink voice-packet
// framing. One packet carries 640 samples (80 ms) of 8 kHz, 16-bit mono audio
// as four GSM frames.
//

import 'dart:typed_data';

import '../gsm/gsm_codec.dart';
import 'rtp_voice_packet.dart';

/// Encodes 8 kHz mono PCM into EchoLink GSM voice packets. One instance holds a
/// single continuous stream (GSM filter memory + RTP sequence number).
class EchoLinkAudioEncoder {
  final GsmEncoder _gsm = GsmEncoder();
  int _seq;
  int ssrc;

  /// Samples consumed per packet (640).
  static const int samplesPerPacket = RtpVoicePacket.gsmSamplesPerPacket;

  EchoLinkAudioEncoder({int initialSeq = 0, this.ssrc = 0})
      : _seq = initialSeq & 0xFFFF;

  /// The sequence number that will be used for the next packet.
  int get nextSeq => _seq;

  /// Clears the codec state and resets the sequence counter.
  void reset({int initialSeq = 0}) {
    _gsm.reset();
    _seq = initialSeq & 0xFFFF;
  }

  /// Encodes exactly [samplesPerPacket] (640) samples into a ready-to-send
  /// datagram (12-byte header + 132 GSM bytes = 144 bytes).
  Uint8List encodePacket(Int16List pcm, {int pcmOff = 0}) {
    if (pcm.length - pcmOff < samplesPerPacket) {
      throw ArgumentError('encodePacket needs $samplesPerPacket samples');
    }
    final Int16List frame = (pcmOff == 0 && pcm.length == samplesPerPacket)
        ? pcm
        : Int16List.sublistView(pcm, pcmOff, pcmOff + samplesPerPacket);

    final Uint8List payload = _gsm.encode(frame);
    final RtpVoicePacket pkt = RtpVoicePacket(
      pt: RtpVoicePacket.ptGsm,
      seqNum: _seq,
      ssrc: ssrc,
      payload: payload,
    );
    _seq = (_seq + 1) & 0xFFFF;
    return pkt.toBytes();
  }

  /// Encodes an integer number of 640-sample blocks, returning one datagram per
  /// block. `pcm.length` must be a multiple of [samplesPerPacket].
  List<Uint8List> encode(Int16List pcm) {
    if (pcm.length % samplesPerPacket != 0) {
      throw ArgumentError('pcm length must be a multiple of $samplesPerPacket');
    }
    final int packets = pcm.length ~/ samplesPerPacket;
    final List<Uint8List> out = <Uint8List>[];
    for (int p = 0; p < packets; p++) {
      out.add(encodePacket(pcm, pcmOff: p * samplesPerPacket));
    }
    return out;
  }
}

/// Decodes received EchoLink GSM voice packets back into 8 kHz mono PCM.
class EchoLinkAudioDecoder {
  final GsmDecoder _gsm = GsmDecoder();

  /// Samples produced per packet (640).
  static const int samplesPerPacket = RtpVoicePacket.gsmSamplesPerPacket;

  /// Clears the codec state to start a new stream.
  void reset() => _gsm.reset();

  /// Decodes a received datagram into 640 samples. Returns null if the packet
  /// is not a GSM audio packet or is too short to contain four GSM frames.
  Int16List? decodePacket(Uint8List datagram, [int offset = 0]) {
    final RtpVoicePacket? pkt = RtpVoicePacket.parse(datagram, offset);
    if (pkt == null || !pkt.isAudio || !pkt.isGsm) return null;
    if (pkt.payload.length < RtpVoicePacket.gsmPayloadBytes) return null;

    final Uint8List gsmBytes = pkt.payload.length == RtpVoicePacket.gsmPayloadBytes
        ? pkt.payload
        : Uint8List.sublistView(pkt.payload, 0, RtpVoicePacket.gsmPayloadBytes);
    return _gsm.decode(gsmBytes);
  }
}
