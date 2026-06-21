/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/foundation.dart';
import 'utils.dart';

/// Radio channel type for dual-channel mode
enum RadioChannelType { off, a, b, c }

/// Radio modulation type
enum RadioModulationType { fm, am, dmr, reserved }

/// Radio bandwidth type
enum RadioBandwidthType { narrow, wide }

/// Radio command state for responses
enum RadioCommandState {
  success,
  notSupported,
  notAuthenticated,
  insufficientResources,
  authenticating,
  invalidParameter,
  incorrectState,
  inProgress,
}

/// Radio connection state
enum RadioState {
  disconnected,
  connecting,
  connected,
  multiRadioSelect,
  unableToConnect,
  bluetoothNotAvailable,
  notRadioFound,
  accessDenied,
}

/// Radio device info - device capabilities and configuration
class RadioDevInfo {
  final Uint8List raw;
  final int vendorId;
  final int productId;
  final int hwVer;
  final int softVer;
  final bool supportRadio;
  final bool supportMediumPower;
  final bool fixedLocSpeakerVol;
  final bool notSupportSoftPowerCtrl;
  final bool haveNoSpeaker;
  final bool haveHmSpeaker;
  final int regionCount;
  final bool supportNoaa;
  final bool gmrs;
  final bool supportVfo;
  final bool supportDmr;
  final int channelCount;
  final int freqRangeCount;

  RadioDevInfo.fromBytes(Uint8List msg)
    : raw = msg,
      vendorId = RadioUtils.getByte(msg, 5),
      productId = RadioUtils.getShort(msg, 6),
      hwVer = RadioUtils.getByte(msg, 8),
      softVer = RadioUtils.getShort(msg, 9),
      supportRadio = (RadioUtils.getByte(msg, 11) & 0x80) != 0,
      supportMediumPower = (RadioUtils.getByte(msg, 11) & 0x40) != 0,
      fixedLocSpeakerVol = (RadioUtils.getByte(msg, 11) & 0x20) != 0,
      notSupportSoftPowerCtrl = (RadioUtils.getByte(msg, 11) & 0x10) != 0,
      haveNoSpeaker = (RadioUtils.getByte(msg, 11) & 0x08) != 0,
      haveHmSpeaker = (RadioUtils.getByte(msg, 11) & 0x04) != 0,
      regionCount =
          ((RadioUtils.getByte(msg, 11) & 0x03) << 4) +
          ((RadioUtils.getByte(msg, 12) & 0xF0) >> 4),
      supportNoaa = (RadioUtils.getByte(msg, 12) & 0x08) != 0,
      gmrs = (RadioUtils.getByte(msg, 12) & 0x04) != 0,
      supportVfo = (RadioUtils.getByte(msg, 12) & 0x02) != 0,
      supportDmr = (RadioUtils.getByte(msg, 12) & 0x01) != 0,
      channelCount = RadioUtils.getByte(msg, 13),
      freqRangeCount = (RadioUtils.getByte(msg, 14) & 0xF0) >> 4;

  /// Get a friendly device name based on product ID
  String get name {
    switch (productId) {
      case 0x0001:
        return 'VR-N7500';
      case 0x0002:
        return 'VR-N76';
      case 0x0003:
        return 'SA-888S';
      case 0x0004:
        return 'HG-UV98';
      case 0x0005:
        return 'HAM-AIO';
      default:
        return 'Unknown Radio ($productId)';
    }
  }

  Map<String, dynamic> toJson() => {
    'vendorId': vendorId,
    'productId': productId,
    'hwVer': hwVer,
    'softVer': softVer,
    'supportRadio': supportRadio,
    'channelCount': channelCount,
    'regionCount': regionCount,
    'supportNoaa': supportNoaa,
    'supportVfo': supportVfo,
    'supportDmr': supportDmr,
  };
}

/// Radio HT status - live status information from the radio
class RadioHtStatus {
  final Uint8List raw;
  final bool isPowerOn;
  final bool isInTx;
  final bool isSq;
  final bool isInRx;
  final RadioChannelType doubleChannel;
  final bool isScan;
  final bool isRadio;
  final int currChIdLower;
  final bool isGpsLocked;
  final bool isHfpConnected;
  final bool isAocConnected;
  final int currChId;
  final int rssi;
  final int currRegion;
  final int currChannelIdUpper;

