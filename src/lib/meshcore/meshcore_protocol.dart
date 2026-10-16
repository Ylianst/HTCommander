/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

//
// meshcore_protocol.dart - Frame codec for the MeshCore companion radio
// protocol. Layouts follow the companion firmware source (v1.16), which is
// authoritative where it differs from the published protocol guide.
//
// Every frame starts with a one-byte code. Multi-byte integers are little
// endian. Over BLE each GATT write / notification carries exactly one frame.
//

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Commands sent from the app to the companion radio.
abstract final class MeshCoreCmd {
  static const int appStart = 1;
  static const int sendTxtMsg = 2;
  static const int sendChannelTxtMsg = 3;
  static const int getContacts = 4;
  static const int getDeviceTime = 5;
  static const int setDeviceTime = 6;
  static const int sendSelfAdvert = 7;
  static const int addUpdateContact = 9;
  static const int syncNextMessage = 10;
  static const int resetPath = 13;
  static const int removeContact = 15;
  static const int getBattAndStorage = 20;
  static const int deviceQuery = 22;
  static const int getContactByKey = 30;
  static const int getChannel = 31;
  static const int setChannel = 32;
}

/// Direct responses to commands (codes below 0x80).
abstract final class MeshCoreResp {
  static const int ok = 0;
  static const int err = 1;
  static const int contactsStart = 2;
  static const int contact = 3;
  static const int endOfContacts = 4;
  static const int selfInfo = 5;
  static const int sent = 6;
  static const int contactMsgRecv = 7;
  static const int channelMsgRecv = 8;
  static const int currTime = 9;
  static const int noMoreMessages = 10;
  static const int battAndStorage = 12;
  static const int deviceInfo = 13;
  static const int disabled = 15;
  static const int contactMsgRecvV3 = 16;
  static const int channelMsgRecvV3 = 17;
  static const int channelInfo = 18;
  static const int channelDataRecv = 27;

  static bool isMessage(int code) =>
      code == contactMsgRecv ||
      code == channelMsgRecv ||
      code == contactMsgRecvV3 ||
      code == channelMsgRecvV3;
}

/// Asynchronous notifications (codes 0x80 and above).
abstract final class MeshCorePush {
  static const int advert = 0x80;
  static const int pathUpdated = 0x81;
  static const int sendConfirmed = 0x82;
  static const int msgWaiting = 0x83;
  static const int logRxData = 0x88;
  static const int newAdvert = 0x8A;
  static const int contactDeleted = 0x8F;
  static const int contactsFull = 0x90;

  static bool isPush(int code) => code >= 0x80;
}

/// Error codes carried in byte 1 of [MeshCoreResp.err].
abstract final class MeshCoreErr {
  static const int unsupportedCmd = 1;
  static const int notFound = 2;
  static const int tableFull = 3;
  static const int badState = 4;
  static const int fileIoError = 5;
  static const int illegalArg = 6;

  static String describe(int code) => switch (code) {
    unsupportedCmd => 'unsupported command',
    notFound => 'not found',
    tableFull => 'table or queue full',
    badState => 'bad state',
    fileIoError => 'file I/O error',
    illegalArg => 'illegal argument',
    _ => 'error $code',
  };
}

/// Advertised node types.
abstract final class MeshCoreAdvType {
  static const int none = 0;
  static const int chat = 1;
  static const int repeater = 2;
  static const int room = 3;
  static const int sensor = 4;
}

/// Text message types.
abstract final class MeshCoreTxtType {
  static const int plain = 0;
  static const int cliData = 1;
  static const int signedPlain = 2;
}

abstract final class MeshCoreConst {
  /// Protocol version HTCommander understands; 3+ selects the V3 message
  /// formats that include SNR.
  static const int appProtocolVersion = 3;
  static const int publicKeySize = 32;
  static const int publicKeyPrefixSize = 6;
  static const int maxPathSize = 64;
  static const int nameFieldSize = 32;
  static const int channelSecretSize = 16;

  /// Firmware MAX_TEXT_LEN: the longest text a single LoRa packet carries.
  static const int maxTextBytes = 160;

  /// Path length value meaning "no known path" (send / store) or "arrived
  /// direct" (receive).
  static const int pathUnknown = 0xFF;

