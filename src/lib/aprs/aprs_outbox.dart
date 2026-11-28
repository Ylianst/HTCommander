/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

enum AprsDelivery { queued, sent, digipeated, delivered, rejected, failed, paused, stopped }

enum AprsComposeError { empty, ascii, reserved, tooLong, address }

class AprsComposeException implements Exception {
  final AprsComposeError reason;
  const AprsComposeException(this.reason);
  @override
  String toString() => 'Invalid APRS message: ${reason.name}';
}

/// The 67-byte text field excludes the addressee and wire ID, but includes
/// gateway prefixes, multipart numbering and our seven-byte auth suffix.
List<String> splitAprsMessage(String text, String destination, {bool authenticated = false}) {
  if (text.trim().isEmpty) throw const AprsComposeException(AprsComposeError.empty);
  if (text.codeUnits.any((c) => c < 32 || c > 126)) {
    throw const AprsComposeException(AprsComposeError.ascii);
  }
  if (RegExp(r'[{}|~]').hasMatch(text)) {
    throw const AprsComposeException(AprsComposeError.reserved);
  }
  final budget = 67 - (authenticated ? 7 : 0);
  if (text.length <= budget) return [text];
  var prefix = '';
  var body = text;
  if (destination == 'SMS' || destination == 'SMSGTE') {
    final match = RegExp(r'^@\S+ ').firstMatch(text);
    if (match != null) {
      prefix = match.group(0)!;
      body = text.substring(prefix.length);
    }
  }
  for (var count = 2; count <= 20; count++) {
    final capacity = budget - prefix.length - '($count/$count) '.length;
    if (capacity < 1 || body.length > capacity * count) continue;
    final parts = <String>[];
    for (var offset = 0; offset < body.length; offset += capacity) {
      final end = (offset + capacity).clamp(0, body.length);
      parts.add('$prefix(${parts.length + 1}/$count) ${body.substring(offset, end)}');
    }
    // A wider counter can reduce capacity; use the actual count consistently.
    if (parts.length == count) return parts;
  }
  throw const AprsComposeException(AprsComposeError.tooLong);
}

class AprsOutboxPart {
  final int wireId;
  final String text;
  final AprsDelivery state;
  final int attempts;
  final DateTime? nextAttempt;
  final String? error;

  const AprsOutboxPart({
    required this.wireId,
    required this.text,
    this.state = AprsDelivery.queued,
    this.attempts = 0,
    this.nextAttempt,
    this.error,
  });

  bool get pending => state == AprsDelivery.queued || state == AprsDelivery.sent || state == AprsDelivery.digipeated;
  bool get answered => state == AprsDelivery.delivered || state == AprsDelivery.rejected;

  AprsOutboxPart update({
    AprsDelivery? state,
    int? attempts,
    DateTime? nextAttempt,
    String? error,
  }) => AprsOutboxPart(
    wireId: wireId,
    text: text,
    state: state ?? this.state,
    attempts: attempts ?? this.attempts,
    nextAttempt: nextAttempt,
    error: error,
  );

  Map<String, Object?> toJson() => {
    'wireId': wireId, 'text': text, 'state': state.name, 'attempts': attempts,
    'nextAttempt': nextAttempt?.millisecondsSinceEpoch, 'error': error,
  };

  factory AprsOutboxPart.fromJson(Map<String, dynamic> json) => AprsOutboxPart(
    wireId: json['wireId'] as int,
    text: json['text'] as String,
    state: AprsDelivery.values.byName(json['state'] as String),
    attempts: json['attempts'] as int,
    nextAttempt: json['nextAttempt'] == null ? null : DateTime.fromMillisecondsSinceEpoch(json['nextAttempt'] as int),
    error: json['error'] as String?,
  );
}

class AprsOutgoingMessage {
  final String id;
  final String source;
  final String destination;
  final String text;
  final DateTime created;
  final int radioDeviceId;
  final String? radioMac;
  final bool internet;
  final bool authenticated;
  final List<String>? route;
  final int maxAttempts;
  final int retrySeconds;
  final List<AprsOutboxPart> parts;

  const AprsOutgoingMessage({
    required this.id, required this.source, required this.destination,
    required this.text, required this.created, required this.radioDeviceId,
    required this.internet, required this.authenticated, required this.parts,
    this.radioMac, this.route, this.maxAttempts = 6, this.retrySeconds = 30,
  });

  bool get active => parts.any((p) => p.pending || p.state == AprsDelivery.paused);
  AprsDelivery get state {
    for (final state in const [
      AprsDelivery.rejected, AprsDelivery.failed, AprsDelivery.stopped,
      AprsDelivery.paused, AprsDelivery.queued, AprsDelivery.sent, AprsDelivery.digipeated,
    ]) {
      if (parts.any((p) => p.state == state)) return state;
    }
    return AprsDelivery.delivered;
  }

  AprsOutgoingMessage withParts(List<AprsOutboxPart> parts) => AprsOutgoingMessage(
    id: id, source: source, destination: destination, text: text, created: created,
    radioDeviceId: radioDeviceId, radioMac: radioMac, internet: internet,
    authenticated: authenticated, route: route, maxAttempts: maxAttempts,
    retrySeconds: retrySeconds, parts: parts,
  );

  Map<String, Object?> toJson() => {
    'id': id, 'source': source, 'destination': destination, 'text': text,
    'created': created.millisecondsSinceEpoch, 'radioDeviceId': radioDeviceId,
    'radioMac': radioMac, 'internet': internet, 'authenticated': authenticated,
    'route': route, 'maxAttempts': maxAttempts, 'retrySeconds': retrySeconds,
    'parts': parts.map((p) => p.toJson()).toList(),
  };

  factory AprsOutgoingMessage.fromJson(Map<String, dynamic> json) => AprsOutgoingMessage(
    id: json['id'] as String, source: json['source'] as String,
    destination: json['destination'] as String, text: json['text'] as String,
    created: DateTime.fromMillisecondsSinceEpoch(json['created'] as int),
    radioDeviceId: json['radioDeviceId'] as int, radioMac: json['radioMac'] as String?,
    internet: json['internet'] as bool, authenticated: json['authenticated'] as bool,
    route: (json['route'] as List?)?.cast<String>(),
    maxAttempts: json['maxAttempts'] as int, retrySeconds: json['retrySeconds'] as int,
    parts: (json['parts'] as List).map((p) => AprsOutboxPart.fromJson(Map<String, dynamic>.from(p as Map))).toList(),
  );
}