  RadioHtStatus.fromBytes(Uint8List msg)
    : raw = msg,
      isPowerOn = (RadioUtils.getByte(msg, 5) & 0x80) != 0,
      isInTx = (RadioUtils.getByte(msg, 5) & 0x40) != 0,
      isSq = (RadioUtils.getByte(msg, 5) & 0x20) != 0,
      isInRx = (RadioUtils.getByte(msg, 5) & 0x10) != 0,
      doubleChannel =
          RadioChannelType.values[(RadioUtils.getByte(msg, 5) & 0x0C) >> 2],
      isScan = (RadioUtils.getByte(msg, 5) & 0x02) != 0,
      isRadio = (RadioUtils.getByte(msg, 5) & 0x01) != 0,
      currChIdLower = RadioUtils.getByte(msg, 6) >> 4,
      isGpsLocked = (RadioUtils.getByte(msg, 6) & 0x08) != 0,
      isHfpConnected = (RadioUtils.getByte(msg, 6) & 0x04) != 0,
      isAocConnected = (RadioUtils.getByte(msg, 6) & 0x02) != 0,
      rssi = RadioUtils.getByte(msg, 7) >> 4,
      currRegion =
          ((RadioUtils.getByte(msg, 7) & 0x0F) << 2) +
          (RadioUtils.getByte(msg, 8) >> 6),
      currChannelIdUpper = (RadioUtils.getByte(msg, 8) & 0x3C) >> 2,
      currChId =
          (((RadioUtils.getByte(msg, 8) & 0x3C) >> 2) << 4) +
          (RadioUtils.getByte(msg, 6) >> 4);

  Map<String, dynamic> toJson() => {
    'isPowerOn': isPowerOn,
    'isInTx': isInTx,
    'isSq': isSq,
    'isInRx': isInRx,
    'doubleChannel': doubleChannel.index,
    'isScan': isScan,
    'isRadio': isRadio,
    'isGpsLocked': isGpsLocked,
    'isHfpConnected': isHfpConnected,
    'isAocConnected': isAocConnected,
    'currChId': currChId,
    'rssi': rssi,
    'currRegion': currRegion,
  };
}

/// Radio settings - configuration settings for the radio
class RadioSettings {
  final Uint8List rawData;
  final int channelA;
  final int channelB;
  final bool scan;
  final bool aghfpCallMode;
  final int doubleChannel;
  final int squelchLevel;
  final bool tailElim;
  final bool autoRelayEn;
  final bool autoPowerOn;
  final bool keepAghfpLink;
  final int micGain;
  final int txHoldTime;
  final int txTimeLimit;
  final int localSpeaker;
  final int btMicGain;
  final bool adaptiveResponse;
  final bool disTone;
  final bool powerSavingMode;
  final int autoPowerOff;
  final int autoShareLocCh;
  final int hmSpeaker;
  final int positioningSystem;
  final int timeOffset;
  final bool useFreqRange2;
  final bool pttLock;
  final bool leadingSyncBitEn;
  final bool pairingAtPowerOn;
  final int screenTimeout;
  final int vfoX;
  final bool imperialUnit;
  final int wxMode;
  final int noaaCh;
  final int vfolTxPowerX;
  final int vfo2TxPowerX;
  final bool disDigitalMute;
  final bool signalingEccEn;
  final bool chDataLock;
  final int vfo1ModFreqX;
  final int vfo2ModFreqX;