  /// Well-known secret of the built-in public channel.
  static const String publicChannelSecretHex =
      '8b3387e9c5cdea6ac9e5edbaa115cd72';

  static const String bleServiceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';

  /// App writes commands to this characteristic.
  static const String bleRxCharUuid = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';

  /// Firmware notifies responses on this characteristic.
  static const String bleTxCharUuid = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

  static const String bleNamePrefix = 'MeshCore-';
}

// ---------------------------------------------------------------------------
// Byte helpers
// ---------------------------------------------------------------------------

String bytesToHex(List<int> bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write((b & 0xFF).toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

/// Parses hex, ignoring spaces, colons and dashes. Throws [FormatException] on
/// invalid input.
Uint8List hexToBytes(String hex) {
  final clean = hex.replaceAll(RegExp(r'[\s:\-]'), '');
  if (clean.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(clean)) {
    throw FormatException('Invalid hex string', hex);
  }
  final out = Uint8List(clean.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// Normalizes a user-entered 32-byte public key to lowercase hex, or returns
/// null when it is not exactly 32 bytes or is all zeros.
String? normalizePublicKeyHex(String input) =>
    _normalizeKeyHex(input, MeshCoreConst.publicKeySize);

/// Normalizes a user-entered 16-byte channel secret to lowercase hex, or
/// returns null when invalid or all zeros.
String? normalizeChannelSecretHex(String input) =>
    _normalizeKeyHex(input, MeshCoreConst.channelSecretSize);

String? _normalizeKeyHex(String input, int size) {
  try {
    final bytes = hexToBytes(input.trim());
    if (bytes.length != size || bytes.every((b) => b == 0)) return null;
    return bytesToHex(bytes);
  } on FormatException {
    return null;
  }
}

/// Number of UTF-8 bytes needed to encode [text].
int utf8Length(String text) => utf8.encode(text).length;

/// Short, readable form of a public key: first and last eight hex digits.
String meshCoreFingerprint(String keyHex) => keyHex.length <= 16
    ? keyHex
    : '${keyHex.substring(0, 8)}…${keyHex.substring(keyHex.length - 8)}';

/// Conversation peer for a direct-message contact: the 6-byte key prefix the
/// companion uses to identify senders.
String meshCorePeerForKey(String keyHex) =>
    keyHex.length >= 2 * MeshCoreConst.publicKeyPrefixSize
    ? keyHex.substring(0, 2 * MeshCoreConst.publicKeyPrefixSize).toLowerCase()
    : keyHex.toLowerCase();

/// Encodes [text] as UTF-8, truncated to at most [maxBytes] without splitting
/// a multi-byte character.
Uint8List utf8Truncate(String text, int maxBytes) {
  final bytes = utf8.encode(text);
  if (bytes.length <= maxBytes) return Uint8List.fromList(bytes);
  var end = maxBytes;
  // Back up over UTF-8 continuation bytes (10xxxxxx).
  while (end > 0 && (bytes[end] & 0xC0) == 0x80) {
    end--;
  }
  return Uint8List.fromList(bytes.sublist(0, end));
}

/// Decodes a NUL-terminated UTF-8 field. Bytes after the NUL are ignored
/// because the firmware may leave stale data there.
String _cString(Uint8List data, int offset, int length) {
  final end = min(offset + length, data.length);
  var stop = offset;
  while (stop < end && data[stop] != 0) {
    stop++;
  }
  return utf8.decode(data.sublist(offset, stop), allowMalformed: true);
}

int _u16(Uint8List d, int o) => d[o] | (d[o + 1] << 8);

int _u32(Uint8List d, int o) =>
    (d[o] | (d[o + 1] << 8) | (d[o + 2] << 16)) + d[o + 3] * 0x1000000;

int _i32(Uint8List d, int o) {
  final v = _u32(d, o);
  return v >= 0x80000000 ? v - 0x100000000 : v;
}

int _i8(int b) => b >= 128 ? b - 256 : b;

class _Writer {
  final BytesBuilder _b = BytesBuilder();

  void u8(int v) => _b.addByte(v & 0xFF);

  void u32(int v) {
    final u = v < 0 ? v + 0x100000000 : v;
    _b.addByte(u & 0xFF);
    _b.addByte((u >> 8) & 0xFF);
    _b.addByte((u >> 16) & 0xFF);
    _b.addByte((u ~/ 0x1000000) & 0xFF);
  }

  void bytes(List<int> v) => _b.add(v);

  /// Writes [v] into a fixed-size zero-padded field.
  void fixed(List<int> v, int size) {
    final out = Uint8List(size);
    out.setRange(0, min(size, v.length), v);
    _b.add(out);
  }

  Uint8List take() => _b.takeBytes();
}

/// Converts signed microdegrees to degrees, or null when unset / invalid.
double? _coord(int micro, double limit) {
  if (micro == 0) return null;
  final v = micro / 1e6;
  if (!v.isFinite || v.abs() > limit) return null;
  return v;
}

/// Hop count encoded in a received path-length byte, or null when the packet
/// arrived via a direct route (0xFF). The low 6 bits are the hop count.
int? hopsFromPathLen(int pathLen) =>
    pathLen == MeshCoreConst.pathUnknown ? null : pathLen & 0x3F;

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Channel secrets
// ---------------------------------------------------------------------------

Uint8List publicChannelSecret() =>
    hexToBytes(MeshCoreConst.publicChannelSecretHex);

/// Secret for a hashtag channel: the first 16 bytes of SHA-256 of the name
/// including the leading '#'.
Uint8List hashtagChannelSecret(String name) {
  final tag = name.startsWith('#') ? name : '#$name';
  final digest = sha256.convert(utf8.encode(tag)).bytes;
  return Uint8List.fromList(digest.sublist(0, MeshCoreConst.channelSecretSize));
}

/// A random 16-byte secret for a private channel.
Uint8List randomChannelSecret([Random? random]) {
  final r = random ?? Random.secure();
  return Uint8List.fromList(
    List<int>.generate(MeshCoreConst.channelSecretSize, (_) => r.nextInt(256)),
  );
}

/// Stable identifier for a channel derived from its secret (without exposing
/// the secret), so history follows a channel even if its slot changes.
String channelKeyForSecret(List<int> secret) =>
    bytesToHex(sha256.convert(secret).bytes.sublist(0, 8));

enum MeshCoreChannelKind { public, hashtag, private }

// ---------------------------------------------------------------------------
// Parsed frames
// ---------------------------------------------------------------------------

class MeshCoreSelfInfo {
  final int advType;
  final int txPowerDbm;
  final int maxTxPowerDbm;
  final Uint8List publicKey;
  final double? latitude;
  final double? longitude;
  final bool manualAddContacts;
  final double radioFreqMhz;
  final double radioBandwidthKhz;
  final int spreadingFactor;
  final int codingRate;
  final String name;

  const MeshCoreSelfInfo({
    required this.advType,
    required this.txPowerDbm,
    required this.maxTxPowerDbm,
    required this.publicKey,
    required this.latitude,
    required this.longitude,
    required this.manualAddContacts,
    required this.radioFreqMhz,
    required this.radioBandwidthKhz,
    required this.spreadingFactor,
    required this.codingRate,
    required this.name,
  });

  String get publicKeyHex => bytesToHex(publicKey);

  static MeshCoreSelfInfo? parse(Uint8List d) {
    if (d.length < 58 || d[0] != MeshCoreResp.selfInfo) return null;
    final lat = _coord(_i32(d, 36), 90);
    final lon = _coord(_i32(d, 40), 180);
    final hasPos = lat != null && lon != null;
    return MeshCoreSelfInfo(
      advType: d[1],
      txPowerDbm: _i8(d[2]),
      maxTxPowerDbm: _i8(d[3]),
      publicKey: Uint8List.fromList(d.sublist(4, 36)),
      latitude: hasPos ? lat : null,
      longitude: hasPos ? lon : null,
      manualAddContacts: d[47] != 0,
      radioFreqMhz: _u32(d, 48) / 1000.0,
      radioBandwidthKhz: _u32(d, 52) / 1000.0,
      spreadingFactor: d[56],
      codingRate: d[57],
      name: utf8.decode(d.sublist(58), allowMalformed: true).trim(),
    );
  }
}

class MeshCoreDeviceInfo {
  final int firmwareVersionCode;
  final int maxContacts;
  final int maxChannels;
  final String buildDate;
  final String model;
  final String version;

  const MeshCoreDeviceInfo({
    required this.firmwareVersionCode,
    required this.maxContacts,
    required this.maxChannels,
    required this.buildDate,
    required this.model,
    required this.version,
  });

  static MeshCoreDeviceInfo? parse(Uint8List d) {
    if (d.length < 2 || d[0] != MeshCoreResp.deviceInfo) return null;
    final ver = d[1];
    if (ver < 3 || d.length < 80) {
      return MeshCoreDeviceInfo(
        firmwareVersionCode: ver,
        maxContacts: 0,
        maxChannels: 0,
        buildDate: '',
        model: '',
        version: '',
      );
    }
    return MeshCoreDeviceInfo(
      firmwareVersionCode: ver,
      maxContacts: d[2] * 2,
      maxChannels: d[3],
      buildDate: _cString(d, 8, 12),
      model: _cString(d, 20, 40),
      version: _cString(d, 60, 20),
    );
  }
}

class MeshCoreContact {
  final Uint8List publicKey;
  final int type;
  final int flags;
  final int outPathLen;
  final Uint8List outPath;
  final String name;
  final int lastAdvert;
  final double? latitude;
  final double? longitude;
  final int lastModified;

  MeshCoreContact({
    required this.publicKey,
    required this.type,
    this.flags = 0,
    this.outPathLen = MeshCoreConst.pathUnknown,
    Uint8List? outPath,
    required this.name,
    this.lastAdvert = 0,
    this.latitude,
    this.longitude,
    this.lastModified = 0,
  }) : outPath = outPath ?? Uint8List(MeshCoreConst.maxPathSize);

  String get publicKeyHex => bytesToHex(publicKey);

  String get prefixHex =>
      bytesToHex(publicKey.sublist(0, MeshCoreConst.publicKeyPrefixSize));

  /// Parses a [MeshCoreResp.contact] or [MeshCorePush.newAdvert] frame.
  static MeshCoreContact? parse(Uint8List d) {
    if (d.length < 1 + 32 + 3 + 64 + 32 + 4) return null;
    var i = 1;
    final key = Uint8List.fromList(d.sublist(i, i + 32));
    i += 32;
    final type = d[i++];
    final flags = d[i++];
    final outPathLen = d[i++];
    final path = Uint8List.fromList(d.sublist(i, i + 64));
    i += 64;
    final name = _cString(d, i, 32);
    i += 32;
    final lastAdvert = _u32(d, i);
    i += 4;
    double? lat;
    double? lon;
    var lastMod = 0;
    if (d.length >= i + 8) {
      lat = _coord(_i32(d, i), 90);
      lon = _coord(_i32(d, i + 4), 180);
      i += 8;
      if (lat == null || lon == null) {
        lat = null;
        lon = null;
      }
      if (d.length >= i + 4) lastMod = _u32(d, i);
    }
    return MeshCoreContact(
      publicKey: key,
      type: type,
      flags: flags,
      outPathLen: outPathLen,
      outPath: path,
      name: name,
      lastAdvert: lastAdvert,
      latitude: lat,
      longitude: lon,
      lastModified: lastMod,
    );
  }
}

class MeshCoreChannel {
  final int index;
  final String name;
  final Uint8List secret;

  const MeshCoreChannel({
    required this.index,
    required this.name,
    required this.secret,
  });

  bool get isEmpty => name.isEmpty && secret.every((b) => b == 0);

  String get key => channelKeyForSecret(secret);

  MeshCoreChannelKind get kind {
    if (_bytesEqual(secret, publicChannelSecret())) {
      return MeshCoreChannelKind.public;
    }
    if (name.startsWith('#') &&
        _bytesEqual(secret, hashtagChannelSecret(name))) {
      return MeshCoreChannelKind.hashtag;
    }
    return MeshCoreChannelKind.private;
  }

  static MeshCoreChannel? parse(Uint8List d) {
    if (d.length < 50 || d[0] != MeshCoreResp.channelInfo) return null;
    return MeshCoreChannel(
      index: d[1],
      name: _cString(d, 2, 32),
      secret: Uint8List.fromList(d.sublist(34, 50)),
    );
  }
}

/// A text message received from the companion's offline queue.
class MeshCoreIncomingMessage {
  /// True for a group channel message, false for a direct message.
  final bool isChannel;
  final int? channelIndex;

  /// Six-byte sender public-key prefix (direct messages only).
  final Uint8List? senderPrefix;
  final int pathLen;
  final int txtType;

  /// Sender's clock, seconds since the epoch.
  final int senderTimestamp;
  final String text;
  final double? snr;

  const MeshCoreIncomingMessage({
    required this.isChannel,
    this.channelIndex,
    this.senderPrefix,
    required this.pathLen,
    required this.txtType,
    required this.senderTimestamp,
    required this.text,
    this.snr,
  });

  String? get senderPrefixHex =>
      senderPrefix == null ? null : bytesToHex(senderPrefix!);

  static MeshCoreIncomingMessage? parse(Uint8List d) {
    if (d.isEmpty || !MeshCoreResp.isMessage(d[0])) return null;
    final code = d[0];
    final v3 =
        code == MeshCoreResp.contactMsgRecvV3 ||
        code == MeshCoreResp.channelMsgRecvV3;
    final isChannel =
        code == MeshCoreResp.channelMsgRecv ||
        code == MeshCoreResp.channelMsgRecvV3;

    var i = 1;
    double? snr;
    if (v3) {
      if (d.length < 4) return null;
      snr = _i8(d[1]) / 4.0;
      i = 4;
    }
    if (isChannel) {
      if (d.length < i + 7) return null;
      return MeshCoreIncomingMessage(
        isChannel: true,
        channelIndex: d[i],
        pathLen: d[i + 1],
        txtType: d[i + 2],
        senderTimestamp: _u32(d, i + 3),
        text: utf8.decode(d.sublist(i + 7), allowMalformed: true),
        snr: snr,
      );
    }
    if (d.length < i + 12) return null;
    final txtType = d[i + 7];
    var textStart = i + 12;
    if (txtType == MeshCoreTxtType.signedPlain) textStart += 4;
    if (textStart > d.length) return null;
    return MeshCoreIncomingMessage(
      isChannel: false,
      senderPrefix: Uint8List.fromList(d.sublist(i, i + 6)),
      pathLen: d[i + 6],
      txtType: txtType,
      senderTimestamp: _u32(d, i + 8),
      text: utf8.decode(d.sublist(textStart), allowMalformed: true),
      snr: snr,
    );
  }
}

/// Reply to [MeshCoreCmd.sendTxtMsg].
class MeshCoreSentInfo {
  final bool flood;
  final int ackTag;
  final int timeoutMs;

  const MeshCoreSentInfo({
    required this.flood,
    required this.ackTag,
    required this.timeoutMs,
  });

  static MeshCoreSentInfo? parse(Uint8List d) {
    if (d.length < 10 || d[0] != MeshCoreResp.sent) return null;
    return MeshCoreSentInfo(
      flood: d[1] != 0,
      ackTag: _u32(d, 2),
      timeoutMs: _u32(d, 6),
    );
  }
}

/// [MeshCorePush.sendConfirmed]: the recipient acknowledged a direct message.
class MeshCoreSendConfirmed {
  final int ackTag;
  final int roundTripMs;

  const MeshCoreSendConfirmed(this.ackTag, this.roundTripMs);

  static MeshCoreSendConfirmed? parse(Uint8List d) {
    if (d.length < 9 || d[0] != MeshCorePush.sendConfirmed) return null;
    return MeshCoreSendConfirmed(_u32(d, 1), _u32(d, 5));
  }
}

class MeshCoreBattery {
  final int millivolts;
  final int? usedKb;
  final int? totalKb;

  const MeshCoreBattery(this.millivolts, this.usedKb, this.totalKb);

  static MeshCoreBattery? parse(Uint8List d) {
    if (d.length < 3 || d[0] != MeshCoreResp.battAndStorage) return null;
    final full = d.length >= 11;
    return MeshCoreBattery(
      _u16(d, 1),
      full ? _u32(d, 3) : null,
      full ? _u32(d, 7) : null,
    );
  }
}

/// Parses the error code of a [MeshCoreResp.err] frame (0 when absent).
int parseErrorCode(Uint8List d) => d.length >= 2 ? d[1] : 0;

/// Parses a [MeshCoreResp.currTime] frame.
int? parseCurrentTime(Uint8List d) =>
    d.length >= 5 && d[0] == MeshCoreResp.currTime ? _u32(d, 1) : null;

/// Parses the 32-byte key of an [MeshCorePush.advert],
/// [MeshCorePush.pathUpdated] or [MeshCorePush.contactDeleted] frame.
Uint8List? parsePushPublicKey(Uint8List d) =>
    d.length >= 33 ? Uint8List.fromList(d.sublist(1, 33)) : null;

// ---------------------------------------------------------------------------
// Command builders
// ---------------------------------------------------------------------------

abstract final class MeshCoreCommands {
  static Uint8List appStart(String appName) {
    final w = _Writer()
      ..u8(MeshCoreCmd.appStart)
      ..fixed(const [], 7)
      ..bytes(utf8Truncate(appName, 32));
    return w.take();
  }

  static Uint8List deviceQuery([
    int version = MeshCoreConst.appProtocolVersion,
  ]) => Uint8List.fromList([MeshCoreCmd.deviceQuery, version]);

  static Uint8List getDeviceTime() =>
      Uint8List.fromList([MeshCoreCmd.getDeviceTime]);

  static Uint8List setDeviceTime(int epochSeconds) {
    final w = _Writer()
      ..u8(MeshCoreCmd.setDeviceTime)
      ..u32(epochSeconds);
    return w.take();
  }

  static Uint8List getContacts({int? since}) {
    final w = _Writer()..u8(MeshCoreCmd.getContacts);
    if (since != null) w.u32(since);
    return w.take();
  }

  static Uint8List getContactByKey(List<int> publicKey) {
    final w = _Writer()
      ..u8(MeshCoreCmd.getContactByKey)
      ..fixed(publicKey, MeshCoreConst.publicKeySize);
    return w.take();
  }

  static Uint8List addUpdateContact(MeshCoreContact c) {
    final w = _Writer()
      ..u8(MeshCoreCmd.addUpdateContact)
      ..fixed(c.publicKey, MeshCoreConst.publicKeySize)
      ..u8(c.type)
      ..u8(c.flags)
      ..u8(c.outPathLen)
      ..fixed(c.outPath, MeshCoreConst.maxPathSize)
      ..fixed(
        utf8Truncate(c.name, MeshCoreConst.nameFieldSize - 1),
        MeshCoreConst.nameFieldSize,
      )
      ..u32(c.lastAdvert)
      ..u32(((c.latitude ?? 0) * 1e6).round())
      ..u32(((c.longitude ?? 0) * 1e6).round());
    return w.take();
  }

  static Uint8List removeContact(List<int> publicKey) {
    final w = _Writer()
      ..u8(MeshCoreCmd.removeContact)
      ..fixed(publicKey, MeshCoreConst.publicKeySize);
    return w.take();
  }

  static Uint8List resetPath(List<int> publicKey) {
    final w = _Writer()
      ..u8(MeshCoreCmd.resetPath)
      ..fixed(publicKey, MeshCoreConst.publicKeySize);
    return w.take();
  }

  static Uint8List syncNextMessage() =>
      Uint8List.fromList([MeshCoreCmd.syncNextMessage]);

  static Uint8List getBattery() =>
      Uint8List.fromList([MeshCoreCmd.getBattAndStorage]);

  static Uint8List sendSelfAdvert({bool flood = true}) =>
      Uint8List.fromList([MeshCoreCmd.sendSelfAdvert, flood ? 1 : 0]);

  static Uint8List getChannel(int index) =>
      Uint8List.fromList([MeshCoreCmd.getChannel, index]);

  static Uint8List setChannel(int index, String name, List<int> secret) {
    if (secret.length != MeshCoreConst.channelSecretSize) {
      throw ArgumentError('Channel secret must be 16 bytes');
    }
    final w = _Writer()
      ..u8(MeshCoreCmd.setChannel)
      ..u8(index)
      ..fixed(
        utf8Truncate(name, MeshCoreConst.nameFieldSize - 1),
        MeshCoreConst.nameFieldSize,
      )
      ..bytes(secret);
    return w.take();
  }

  /// Direct text message. [publicKey] may be the full key or a prefix; only
  /// the first six bytes are sent.
  static Uint8List sendText(
    List<int> publicKey,
    String text, {
    required int timestamp,
    int attempt = 0,
  }) {
    final w = _Writer()
      ..u8(MeshCoreCmd.sendTxtMsg)
      ..u8(MeshCoreTxtType.plain)
      ..u8(attempt)
      ..u32(timestamp)
      ..fixed(publicKey, MeshCoreConst.publicKeyPrefixSize)
      ..bytes(utf8Truncate(text, MeshCoreConst.maxTextBytes));
    return w.take();
  }

  static Uint8List sendChannelText(
    int channelIndex,
    String text, {
    required int timestamp,
  }) {
    final w = _Writer()
      ..u8(MeshCoreCmd.sendChannelTxtMsg)
      ..u8(MeshCoreTxtType.plain)
      ..u8(channelIndex)
      ..u32(timestamp)
      ..bytes(utf8Truncate(text, MeshCoreConst.maxTextBytes));
    return w.take();
  }
}

/// Maximum UTF-8 bytes of user text for a channel message: the firmware
/// prepends the node name and ": " inside the same 160-byte limit.
int maxChannelTextBytes(String nodeName) =>
    max(0, MeshCoreConst.maxTextBytes - utf8Length(nodeName) - 2);

/// Splits a received channel message "Name: text" into sender and body. The
/// sender is display-only: channel messages carry no verified identity.
({String? sender, String text}) splitChannelText(String raw) {
  final idx = raw.indexOf(': ');
  if (idx <= 0 || idx >= MeshCoreConst.nameFieldSize) {
    return (sender: null, text: raw);
  }
  return (sender: raw.substring(0, idx), text: raw.substring(idx + 2));
}

// ---------------------------------------------------------------------------
// USB serial / TCP stream framing
// ---------------------------------------------------------------------------
//
// Over USB serial and TCP the companion frames each message with a 3-byte
// header: a direction byte ('<' app to radio, '>' radio to app) and a 16-bit
// little-endian payload length.

const int _toRadio = 0x3C; // '<'
const int _fromRadio = 0x3E; // '>'

/// Longest payload accepted from the radio; anything larger is treated as
/// line noise (the firmware never sends more than its 176-byte frame size).
const int _maxStreamFrame = 512;

/// Wraps [payload] for sending to the radio over a serial or TCP stream.
Uint8List encodeStreamFrame(List<int> payload) {
  final out = Uint8List(3 + payload.length);
  out[0] = _toRadio;
  out[1] = payload.length & 0xFF;
  out[2] = (payload.length >> 8) & 0xFF;
  out.setRange(3, out.length, payload);
  return out;
}

/// Reassembles radio-to-app frames from an arbitrarily chunked byte stream.
/// Bytes outside a frame (e.g. boot messages) are skipped.
class MeshCoreStreamDecoder {
  final List<int> _buf = [];

  /// Adds received bytes and returns every frame payload now complete.
  List<Uint8List> add(List<int> bytes) {
    _buf.addAll(bytes);
    final frames = <Uint8List>[];
    var i = 0;
    while (true) {
      final start = _buf.indexOf(_fromRadio, i);
      if (start < 0) {
        i = _buf.length;
        break;
      }
      if (start + 3 > _buf.length) {
        i = start;
        break;
      }
      final len = _buf[start + 1] | (_buf[start + 2] << 8);
      if (len == 0 || len > _maxStreamFrame) {
        // Not a real header: resume the search after this byte.
        i = start + 1;
        continue;
      }
      if (start + 3 + len > _buf.length) {
        i = start;
        break;
      }
      frames.add(Uint8List.fromList(_buf.sublist(start + 3, start + 3 + len)));
      i = start + 3 + len;
    }
    _buf.removeRange(0, i);
    return frames;
  }

  void reset() => _buf.clear();
}
