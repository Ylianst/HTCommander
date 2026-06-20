/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:convert';
import 'dart:typed_data';

import 'utils.dart';

/// BSS (Binary Short Serialization) packet field type identifiers.
class BSSFieldType {
  static const int callsign = 0x20;
  static const int destination = 0x21;
  static const int message = 0x24;
  static const int location = 0x25;

  /// Contains a callsign string like "N0CALL" or "NOCALL-0".
  static const int locationRequest = 0x27;

  /// Contains a callsign string like "N0CALL" or "NOCALL-0".
  static const int callRequest = 0x28;
}

/// Represents a BSS (Binary Short Serialization) packet used for compact data
/// encoding. The packet format is:
///   0x01 [length][type][value...] [length][type][value...] ...
/// where length includes the type byte (length = 1 + value.length).
class BSSPacket {
  /// The callsign field (type 0x20).
  String? callsign;

  /// The destination field (type 0x21).
  String? destination;

  /// The message field (type 0x24).
  String? message;

  /// The raw bytes of the location field (type 0x25).
  Uint8List? location;

  /// The location request field (type 0x27).
  String? locationRequest;

  /// The call request field (type 0x28).
  String? callRequest;

  /// The message ID field (parsed when length byte is 0x85).
  int messageId = 0;

  /// Raw field values keyed by field type byte, for unknown/future fields.
  final Map<int, Uint8List> rawFields = {};

  BSSPacket();

  /// Returns true if the given data appears to be a BSS packet (starts with
  /// 0x01 and has at least 2 bytes).
  static bool isBSSPacket(Uint8List? data) {
    return data != null && data.length >= 2 && data[0] == 0x01;
  }

  /// Decodes a BSS packet from raw byte data. Returns null if the data is
  /// invalid.
  static BSSPacket? decode(Uint8List? data) {
    if (data == null || data.length < 2) return null;

    // BSS packets must start with 0x01
    if (data[0] != 0x01) return null;

    final packet = BSSPacket();
    int index = 1; // Skip the leading 0x01

    while (index < data.length) {
      // Need at least length + type bytes
      if (index + 1 >= data.length) break;

      final length = data[index];

      // Special case: 0x85 indicates MessageID (next 2 bytes, MSB first)
      if (length == 0x85) {
        if (index + 3 > data.length) break;
        packet.messageId = (data[index + 1] << 8) | data[index + 2];
        index += 3;
        continue;
      }

      final fieldType = data[index + 1];

      // Length must allow type (1) + value (0+)
      if (length < 1) break;

      final valueLen = length - 1;

      // Check if we have enough bytes for the value
      if (index + 2 + valueLen > data.length) break;

      final value = Uint8List.sublistView(
        data,
        index + 2,
        index + 2 + valueLen,
      );

      // Store the raw field
      packet.rawFields[fieldType] = Uint8List.fromList(value);

      // Parse known field types
      switch (fieldType) {
        case BSSFieldType.callsign:
          packet.callsign = utf8.decode(value, allowMalformed: true);
          break;
        case BSSFieldType.destination:
          packet.destination = utf8.decode(value, allowMalformed: true);
          break;
        case BSSFieldType.message:
          packet.message = utf8.decode(value, allowMalformed: true);
          break;
        case BSSFieldType.location:
          packet.location = Uint8List.fromList(value);
          break;
        case BSSFieldType.locationRequest:
          packet.locationRequest = utf8.decode(value, allowMalformed: true);
          break;
        case BSSFieldType.callRequest:
          packet.callRequest = utf8.decode(value, allowMalformed: true);
          break;
      }

      // Move to the next field
      index += 2 + valueLen;
    }

    return packet;
  }

  /// Gets a raw field value by type, or null if not present.
  Uint8List? getRawField(int fieldType) => rawFields[fieldType];

  /// Returns true if [fieldType] is one of the known/parsed field types.
  static bool isKnownField(int fieldType) {
    return fieldType == BSSFieldType.callsign ||
        fieldType == BSSFieldType.destination ||
        fieldType == BSSFieldType.message ||
        fieldType == BSSFieldType.location ||
        fieldType == BSSFieldType.locationRequest ||
        fieldType == BSSFieldType.callRequest;
  }

  @override
  String toString() {
    final sb = StringBuffer();
    bool first = true;

    if (callsign != null && callsign!.isNotEmpty) {
      sb.write('Callsign: $callsign');
      first = false;
    }

    if (destination != null && destination!.isNotEmpty) {
      if (!first) sb.write(', ');
      sb.write('Dest: $destination');
      first = false;
    }

    if (message != null && message!.isNotEmpty) {
      if (!first) sb.write(', ');
      sb.write('Msg: $message');
      first = false;
    }

    if (location != null) {
      if (!first) sb.write(', ');
      sb.write('Loc: ${RadioUtils.bytesToHex(location!)}');
      first = false;
    }

    // Include any unknown raw fields
    for (final entry in rawFields.entries) {
      if (isKnownField(entry.key)) continue;
      if (!first) sb.write(', ');
      sb.write('${entry.key}: ${RadioUtils.bytesToHex(entry.value)}');
      first = false;
    }

    return sb.toString();
  }
}