  RadioSettings.fromBytes(Uint8List msg)
    : rawData = msg,
      channelA =
          ((RadioUtils.getByte(msg, 5) & 0xF0) >> 4) +
          (RadioUtils.getByte(msg, 14) & 0xF0),
      channelB =
          (RadioUtils.getByte(msg, 5) & 0x0F) +
          ((RadioUtils.getByte(msg, 14) & 0x0F) << 4),
      scan = (RadioUtils.getByte(msg, 6) & 0x80) != 0,
      aghfpCallMode = (RadioUtils.getByte(msg, 6) & 0x40) != 0,
      doubleChannel = (RadioUtils.getByte(msg, 6) & 0x30) >> 4,
      squelchLevel = RadioUtils.getByte(msg, 6) & 0x0F,
      tailElim = (RadioUtils.getByte(msg, 7) & 0x80) != 0,
      autoRelayEn = (RadioUtils.getByte(msg, 7) & 0x40) != 0,
      autoPowerOn = (RadioUtils.getByte(msg, 7) & 0x20) != 0,
      keepAghfpLink = (RadioUtils.getByte(msg, 7) & 0x10) != 0,
      micGain = (RadioUtils.getByte(msg, 7) & 0x0E) >> 1,
      txHoldTime =
          ((RadioUtils.getByte(msg, 7) & 0x01) << 4) +
          ((RadioUtils.getByte(msg, 8) & 0xE0) >> 4),
      txTimeLimit = RadioUtils.getByte(msg, 8) & 0x1F,
      localSpeaker = RadioUtils.getByte(msg, 9) >> 6,
      btMicGain = (RadioUtils.getByte(msg, 9) & 0x38) >> 3,
      adaptiveResponse = (RadioUtils.getByte(msg, 9) & 0x04) != 0,
      disTone = (RadioUtils.getByte(msg, 9) & 0x02) != 0,
      powerSavingMode = (RadioUtils.getByte(msg, 9) & 0x01) != 0,
      autoPowerOff = RadioUtils.getByte(msg, 10) >> 5,
      autoShareLocCh = RadioUtils.getByte(msg, 10) & 0x1F,
      hmSpeaker = RadioUtils.getByte(msg, 11) >> 6,
      positioningSystem = (RadioUtils.getByte(msg, 11) & 0x3C) >> 2,
      timeOffset =
          ((RadioUtils.getByte(msg, 11) & 0x03) << 4) +
          ((RadioUtils.getByte(msg, 12) & 0xF0) >> 4),
      useFreqRange2 = (RadioUtils.getByte(msg, 12) & 0x08) != 0,
      pttLock = (RadioUtils.getByte(msg, 12) & 0x04) != 0,
      leadingSyncBitEn = (RadioUtils.getByte(msg, 12) & 0x02) != 0,
      pairingAtPowerOn = (RadioUtils.getByte(msg, 12) & 0x01) != 0,
      screenTimeout = RadioUtils.getByte(msg, 13) >> 3,
      vfoX = (RadioUtils.getByte(msg, 13) & 0x06) >> 1,
      imperialUnit = (RadioUtils.getByte(msg, 13) & 0x01) != 0,
      wxMode = RadioUtils.getByte(msg, 15) >> 6,
      noaaCh = (RadioUtils.getByte(msg, 15) & 0x3C) >> 2,
      vfolTxPowerX = RadioUtils.getByte(msg, 15) & 0x03,
      vfo2TxPowerX = RadioUtils.getByte(msg, 16) >> 6,
      disDigitalMute = (RadioUtils.getByte(msg, 16) & 0x20) != 0,
      signalingEccEn = (RadioUtils.getByte(msg, 16) & 0x10) != 0,
      chDataLock = (RadioUtils.getByte(msg, 16) & 0x08) != 0,
      vfo1ModFreqX = RadioUtils.getInt(msg, 17),
      vfo2ModFreqX = RadioUtils.getInt(msg, 21);

  /// Serialize settings to bytes for writing to radio
  Uint8List toByteArray(
    int chA,
    int chB,
    int dualChannel,
    bool scanEnabled,
    int squelch,
  ) {
    // Match C# behavior: buffer size is rawData.length - 5
    final bufLen = rawData.length - 5;
    debugPrint(
      'RadioSettings.toByteArray: rawData.length=${rawData.length}, bufLen=$bufLen',
    );
    debugPrint(
      'RadioSettings.toByteArray: chA=$chA, chB=$chB, dualChannel=$dualChannel, scan=$scanEnabled, squelch=$squelch',
    );
    final data = Uint8List(bufLen);

    // Copy all raw data starting from offset 5 (matching C# Array.Copy)
    for (int i = 0; i < bufLen && i + 5 < rawData.length; i++) {
      data[i] = rawData[i + 5];
    }
    debugPrint('RadioSettings.toByteArray: after copy: $data');

    // Channel A and B (split between two bytes)
    data[0] = ((chA & 0x0F) << 4) | (chB & 0x0F);

    // Scan, aghfp, double channel, squelch
    data[1] =
        (scanEnabled ? 0x80 : 0) |
        (aghfpCallMode ? 0x40 : 0) |
        ((dualChannel & 0x03) << 4) |
        (squelch & 0x0F);

    // Update channel A/B upper bits (chA high nibble in upper, chB high nibble shifted to lower)
    if (data.length > 9) {
      data[9] = (chA & 0xF0) | ((chB >> 4) & 0x0F);
    }

    debugPrint('RadioSettings.toByteArray: final data: $data');

    return data;
  }

