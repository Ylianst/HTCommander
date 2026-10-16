/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// Conversation kinds for MeshCore messages.
abstract final class MeshCoreKind {
  /// Direct message; the peer is the 12-hex-digit public-key prefix.
  static const String user = 'user';

  /// Group channel; the peer is the channel key derived from its secret.
  static const String group = 'group';
}

/// Delivery states for MeshCore messages.
abstract final class MeshCoreDelivery {
  static const String received = 'received';
  static const String pending = 'pending';
  static const String sent = 'sent';
  static const String delivered = 'delivered';
  static const String failed = 'failed';
}

/// Whether [msg] should raise a notification: an incoming direct message,
/// i.e. one addressed to this companion. Group/channel messages and our own
/// outgoing messages never notify.
bool isDirectMessageToUs(MeshCoreMessage msg) =>
    !msg.outgoing && msg.kind == MeshCoreKind.user;

/// One MeshCore message as stored and passed over the Data Broker.
class MeshCoreMessage {
  int id;
  final DateTime time;

  /// Sender clock (seconds since the epoch), used for de-duplication. A manual
  /// resend gives an outgoing message a fresh value.
  int senderTime;
  final String kind;
  final String peer;
  final bool outgoing;

  /// Display name of the sender. For group messages this comes from the
  /// message text and is not verified.
  final String sender;
  final String text;

  /// Received path length byte (0xFF = direct), when known.
  final int? pathLen;
  final double? snr;
  String state;
  int? ackTag;

  MeshCoreMessage({
    this.id = 0,
    required this.time,
    required this.senderTime,
    required this.kind,
    required this.peer,
    required this.outgoing,
    required this.sender,
    required this.text,
    this.pathLen,
    this.snr,
    required this.state,
    this.ackTag,
  });

  String get conversationKey => '$kind:$peer';

  Map<String, dynamic> toJson() => {
    'id': id,
    'time': time.millisecondsSinceEpoch,
    'senderTime': senderTime,
    'kind': kind,
    'peer': peer,
    'out': outgoing,
    'sender': sender,
    'text': text,
    'pathLen': pathLen,
    'snr': snr,
    'state': state,
    'ack': ackTag,
  };

  static MeshCoreMessage fromJson(Map<dynamic, dynamic> j) => MeshCoreMessage(
    id: (j['id'] as num?)?.toInt() ?? 0,
    time: DateTime.fromMillisecondsSinceEpoch(
      (j['time'] as num?)?.toInt() ?? 0,
    ),
    senderTime: (j['senderTime'] as num?)?.toInt() ?? 0,
    kind: j['kind']?.toString() ?? MeshCoreKind.user,
    peer: j['peer']?.toString() ?? '',
    outgoing: j['out'] == true,
    sender: j['sender']?.toString() ?? '',
    text: j['text']?.toString() ?? '',
    pathLen: (j['pathLen'] as num?)?.toInt(),
    snr: (j['snr'] as num?)?.toDouble(),
    state: j['state']?.toString() ?? MeshCoreDelivery.received,
    ackTag: (j['ack'] as num?)?.toInt(),
  );

  Map<String, Object?> toRow() => {
    'time_ms': time.millisecondsSinceEpoch,
    'sender_time': senderTime,
    'kind': kind,
    'peer': peer,
    'outgoing': outgoing ? 1 : 0,
    'sender': sender,
    'text': text,
    'path_len': pathLen,
    'snr': snr,
    'state': state,
    'ack_tag': ackTag,
  };

  static MeshCoreMessage fromRow(Map<String, Object?> r) => MeshCoreMessage(
    id: r['id'] as int? ?? 0,
    time: DateTime.fromMillisecondsSinceEpoch(r['time_ms'] as int? ?? 0),
    senderTime: r['sender_time'] as int? ?? 0,
    kind: r['kind'] as String? ?? MeshCoreKind.user,
    peer: r['peer'] as String? ?? '',
    outgoing: (r['outgoing'] as int? ?? 0) != 0,
    sender: r['sender'] as String? ?? '',
    text: r['text'] as String? ?? '',
    pathLen: r['path_len'] as int?,
    snr: (r['snr'] as num?)?.toDouble(),
    state: r['state'] as String? ?? MeshCoreDelivery.received,
    ackTag: r['ack_tag'] as int?,
  );
}
