/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from the C# `aprsparser.AprsPacket` class.
*/

import '../radio/ax25_packet.dart';
import 'callsign.dart';
import 'coordinate.dart';
import 'message_data.dart';
import 'packet_data_type.dart';
import 'aprs_util.dart';

/// Represents a parsed APRS packet (TNC2 format), built from an [AX25Packet].
class AprsPacket {
  String rawPacket = '';
  Callsign? destCallsign;
  int dataTypeCh = 0; // code unit of the data-type character (0 = none)
  PacketDataType dataType = PacketDataType.unknown;
  String informationField = '';
  String comment = '';
  String? thirdPartyHeader;
  int symbolTableIdentifier = 0; // code unit (0 = none)
  int symbolCode = 0; // code unit (0 = none)
  bool fromD7 = false;
  bool fromD700 = false;
  AX25Packet? packet;
  String? authCode;
  Position position = Position();
  DateTime? timeStamp;
  MessageData messageData = MessageData();

  AprsPacket._();

  String get dataTypeChar =>
      dataTypeCh == 0 ? '' : String.fromCharCode(dataTypeCh);

  String get symbolTable => symbolTableIdentifier == 0
      ? ''
      : String.fromCharCode(symbolTableIdentifier);

  String get symbol => symbolCode == 0 ? '' : String.fromCharCode(symbolCode);

  /// Serializes for cross-window transport by encoding the underlying AX.25
  /// frame. Consumers rebuild the fully parsed packet with [fromJson].
  Map<String, dynamic>? toJson() => packet?.toJson();

  /// Rebuilds an [AprsPacket] from data produced by [toJson]. Always returns a
  /// non-null instance so it can be used as a data-broker serializer; if the
  /// frame cannot be parsed as APRS the returned packet has no underlying
  /// [packet] and is ignored by consumers.
  static AprsPacket fromJson(Map<String, dynamic> json) {
    final ax25 = AX25Packet.fromJson(json);
    if (ax25 != null) {
      final parsed = AprsPacket.parse(ax25);
      if (parsed != null) return parsed;
      final fallback = AprsPacket._();
      fallback.packet = ax25;
      return fallback;
    }
    return AprsPacket._();
  }

  static const int _charBrace = 0x7D; // '}'
  static const int _charLBrace = 0x7B; // '{'

  /// Parses an [AX25Packet] into an [AprsPacket]. Returns null on failure.
  static AprsPacket? parse(AX25Packet packet) {
    final r = AprsPacket._();
    try {
      String? dataStr = packet.dataStr;
      if (dataStr == null || dataStr.isEmpty) return null;

      // Strip a third-party header: "}HEADER*:..."
      if (dataStr.codeUnitAt(0) == _charBrace) {
        final i = dataStr.indexOf('*:');
        if (i < 1) return null;
        r.thirdPartyHeader = dataStr.substring(1, i);
        dataStr = dataStr.substring(i + 2);
      }
      if (dataStr.isEmpty) return null;

      r.packet = packet;
      r.position.clear();
      r.rawPacket = dataStr;
      if (packet.addresses.isEmpty) return null;
      r.destCallsign = Callsign.parseCallsign(
        packet.addresses[0].callSignWithId,
      );
      r.dataTypeCh = dataStr.codeUnitAt(0);
      r.dataType = AprsDataType.getDataType(r.dataTypeCh);
      if (r.dataType == PacketDataType.unknown) r.dataTypeCh = 0;
      if (r.dataType != PacketDataType.unknown) {
        r.informationField = dataStr.substring(1);
      } else {
        r.informationField = dataStr;
      }

      // Parse the optional auth code embedded as "}XXXXXX" near the end.
      if (r.informationField.isNotEmpty) {
        final i = r.informationField.lastIndexOf('}');
        if (i >= 0 && i == r.informationField.length - 7) {
          r.authCode = r.informationField.substring(i + 1, i + 7);
          r.informationField = r.informationField.substring(0, i);
        } else if (i >= 0 &&
            i < r.informationField.length - 7 &&
            r.informationField.codeUnitAt(i + 7) == _charLBrace) {
          r.authCode = r.informationField.substring(i + 1, i + 7);
          r.informationField =
              r.informationField.substring(0, i) +
              r.informationField.substring(i + 7);
        }
      }

      // Parse the information field.
      if (r.informationField.isNotEmpty) {
        r._parseInformationField();
      } else {
        r.dataType = PacketDataType.beacon;
      }

      // Compute the grid square if not already set.
      if (r.position.isValid() && r.position.gridsquare.isEmpty) {
        r.position.gridsquare = AprsUtil.latLonToGridSquareSet(
          r.position.coordinateSet,
        );
      }

      return r;
    } catch (_) {
      return null;
    }
  }