  Map<String, dynamic> toJson() => {
    'channelA': channelA,
    'channelB': channelB,
    'scan': scan,
    'doubleChannel': doubleChannel,
    'squelchLevel': squelchLevel,
    'pttLock': pttLock,
    'noaaCh': noaaCh,
  };

  /// Create a modified byte array for settings, using current values for any null parameters
  Uint8List toByteArrayWith({
    int? channelA,
    int? channelB,
    int? doubleChannel,
    bool? scan,
    int? squelchLevel,
  }) {
    return toByteArray(
      channelA ?? this.channelA,
      channelB ?? this.channelB,
      doubleChannel ?? this.doubleChannel,
      scan ?? this.scan,
      squelchLevel ?? this.squelchLevel,
    );
  }
}

/// Radio channel info - information about a single channel
class RadioChannelInfo {
  final Uint8List raw;
  final int channelId;
  final RadioModulationType txMod;
  final int txFreq;
  final RadioModulationType rxMod;
  final int rxFreq;
  final int txSubAudio;
  final int rxSubAudio;
  final bool scan;
  final bool txAtMaxPower;
  final bool talkAround;
  final RadioBandwidthType bandwidth;
  final bool preDeEmphBypass;
  final bool sign;
  final bool txAtMedPower;
  final bool txDisable;
  final bool fixedFreq;
  final bool fixedBandwidth;
  final bool fixedTxPower;
  final bool mute;
  final String name;

  RadioChannelInfo.fromBytes(Uint8List msg)
    : raw = msg,
      channelId = RadioUtils.getByte(msg, 5),
      txMod = RadioModulationType.values[RadioUtils.getByte(msg, 6) >> 6],
      txFreq = RadioUtils.getInt(msg, 6) & 0x3FFFFFFF,
      rxMod = RadioModulationType.values[RadioUtils.getByte(msg, 10) >> 6],
      rxFreq = RadioUtils.getInt(msg, 10) & 0x3FFFFFFF,
      txSubAudio = RadioUtils.getShort(msg, 14),
      rxSubAudio = RadioUtils.getShort(msg, 16),
      scan = (RadioUtils.getByte(msg, 18) & 0x80) != 0,
      txAtMaxPower = (RadioUtils.getByte(msg, 18) & 0x40) != 0,
      talkAround = (RadioUtils.getByte(msg, 18) & 0x20) != 0,
      bandwidth = (RadioUtils.getByte(msg, 18) & 0x10) != 0
          ? RadioBandwidthType.wide
          : RadioBandwidthType.narrow,
      preDeEmphBypass = (RadioUtils.getByte(msg, 18) & 0x08) != 0,
      sign = (RadioUtils.getByte(msg, 18) & 0x04) != 0,
      txAtMedPower = (RadioUtils.getByte(msg, 18) & 0x02) != 0,
      txDisable = (RadioUtils.getByte(msg, 18) & 0x01) != 0,
      fixedFreq = (RadioUtils.getByte(msg, 19) & 0x80) != 0,
      fixedBandwidth = (RadioUtils.getByte(msg, 19) & 0x40) != 0,
      fixedTxPower = (RadioUtils.getByte(msg, 19) & 0x20) != 0,
      mute = (RadioUtils.getByte(msg, 19) & 0x10) != 0,
      name = RadioUtils.decodeUtf8Trimmed(msg, 20, 10);

  /// Frequency display in MHz with 3 decimal places
  String get frequencyDisplay {
    if (rxFreq == 0) return '';
    return (rxFreq / 1000000).toStringAsFixed(3);
  }

