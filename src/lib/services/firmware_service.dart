/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:grpc/grpc.dart';
import 'package:http/http.dart' as http;

import '../utils/bspatch.dart';

/// Firmware update acquisition: cloud check (Layer 1) and download + assemble
/// (Layer 2).
///
/// Dart port of the `benlink` reference `firmware.py`. Layer 3 (flashing the
/// assembled image to the radio) lives in `firmware_updater.dart`.

/// Progress callback: `(stage, bytesDone, bytesTotal)`. `bytesTotal` may be 0
/// when the total is unknown.
typedef FirmwareProgress = void Function(String stage, int done, int total);

/// A single firmware descriptor returned by `CheckFirmwareUpdate`
/// (`FirmwareInfo` in the proto).
class FirmwareInfo {
  final int version;
  final String url;
  final String md5;
  final String releaseNotes;

  /// Release date as a Unix timestamp in seconds (0 when unknown).
  final int releaseDate;

  const FirmwareInfo({
    required this.version,
    required this.url,
    this.md5 = '',
    this.releaseNotes = '',
    this.releaseDate = 0,
  });
}

/// Firmware returned by the cloud check: the `firmware` (patch) and `base`
/// descriptors from `CheckFirmwareUpdateResult`.
class FirmwareUpdateInfo {
  final FirmwareInfo firmware;
  final FirmwareInfo base;

  const FirmwareUpdateInfo({required this.firmware, required this.base});

  String get patchUrl => firmware.url;
  String get baseUrl => base.url;

  /// The firmware version reported by the server (e.g. `147`).
  int get version => firmware.version;

  /// The firmware version formatted as `major.minor.patch` from the packed
  /// nibble representation (e.g. `147` -> `0.9.3`), matching how the radio
  /// reports its own software version.
  String get semanticVersion =>
      '${(version >> 8) & 0xF}.${(version >> 4) & 0xF}.${version & 0xF}';

  /// Human-readable version tag (e.g. `v0.9.3`), or `unknown`.
  String get displayVersion => version > 0 ? 'v$semanticVersion' : 'unknown';

  /// Release notes for the firmware, or an empty string when none were sent.
  String get releaseNotes => firmware.releaseNotes;

  /// Release date as a Unix timestamp in seconds (0 when unknown).
  int get releaseDate => firmware.releaseDate;
}

/// An assembled, ready-to-flash firmware image.
class FirmwareBundle {
  final Uint8List data;
  final FirmwareUpdateInfo? updateInfo;

  /// Lower-case hex MD5 of [data].
  final String md5Hex;

  FirmwareBundle._(this.data, this.updateInfo, this.md5Hex);

  factory FirmwareBundle(Uint8List data, {FirmwareUpdateInfo? updateInfo}) {
    final digest = md5.convert(data).toString();
    return FirmwareBundle._(data, updateInfo, digest);
  }

  int get size => data.length;

  /// Last 4 bytes of the MD5 digest — sent in `UPDATE_SYNC_REQ`.
  Uint8List get md5Tail {
    final bytes = md5.convert(data).bytes;
    return Uint8List.fromList(bytes.sublist(bytes.length - 4));
  }
}

class FirmwareService {
  static const String _grpcHost = 'rpc.benshikj.com';
  static const int _grpcPort = 800;
  static const String _grpcPath =
      '/benshikj.DeviceManagement/CheckFirmwareUpdate';

  /// Layer 1: query the Benshi gRPC endpoint for the latest firmware.
  ///
  /// [productId] is the radio's numeric product ID (from `GET_DEV_INFO` /
  /// `RadioDevInfo.productId`). Pass [firmwareVersion] `0` (the default) to get
  /// the latest firmware. Returns `null` when the server returns no firmware
  /// information.
  static Future<FirmwareUpdateInfo?> checkUpdate({
    required int productId,
    int firmwareVersion = 0,
    bool beta = false,
    void Function(String message)? log,
  }) async {
    final channel = ClientChannel(
      _grpcHost,
      port: _grpcPort,
      options: const ChannelOptions(credentials: ChannelCredentials.secure()),
    );
    final client = _RawGrpcClient(channel);

    try {
      final request = _encodeCheckRequest(productId, firmwareVersion, beta);
      final response = await client.checkUpdate(
        request,
        options: CallOptions(timeout: const Duration(seconds: 10)),
      );

      final respBytes = Uint8List.fromList(response);

      if (response.isEmpty) return null;

      final info = _decodeResult(respBytes);
      if (info == null) {
        log?.call('Firmware check parsed: no firmware information');
        return null;
      }
      log?.call(
        'Firmware check parsed: version=${info.version} '
        'patch=${info.patchUrl} base=${info.baseUrl}',
      );
      return info;
    } catch (e) {
      log?.call('Firmware check failed: $e');
      rethrow;
    } finally {
      await channel.shutdown();
    }
  }

