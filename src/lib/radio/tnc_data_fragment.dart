/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:typed_data';
import 'utils.dart';

/// Encoding type for TNC data fragments
enum FragmentEncodingType {
  unknown,
  loopback,
  hardwareAfsk1200,
  softwareAfsk1200,
  softwarePsk2400,
  softwareDart,
}

/// Frame type for TNC data fragments
enum FragmentFrameType { unknown, ax25, fx25 }

/// TNC Data Fragment - represents a fragment of data received from or to be sent to the radio
class TncDataFragment {
  bool finalFragment;
  int fragmentId;
  Uint8List data;
  int regionId;
  int channelId;
  String channelName;
  bool incoming;
  DateTime time;
  FragmentEncodingType encoding;
  FragmentFrameType frameType;
  int corrections;
  String? radioMac;
  int? radioDeviceId;
  String? usage;

  TncDataFragment({
    required this.finalFragment,
    required this.fragmentId,
    required this.data,
    required this.channelId,
    required this.regionId,
    this.channelName = '',
    this.incoming = false,
    DateTime? time,
    this.encoding = FragmentEncodingType.unknown,
    this.frameType = FragmentFrameType.unknown,
    this.corrections = -1,
    this.radioMac,
    this.radioDeviceId,
    this.usage,
  }) : time = time ?? DateTime.now() {
    if (channelName.isEmpty) {
      channelName = channelId == -1 ? '' : (channelId + 1).toString();
    }
  }

  /// Decode a TNC data fragment from raw bytes received from radio
  static TncDataFragment fromBytes(Uint8List msg) {
    final finalFragment = (msg[5] & 0x80) != 0;
    final withChannelId = (msg[5] & 0x40) != 0;
    final fragmentId = msg[5] & 0x3F;
    final dataLen = msg.length - 6 - (withChannelId ? 1 : 0);
    final data = Uint8List(dataLen);
    for (int i = 0; i < dataLen; i++) {
      data[i] = msg[6 + i];
    }
    final channelId = withChannelId ? msg[msg.length - 1] : -1;

    return TncDataFragment(
      finalFragment: finalFragment,
      fragmentId: fragmentId,
      data: data,
      channelId: channelId,
      regionId: -1,
    );
  }

  /// Append another fragment to this one (for multi-fragment packets)
  TncDataFragment append(TncDataFragment frame) {
    if (frame.fragmentId == fragmentId + 1 && !finalFragment) {
      // Merge the data
      final mergedData = Uint8List(data.length + frame.data.length);
      mergedData.setRange(0, data.length, data);
      mergedData.setRange(data.length, mergedData.length, frame.data);
      frame.data = mergedData;
      return frame;
    } else {
      // Discard the old data and just keep the new frame
      return frame;
    }
  }

  /// Serialize to bytes for sending to radio
  Uint8List toByteArray() {
    final len = 1 + data.length + (channelId != -1 ? 1 : 0);
    final rdata = Uint8List(len);

    rdata[0] = 0;
    if (finalFragment) rdata[0] |= 0x80;
    if (channelId != -1) rdata[0] |= 0x40;
    rdata[0] |= fragmentId & 0x3F;

    for (int i = 0; i < data.length; i++) {
      rdata[1 + i] = data[i];
    }

    if (channelId != -1) {
      rdata[rdata.length - 1] = channelId;
    }

    return rdata;
  }

  @override
  String toString() {
    return 'TncFrag4,$channelId,$regionId,$channelName,${RadioUtils.bytesToHex(data)},'
        '${encoding.index},${frameType.index},$corrections,${radioMac ?? ""}';
  }

  /// Parse a TNC fragment from its string representation
  static TncDataFragment? fromString(String str) {
    final parts = str.split(',');
    if (parts.length < 5 || !parts[0].startsWith('TncFrag')) return null;

    final channelId = int.tryParse(parts[1]) ?? -1;
    final regionId = int.tryParse(parts[2]) ?? -1;
    final channelName = parts[3];
    final data = RadioUtils.hexStringToByteArray(parts[4]);
    if (data == null) return null;

    var encoding = FragmentEncodingType.unknown;
    var frameType = FragmentFrameType.unknown;
    var corrections = -1;
    String? radioMac;

    if (parts.length > 5) {
      encoding = FragmentEncodingType.values[int.tryParse(parts[5]) ?? 0];
    }
    if (parts.length > 6) {
      frameType = FragmentFrameType.values[int.tryParse(parts[6]) ?? 0];
    }
    if (parts.length > 7) {
      corrections = int.tryParse(parts[7]) ?? -1;
    }
    if (parts.length > 8 && parts[8].isNotEmpty) {
      radioMac = parts[8];
    }

    return TncDataFragment(
      finalFragment: true,
      fragmentId: 0,
      data: data,
      channelId: channelId,
      regionId: regionId,
      channelName: channelName,
      encoding: encoding,
      frameType: frameType,
      corrections: corrections,
      radioMac: radioMac,
    );
  }

  /// Convert to JSON representation
  Map<String, dynamic> toJson() => {
    'finalFragment': finalFragment,
    'fragmentId': fragmentId,
    'channelId': channelId,
    'regionId': regionId,
    'channelName': channelName,
    'incoming': incoming,
    'time': time.toIso8601String(),
    'encoding': encoding.name,
    'frameType': frameType.name,
    'corrections': corrections,
    'dataHex': RadioUtils.bytesToHex(data),
    if (radioMac != null) 'radioMac': radioMac,
    if (radioDeviceId != null) 'radioDeviceId': radioDeviceId,
    if (usage != null) 'usage': usage,
  };

  /// Getter for isLast (alias for finalFragment)
  bool get isLast => finalFragment;

  /// Returns the hex string representation of this fragment's data.
  String toHex() => RadioUtils.bytesToHex(data);
}
