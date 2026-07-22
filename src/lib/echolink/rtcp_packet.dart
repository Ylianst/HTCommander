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
// rtcp_packet.dart - EchoLink RTCP SDES/BYE control packets.
//
// Faithful port of reference/svxlink/src/echolib/rtpacket.cpp
// (rtp_make_sdes, rtp_make_bye, parseSDES, isRTCPByepacket, isRTCPSdespacket).
// These travel on the control port (audio port + 1, i.e. 5199 by default).
//
// Note: EchoLink uses RTP version 3 (not the RFC-standard 2), and the SDES
// CNAME/EMAIL items are the literal string "CALLSIGN" while the real callsign
// and name are carried in the NAME item as sprintf("%-15s%s", callsign, name).
//

import 'dart:convert';
import 'dart:typed_data';

/// RTP protocol version used by EchoLink.
const int rtpVersion = 3;

// RTCP packet types (rtp.h).
const int rtcpSr = 200;
const int rtcpRr = 201;
const int rtcpSdes = 202;
const int rtcpBye = 203;
const int rtcpApp = 204;

// RTCP SDES item types (rtp.h).
const int sdesEnd = 0;
const int sdesCname = 1;
const int sdesName = 2;
const int sdesEmail = 3;
const int sdesPhone = 4;
const int sdesLoc = 5;
const int sdesTool = 6;
const int sdesNote = 7;
const int sdesPriv = 8;

Uint8List _bytesOf(String s) => Uint8List.fromList(latin1.encode(s));

/// printf "%-15s%s": left-justify [callsign] in a 15-char field, append [name].
String _formatName(String callsign, String name) {
  final String padded =
      callsign.length >= 15 ? callsign : callsign.padRight(15);
  return '$padded$name';
}

/// Builds an RTCP SDES packet identifying the local station, prefixed with the
/// mandatory null RR report. Mirrors rtp_make_sdes.
Uint8List buildSdes({
  required String callsign,
  String name = '',
  String? priv,
}) {
  final List<int> p = <int>[];

  // Null receiver report prefix (8 bytes).
  p.addAll(<int>[rtpVersion << 6, rtcpRr, 0, 1, 0, 0, 0, 0]);

  final int s = p.length; // start of the SDES subpacket
  final int ver = (rtpVersion << 14) | rtcpSdes | (1 << 8);
  p.add((ver >> 8) & 0xFF); // version/count
  p.add(ver & 0xFF); // packet type (SDES)
  p.add(0); // length placeholder (hi)
  p.add(0); // length placeholder (lo)
  p.addAll(<int>[0, 0, 0, 0]); // SDES source (SSRC) = 0

  void addItem(int type, String text) {
    final Uint8List t = _bytesOf(text);
    p.add(type);
    p.add(t.length);
    p.addAll(t);
  }

  addItem(sdesCname, 'CALLSIGN');
  addItem(sdesName, _formatName(callsign, name));
  addItem(sdesEmail, 'CALLSIGN');
  addItem(sdesPhone, '08:30');
  if (priv != null) {
    addItem(sdesPriv, priv);
  }

  // SDES END item + zero length.
  p.add(sdesEnd);
  p.add(0);

  // Pad the SDES subpacket to a 4-byte boundary.
  while (((p.length - s) & 3) != 0) {
    p.add(0);
  }

  // Length in 32-bit words minus one.
  final int len = ((p.length - s) ~/ 4) - 1;
  p[s + 2] = (len >> 8) & 0xFF;
  p[s + 3] = len & 0xFF;

  return Uint8List.fromList(p);
}

