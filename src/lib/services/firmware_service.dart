/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

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

/// URLs returned by the cloud for an available firmware update.
class FirmwareUpdateInfo {
  final String patchUrl;
  final String baseUrl;

  const FirmwareUpdateInfo({required this.patchUrl, required this.baseUrl});

  /// Best-effort parse of the OSS internal version (e.g. `v147`) from the patch
  /// URL, or `unknown`.
  String get internalVersion {
    final m = RegExp(r'/firmware/(v\d+)/').firstMatch(patchUrl);
    return m != null ? m.group(1)! : 'unknown';
  }
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
  static const String _grpcPath = '/benshikj.APP/CheckUpdate';

  /// Default model name sent to the update server.
  static const String defaultModel = 'VR_N7600';

  /// Public OSS URLs for the latest firmware known to this build (from the
  /// benlink reference: OSS v147 / firmware v0.9.3-7).
  ///
  /// The vendor's gRPC check only reports an update when it recognizes the
  /// radio's serial number, which HTCommander does not send. These public URLs
  /// let the user download and assemble the latest known firmware with **no**
  /// identifying information (no serial, no gRPC call at all). Update these when
  /// a newer firmware release is confirmed.
  static const String knownLatestVersion = 'v147';
  static const String _knownPatchUrl =
      'https://pubdatas.oss-cn-shenzhen.aliyuncs.com/firmware/v147/patch_base_to_vr_n76.bin';
  static const String _knownBaseUrl =
      'https://pubdatas.oss-cn-shenzhen.aliyuncs.com/upgrade_base_v1.bin.zip';

  /// The latest firmware known to this build, as public OSS URLs. Downloading
  /// this requires no identifying information and does not contact the vendor's
  /// gRPC endpoint.
  static FirmwareUpdateInfo knownLatest() =>
      const FirmwareUpdateInfo(patchUrl: _knownPatchUrl, baseUrl: _knownBaseUrl);

  /// Layer 1: query the Benshi gRPC endpoint for an available firmware update.
  ///
  /// [did] is the device serial (optional — the server returns URLs regardless
  /// of DID). [fwVersion] is the radio's current version; pass `"V0.0.0"` to
  /// always trigger an update response. Returns `null` when no update is
  /// available.
  static Future<FirmwareUpdateInfo?> checkUpdate({
    String did = '',
    String fwVersion = 'V0.0.0',
    String model = defaultModel,
    void Function(String message)? log,
  }) async {
    final channel = ClientChannel(
      _grpcHost,
      port: _grpcPort,
      options: const ChannelOptions(credentials: ChannelCredentials.secure()),
    );
    final client = _RawGrpcClient(channel);

    try {
      final request = _encodeCheckRequest(did, fwVersion, model);
      log?.call(
        'Firmware check request -> $_grpcHost:$_grpcPort$_grpcPath '
        'model="$model" version="$fwVersion" '
        'did="${did.isEmpty ? '(empty)' : did}"',
      );
      log?.call('Firmware check request bytes: ${_hex(request)}');
      final response = await client.checkUpdate(
        request,
        options: CallOptions(timeout: const Duration(seconds: 10)),
      );

      final respBytes = Uint8List.fromList(response);
      log?.call(
        'Firmware check response (${respBytes.length} bytes): '
        '${respBytes.isEmpty ? '(empty)' : _hex(respBytes)}',
      );

      if (response.isEmpty) return null;

      final have = _decodeHaveUpdate(respBytes);
      final urls = _extractUrls(respBytes);
      log?.call('Firmware check parsed: haveUpdate=$have urls=$urls');

      if (!have) return null;
      if (urls.length < 2) return null;

      final patchUrl = urls.firstWhere(
        (u) => u.contains('patch'),
        orElse: () => urls[0],
      );
      final baseUrl = urls.firstWhere(
        (u) => u.contains('base') && !u.contains('patch'),
        orElse: () => urls.firstWhere(
          (u) => u != patchUrl,
          orElse: () => '',
        ),
      );
      if (baseUrl.isEmpty) return null;

      return FirmwareUpdateInfo(patchUrl: patchUrl, baseUrl: baseUrl);
    } catch (e) {
      log?.call('Firmware check failed: $e');
      rethrow;
    } finally {
      await channel.shutdown();
    }
  }

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

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
    String did = '',
    String fwVersion = 'V0.0.0',
    FirmwareProgress? progress,
  }) async {
    final info = await checkUpdate(did: did, fwVersion: fwVersion);
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

  static Uint8List _encodeStringField(int fieldNum, String s) {
    final b = Uint8List.fromList(s.codeUnits);
    final tag = (fieldNum << 3) | 2; // wire type 2 = length-delimited
    return Uint8List.fromList([tag, ..._varint(b.length), ...b]);
  }

  /// Encode `CheckFirmwareUpdateRequest { did=1, firmwareVersion=2, model=3 }`.
  static Uint8List _encodeCheckRequest(
    String did,
    String fwVersion,
    String model,
  ) {
    return Uint8List.fromList([
      ..._encodeStringField(1, did),
      ..._encodeStringField(2, fwVersion),
      ..._encodeStringField(3, model),
    ]);
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

  /// Recursively collect all `https://` URL strings from proto fields.
  static List<String> _extractUrls(Uint8List data) {
    final urls = <String>[];
    for (final (_, wireType, value) in _decodeProtoFields(data)) {
      if (wireType == 2) {
        String? s;
        try {
          s = String.fromCharCodes(value);
        } catch (_) {
          s = null;
        }
        if (s != null && s.startsWith('https://')) {
          urls.add(s);
          continue;
        }
        // Otherwise recurse — the value might be a nested message.
        urls.addAll(_extractUrls(Uint8List.fromList(value)));
      }
    }
    return urls;
  }

  /// Extract field 1 (bool `haveUpdate`) from the response.
  static bool _decodeHaveUpdate(Uint8List data) {
    for (final (fieldNum, wireType, value) in _decodeProtoFields(data)) {
      if (fieldNum == 1 && wireType == 0) {
        return value.isNotEmpty && value[0] != 0;
      }
    }
    return false;
  }

  // ── Test hooks ────────────────────────────────────────────────────────────

  @visibleForTesting
  static Uint8List debugEncodeCheckRequest(
    String did,
    String fwVersion,
    String model,
  ) => _encodeCheckRequest(did, fwVersion, model);

  @visibleForTesting
  static Uint8List debugEncodeStringField(int fieldNum, String s) =>
      _encodeStringField(fieldNum, s);

  @visibleForTesting
  static List<String> debugExtractUrls(Uint8List data) => _extractUrls(data);

  @visibleForTesting
  static bool debugDecodeHaveUpdate(Uint8List data) => _decodeHaveUpdate(data);
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