  void _parseInformationField() {
    switch (dataType) {
      case PacketDataType.unknown:
        break;
      case PacketDataType.position: // '!'
      case PacketDataType.positionMsg: // '='
        _parsePosition();
        break;
      case PacketDataType.positionTime: // '/'
      case PacketDataType.positionTimeMsg: // '@'
        _parsePositionTime();
        break;
      case PacketDataType.message: // ':'
        _parseMessage(informationField);
        break;
      case PacketDataType.micECurrent:
      case PacketDataType.micEOld:
      case PacketDataType.tmd700:
      case PacketDataType.micE:
        _parseMicE();
        break;
      default:
        // Not implemented - do nothing.
        break;
    }
  }

  void _parseDateTime(String str) {
    try {
      if (str.isEmpty) return;

      // Assume current date/time.
      timeStamp = DateTime.now().toUtc();

      final int l = str.length;
      final int last = str.codeUnitAt(l - 1);
      if (last == 0x7A) {
        // 'z' — DHM format (day/hour/minute) in Zulu (UTC).
        try {
          final day = int.parse(str.substring(0, 2));
          final hour = int.parse(str.substring(2, 4));
          final minute = int.parse(str.substring(4, 6));
          final now = timeStamp!;
          timeStamp = DateTime.utc(now.year, now.month, day, hour, minute, 0);
          // If the result is in the future the day must belong to the previous
          // month (e.g. day 30 parsed on the 5th of the next month).
          if (timeStamp!.isAfter(now)) {
            timeStamp = DateTime.utc(
              now.year,
              now.month - 1,
              day,
              hour,
              minute,
              0,
            );
          }
        } catch (_) {
          timeStamp = DateTime.now().toUtc();
        }
      } else if (last == 0x2F) {
        // '/' local time - not handled
        timeStamp = null;
      } else if (last == 0x68) {
        // 'h' — HMS format (hour/minute/second) in UTC.
        final hour = int.parse(str.substring(0, 2));
        final minute = int.parse(str.substring(2, 4));
        final second = int.parse(str.substring(4, 6));
        final now = timeStamp!;
        timeStamp = DateTime.utc(
          now.year,
          now.month,
          now.day,
          hour,
          minute,
          second,
        );
        // If the result is in the future the time must belong to yesterday
        // (e.g. 23:00h parsed at 02:00 the next day).
        if (timeStamp!.isAfter(now)) {
          timeStamp = timeStamp!.subtract(const Duration(days: 1));
        }
      } else if (l == 8) {
        final month = int.parse(str.substring(0, 2));
        final day = int.parse(str.substring(2, 4));
        final hour = int.parse(str.substring(4, 6));
        final minute = int.parse(str.substring(6, 8));
        final now = timeStamp!;
        timeStamp = DateTime.utc(now.year, month, day, hour, minute, 0);
        // If the result is in the future it likely belongs to the previous year.
        if (timeStamp!.isAfter(now)) {
          timeStamp = DateTime.utc(now.year - 1, month, day, hour, minute, 0);
        }
      } else {
        timeStamp = null;
      }
    } catch (_) {
      timeStamp = null;
    }
  }

