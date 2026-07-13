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

/// Channel-Share String — a compact, human-readable, one-line text encoding of
/// a radio channel that can be dropped into a chat/APRS message and sent to
/// another operator (even over the air).
///
/// Format (see docs/blogs/channel-share-string.md):
///
///   HTC:1:NAME:RXFREQ:OFFSET:TXTONE:RXTONE:FLAGS*CK
///
///  * HTC     - magic prefix so a receiver can spot a channel in free text.
///  * 1       - format version (analog FM/AM only).
///  * NAME    - percent-encoded channel name (no spaces / reserved chars).
///  * RXFREQ  - receive frequency in MHz (trailing zeros trimmed).
///  * OFFSET  - transmit offset in MHz: `0` simplex, `+0.6`/`-5` signed offset,
///              or `=147.315` absolute transmit frequency for an odd split.
///  * TXTONE  - transmit sub-audio: empty=none, `88.5`=CTCSS Hz, `D023`=DCS.
///  * RXTONE  - receive sub-audio (same encoding as TXTONE).
///  * FLAGS   - 10-bit flag word as two Crockford Base32 characters.
///  * *CK     - `*` + two-digit uppercase hex XOR checksum of everything before.
library;

import 'dart:convert';

import '../radio/radio_models.dart';

/// A channel-share token located inside a larger block of text, together with
/// the decoded channel and the character range it occupies. Used to render
/// received channels as draggable "yellow blocks" in message views.
class ChannelShareMatch {
  /// Index of the first character of the token in the source string.
  final int start;

  /// Index just past the last character of the token in the source string.
  final int end;

  /// The exact token text (`HTC:1:...*CK`).
  final String raw;

  /// The decoded channel.
  final RadioChannelInfo channel;

  const ChannelShareMatch({
    required this.start,
    required this.end,
    required this.raw,
    required this.channel,
  });
}

/// Encodes and decodes [RadioChannelInfo] objects to/from the compact
/// channel-share text format.
class ChannelShare {
  ChannelShare._();

  /// The magic prefix that identifies a channel-share token.
  static const String magic = 'HTC';

  /// The format version produced by [encode].
  static const int version = 1;

  /// Crockford Base32 alphabet (excludes the ambiguous I, L, O, U).
  static const String _base32 = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  // Flag-word bit masks.
  static const int _flagWide = 0x001;
  static const int _flagRxAm = 0x002;
  static const int _flagTxAm = 0x004;
  static const int _flagMute = 0x008;
  static const int _flagDeEmphBypass = 0x010;
  static const int _flagTxDisable = 0x020;
  static const int _flagScan = 0x040;
  static const int _flagTalkAround = 0x080;
  static const int _flagTxMedPower = 0x100;
  static const int _flagTxHighPower = 0x200;

  /// Matches a complete channel-share token embedded anywhere in text. The
  /// middle captures every field (which may contain the `:` delimiter) but no
  /// whitespace or `*`, so the token cleanly ends at the `*CK` checksum even
  /// when user text is glued directly before or after it.
  static final RegExp tokenPattern = RegExp(
    r'HTC:\d+:[^\s*]*\*[0-9A-Fa-f]{2}',
  );

  // ---------------------------------------------------------------------------
  // Encoding
  // ---------------------------------------------------------------------------

  /// Encodes [channel] into a channel-share token, e.g.
  /// `HTC:1:Calling:146.52:0:::G1*4A`.
  static String encode(RadioChannelInfo channel) {
    final name = _encodeName(channel.name);
    final rx = _formatMhzMagnitude(channel.rxFreq);
    final offset = _formatOffset(channel.rxFreq, channel.txFreq);
    final txTone = _formatTone(channel.txSubAudio);
    final rxTone = _formatTone(channel.rxSubAudio);

    int flags = 0;
    if (channel.bandwidth == RadioBandwidthType.wide) flags |= _flagWide;
    if (channel.rxMod == RadioModulationType.am) flags |= _flagRxAm;
    if (channel.txMod == RadioModulationType.am) flags |= _flagTxAm;
    if (channel.mute) flags |= _flagMute;
    if (channel.preDeEmphBypass) flags |= _flagDeEmphBypass;
    if (channel.txDisable) flags |= _flagTxDisable;
    if (channel.scan) flags |= _flagScan;
    if (channel.talkAround) flags |= _flagTalkAround;
    if (channel.txAtMedPower) flags |= _flagTxMedPower;
    if (channel.txAtMaxPower) flags |= _flagTxHighPower;

    final body =
        '$magic:$version:$name:$rx:$offset:$txTone:$rxTone:${_encodeFlags(flags)}';
    return '$body*${_checksum(body)}';
  }

