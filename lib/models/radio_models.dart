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
  final int doubleChannel; // 0 = off, 1 = on
  final int squelchLevel;
  final bool pttLock;
  final int noaaCh;

  RadioSettings({
    this.channelA = 0,
    this.channelB = 0,
    this.scan = false,
    this.doubleChannel = 0,
    this.squelchLevel = 0,
    this.pttLock = false,
    this.noaaCh = 0,
  });

  factory RadioSettings.fromJson(Map<String, dynamic> json) {
    return RadioSettings(
      channelA: json['channelA'] as int? ?? json['channel_a'] as int? ?? 0,
      channelB: json['channelB'] as int? ?? json['channel_b'] as int? ?? 0,
      scan: json['scan'] as bool? ?? false,
      doubleChannel:
          json['doubleChannel'] as int? ?? json['double_channel'] as int? ?? 0,
      squelchLevel:
          json['squelchLevel'] as int? ?? json['squelch_level'] as int? ?? 0,
      pttLock: json['pttLock'] as bool? ?? json['ptt_lock'] as bool? ?? false,
      noaaCh: json['noaaCh'] as int? ?? json['noaa_ch'] as int? ?? 0,
    );
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
  final bool locked;
  final DateTime? timestamp;

  RadioPosition({
    this.latitude = 0,
    this.longitude = 0,
    this.altitude = 0,
    this.speed = 0,
    this.heading = 0,
    this.locked = false,
    this.timestamp,
  });

  factory RadioPosition.fromJson(Map<String, dynamic> json) {
    return RadioPosition(
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      altitude: (json['altitude'] as num?)?.toDouble() ?? 0,
      speed: (json['speed'] as num?)?.toDouble() ?? 0,
      heading: (json['heading'] as num?)?.toDouble() ?? 0,
      locked: json['locked'] as bool? ?? json['Locked'] as bool? ?? false,
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'altitude': altitude,
    'speed': speed,
    'heading': heading,
    'locked': locked,
    'timestamp': timestamp?.toIso8601String(),
  };
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