  void _parseMessage(String infoField) {
    var s = infoField;

    // Addressee field must be 9 characters long.
    if (s.length < 9) {
      dataType = PacketDataType.invalidOrTestData;
      return;
    }

    // Get addressee.
    messageData.addressee = s.substring(0, 9).toUpperCase().trim();

    if (s.length < 10) return; // no message

    s = s.substring(10);

    // Look for ack and reject messages.
    if (s.length > 3) {
      if (s.toUpperCase().startsWith('ACK')) {
        final i = s.lastIndexOf('}');
        if (i >= 0) {
          authCode = s.substring(i + 1);
          s = s.substring(0, i - 1);
        }
        messageData.msgType = MessageType.mtAck;
        messageData.seqId = s.substring(3).trim();
        messageData.msgText = '';
        return;
      }
      if (s.toUpperCase().startsWith('REJ')) {
        final i = s.lastIndexOf('}');
        if (i >= 0) {
          authCode = s.substring(i + 1);
          s = s.substring(0, i - 1);
        }
        messageData.msgType = MessageType.mtRej;
        messageData.seqId = s.substring(3).trim();
        messageData.msgText = '';
        return;
      }
    }

    // Save sequence number - if any.
    final idx = s.lastIndexOf('{');
    if (idx >= 0) {
      messageData.seqId = s.substring(idx + 1);
      s = s.substring(0, s.length - messageData.seqId.length - 1);
    }

    // Assume standard message.
    messageData.msgType = MessageType.mtGeneral;

    if (s.isNotEmpty) {
      final upper = s.toUpperCase();
      if (upper.startsWith('NWS-')) {
        messageData.msgType = MessageType.mtNWS;
      } else if (upper.startsWith('NWS_')) {
        s = s.replaceAll('NWS_', 'NWS-');
        messageData.msgType = MessageType.mtNWS;
      } else if (upper.startsWith('BLN')) {
        if (RegExp(
          r'^BLN[A-Z]',
          caseSensitive: false,
        ).hasMatch(messageData.addressee)) {
          messageData.msgType = MessageType.mtAnnouncement;
        } else if (RegExp(
          r'^BLN[0-9]',
          caseSensitive: false,
        ).hasMatch(messageData.addressee)) {
          messageData.msgType = MessageType.mtBulletin;
        }
      } else if (RegExp(r'^AA:|^\[AA\]', caseSensitive: false).hasMatch(s)) {
        messageData.msgType = MessageType.mtAutoAnswer;
      }
    }

    // Save text of message.
    messageData.msgText = s;
  }

  int _convertDest(int ch) {
    int ci = ch - 0x30; // adjust all to be 0 based
    if (ci == 0x1C) ci = 0x0A; // change L to be a space digit
    if (ci > 0x10 && ci <= 0x1B) ci = ci - 1; // A-K need to be decremented
    if ((ci & 0x0F) == 0x0A) ci = ci & 0xF0; // space -> 0 (no ambiguity)
    return ci;
  }

