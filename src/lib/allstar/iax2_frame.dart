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
// iax2_frame.dart - IAX2 full frame and mini frame encoding/decoding.
//
// Full frames (12-byte header) carry reliable signaling and may carry media;
// mini frames (4-byte header) carry unreliable media only. All multi-byte
// fields are big-endian (network byte order). See RFC 5456 section 8.1.
//
//   Full: F|15b srcCall | R|15b dstCall | 32b ts | OSeqno | ISeqno |
//         frametype | C|7b subclass | data...
//   Mini: F(0)|15b srcCall | 16b ts | data...
//

import 'dart:typed_data';

import 'iax2_constants.dart';
import 'iax2_ie.dart';

/// A decoded IAX2 full frame. Signaling frames (IAX/control) carry information
/// elements; media frames (voice/dtmf) carry a raw payload in [payload].
class Iax2FullFrame {
  /// 15-bit call number assigned by the sender.
  int sourceCallNumber;

  /// 15-bit call number identifying the call on the remote peer (0 for NEW).
  int destCallNumber;

  /// True when this is a retransmission (R bit).
  bool retransmit;

  /// 32-bit millisecond timestamp since the call started.
  int timestamp;

  /// Outbound sequence number.
  int oSeqno;

  /// Inbound sequence number (next expected from peer).
  int iSeqno;

  /// Frame type (see [Iax2FrameType]).
  int frameType;

  /// Subclass value. For media frames this is the codec/format; for IAX and
  /// control frames it is the command. When [subclassIsPower] is set on the
  /// wire the value is transmitted as a power of two.
  int subclass;

  /// Payload for media/text frames; empty for pure-signaling frames.
  Uint8List payload;

  Iax2FullFrame({
    required this.sourceCallNumber,
    required this.destCallNumber,
    this.retransmit = false,
    required this.timestamp,
    required this.oSeqno,
    required this.iSeqno,
    required this.frameType,
    required this.subclass,
    Uint8List? payload,
  }) : payload = payload ?? Uint8List(0);

  static const int headerSize = 12;

  bool get isIax => frameType == Iax2FrameType.iax;
  bool get isVoice => frameType == Iax2FrameType.voice;
  bool get isControl => frameType == Iax2FrameType.control;

  /// Parses the [payload] as information elements (valid for IAX signaling
  /// frames).
  Iax2IeSet parseIes() => Iax2IeSet.parse(payload);

  /// Serializes the frame. When [ies] is provided its bytes are used as the
  /// payload (convenience for building signaling frames).
  Uint8List toBytes({Iax2IeSet? ies}) {
    final Uint8List body = ies != null ? ies.toBytes() : payload;
    final Uint8List out = Uint8List(headerSize + body.length);
    final ByteData bd = ByteData.sublistView(out);
    // F bit (0x8000) set to mark a full frame.
    bd.setUint16(0, 0x8000 | (sourceCallNumber & 0x7FFF), Endian.big);
    bd.setUint16(2, (retransmit ? 0x8000 : 0) | (destCallNumber & 0x7FFF), Endian.big);
    bd.setUint32(4, timestamp & 0xFFFFFFFF, Endian.big);
    bd.setUint8(8, oSeqno & 0xFF);
    bd.setUint8(9, iSeqno & 0xFF);
    bd.setUint8(10, frameType & 0xFF);
    // Subclass is sent as a plain 7-bit value (C bit clear). Media formats and
    // command values used by this client all fit in 7 bits or are power-of-two
    // encoded by [subclassByte].
    bd.setUint8(11, _subclassByte(subclass));
    out.setRange(headerSize, headerSize + body.length, body);
    return out;
  }

  /// Encodes a subclass value into the wire octet. Values that fit in 7 bits are
  /// sent verbatim; larger power-of-two values (e.g. media formats) are sent
  /// with the C bit set and the log2 exponent in the low 7 bits.
  static int _subclassByte(int subclass) {
    if (subclass >= 0 && subclass <= 0x7F) return subclass & 0x7F;
    // Must be a power of two to be representable.
    int exp = 0;
    int v = subclass;
    while (v > 1) {
      v >>= 1;
      exp++;
    }
    return 0x80 | (exp & 0x7F);
  }

  /// Decodes a subclass wire octet back into its value.
  static int _subclassValue(int b) {
    if ((b & 0x80) != 0) return 1 << (b & 0x7F);
    return b & 0x7F;
  }

  /// Parses a received full frame. Returns null if [data] is too short or is a
  /// mini frame (F bit clear). The [payload] is a copy.
  static Iax2FullFrame? parse(Uint8List data, [int offset = 0]) {
    if (data.length - offset < headerSize) return null;
    final ByteData bd = ByteData.sublistView(data, offset);
    final int w0 = bd.getUint16(0, Endian.big);
    if ((w0 & 0x8000) == 0) return null; // Mini frame.
    final int w1 = bd.getUint16(2, Endian.big);
    final Uint8List payload = Uint8List.fromList(
        data.sublist(offset + headerSize, data.length));
    return Iax2FullFrame(
      sourceCallNumber: w0 & 0x7FFF,
      destCallNumber: w1 & 0x7FFF,
      retransmit: (w1 & 0x8000) != 0,
      timestamp: bd.getUint32(4, Endian.big),
      oSeqno: bd.getUint8(8),
      iSeqno: bd.getUint8(9),
      frameType: bd.getUint8(10),
      subclass: _subclassValue(bd.getUint8(11)),
      payload: payload,
    );
  }

  @override
  String toString() {
    final String kind = frameType == Iax2FrameType.iax
        ? Iax2Subclass.name(subclass)
        : 'type=$frameType/sub=$subclass';
    return 'FullFrame(src=$sourceCallNumber dst=$destCallNumber ts=$timestamp '
        'o=$oSeqno i=$iSeqno $kind len=${payload.length})';
  }
}

/// A decoded IAX2 mini frame: media payload with a 16-bit timestamp.
class Iax2MiniFrame {
  int sourceCallNumber;
  int timestamp; // Low 16 bits of the call timestamp.
  Uint8List payload;

  Iax2MiniFrame({
    required this.sourceCallNumber,
    required this.timestamp,
    required this.payload,
  });

  static const int headerSize = 4;

  Uint8List toBytes() {
    final Uint8List out = Uint8List(headerSize + payload.length);
    final ByteData bd = ByteData.sublistView(out);
    // F bit clear (0x0000) marks a mini frame.
    bd.setUint16(0, sourceCallNumber & 0x7FFF, Endian.big);
    bd.setUint16(2, timestamp & 0xFFFF, Endian.big);
    out.setRange(headerSize, headerSize + payload.length, payload);
    return out;
  }

  /// Parses a received mini frame. Returns null if it is a full frame (F bit
  /// set), a meta frame (source call number 0), or too short.
  static Iax2MiniFrame? parse(Uint8List data, [int offset = 0]) {
    if (data.length - offset < headerSize) return null;
    final ByteData bd = ByteData.sublistView(data, offset);
    final int w0 = bd.getUint16(0, Endian.big);
    if ((w0 & 0x8000) != 0) return null; // Full frame.
    final int src = w0 & 0x7FFF;
    if (src == 0) return null; // Meta frame (trunk/video), not handled.
    return Iax2MiniFrame(
      sourceCallNumber: src,
      timestamp: bd.getUint16(2, Endian.big),
      payload: Uint8List.fromList(data.sublist(offset + headerSize, data.length)),
    );
  }
}

/// True if [data] (a received datagram) is an IAX2 full frame.
bool iax2IsFullFrame(Uint8List data) =>
    data.length >= 2 && (data[0] & 0x80) != 0;