  /// Serialize channel info to bytes for writing to radio
  Uint8List toByteArray() {
    final r = Uint8List(25);
    r[0] = channelId;
    RadioUtils.setInt(r, 1, txFreq);
    r[1] = (r[1] & 0x3F) | ((txMod.index & 0x03) << 6);
    RadioUtils.setInt(r, 5, rxFreq);
    r[5] = (r[5] & 0x3F) | ((rxMod.index & 0x03) << 6);
    RadioUtils.setShort(r, 9, txSubAudio);
    RadioUtils.setShort(r, 11, rxSubAudio);

    r[13] =
        (scan ? 0x80 : 0) |
        (txAtMaxPower ? 0x40 : 0) |
        (talkAround ? 0x20 : 0) |
        (bandwidth == RadioBandwidthType.wide ? 0x10 : 0) |
        (preDeEmphBypass ? 0x08 : 0) |
        (sign ? 0x04 : 0) |
        (txAtMedPower ? 0x02 : 0) |
        (txDisable ? 0x01 : 0);

    r[14] =
        (fixedFreq ? 0x80 : 0) |
        (fixedBandwidth ? 0x40 : 0) |
        (fixedTxPower ? 0x20 : 0) |
        (mute ? 0x10 : 0);

    final nameBytes = RadioUtils.encodeUtf8Padded(name, 10);
    for (int i = 0; i < 10; i++) {
      r[15 + i] = nameBytes[i];
    }

    return r;
  }

  Map<String, dynamic> toJson() => {
    'channelId': channelId,
    'name': name,
    'rxFreq': rxFreq,
    'txFreq': txFreq,
    'scan': scan,
    'txDisable': txDisable,
    'mute': mute,
    'txMod': txMod.index,
    'rxMod': rxMod.index,
    'bandwidth': bandwidth == RadioBandwidthType.wide ? 1 : 0,
  };
}

/// Radio position - GPS position information
class RadioPosition {
  final RadioCommandState status;
  final int latitudeRaw;
  final int longitudeRaw;
  final int altitude;
  final int speed;
  final int heading;
  final int timeRaw;
  final int accuracy;
  final double latitude;
  final double longitude;
  final DateTime timeUtc;
  final DateTime receivedTime;
  final bool locked;

  RadioPosition.fromBytes(Uint8List msg)
    : status = msg.length > 4
          ? RadioCommandState.values[msg[4]]
          : RadioCommandState.success,
      latitudeRaw =
          (RadioUtils.getByte(msg, 5) << 16) +
          (RadioUtils.getByte(msg, 6) << 8) +
          RadioUtils.getByte(msg, 7),
      longitudeRaw =
          (RadioUtils.getByte(msg, 8) << 16) +
          (RadioUtils.getByte(msg, 9) << 8) +
          RadioUtils.getByte(msg, 10),
      altitude =
          (RadioUtils.getByte(msg, 11) << 8) + RadioUtils.getByte(msg, 12),
      speed = (RadioUtils.getByte(msg, 13) << 8) + RadioUtils.getByte(msg, 14),
      heading =
          (RadioUtils.getByte(msg, 15) << 8) + RadioUtils.getByte(msg, 16),
      timeRaw =
          (RadioUtils.getByte(msg, 17) << 24) +
          (RadioUtils.getByte(msg, 18) << 16) +
          (RadioUtils.getByte(msg, 19) << 8) +
          RadioUtils.getByte(msg, 20),
      accuracy =
          (RadioUtils.getByte(msg, 21) << 8) + RadioUtils.getByte(msg, 22),
      latitude = _convertLatitude(
        (RadioUtils.getByte(msg, 5) << 16) +
            (RadioUtils.getByte(msg, 6) << 8) +
            RadioUtils.getByte(msg, 7),
      ),
      longitude = _convertLatitude(
        (RadioUtils.getByte(msg, 8) << 16) +
            (RadioUtils.getByte(msg, 9) << 8) +
            RadioUtils.getByte(msg, 10),
      ),
      timeUtc = msg.length > 17
          ? RadioUtils.unixTimeStampToDateTime(
              (RadioUtils.getByte(msg, 17) << 24) +
                  (RadioUtils.getByte(msg, 18) << 16) +
                  (RadioUtils.getByte(msg, 19) << 8) +
                  RadioUtils.getByte(msg, 20),
            )
          : DateTime.now().toUtc(),
      receivedTime = DateTime.now(),
      locked =
          msg.length > 4 &&
          RadioCommandState.values[msg[4]] == RadioCommandState.success;