  void _parseMicE() {
    if (destCallsign == null) return;
    final String dest = destCallsign!.stationCallsign;
    if (dest.length < 6 || dest.length == 7) return;

    final int a = 'A'.codeUnitAt(0);
    final int k = 'K'.codeUnitAt(0);
    final int l = 'L'.codeUnitAt(0);
    final int p = 'P'.codeUnitAt(0);
    final int z = 'Z'.codeUnitAt(0);
    final int zero = '0'.codeUnitAt(0);
    final int nine = '9'.codeUnitAt(0);

    final d0 = dest.codeUnitAt(0);
    final d1 = dest.codeUnitAt(1);
    final d2 = dest.codeUnitAt(2);
    final bool custom =
        (d0 >= a && d0 <= k) || (d1 >= a && d1 <= k) || (d2 >= a && d2 <= k);
    for (int j = 0; j < 3; j++) {
      final ch = dest.codeUnitAt(j);
      if (custom) {
        if (ch < zero || ch > l || (ch > nine && ch < a)) return;
      } else {
        if (ch < zero ||
            ch > z ||
            (ch > nine && ch < l) ||
            (ch > l && ch < p)) {
          return;
        }
      }
    }
    for (int j = 3; j < 6; j++) {
      final ch = dest.codeUnitAt(j);
      if (ch < zero || ch > z || (ch > nine && ch < l) || (ch > l && ch < p)) {
        return;
      }
    }
    if (dest.length > 6) {
      if (dest.codeUnitAt(6) != 0x2D ||
          dest.codeUnitAt(7) < zero ||
          dest.codeUnitAt(7) > nine) {
        return;
      }
      if (dest.length == 9) {
        if (dest.codeUnitAt(8) < zero || dest.codeUnitAt(8) > nine) return;
      }
    }

    // Parse the destination field.
    int c = _convertDest(dest.codeUnitAt(0));
    int mes = 0; // message code
    if ((c & 0x10) != 0) mes = 0x08; // custom flag
    if (c >= 0x10) mes = mes + 0x04;
    int d = (c & 0x0F) * 10; // degrees
    c = _convertDest(dest.codeUnitAt(1));
    if (c >= 0x10) mes = mes + 0x02;
    d = d + (c & 0x0F);
    c = _convertDest(dest.codeUnitAt(2));
    if (c >= 0x10) mes += 1;
    messageData.msgIndex = mes;
    int m = (c & 0x0F) * 10; // minutes
    c = _convertDest(dest.codeUnitAt(3));
    final bool north = c >= 0x20;
    m = m + (c & 0x0F);
    c = _convertDest(dest.codeUnitAt(4));
    final bool hundred = c >= 0x20; // flag for adjustment
    int sv = (c & 0x0F) * 10; // hundredths of minutes
    c = _convertDest(dest.codeUnitAt(5));
    final bool west = c >= 0x20;
    sv = sv + (c & 0x0F);
    double lat = d + (m / 60.0) + (sv / 6000.0);
    if (!north) lat = -lat;
    position.coordinateSet.latitude = Coordinate.fromValue(lat, true);

    // Parse the symbol.
    if (informationField.length > 6) {
      symbolCode = informationField.codeUnitAt(6);
    }
    if (informationField.length > 7) {
      symbolTableIdentifier = informationField.codeUnitAt(7);
    }

    // D7/D700 flags.
    if (informationField.length > 8) {
      fromD7 = informationField.codeUnitAt(8) == 0x3E; // '>'
      fromD700 = informationField.codeUnitAt(8) == 0x5D; // ']'
    }

    // Parse the longitude.
    d = informationField.codeUnitAt(0) - 28;
    m = informationField.codeUnitAt(1) - 28;
    sv = informationField.codeUnitAt(2) - 28;

    if (d < 0 || d > 99 || m < 0 || m > 99 || sv < 0 || sv > 99) {
      position.clear();
      return;
    }

    if (hundred) d = d + 100;
    if (d >= 190) {
      d = d - 190;
    } else if (d >= 180) {
      d = d - 80;
    }
    if (m >= 60) m = m - 60;
    double lon = d + (m / 60.0) + (sv / 6000.0);
    if (west) lon = -lon;
    position.coordinateSet.longitude = Coordinate.fromValue(lon, false);

    // Record comment.
    comment = informationField.length > 8 ? informationField.substring(8) : '';

    if (comment.length >= 4 && comment.codeUnitAt(3) == _charBrace) {
      d = comment.codeUnitAt(0) - 33;
      m = comment.codeUnitAt(1) - 33;
      sv = comment.codeUnitAt(2) - 33;
      if (d >= 0 && d <= 91 && m >= 0 && m <= 91 && sv >= 0 && sv <= 91) {
        position.altitude = (d * 91 * 91) + (m * 91) + sv;
      }
      comment = comment.substring(4);
    } else if (comment.length >= 5 &&
        (comment.codeUnitAt(0) == 0x3E || comment.codeUnitAt(0) == 0x5D) &&
        comment.codeUnitAt(4) == _charBrace) {
      d = comment.codeUnitAt(1) - 33;
      m = comment.codeUnitAt(2) - 33;
      sv = comment.codeUnitAt(3) - 33;
      if (d >= 0 && d <= 91 && m >= 0 && m <= 91 && sv >= 0 && sv <= 91) {
        position.altitude = (d * 91 * 91) + (m * 91) + sv;
      }
      comment = comment.substring(5);
    }
    comment = comment.trim();

    if (informationField.length > 5) {
      // Parse the Speed/Course (s/d).
      m = informationField.codeUnitAt(4) - 28;
      if (m < 0 || m > 97) return;
      sv = informationField.codeUnitAt(3) - 28;
      if (sv < 0 || sv > 99) return;
      sv = (sv * 10) + (m ~/ 10); // speed in knots
      d = informationField.codeUnitAt(5) - 28;
      if (d < 0 || d > 99) return;

      d = ((m % 10) * 100) + d; // course
      if (sv >= 800) sv = sv - 800;
      if (d >= 400) d = d - 400;
      if (d > 0) {
        position.course = d;
        position.speed = sv;
      }
    }
  }

  void _parsePosition() {
    comment = _parsePositionAndSymbol(informationField);
  }

  bool _isDigit(int ch) => ch >= 0x30 && ch <= 0x39;

