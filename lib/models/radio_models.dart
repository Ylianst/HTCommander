/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// Radio channel type for dual-channel mode
enum RadioChannelType { a, b, c, d }

/// Radio modulation type
enum RadioModulationType { fm, am, dmr, reserved }

/// Radio bandwidth type
enum RadioBandwidthType { narrow, wide }

/// Radio HT status - live status information from the radio
class RadioHtStatus {
  final bool isPowerOn;
  final bool isInTx;
  final bool isSq;
  final bool isInRx;
  final RadioChannelType doubleChannel;
  final bool isScan;
  final bool isRadio;
  final bool isGpsLocked;
  final bool isHfpConnected;
  final bool isAocConnected;
  final int currChId;
  final int rssi;
  final int currRegion;

  RadioHtStatus({
    this.isPowerOn = false,
    this.isInTx = false,
    this.isSq = false,
    this.isInRx = false,
    this.doubleChannel = RadioChannelType.a,
    this.isScan = false,
    this.isRadio = false,
    this.isGpsLocked = false,
    this.isHfpConnected = false,
    this.isAocConnected = false,
    this.currChId = 0,
    this.rssi = 0,
    this.currRegion = 0,
  });

  factory RadioHtStatus.fromJson(Map<String, dynamic> json) {
    return RadioHtStatus(
      isPowerOn: json['isPowerOn'] as bool? ?? false,
      isInTx: json['isInTx'] as bool? ?? false,
      isSq: json['isSq'] as bool? ?? false,
      isInRx: json['isInRx'] as bool? ?? false,
      doubleChannel:
          RadioChannelType.values[json['doubleChannel'] as int? ?? 0],
      isScan: json['isScan'] as bool? ?? false,
      isRadio: json['isRadio'] as bool? ?? false,
      isGpsLocked: json['isGpsLocked'] as bool? ?? false,
      isHfpConnected: json['isHfpConnected'] as bool? ?? false,
      isAocConnected: json['isAocConnected'] as bool? ?? false,
      currChId: json['currChId'] as int? ?? 0,
      rssi: json['rssi'] as int? ?? 0,
      currRegion: json['currRegion'] as int? ?? 0,
    );
  }

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
  final int channelA;
  final int channelB;
  final bool scan;
  final bool aghfpCallMode;
  final int doubleChannel; // 0 = off, 1 = on
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

  RadioSettings({
    this.channelA = 0,
    this.channelB = 0,
    this.scan = false,
    this.aghfpCallMode = false,
    this.doubleChannel = 0,
    this.squelchLevel = 0,
    this.tailElim = false,
    this.autoRelayEn = false,
    this.autoPowerOn = false,
    this.keepAghfpLink = false,
    this.micGain = 0,
    this.txHoldTime = 0,
    this.txTimeLimit = 0,
    this.localSpeaker = 0,
    this.btMicGain = 0,
    this.adaptiveResponse = false,
    this.disTone = false,
    this.powerSavingMode = false,
    this.autoPowerOff = 0,
    this.autoShareLocCh = 0,
    this.hmSpeaker = 0,
    this.positioningSystem = 0,
    this.timeOffset = 0,
    this.useFreqRange2 = false,
    this.pttLock = false,
    this.leadingSyncBitEn = false,
    this.pairingAtPowerOn = false,
    this.screenTimeout = 0,
    this.vfoX = 0,
    this.imperialUnit = false,
    this.wxMode = 0,
    this.noaaCh = 0,
    this.vfolTxPowerX = 0,
    this.vfo2TxPowerX = 0,
    this.disDigitalMute = false,
    this.signalingEccEn = false,
    this.chDataLock = false,
    this.vfo1ModFreqX = 0,
    this.vfo2ModFreqX = 0,
  });