  RadioPosition.fromCoordinates({
    required double lat,
    required double lon,
    double altitudeMetres = 0,
    double speedKnots = 0,
    double headingDegrees = 0,
    DateTime? utcTime,
  }) : status = RadioCommandState.success,
       latitude = lat,
       longitude = lon,
       latitudeRaw = (lat * 60.0 * 500.0).round(),
       longitudeRaw = (lon * 60.0 * 500.0).round(),
       altitude = altitudeMetres.round(),
       speed = speedKnots.round(),
       heading = headingDegrees.round(),
       timeRaw =
           ((utcTime ?? DateTime.now().toUtc()).millisecondsSinceEpoch ~/ 1000),
       timeUtc = utcTime ?? DateTime.now().toUtc(),
       receivedTime = DateTime.now(),
       accuracy = 0,
       locked = true;

  static double _convertLatitude(int latitudeRaw) {
    // Handle 24-bit two's complement
    if ((latitudeRaw & 0x00800000) != 0) {
      latitudeRaw |= 0xFF000000; // Sign extend
    } else {
      latitudeRaw &= 0x00FFFFFF;
    }
    return latitudeRaw / 60.0 / 500.0;
  }

  bool isGpsLocked() {
    return locked &&
        status == RadioCommandState.success &&
        receivedTime.add(const Duration(seconds: 10)).isAfter(DateTime.now());
  }

  /// Serialize to 18-byte payload for SET_POSITION command
  Uint8List toByteArray() {
    return Uint8List.fromList([
      (latitudeRaw >> 16) & 0xFF,
      (latitudeRaw >> 8) & 0xFF,
      latitudeRaw & 0xFF,
      (longitudeRaw >> 16) & 0xFF,
      (longitudeRaw >> 8) & 0xFF,
      longitudeRaw & 0xFF,
      (altitude >> 8) & 0xFF,
      altitude & 0xFF,
      (speed >> 8) & 0xFF,
      speed & 0xFF,
      (heading >> 8) & 0xFF,
      heading & 0xFF,
      (timeRaw >> 24) & 0xFF,
      (timeRaw >> 16) & 0xFF,
      (timeRaw >> 8) & 0xFF,
      timeRaw & 0xFF,
      (accuracy >> 8) & 0xFF,
      accuracy & 0xFF,
    ]);
  }

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'altitude': altitude,
    'speed': speed,
    'heading': heading,
    'locked': locked,
    'timestamp': timeUtc.toIso8601String(),
  };
}

/// Radio BSS settings - beacon/location sharing settings
class RadioBssSettings {
  int maxFwdTimes;
  int timeToLive;
  bool pttReleaseSendLocation;
  bool pttReleaseSendIdInfo;
  bool pttReleaseSendBssUserId;
  bool shouldShareLocation;
  bool sendPwrVoltage;
  int packetFormat;
  bool allowPositionCheck;
  int aprsSsid;
  int locationShareInterval;
  int bssUserIdLower;
  String pttReleaseIdInfo;
  String beaconMessage;
  String aprsSymbol;
  String aprsCallsign;

  RadioBssSettings.fromBytes(Uint8List msg)
    : maxFwdTimes = (RadioUtils.getByte(msg, 5) & 0xF0) >> 4,
      timeToLive = RadioUtils.getByte(msg, 5) & 0x0F,
      pttReleaseSendLocation = (RadioUtils.getByte(msg, 6) & 0x80) != 0,
      pttReleaseSendIdInfo = (RadioUtils.getByte(msg, 6) & 0x40) != 0,
      pttReleaseSendBssUserId = (RadioUtils.getByte(msg, 6) & 0x20) != 0,
      shouldShareLocation = (RadioUtils.getByte(msg, 6) & 0x10) != 0,
      sendPwrVoltage = (RadioUtils.getByte(msg, 6) & 0x08) != 0,
      packetFormat = (RadioUtils.getByte(msg, 6) & 0x04) >> 2,
      allowPositionCheck = (RadioUtils.getByte(msg, 6) & 0x02) != 0,
      aprsSsid = (RadioUtils.getByte(msg, 7) & 0xF0) >> 4,
      locationShareInterval = RadioUtils.getByte(msg, 8) * 10,
      bssUserIdLower = _getInt32LESafe(msg, 9),
      pttReleaseIdInfo = RadioUtils.decodeUtf8Trimmed(msg, 13, 12),
      beaconMessage = RadioUtils.decodeUtf8Trimmed(msg, 25, 18),
      aprsSymbol = RadioUtils.decodeUtf8Trimmed(msg, 43, 2),
      aprsCallsign = RadioUtils.decodeUtf8Trimmed(msg, 45, 6);