  String _parsePositionAndSymbol(String ps) {
    try {
      if (ps.isEmpty) {
        position.clear();
        return '';
      }

      // Compressed format if the first character is not a digit.
      if (!_isDigit(ps.codeUnitAt(0))) {
        if (ps.length < 13) {
          position.clear();
          return '';
        }
        final pd = ps.substring(0, 13);

        symbolTableIdentifier = pd.codeUnitAt(0);
        // Compressed format never starts with a digit; to represent a digit
        // overlay character, a letter (a..j) is used instead.
        if (symbolTableIdentifier >= 0x61 && symbolTableIdentifier <= 0x6A) {
          symbolTableIdentifier =
              symbolTableIdentifier - 'a'.codeUnitAt(0) + '0'.codeUnitAt(0);
        }
        symbolCode = pd.codeUnitAt(9);

        const int sqr91 = 91 * 91;
        const int cube91 = 91 * 91 * 91;

        // lat
        final sLat = pd.substring(1, 5);
        final double dLat =
            90 -
            ((sLat.codeUnitAt(0) - 33) * cube91 +
                    (sLat.codeUnitAt(1) - 33) * sqr91 +
                    (sLat.codeUnitAt(2) - 33) * 91 +
                    (sLat.codeUnitAt(3) - 33)) /
                380926.0;
        position.coordinateSet.latitude = Coordinate.fromValue(dLat, true);

        // lon
        final sLon = pd.substring(5, 9);
        final double dLon =
            -180 +
            ((sLon.codeUnitAt(0) - 33) * cube91 +
                    (sLon.codeUnitAt(1) - 33) * sqr91 +
                    (sLon.codeUnitAt(2) - 33) * 91 +
                    (sLon.codeUnitAt(3) - 33)) /
                190463.0;
        position.coordinateSet.longitude = Coordinate.fromValue(dLon, false);

        ps = ps.substring(13);
      } else {
        if (ps.length < 19) {
          position.clear();
          return '';
        }

        // Normal (uncompressed).
        final pd = ps.substring(0, 19);
        final sLat = pd.substring(0, 8);
        symbolTableIdentifier = pd.codeUnitAt(8);
        final sLon = pd.substring(9, 18);
        symbolCode = pd.codeUnitAt(18);

        position.coordinateSet.latitude = Coordinate.fromNmea(sLat);
        position.coordinateSet.longitude = Coordinate.fromNmea(sLon);

        if (position.coordinateSet.latitude.value < -90 ||
            position.coordinateSet.latitude.value > 90 ||
            position.coordinateSet.longitude.value < -180 ||
            position.coordinateSet.longitude.value > 180) {
          position.clear();
        }

        ps = ps.substring(19);

        // Course and speed.
        if (ps.length >= 7 &&
            ps.codeUnitAt(3) == 0x2F &&
            _isDigit(ps.codeUnitAt(0)) &&
            _isDigit(ps.codeUnitAt(1)) &&
            _isDigit(ps.codeUnitAt(2)) &&
            _isDigit(ps.codeUnitAt(4)) &&
            _isDigit(ps.codeUnitAt(5)) &&
            _isDigit(ps.codeUnitAt(6))) {
          position.course = int.parse(ps.substring(0, 3));
          position.speed = int.parse(ps.substring(4, 7));
          ps = ps.substring(7);
        }

        // Altitude (/A=nnnnnn).
        if (ps.length >= 9 &&
            ps.codeUnitAt(0) == 0x2F &&
            ps.codeUnitAt(1) == 0x41 &&
            ps.codeUnitAt(2) == 0x3D &&
            _isDigit(ps.codeUnitAt(3)) &&
            _isDigit(ps.codeUnitAt(4)) &&
            _isDigit(ps.codeUnitAt(5)) &&
            _isDigit(ps.codeUnitAt(6)) &&
            _isDigit(ps.codeUnitAt(7)) &&
            _isDigit(ps.codeUnitAt(8))) {
          position.altitude = int.parse(ps.substring(3, 9));
          ps = ps.substring(9);
        }
      }
      return ps;
    } catch (_) {
      return informationField;
    }
  }

  void _parsePositionTime() {
    _parseDateTime(informationField.substring(0, 7));
    final psr = informationField.substring(7);
    comment = _parsePositionAndSymbol(psr);
    // Ignoring weather data "_" for now.
  }
}
