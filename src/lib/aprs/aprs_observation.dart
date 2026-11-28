/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

enum AprsReceiveKind { directRf, digipeatedRf, thirdParty, internet, loopback, invalid }
enum AprsDecodeDuplicate { none, sameDecoder, otherDecoder }

class AprsObservedHop {
  final String callsign;
  final bool used;
  const AprsObservedHop(this.callsign, this.used);
  Map<String, dynamic> toJson() => {'callsign': callsign, 'used': used};
  factory AprsObservedHop.fromJson(Map<String, dynamic> json) =>
      AprsObservedHop(json['callsign'] as String, json['used'] as bool);
}

/// One decoder observation, not proof of a distinct physical transmission.
class AprsObservation {
  static const capacity = 1000;
  final String id;
  final DateTime observed, received;
  final int? radioDeviceId;
  final String? radioMac;
  final int channel, region;
  final String channelName, decoder, frameType, dataHex, information;
  final int corrections;
  final String? source, frameSource, destination, addressee;
  final List<AprsObservedHop> path;
  final AprsReceiveKind kind;
  final AprsDecodeDuplicate duplicate;
  final String? duplicateOf;
  final bool live, persisted;

  AprsObservation({
    required this.id, required DateTime observed, required DateTime received,
    required this.radioDeviceId, required this.radioMac, required this.channel,
    required this.region, required this.channelName, required this.decoder,
    required this.frameType, required this.corrections, required this.dataHex,
    required this.information, required this.source, required this.frameSource,
    required this.destination, required this.addressee, required List<AprsObservedHop> path,
    required this.kind, this.duplicate = AprsDecodeDuplicate.none, this.duplicateOf,
    this.live = true, this.persisted = false,
  }) : observed = observed.toUtc(), received = received.toUtc(), path = List.unmodifiable(path);

  /// Consumers establishing current RF reachability must use live events,
  /// never a restored snapshot; third-party sources are not directly heard.
  bool get isLiveDirectRf => live && kind == AprsReceiveKind.directRf;

  AprsObservation withStatus({required bool live, required bool persisted}) => AprsObservation(
    id: id, observed: observed, received: received, radioDeviceId: radioDeviceId,
    radioMac: radioMac, channel: channel, region: region, channelName: channelName,
    decoder: decoder, frameType: frameType, corrections: corrections, dataHex: dataHex,
    information: information, source: source, frameSource: frameSource, destination: destination,
    addressee: addressee, path: path, kind: kind, duplicate: duplicate, duplicateOf: duplicateOf,
    live: live, persisted: persisted,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'observed': observed.toIso8601String(), 'received': received.toIso8601String(),
    'radioDeviceId': radioDeviceId, 'radioMac': radioMac, 'channel': channel, 'region': region,
    'channelName': channelName, 'decoder': decoder, 'frameType': frameType,
    'corrections': corrections, 'dataHex': dataHex, 'information': information,
    'source': source, 'frameSource': frameSource, 'destination': destination, 'addressee': addressee,
    'path': path.map((h) => h.toJson()).toList(), 'kind': kind.name,
    'duplicate': duplicate.name, 'duplicateOf': duplicateOf, 'live': live, 'persisted': persisted,
  };

  factory AprsObservation.fromJson(Map<String, dynamic> json) => AprsObservation(
    id: json['id'] as String, observed: DateTime.parse(json['observed'] as String),
    received: DateTime.parse(json['received'] as String), radioDeviceId: json['radioDeviceId'] as int?,
    radioMac: json['radioMac'] as String?, channel: json['channel'] as int, region: json['region'] as int,
    channelName: json['channelName'] as String, decoder: json['decoder'] as String,
    frameType: json['frameType'] as String, corrections: json['corrections'] as int,
    dataHex: json['dataHex'] as String, information: json['information'] as String,
    source: json['source'] as String?, frameSource: json['frameSource'] as String?,
    destination: json['destination'] as String?, addressee: json['addressee'] as String?,
    path: (json['path'] as List).map((h) => AprsObservedHop.fromJson(Map<String, dynamic>.from(h as Map))).toList(),
    kind: AprsReceiveKind.values.byName(json['kind'] as String),
    duplicate: AprsDecodeDuplicate.values.byName(json['duplicate'] as String),
    duplicateOf: json['duplicateOf'] as String?, live: json['live'] as bool,
    persisted: json['persisted'] as bool,
  );
}