  // ---------------------------------------------------------------------------
  // Decoding
  // ---------------------------------------------------------------------------

  /// Decodes a single channel-share [token] (as produced by [encode]) back into
  /// a [RadioChannelInfo]. Returns `null` if the token is malformed, has an
  /// unsupported version, or fails the checksum.
  static RadioChannelInfo? decode(String token) {
    final trimmed = token.trim();
    final match = tokenPattern.matchAsPrefix(trimmed);
    if (match == null || match.end != trimmed.length) return null;
    return _decodeMatched(trimmed);
  }

  /// Finds every valid channel-share token inside [text] and decodes it,
  /// returning the matches in order of appearance. Tokens that fail validation
  /// are skipped.
  static List<ChannelShareMatch> findAll(String text) {
    final results = <ChannelShareMatch>[];
    for (final m in tokenPattern.allMatches(text)) {
      final raw = m.group(0)!;
      final channel = _decodeMatched(raw);
      if (channel == null) continue;
      results.add(
        ChannelShareMatch(
          start: m.start,
          end: m.end,
          raw: raw,
          channel: channel,
        ),
      );
    }
    return results;
  }

  /// Returns `true` if [text] contains at least one valid channel-share token.
  static bool contains(String text) => findAll(text).isNotEmpty;

  static RadioChannelInfo? _decodeMatched(String raw) {
    final star = raw.lastIndexOf('*');
    if (star < 0) return null;
    final body = raw.substring(0, star);
    final checksum = raw.substring(star + 1);
    if (_checksum(body).toUpperCase() != checksum.toUpperCase()) return null;

    final parts = body.split(':');
    if (parts.length != 8) return null;
    if (parts[0] != magic) return null;
    if (int.tryParse(parts[1]) != version) return null;

    try {
      final name = _decodeName(parts[2]);
      final rxFreq = _parseMhz(parts[3]);
      final txFreq = _parseOffset(parts[4], rxFreq);
      final txSubAudio = _parseTone(parts[5]);
      final rxSubAudio = _parseTone(parts[6]);
      final flags = _decodeFlags(parts[7]);
      if (flags == null) return null;

      return RadioChannelInfo(
        channelId: 0,
        name: name,
        rxFreq: rxFreq,
        txFreq: txFreq,
        rxMod: (flags & _flagRxAm) != 0
            ? RadioModulationType.am
            : RadioModulationType.fm,
        txMod: (flags & _flagTxAm) != 0
            ? RadioModulationType.am
            : RadioModulationType.fm,
        txSubAudio: txSubAudio,
        rxSubAudio: rxSubAudio,
        bandwidth: (flags & _flagWide) != 0
            ? RadioBandwidthType.wide
            : RadioBandwidthType.narrow,
        mute: (flags & _flagMute) != 0,
        preDeEmphBypass: (flags & _flagDeEmphBypass) != 0,
        txDisable: (flags & _flagTxDisable) != 0,
        scan: (flags & _flagScan) != 0,
        talkAround: (flags & _flagTalkAround) != 0,
        txAtMedPower: (flags & _flagTxMedPower) != 0,
        txAtMaxPower: (flags & _flagTxHighPower) != 0,
      );
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Field helpers
  // ---------------------------------------------------------------------------

  /// Formats a non-negative frequency in whole hertz as a MHz decimal string
  /// with trailing zeros (and a trailing dot) trimmed. 146520000 -> "146.52".
  static String _formatMhzMagnitude(int hz) {
    final whole = hz ~/ 1000000;
    final frac = hz % 1000000;
    if (frac == 0) return '$whole';
    final f = frac.toString().padLeft(6, '0').replaceFirst(RegExp(r'0+$'), '');
    return '$whole.$f';
  }

  /// Formats the transmit offset relative to the receive frequency. Simplex is
  /// `0`; a clean offset is signed (`+0.6`, `-5`); a large / cross-band split
  /// falls back to the absolute `=<txMHz>` form.
  static String _formatOffset(int rxFreq, int txFreq) {
    final offset = txFreq - rxFreq;
    if (offset == 0) return '0';
    if (offset.abs() > 100000000) return '=${_formatMhzMagnitude(txFreq)}';
    final sign = offset > 0 ? '+' : '-';
    return '$sign${_formatMhzMagnitude(offset.abs())}';
  }

  /// Formats a sub-audio value. 0 -> empty; CTCSS (stored as Hz x 100, always
  /// >= 1000) -> decimal Hz; DCS (the bare numeric code, < 1000) -> `D023`.
  static String _formatTone(int subAudio) {
    if (subAudio == 0) return '';
    if (subAudio >= 1000) {
      final whole = subAudio ~/ 100;
      final rem = subAudio % 100;
      if (rem == 0) return '$whole';
      final r = rem.toString().padLeft(2, '0').replaceFirst(RegExp(r'0+$'), '');
      return '$whole.$r';
    }
    return 'D${subAudio.toString().padLeft(3, '0')}';
  }

  static int _parseMhz(String mhz) => (double.parse(mhz) * 1000000).round();

  static int _parseOffset(String offset, int rxFreq) {
    if (offset.isEmpty || offset == '0') return rxFreq;
    if (offset.startsWith('=')) return _parseMhz(offset.substring(1));
    // double.parse accepts a leading '+' or '-'.
    return rxFreq + (double.parse(offset) * 1000000).round();
  }

  static int _parseTone(String tone) {
    if (tone.isEmpty) return 0;
    final first = tone[0].toUpperCase();
    if (first == 'D') return int.parse(tone.substring(1));
    return (double.parse(tone) * 100).round();
  }

  // ---------------------------------------------------------------------------
  // Name percent-encoding
  // ---------------------------------------------------------------------------

  static bool _isUnreserved(int b) =>
      (b >= 0x30 && b <= 0x39) || // 0-9
      (b >= 0x41 && b <= 0x5A) || // A-Z
      (b >= 0x61 && b <= 0x7A) || // a-z
      b == 0x2D || // -
      b == 0x5F || // _
      b == 0x2E; // .

  static String _encodeName(String name) {
    final bytes = utf8.encode(name);
    final sb = StringBuffer();
    for (final b in bytes) {
      if (_isUnreserved(b)) {
        sb.writeCharCode(b);
      } else {
        sb.write('%');
        sb.write(b.toRadixString(16).toUpperCase().padLeft(2, '0'));
      }
    }
    return sb.toString();
  }

  static String _decodeName(String s) {
    final bytes = <int>[];
    for (int i = 0; i < s.length; i++) {
      if (s[i] == '%' && i + 2 < s.length) {
        final v = int.tryParse(s.substring(i + 1, i + 3), radix: 16);
        if (v != null) {
          bytes.add(v);
          i += 2;
          continue;
        }
      }
      bytes.add(s.codeUnitAt(i));
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  // ---------------------------------------------------------------------------
  // Flags (Crockford Base32) and checksum
  // ---------------------------------------------------------------------------

  static String _encodeFlags(int value) =>
      '${_base32[(value >> 5) & 0x1F]}${_base32[value & 0x1F]}';

  static int? _decodeFlags(String s) {
    if (s.length != 2) return null;
    int out = 0;
    for (final unit in s.toUpperCase().codeUnits) {
      var c = String.fromCharCode(unit);
      // Crockford leniency: treat I/L as 1 and O as 0; U is invalid.
      if (c == 'I' || c == 'L') c = '1';
      if (c == 'O') c = '0';
      final idx = _base32.indexOf(c);
      if (idx < 0) return null;
      out = (out << 5) | idx;
    }
    return out;
  }

  /// NMEA/APRS-style checksum: XOR of every byte of [body], as two uppercase
  /// hex digits.
  static String _checksum(String body) {
    int x = 0;
    for (final unit in body.codeUnits) {
      x ^= unit;
    }
    return (x & 0xFF).toRadixString(16).toUpperCase().padLeft(2, '0');
  }
}
