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

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/winlink/winlink_gateway_database.dart';

// Mirrors the encoding in src/tools/build_winlink_db.py so the test builds a
// byte-identical .wdb image and exercises the reader against it.
int _encodeCallKey(String callWithSsid) {
  final parts = callWithSsid.split('-');
  final base = parts[0];
  final ssid = parts.length > 1 ? int.parse(parts[1]) : 0;
  var key = 0;
  for (final c in base.codeUnits) {
    final code = (c >= 0x41 && c <= 0x5A) ? c - 0x41 + 1 : c - 0x30 + 27;
    key = key * 37 + code;
  }
  return key * 16 + ssid;
}

void _writeUintBE(BytesBuilder b, int value, int len) {
  final out = <int>[];
  for (var i = 0; i < len; i++) {
    out.add((value >> (8 * (len - 1 - i))) & 0xFF);
  }
  b.add(out);
}

/// Builds a .wdb image from `(callWithSsid, lat, lon, freqHz)` rows. Rows must
/// already be grouped/sorted the way the builder emits them.
Uint8List _buildWdb(
  List<(String, double, double, int)> rows, {
  int sourceDate = 20260916,
  int version = WinlinkGatewayDatabase.formatVersion,
  List<int>? modes,
}) {
  final header = ByteData(WinlinkGatewayDatabase.headerSize);
  header.setUint32(0, WinlinkGatewayDatabase.magic, Endian.little);
  header.setUint16(4, version, Endian.little);
  header.setUint16(6, 0, Endian.little);
  header.setUint32(8, rows.length, Endian.little);
  header.setUint32(12, sourceDate, Endian.little);
  header.setUint32(16, WinlinkGatewayDatabase.headerSize, Endian.little);

  final body = BytesBuilder();
  for (final (index, (call, lat, lon, freq)) in rows.indexed) {
    _writeUintBE(body, _encodeCallKey(call), 5);
    _writeUintBE(body, ((lat + 90) * 10000).round(), 3);
    _writeUintBE(body, ((lon + 180) * 10000).round(), 3);
    _writeUintBE(body, (freq / 100).round(), 3);
    if (version != 1) body.add([modes?[index] ?? 1]);
  }

  final out = BytesBuilder();
  out.add(header.buffer.asUint8List());
  out.add(body.toBytes());
  return out.toBytes();
}

void main() {
  group('WinlinkGatewayDatabase', () {
    test('parses, groups frequencies, decodes callsign/SSID', () {
      final bytes = _buildWdb([
        ('KG4MRA-10', 37.5688421, -77.4663340, 145030000),
        ('KH6UU', 20.7363082, -156.4659692, 145090000),
        ('KK6DA-10', 34.1129432, -118.3022661, 145070000),
        ('KK6DA-10', 34.1129432, -118.3022661, 431050000),
      ]);
      final db = WinlinkGatewayDatabase.fromBytes(bytes);

      expect(db.sourceDate, 20260916);
      expect(db.gatewayCount, 3);

      final byCall = {for (final g in db.gateways) g.callsign: g};
      expect(byCall.containsKey('KH6UU'), true, reason: 'bare SSID-0 callsign');
      expect(byCall.containsKey('KG4MRA-10'), true);

      final kk = byCall['KK6DA-10']!;
      expect(kk.frequenciesHz, [145070000, 431050000]);
      expect(kk.frequenciesMHz, ['145.070', '431.050']);

      final kg = byCall['KG4MRA-10']!;
      expect((kg.latitude - 37.5688421).abs() < 1e-4, true);
      expect((kg.longitude - -77.4663340).abs() < 1e-4, true);
      expect(kg.frequenciesHz.single, 145030000);
    });

    test('nearest returns closest gateways first', () {
      final bytes = _buildWdb([
        ('AA1AA-10', 40.0, -75.0, 145010000),
        ('BB2BB-10', 41.0, -75.0, 145030000),
        ('CC3CC-10', 34.0, -118.0, 145050000),
      ]);
      final db = WinlinkGatewayDatabase.fromBytes(bytes);
      final near = db.nearest(40.1, -75.0, count: 2);
      expect(near.map((g) => g.callsign).toList(), ['AA1AA-10', 'BB2BB-10']);
    });

    test('preserves mode support and displays XARA-FM channel labels', () {
      final db = WinlinkGatewayDatabase.fromBytes(
        _buildWdb(
          [
            ('AA1AA-10', 40.0, -75.0, 145010000),
            ('AA1AA-10', 40.0, -75.0, 145030000),
            ('AA1AA-10', 40.0, -75.0, 145050000),
            ('BB2BB-10', 41.0, -75.0, 145070000),
          ],
          modes: [1, 2, 3, 2],
        ),
      );
      expect(db.gatewayCount, 2);
      final channels = db.gateways.first.channels;
      expect(channels.map((channel) => channel.supportsPacket), [
        true,
        false,
        true,
      ]);
      expect(channels.map((channel) => channel.supportsVaraFm), [
        false,
        true,
        true,
      ]);
      expect(channels.map((channel) => channel.modeLabel), [
        'Packet 1200',
        'XARA-FM',
        'Packet 1200 / XARA-FM',
      ]);
      expect(db.gateways.last.channels.single.supportsVaraFm, true);
    });

    test('reads version 1 caches as packet-only', () {
      final db = WinlinkGatewayDatabase.fromBytes(
        _buildWdb([
          ('AA1AA-10', 40.0, -75.0, 145010000),
          ('AA1AA-10', 40.0, -75.0, 145030000),
        ], version: 1),
      );
      expect(db.gateways.single.frequenciesHz, [145010000, 145030000]);
      expect(
        db.gateways.single.channels.every(
          (channel) => channel.supportsPacket && !channel.supportsVaraFm,
        ),
        true,
      );
    });

    test('rejects unknown versions, invalid modes and truncated records', () {
      for (final version in [0, 3]) {
        expect(
          () =>
              WinlinkGatewayDatabase.fromBytes(_buildWdb([], version: version)),
          throwsA(isA<FormatException>()),
        );
      }
      for (final modes in [0, 4]) {
        expect(
          () => WinlinkGatewayDatabase.fromBytes(
            _buildWdb([('AA1AA-10', 40.0, -75.0, 145010000)], modes: [modes]),
          ),
          throwsA(isA<FormatException>()),
        );
      }
      final bytes = _buildWdb([('AA1AA-10', 40.0, -75.0, 145010000)]);
      expect(
        () => WinlinkGatewayDatabase.fromBytes(
          Uint8List.sublistView(bytes, 0, bytes.length - 1),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('withinBounds culls to the box', () {
      final bytes = _buildWdb([
        ('AA1AA-10', 40.0, -75.0, 145010000),
        ('CC3CC-10', 34.0, -118.0, 145050000),
      ]);
      final db = WinlinkGatewayDatabase.fromBytes(bytes);
      final inBox = db.withinBounds(39.0, -76.0, 41.0, -74.0);
      expect(inBox.map((g) => g.callsign).toList(), ['AA1AA-10']);
    });

    test('rejects a bad magic', () {
      final bytes = _buildWdb([('AA1AA-10', 40.0, -75.0, 145010000)]);
      bytes[0] = 0x00;
      expect(
        () => WinlinkGatewayDatabase.fromBytes(bytes),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