  /// Layer 2: download the patch + base zip and assemble the final image.
  static Future<FirmwareBundle> downloadFirmware(
    FirmwareUpdateInfo info, {
    FirmwareProgress? progress,
  }) async {
    final patchBytes = await _fetch(info.patchUrl, 'patch', progress);
    final baseZipBytes = await _fetch(info.baseUrl, 'base', progress);

    // Extract the .bin from the base zip.
    final archive = ZipDecoder().decodeBytes(baseZipBytes);
    ArchiveFile? binFile;
    for (final file in archive.files) {
      if (file.isFile && file.name.toLowerCase().endsWith('.bin')) {
        binFile = file;
        break;
      }
    }
    if (binFile == null) {
      throw const FormatException('No .bin file found inside base zip');
    }
    final baseBytes = Uint8List.fromList(binFile.content as List<int>);

    if (!BsPatch.isBsdiff40(patchBytes)) {
      throw const FormatException('Unexpected patch format (expected BSDIFF40)');
    }

    // Assembly is a single synchronous step; report it as indeterminate rather
    // than a meaningless 1-byte progress count.
    progress?.call('assemble', 0, 0);
    final firmware = BsPatch.apply(baseBytes, patchBytes);

    return FirmwareBundle(firmware, updateInfo: info);
  }

  /// Assemble firmware from already-downloaded local files (offline/testing).
  static Uint8List assembleFromBytes(Uint8List baseBin, Uint8List patchBin) {
    if (!BsPatch.isBsdiff40(patchBin)) {
      throw const FormatException('Unexpected patch format (expected BSDIFF40)');
    }
    return BsPatch.apply(baseBin, patchBin);
  }

  /// Layer 1 + 2 combined: check, then download and assemble if available.
  static Future<FirmwareBundle?> fetchFirmware({
    required int productId,
    int firmwareVersion = 0,
    FirmwareProgress? progress,
  }) async {
    final info = await checkUpdate(
      productId: productId,
      firmwareVersion: firmwareVersion,
    );
    if (info == null) return null;
    return downloadFirmware(info, progress: progress);
  }

  // ── HTTP download ─────────────────────────────────────────────────────────

