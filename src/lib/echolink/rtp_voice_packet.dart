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
// rtp_voice_packet.dart - EchoLink RTP-style voice packet framing.
//
// Mirrors the on-the-wire VoicePacket used by EchoLink / EchoLib (see
// reference/svxlink/src/echolib/EchoLinkQso.{h,cpp}). The 12-byte header is
// packed (no padding) and all multi-byte fields are big-endian (network byte
// order). For GSM the payload is 4 x 33-byte frames (80 ms, 640 samples).
//
//   struct { u8 version; u8 pt; u16 seqNum; u32 time; u32 ssrc; } header;
//   u8 data[...];
//

import 'dart:typed_data';

/// A parsed / buildable EchoLink voice packet.
class RtpVoicePacket {
  /// First header byte of an audio packet (identifies the packet as audio).
  static const int audioVersion = 0xc0;

  /// Payload type for full-rate GSM 06.10 audio.
  static const int ptGsm = 0x03;

  /// Payload type for Speex audio (not produced here, recognised on parse).
  static const int ptSpeex = 0x96;

  /// Size of the packed header in bytes.
  static const int headerSize = 12;

  /// Number of GSM frames carried in one audio packet.
  static const int gsmFrameCount = 4;

  /// Size of a single GSM frame in bytes.
  static const int gsmFrameBytes = 33;

  /// Total GSM payload size (4 x 33).
  static const int gsmPayloadBytes = gsmFrameCount * gsmFrameBytes; // 132

  /// PCM samples represented by one GSM audio packet (4 x 160).
  static const int gsmSamplesPerPacket = gsmFrameCount * 160; // 640

  int version;
  int pt;
  int seqNum;
  int timestamp;
  int ssrc;
  Uint8List payload;

  RtpVoicePacket({
    this.version = audioVersion,
    this.pt = ptGsm,
    this.seqNum = 0,
    this.timestamp = 0,
    this.ssrc = 0,
    required this.payload,
  });

  /// True if this looks like an EchoLink audio packet.
  bool get isAudio => version == audioVersion;

  /// True if the payload is full-rate GSM.
  bool get isGsm => pt == ptGsm;

  /// True if the payload is Speex.
  bool get isSpeex => pt == ptSpeex;

  /// Serializes the packet (header + payload) into a new [Uint8List].
  Uint8List toBytes() {
    final Uint8List out = Uint8List(headerSize + payload.length);
    final ByteData bd = ByteData.sublistView(out);
    bd.setUint8(0, version & 0xFF);
    bd.setUint8(1, pt & 0xFF);
    bd.setUint16(2, seqNum & 0xFFFF, Endian.big);
    bd.setUint32(4, timestamp & 0xFFFFFFFF, Endian.big);
    bd.setUint32(8, ssrc & 0xFFFFFFFF, Endian.big);
    out.setRange(headerSize, headerSize + payload.length, payload);
    return out;
  }

  /// Parses a received datagram. Returns null if it is too short to contain a
  /// header. The [payload] is a view over [data] (no copy).
  static RtpVoicePacket? parse(Uint8List data, [int offset = 0]) {
    if (data.length - offset < headerSize) return null;
    final ByteData bd = ByteData.sublistView(data, offset);
    return RtpVoicePacket(
      version: bd.getUint8(0),
      pt: bd.getUint8(1),
      seqNum: bd.getUint16(2, Endian.big),
      timestamp: bd.getUint32(4, Endian.big),
      ssrc: bd.getUint32(8, Endian.big),
      payload: Uint8List.sublistView(data, offset + headerSize),
    );
  }
}
