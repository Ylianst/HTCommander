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
// echolink_data_packet.dart - EchoLink "oNDATA" info/chat packets.
//
// These share the audio port with voice packets. Mirrors Qso::sendInfoData,
// Qso::sendChatData and Qso::handleNonAudioPacket in
// reference/svxlink/src/echolib/EchoLinkQso.cpp.
//
//   Audio : first byte 0xC0
//   Info  : "oNDATA\r" + info               (byte[6] == '\r')
//   Chat  : "oNDATA" + callsign + '>' + msg  (byte[6] != '\r')
// Both info and chat packets are null-terminated on the wire.
//

import 'dart:convert';
import 'dart:typed_data';

/// Classification of a packet received on the EchoLink audio port.
enum EchoLinkAudioPortPacket { audio, info, chat, unknown }

const List<int> _ndata = <int>[0x4e, 0x44, 0x41, 0x54, 0x41]; // "NDATA"
const int _cr = 0x0d;

bool _hasNdata(Uint8List d) {
  if (d.length < 7) return false;
  for (int i = 0; i < 5; i++) {
    if (d[1 + i] != _ndata[i]) return false;
  }
  return true;
}

/// Classifies a datagram received on the audio port.
EchoLinkAudioPortPacket classifyAudioPortPacket(Uint8List d) {
  if (d.isNotEmpty && d[0] == 0xc0) return EchoLinkAudioPortPacket.audio;
  if (_hasNdata(d)) {
    return d[6] == _cr
        ? EchoLinkAudioPortPacket.info
        : EchoLinkAudioPortPacket.chat;
  }
  return EchoLinkAudioPortPacket.unknown;
}

Uint8List _terminated(String s) {
  final List<int> b = latin1.encode(s);
  final Uint8List out = Uint8List(b.length + 1);
  out.setRange(0, b.length, b);
  return out; // trailing 0 already present from zero-filled allocation
}

/// Builds a station-info packet: "oNDATA\r" + info (newlines normalized to
/// carriage returns), null-terminated. Mirrors Qso::sendInfoData.
Uint8List buildInfoPacket(String info) {
  final String body = 'oNDATA\r$info'.replaceAll('\n', '\r');
  return _terminated(body);
}

/// Builds a chat packet: "oNDATA" + callsign + '>' + msg + "\r\n",
/// null-terminated. Mirrors Qso::sendChatData.
Uint8List buildChatPacket(String callsign, String msg) {
  return _terminated('oNDATA$callsign>$msg\r\n');
}

String _decodeToNull(Uint8List d, int start) {
  int endIdx = d.indexOf(0, start);
  if (endIdx < 0) endIdx = d.length;
  return latin1.decode(Uint8List.sublistView(d, start, endIdx));
}

/// Extracts the info text from an info packet (bytes after "oNDATA\r"), with
/// carriage returns normalized to newlines. Mirrors the receiver side of
/// handleNonAudioPacket.
String parseInfoPacket(Uint8List d) =>
    _decodeToNull(d, 7).replaceAll('\r', '\n');

/// A received chat message: the raw "callsign>message" text plus the split
/// callsign and message.
class EchoLinkChat {
  final String raw;
  final String callsign;
  final String message;
  const EchoLinkChat(this.raw, this.callsign, this.message);
}

/// Parses a chat packet (bytes after "oNDATA"), splitting on the first '>' into
/// callsign and message. Mirrors the receiver side of handleNonAudioPacket.
EchoLinkChat parseChatPacket(Uint8List d) {
  final String raw = _decodeToNull(d, 6).replaceAll('\r', '\n').trimRight();
  final int gt = raw.indexOf('>');
  if (gt < 0) return EchoLinkChat(raw, '', raw);
  return EchoLinkChat(raw, raw.substring(0, gt), raw.substring(gt + 1));
}