  static Future<Uint8List> _fetch(
    String url,
    String stage,
    FirmwareProgress? progress,
  ) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw http.ClientException(
          'Download failed (${response.statusCode}) for $url',
        );
      }
      final total = response.contentLength ?? 0;
      final builder = BytesBuilder(copy: false);
      int received = 0;
      await for (final chunk in response.stream) {
        builder.add(chunk);
        received += chunk.length;
        progress?.call(stage, received, total);
      }
      return builder.toBytes();
    } finally {
      client.close();
    }
  }

  // ── Minimal proto3 wire-format encode / decode ────────────────────────────

  static Uint8List _varint(int n) {
    final out = <int>[];
    while (n > 0x7F) {
      out.add((n & 0x7F) | 0x80);
      n >>= 7;
    }
    out.add(n & 0x7F);
    return Uint8List.fromList(out);
  }

  static Uint8List _encodeLengthDelimited(int fieldNum, List<int> b) {
    final tag = (fieldNum << 3) | 2; // wire type 2 = length-delimited
    return Uint8List.fromList([tag, ..._varint(b.length), ...b]);
  }

  static Uint8List _encodeStringField(int fieldNum, String s) =>
      _encodeLengthDelimited(fieldNum, Uint8List.fromList(s.codeUnits));

  static Uint8List _encodeVarintField(int fieldNum, int value) {
    final tag = fieldNum << 3; // wire type 0 = varint
    return Uint8List.fromList([..._varint(tag), ..._varint(value)]);
  }

  /// Encode `CheckFirmwareUpdateRequest { productId=1, firmwareVersion=2,
  /// beta=3, userId=4, inviteCode=5 }`. Proto3 omits zero/false fields.
  static Uint8List _encodeCheckRequest(
    int productId,
    int firmwareVersion,
    bool beta, {
    int userId = 0,
    int inviteCode = 0,
  }) {
    final out = <int>[];
    if (productId != 0) out.addAll(_encodeVarintField(1, productId));
    if (firmwareVersion != 0) {
      out.addAll(_encodeVarintField(2, firmwareVersion));
    }
    if (beta) out.addAll(_encodeVarintField(3, 1));
    if (userId != 0) out.addAll(_encodeVarintField(4, userId));
    if (inviteCode != 0) out.addAll(_encodeVarintField(5, inviteCode));
    return Uint8List.fromList(out);
  }

  /// Decode proto3 wire fields into `(fieldNumber, wireType, rawValueBytes)`.
  static List<(int, int, Uint8List)> _decodeProtoFields(Uint8List data) {
    final out = <(int, int, Uint8List)>[];
    int pos = 0;
    final n = data.length;

    int readVarint() {
      int val = 0;
      int shift = 0;
      while (pos < n) {
        final b = data[pos];
        pos++;
        val |= (b & 0x7F) << shift;
        shift += 7;
        if ((b & 0x80) == 0) return val;
      }
      return val;
    }

    while (pos < n) {
      final tag = readVarint();
      final fieldNum = tag >> 3;
      final wireType = tag & 0x7;

      if (wireType == 0) {
        final val = readVarint();
        out.add((fieldNum, wireType, _varint(val)));
      } else if (wireType == 2) {
        final length = readVarint();
        if (pos + length > n) break;
        out.add((fieldNum, wireType, Uint8List.sublistView(data, pos, pos + length)));
        pos += length;
      } else if (wireType == 5) {
        if (pos + 4 > n) break;
        out.add((fieldNum, wireType, Uint8List.sublistView(data, pos, pos + 4)));
        pos += 4;
      } else if (wireType == 1) {
        if (pos + 8 > n) break;
        out.add((fieldNum, wireType, Uint8List.sublistView(data, pos, pos + 8)));
        pos += 8;
      } else {
        break; // unknown wire type — stop gracefully
      }
    }
    return out;
  }

  static int _readVarintBytes(Uint8List b) {
    int val = 0;
    int shift = 0;
    for (final byte in b) {
      val |= (byte & 0x7F) << shift;
      shift += 7;
      if ((byte & 0x80) == 0) break;
    }
    return val;
  }

  /// Decode a nested `FirmwareInfo { version=1, url=2, md5=3, releaseNotes=4,
  /// releaseDate=5 }` message.
  static FirmwareInfo? _decodeFirmwareInfo(Uint8List data) {
    int version = 0;
    String url = '';
    String md5Str = '';
    String notes = '';
    int date = 0;
    for (final (fieldNum, wireType, value) in _decodeProtoFields(data)) {
      switch (fieldNum) {
        case 1:
          if (wireType == 0) version = _readVarintBytes(value);
          break;
        case 2:
          if (wireType == 2) url = String.fromCharCodes(value);
          break;
        case 3:
          if (wireType == 2) md5Str = String.fromCharCodes(value);
          break;
        case 4:
          if (wireType == 2) notes = utf8.decode(value, allowMalformed: true);
          break;
        case 5:
          // Release date: a Unix timestamp encoded as a varint.
          if (wireType == 0) date = _readVarintBytes(value);
          break;
      }
    }
    if (url.isEmpty) return null;
    return FirmwareInfo(
      version: version,
      url: url,
      md5: md5Str,
      releaseNotes: notes,
      releaseDate: date,
    );
  }

  /// Decode `CheckFirmwareUpdateResult { firmware=1, base=2 }`.
  static FirmwareUpdateInfo? _decodeResult(Uint8List data) {
    FirmwareInfo? firmware;
    FirmwareInfo? base;
    for (final (fieldNum, wireType, value) in _decodeProtoFields(data)) {
      if (wireType != 2) continue;
      if (fieldNum == 1) {
        firmware = _decodeFirmwareInfo(value);
      } else if (fieldNum == 2) {
        base = _decodeFirmwareInfo(value);
      }
    }
    if (firmware == null || base == null) return null;
    return FirmwareUpdateInfo(firmware: firmware, base: base);
  }

  // ── Test hooks ────────────────────────────────────────────────────────────

  @visibleForTesting
  static Uint8List debugEncodeCheckRequest(
    int productId, {
    int firmwareVersion = 0,
    bool beta = false,
  }) => _encodeCheckRequest(productId, firmwareVersion, beta);

  @visibleForTesting
  static Uint8List debugEncodeStringField(int fieldNum, String s) =>
      _encodeStringField(fieldNum, s);

  @visibleForTesting
  static Uint8List debugEncodeMessageField(int fieldNum, Uint8List b) =>
      _encodeLengthDelimited(fieldNum, b);

  @visibleForTesting
  static FirmwareUpdateInfo? debugDecodeResult(Uint8List data) =>
      _decodeResult(data);
}

/// A gRPC client that sends and receives raw bytes, avoiding generated protobuf
/// stubs (the request/response are hand-encoded proto3).
class _RawGrpcClient extends Client {
  _RawGrpcClient(super.channel);

  static final ClientMethod<List<int>, List<int>> _checkUpdateMethod =
      ClientMethod<List<int>, List<int>>(
        FirmwareService._grpcPath,
        (List<int> value) => value,
        (List<int> value) => value,
      );

  ResponseFuture<List<int>> checkUpdate(
    List<int> request, {
    CallOptions? options,
  }) {
    return $createUnaryCall(_checkUpdateMethod, request, options: options);
  }
}
