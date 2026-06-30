/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:typed_data';

/// AX.25 address (callsign + SSID)
class AX25Address {
  String address;
  int ssid;
  bool crBit1 = false; // Command/Response bit
  bool crBit2 = false; // Reserved bit 1
  bool crBit3 = true; // Reserved bit 2

  AX25Address._({required this.address, required this.ssid});

  /// Returns the callsign with SSID (e.g., "K7VZT-5")
  String get callSignWithId => '$address-$ssid';

  /// Check if two addresses are the same (ignoring CR bits)
  bool isSame(AX25Address a) {
    return address == a.address && ssid == a.ssid;
  }

  /// Create an address from callsign and SSID
  static AX25Address? getAddress(String address, [int ssid = 0]) {
    if (address.isEmpty || address.length > 6) return null;
    if (ssid > 15 || ssid < 0) return null;
    return AX25Address._(address: address.toUpperCase(), ssid: ssid);
  }

  /// Parse an address from string (e.g., "K7VZT-5" or "K7VZT")
  static AX25Address? parse(String addressStr) {
    if (addressStr.isEmpty || addressStr.length > 9) return null;

    final dashIndex = addressStr.indexOf('-');
    int ssid = 0;
    String address;

    if (dashIndex == -1) {
      // No SSID, assume 0
      if (addressStr.length > 6) return null;
      address = addressStr;
    } else {
      if (dashIndex < 1) return null;
      final ssidStr = addressStr.substring(dashIndex + 1);
      final parsedSsid = int.tryParse(ssidStr);
      if (parsedSsid == null || parsedSsid > 15 || parsedSsid < 0) return null;
      ssid = parsedSsid;
      address = addressStr.substring(0, dashIndex);
    }

    if (address.isEmpty) return null;
    return AX25Address.getAddress(address, ssid);
  }

  /// Decode an AX.25 address from raw bytes
  /// Returns the address and whether this is the last address in the path
  static ({AX25Address? address, bool last}) decodeAX25Address(
    Uint8List data,
    int index,
  ) {
    if (index + 7 > data.length) return (address: null, last: false);

    final addressBuilder = StringBuffer();
    for (int i = 0; i < 6; i++) {
      final c = data[index + i] >> 1;
      if (c < 0x20) return (address: null, last: false);
      if (c != 0x20) addressBuilder.write(String.fromCharCode(c));
      if ((data[index + i] & 0x01) != 0) return (address: null, last: false);
    }

    final ssid = (data[index + 6] >> 1) & 0x0F;
    final last = (data[index + 6] & 0x01) != 0;

    final addr = AX25Address.getAddress(addressBuilder.toString(), ssid);
    if (addr == null) return (address: null, last: false);

    addr.crBit1 = (data[index + 6] & 0x80) != 0;
    addr.crBit2 = (data[index + 6] & 0x40) != 0;
    addr.crBit3 = (data[index + 6] & 0x20) != 0;

    return (address: addr, last: last);
  }

  /// Encode this address to bytes
  Uint8List toByteArray(bool last) {
    if (address.isEmpty || address.length > 6) return Uint8List(0);
    if (ssid > 15 || ssid < 0) return Uint8List(0);

    final rdata = Uint8List(7);
    String addressPadded = address;
    while (addressPadded.length < 6) {
      addressPadded += String.fromCharCode(0x20);
    }

    for (int i = 0; i < 6; i++) {
      rdata[i] = addressPadded.codeUnitAt(i) << 1;
    }

    rdata[6] = ssid << 1;
    if (crBit1) rdata[6] |= 0x80;
    if (crBit2) rdata[6] |= 0x40;
    if (crBit3) rdata[6] |= 0x20;
    if (last) rdata[6] |= 0x01;

    return rdata;
  }

  @override
  String toString() {
    if (ssid == 0) return address;
    return '$address-$ssid';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AX25Address &&
        other.address == address &&
        other.ssid == ssid;
  }

  @override
  int get hashCode => address.hashCode ^ ssid.hashCode;
}