/// Builds an RTCP BYE packet (prefixed with a null RR report). Mirrors
/// rtp_make_bye.
Uint8List buildBye() {
  final List<int> p = <int>[];

  p.addAll(<int>[rtpVersion << 6, rtcpRr, 0, 1, 0, 0, 0, 0]);

  final int s = p.length;
  final int ver = (rtpVersion << 14) | rtcpBye | (1 << 8);
  p.add((ver >> 8) & 0xFF);
  p.add(ver & 0xFF);
  p.add(0);
  p.add(0);
  p.addAll(<int>[0, 0, 0, 0]); // BYE source = 0

  // Trailing text with a length prefix.
  final Uint8List t = _bytesOf('jan2002');
  p.add(t.length);
  p.addAll(t);

  while (((p.length - s) & 3) != 0) {
    p.add(0);
  }

  final int len = ((p.length - s) ~/ 4) - 1;
  p[s + 2] = (len >> 8) & 0xFF;
  p[s + 3] = len & 0xFF;

  return Uint8List.fromList(p);
}

int _be16(Uint8List p, int off) => (p[off] << 8) | p[off + 1];

/// Extracts the text of the first SDES item of type [itemType] from a
/// (possibly composite) RTCP packet. Returns null if not present. Every access
/// is bounds-checked. Mirrors parseSDES.
String? parseSdesItem(Uint8List packet, int itemType) {
  int p = 0;
  final int end = packet.length;

  while (p + 4 <= end &&
      (((packet[p] >> 6) & 3) == rtpVersion || ((packet[p] >> 6) & 3) == 1)) {
    final int len = (_be16(packet, p + 2) + 1) * 4;
    if (len <= 0 || p + len > end) break;

    if (packet[p + 1] == rtcpSdes && (packet[p] & 0x1F) > 0) {
      int cp = p + 8;
      final int lp = p + len;
      while (cp + 2 <= lp) {
        final int itype = packet[cp];
        final int ilen = packet[cp + 1];
        if (itype == sdesEnd) break;
        if (cp + 2 + ilen > lp) break;
        if (itemType == itype) {
          return latin1.decode(
              Uint8List.sublistView(packet, cp + 2, cp + 2 + ilen));
        }
        cp += ilen + 2;
      }
      break;
    }
    p += len;
  }
  return null;
}

bool _rtcpContains(Uint8List p, int type) {
  final int end = p.length;
  if (4 > end) return false;

  final int v = (p[0] >> 6) & 3;
  if ((v != rtpVersion && v != 1) ||
      (p[0] & 0x20) != 0 ||
      (p[1] != rtcpSr && p[1] != rtcpRr)) {
    return false;
  }

  int i = 0;
  bool saw = false;
  do {
    if (p[i + 1] == type) saw = true;
    i += (_be16(p, i + 2) + 1) * 4;
  } while (i + 4 <= end && (((p[i] >> 6) & 3) == rtpVersion));

  return saw;
}

/// True if the RTCP packet contains a BYE subpacket. Mirrors isRTCPByepacket.
bool isByePacket(Uint8List packet) => _rtcpContains(packet, rtcpBye);

/// True if the RTCP packet contains an SDES subpacket. Mirrors isRTCPSdespacket.
bool isSdesPacket(Uint8List packet) => _rtcpContains(packet, rtcpSdes);

/// Parsed station identity from an SDES NAME item.
class SdesStation {
  final String callsign;
  final String name;
  const SdesStation(this.callsign, this.name);
}

/// Extracts and splits the SDES NAME item into callsign and name. The NAME item
/// is `callsign<spaces>name`; the callsign is the first whitespace-delimited
/// token. Returns null if there is no SDES NAME item.
SdesStation? parseSdesStation(Uint8List packet) {
  final String? nameItem = parseSdesItem(packet, sdesName);
  if (nameItem == null) return null;
  final String trimmed = nameItem.trimLeft();
  final int sp = trimmed.indexOf(RegExp(r'\s'));
  if (sp < 0) return SdesStation(trimmed, '');
  final String callsign = trimmed.substring(0, sp);
  final String name = trimmed.substring(sp).trim();
  return SdesStation(callsign, name);
}