  factory RadioSettings.fromJson(Map<String, dynamic> json) {
    return RadioSettings(
      channelA: json['channelA'] as int? ?? json['channel_a'] as int? ?? 0,
      channelB: json['channelB'] as int? ?? json['channel_b'] as int? ?? 0,
      scan: json['scan'] as bool? ?? false,
      aghfpCallMode: json['aghfpCallMode'] as bool? ?? false,
      doubleChannel:
          json['doubleChannel'] as int? ?? json['double_channel'] as int? ?? 0,
      squelchLevel:
          json['squelchLevel'] as int? ?? json['squelch_level'] as int? ?? 0,
      tailElim: json['tailElim'] as bool? ?? false,
      autoRelayEn: json['autoRelayEn'] as bool? ?? false,
      autoPowerOn: json['autoPowerOn'] as bool? ?? false,
      keepAghfpLink: json['keepAghfpLink'] as bool? ?? false,
      micGain: json['micGain'] as int? ?? 0,
      txHoldTime: json['txHoldTime'] as int? ?? 0,
      txTimeLimit: json['txTimeLimit'] as int? ?? 0,
      localSpeaker: json['localSpeaker'] as int? ?? 0,
      btMicGain: json['btMicGain'] as int? ?? 0,
      adaptiveResponse: json['adaptiveResponse'] as bool? ?? false,
      disTone: json['disTone'] as bool? ?? false,
      powerSavingMode: json['powerSavingMode'] as bool? ?? false,
      autoPowerOff: json['autoPowerOff'] as int? ?? 0,
      autoShareLocCh: json['autoShareLocCh'] as int? ?? 0,
      hmSpeaker: json['hmSpeaker'] as int? ?? 0,
      positioningSystem: json['positioningSystem'] as int? ?? 0,
      timeOffset: json['timeOffset'] as int? ?? 0,
      useFreqRange2: json['useFreqRange2'] as bool? ?? false,
      pttLock: json['pttLock'] as bool? ?? json['ptt_lock'] as bool? ?? false,
      leadingSyncBitEn: json['leadingSyncBitEn'] as bool? ?? false,
      pairingAtPowerOn: json['pairingAtPowerOn'] as bool? ?? false,
      screenTimeout: json['screenTimeout'] as int? ?? 0,
      vfoX: json['vfoX'] as int? ?? 0,
      imperialUnit: json['imperialUnit'] as bool? ?? false,
      wxMode: json['wxMode'] as int? ?? 0,
      noaaCh: json['noaaCh'] as int? ?? json['noaa_ch'] as int? ?? 0,
      vfolTxPowerX: json['vfolTxPowerX'] as int? ?? 0,
      vfo2TxPowerX: json['vfo2TxPowerX'] as int? ?? 0,
      disDigitalMute: json['disDigitalMute'] as bool? ?? false,
      signalingEccEn: json['signalingEccEn'] as bool? ?? false,
      chDataLock: json['chDataLock'] as bool? ?? false,
      vfo1ModFreqX: json['vfo1ModFreqX'] as int? ?? 0,
      vfo2ModFreqX: json['vfo2ModFreqX'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'channelA': channelA,
    'channelB': channelB,
    'scan': scan,
    'aghfpCallMode': aghfpCallMode,
    'doubleChannel': doubleChannel,
    'squelchLevel': squelchLevel,
    'tailElim': tailElim,
    'autoRelayEn': autoRelayEn,
    'autoPowerOn': autoPowerOn,
    'keepAghfpLink': keepAghfpLink,
    'micGain': micGain,
    'txHoldTime': txHoldTime,
    'txTimeLimit': txTimeLimit,
    'localSpeaker': localSpeaker,
    'btMicGain': btMicGain,
    'adaptiveResponse': adaptiveResponse,
    'disTone': disTone,
    'powerSavingMode': powerSavingMode,
    'autoPowerOff': autoPowerOff,
    'autoShareLocCh': autoShareLocCh,
    'hmSpeaker': hmSpeaker,
    'positioningSystem': positioningSystem,
    'timeOffset': timeOffset,
    'useFreqRange2': useFreqRange2,
    'pttLock': pttLock,
    'leadingSyncBitEn': leadingSyncBitEn,
    'pairingAtPowerOn': pairingAtPowerOn,
    'screenTimeout': screenTimeout,
    'vfoX': vfoX,
    'imperialUnit': imperialUnit,
    'wxMode': wxMode,
    'noaaCh': noaaCh,
    'vfolTxPowerX': vfolTxPowerX,
    'vfo2TxPowerX': vfo2TxPowerX,
    'disDigitalMute': disDigitalMute,
    'signalingEccEn': signalingEccEn,
    'chDataLock': chDataLock,
    'vfo1ModFreqX': vfo1ModFreqX,
    'vfo2ModFreqX': vfo2ModFreqX,
  };
}

/// Radio channel info - information about a single channel
class RadioChannelInfo {
  final int channelId;
  final String name;
  final int rxFreq;
  final int txFreq;
  final bool scan;
  final bool txDisable;
  final bool mute;
  final RadioModulationType txMod;
  final RadioModulationType rxMod;
  final RadioBandwidthType bandwidth;

  RadioChannelInfo({
    required this.channelId,
    this.name = '',
    this.rxFreq = 0,
    this.txFreq = 0,
    this.scan = false,
    this.txDisable = false,
    this.mute = false,
    this.txMod = RadioModulationType.fm,
    this.rxMod = RadioModulationType.fm,
    this.bandwidth = RadioBandwidthType.narrow,
  });

  /// Frequency display in MHz with 3 decimal places
  String get frequencyDisplay {
    if (rxFreq == 0) return '';
    return (rxFreq / 1000000).toStringAsFixed(3);
  }

  factory RadioChannelInfo.fromJson(Map<String, dynamic> json) {
    return RadioChannelInfo(
      channelId: json['channelId'] as int? ?? json['channel_id'] as int? ?? 0,
      name: json['name'] as String? ?? json['name_str'] as String? ?? '',
      rxFreq: json['rxFreq'] as int? ?? json['rx_freq'] as int? ?? 0,
      txFreq: json['txFreq'] as int? ?? json['tx_freq'] as int? ?? 0,
      scan: json['scan'] as bool? ?? false,
      txDisable:
          json['txDisable'] as bool? ?? json['tx_disable'] as bool? ?? false,
      mute: json['mute'] as bool? ?? false,
      txMod: RadioModulationType.values[json['txMod'] as int? ?? 0],
      rxMod: RadioModulationType.values[json['rxMod'] as int? ?? 0],
      bandwidth: json['bandwidth'] == 1
          ? RadioBandwidthType.wide
          : RadioBandwidthType.narrow,
    );
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
  final double latitude;
  final double longitude;
  final double altitude;
  final double speed;
  final double heading;
  final double accuracy;
  final bool locked;
  final DateTime? timestamp;
  final DateTime? receivedTime;

  RadioPosition({
    this.latitude = 0,
    this.longitude = 0,
    this.altitude = 0,
    this.speed = 0,
    this.heading = 0,
    this.accuracy = 0,
    this.locked = false,
    this.timestamp,
    this.receivedTime,
  });

  factory RadioPosition.fromJson(Map<String, dynamic> json) {
    return RadioPosition(
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      altitude: (json['altitude'] as num?)?.toDouble() ?? 0,
      speed: (json['speed'] as num?)?.toDouble() ?? 0,
      heading: (json['heading'] as num?)?.toDouble() ?? 0,
      accuracy: (json['accuracy'] as num?)?.toDouble() ?? 0,
      locked: json['locked'] as bool? ?? json['Locked'] as bool? ?? false,
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String)
          : null,
      receivedTime: json['receivedTime'] != null
          ? DateTime.tryParse(json['receivedTime'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'altitude': altitude,
    'speed': speed,
    'heading': heading,
    'accuracy': accuracy,
    'locked': locked,
    'timestamp': timestamp?.toIso8601String(),
    'receivedTime': receivedTime?.toIso8601String(),
  };
}

/// Radio device information - static capabilities reported by the radio.
class RadioDevInfo {
  final int vendorId;
  final int productId;
  final int hwVer;
  final int softVer;
  final bool supportRadio;
  final bool supportMediumPower;
  final bool haveHmSpeaker;
  final int channelCount;
  final int regionCount;
  final bool supportNoaa;
  final bool gmrs;
  final bool supportVfo;
  final bool supportDmr;
  final int freqRangeCount;

  RadioDevInfo({
    this.vendorId = 0,
    this.productId = 0,
    this.hwVer = 0,
    this.softVer = 0,
    this.supportRadio = false,
    this.supportMediumPower = false,
    this.haveHmSpeaker = false,
    this.channelCount = 0,
    this.regionCount = 0,
    this.supportNoaa = false,
    this.gmrs = false,
    this.supportVfo = false,
    this.supportDmr = false,
    this.freqRangeCount = 0,
  });

  factory RadioDevInfo.fromJson(Map<String, dynamic> json) {
    return RadioDevInfo(
      vendorId: json['vendorId'] as int? ?? 0,
      productId: json['productId'] as int? ?? 0,
      hwVer: json['hwVer'] as int? ?? 0,
      softVer: json['softVer'] as int? ?? 0,
      supportRadio: json['supportRadio'] as bool? ?? false,
      supportMediumPower: json['supportMediumPower'] as bool? ?? false,
      haveHmSpeaker: json['haveHmSpeaker'] as bool? ?? false,
      channelCount: json['channelCount'] as int? ?? 0,
      regionCount: json['regionCount'] as int? ?? 0,
      supportNoaa: json['supportNoaa'] as bool? ?? false,
      gmrs: json['gmrs'] as bool? ?? false,
      supportVfo: json['supportVfo'] as bool? ?? false,
      supportDmr: json['supportDmr'] as bool? ?? false,
      freqRangeCount: json['freqRangeCount'] as int? ?? 0,
    );
  }

  /// Software version formatted as "major.minor.patch" (matches C#).
  String get softwareVersion =>
      '${(softVer >> 8) & 0xF}.${(softVer >> 4) & 0xF}.${softVer & 0xF}';
}

/// Radio BSS (beacon/location sharing) settings as published to the broker.
class RadioBssSettings {
  final int maxFwdTimes;
  final int timeToLive;
  final bool pttReleaseSendLocation;
  final bool pttReleaseSendIdInfo;
  final bool pttReleaseSendBssUserId;
  final bool shouldShareLocation;
  final bool sendPwrVoltage;
  final int packetFormat;
  final bool allowPositionCheck;
  final int aprsSsid;
  final int locationShareInterval;
  final int bssUserIdLower;
  final String pttReleaseIdInfo;
  final String beaconMessage;
  final String aprsSymbol;
  final String aprsCallsign;

  RadioBssSettings({
    this.maxFwdTimes = 0,
    this.timeToLive = 0,
    this.pttReleaseSendLocation = false,
    this.pttReleaseSendIdInfo = false,
    this.pttReleaseSendBssUserId = false,
    this.shouldShareLocation = false,
    this.sendPwrVoltage = false,
    this.packetFormat = 0,
    this.allowPositionCheck = false,
    this.aprsSsid = 0,
    this.locationShareInterval = 0,
    this.bssUserIdLower = 0,
    this.pttReleaseIdInfo = '',
    this.beaconMessage = '',
    this.aprsSymbol = '',
    this.aprsCallsign = '',
  });

  factory RadioBssSettings.fromJson(Map<String, dynamic> json) {
    return RadioBssSettings(
      maxFwdTimes: json['maxFwdTimes'] as int? ?? 0,
      timeToLive: json['timeToLive'] as int? ?? 0,
      pttReleaseSendLocation: json['pttReleaseSendLocation'] as bool? ?? false,
      pttReleaseSendIdInfo: json['pttReleaseSendIdInfo'] as bool? ?? false,
      pttReleaseSendBssUserId:
          json['pttReleaseSendBssUserId'] as bool? ?? false,
      shouldShareLocation: json['shouldShareLocation'] as bool? ?? false,
      sendPwrVoltage: json['sendPwrVoltage'] as bool? ?? false,
      packetFormat: json['packetFormat'] as int? ?? 0,
      allowPositionCheck: json['allowPositionCheck'] as bool? ?? false,
      aprsSsid: json['aprsSsid'] as int? ?? 0,
      locationShareInterval: json['locationShareInterval'] as int? ?? 0,
      bssUserIdLower: json['bssUserIdLower'] as int? ?? 0,
      pttReleaseIdInfo: json['pttReleaseIdInfo'] as String? ?? '',
      beaconMessage: json['beaconMessage'] as String? ?? '',
      aprsSymbol: json['aprsSymbol'] as String? ?? '',
      aprsCallsign: json['aprsCallsign'] as String? ?? '',
    );
  }
}

/// Radio lock state - whether the radio is locked for certain operations
class RadioLockState {
  final bool isLocked;
  final String usage;

  RadioLockState({this.isLocked = false, this.usage = ''});

  factory RadioLockState.fromJson(Map<String, dynamic> json) {
    return RadioLockState(
      isLocked: json['isLocked'] as bool? ?? json['IsLocked'] as bool? ?? false,
      usage: json['usage'] as String? ?? json['Usage'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'isLocked': isLocked, 'usage': usage};
}

/// Connected radio info - information about a connected radio
class ConnectedRadioInfo {
  final int deviceId;
  final String macAddress;
  final String friendlyName;
  final String state;

  ConnectedRadioInfo({
    required this.deviceId,
    this.macAddress = '',
    this.friendlyName = '',
    this.state = '',
  });

  factory ConnectedRadioInfo.fromJson(Map<String, dynamic> json) {
    return ConnectedRadioInfo(
      deviceId: json['DeviceId'] as int? ?? json['deviceId'] as int? ?? 0,
      macAddress:
          json['MacAddress'] as String? ?? json['macAddress'] as String? ?? '',
      friendlyName:
          json['FriendlyName'] as String? ??
          json['friendlyName'] as String? ??
          '',
      state: json['State'] as String? ?? json['state'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'macAddress': macAddress,
    'friendlyName': friendlyName,
    'state': state,
  };
}