  static int _getInt32LESafe(Uint8List data, int offset) {
    if (offset + 3 >= data.length) return 0;
    return data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24);
  }

  static int _getInt32LE(Uint8List data, int offset) {
    return data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24);
  }

  static void _setInt32LE(Uint8List data, int offset, int value) {
    data[offset] = value & 0xFF;
    data[offset + 1] = (value >> 8) & 0xFF;
    data[offset + 2] = (value >> 16) & 0xFF;
    data[offset + 3] = (value >> 24) & 0xFF;
  }

  Uint8List toByteArray() {
    final msg = Uint8List(46);

    msg[0] = ((maxFwdTimes << 4) | (timeToLive & 0x0F));
    msg[1] =
        (pttReleaseSendLocation ? 0x80 : 0) |
        (pttReleaseSendIdInfo ? 0x40 : 0) |
        (pttReleaseSendBssUserId ? 0x20 : 0) |
        (shouldShareLocation ? 0x10 : 0) |
        (sendPwrVoltage ? 0x08 : 0) |
        ((packetFormat & 0x01) << 2) |
        (allowPositionCheck ? 0x02 : 0);
    msg[2] = ((aprsSsid & 0x0F) << 4);
    msg[3] = (locationShareInterval ~/ 10);
    _setInt32LE(msg, 4, bssUserIdLower);

    final idInfoBytes = RadioUtils.encodeUtf8Padded(pttReleaseIdInfo, 12);
    for (int i = 0; i < 12; i++) {
      msg[8 + i] = idInfoBytes[i];
    }

    final beaconBytes = RadioUtils.encodeUtf8Padded(beaconMessage, 18);
    for (int i = 0; i < 18; i++) {
      msg[20 + i] = beaconBytes[i];
    }

    final symbolBytes = RadioUtils.encodeUtf8Padded(aprsSymbol, 2);
    msg[38] = symbolBytes[0];
    msg[39] = symbolBytes[1];

    final callsignBytes = RadioUtils.encodeUtf8Padded(aprsCallsign, 6);
    for (int i = 0; i < 6; i++) {
      msg[40 + i] = callsignBytes[i];
    }

    return msg;
  }

  Map<String, dynamic> toJson() => {
    'maxFwdTimes': maxFwdTimes,
    'timeToLive': timeToLive,
    'pttReleaseSendLocation': pttReleaseSendLocation,
    'shouldShareLocation': shouldShareLocation,
    'aprsSsid': aprsSsid,
    'locationShareInterval': locationShareInterval,
    'aprsCallsign': aprsCallsign,
    'aprsSymbol': aprsSymbol,
    'beaconMessage': beaconMessage,
  };
}

/// Radio lock state - for exclusive operations
class RadioLockState {
  bool isLocked;
  String? usage;
  int regionId;
  int channelId;

  RadioLockState({
    this.isLocked = false,
    this.usage,
    this.regionId = -1,
    this.channelId = -1,
  });

  Map<String, dynamic> toJson() => {
    'isLocked': isLocked,
    'usage': usage,
    'regionId': regionId,
    'channelId': channelId,
  };

  factory RadioLockState.fromJson(Map<String, dynamic> json) {
    return RadioLockState(
      isLocked: json['isLocked'] as bool? ?? json['IsLocked'] as bool? ?? false,
      usage: json['usage'] as String? ?? json['Usage'] as String?,
      regionId: json['regionId'] as int? ?? json['RegionId'] as int? ?? -1,
      channelId: json['channelId'] as int? ?? json['ChannelId'] as int? ?? -1,
    );
  }
}

/// Compatible device info for Bluetooth scanning
class CompatibleDevice {
  final String name;
  final String mac;

  CompatibleDevice(this.name, this.mac);
}
