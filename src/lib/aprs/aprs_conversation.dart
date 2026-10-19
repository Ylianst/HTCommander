/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

//
// aprs_conversation.dart - Shared APRS Messenger threading rules. The APRS tab
// uses these to group messages into conversations, and the stores use the same
// rules to delete exactly the messages of a conversation the user cleared.
//

import '../radio/ax25_packet.dart';
import '../radio/tnc_data_fragment.dart';
import 'aprs_packet.dart';
import 'message_data.dart';
import 'packet_data_type.dart';

/// Broker event (device 1) asking every APRS store to delete the messages of one
/// Messenger conversation. Data: `{'peer': conversationKey}`.
const String clearAprsConversationEvent = 'ClearAprsConversation';

/// Our own station identity, used to tell which messages are addressed to us.
class AprsLocalStation {
  /// Bare callsign (e.g. "K7VZT").
  final String callsign;

  /// Callsign with station id (e.g. "K7VZT-5"), or the bare callsign when the
  /// station id is 0.
  final String callsignWithId;

  const AprsLocalStation(this.callsign, this.callsignWithId);

  /// Builds the identity from the `CallSign` / `StationId` settings.
  factory AprsLocalStation.fromSettings(String callsign, int stationId) =>
      AprsLocalStation(
        callsign,
        stationId > 0 ? '$callsign-$stationId' : callsign,
      );
}

/// Conversation key for a callsign: uppercased, with a "-0" SSID dropped so
/// "SMS" and "SMS-0" share one thread.
String aprsPeerKey(String callsign) {
  final upper = callsign.trim().toUpperCase();
  return upper.endsWith('-0') ? upper.substring(0, upper.length - 2) : upper;
}

/// Digits-only form of a phone number, used as the SMS conversation key.
String aprsDigitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

/// Whether [callsign] is the APRS SMS gateway (SMS / SMSGTE, any SSID).
bool isAprsSmsGateway(String callsign) {
  final base = callsign.split('-').first.toUpperCase();
  return base == 'SMS' || base == 'SMSGTE';
}

/// Returns the conversation key a message belongs to, or null when it is not
/// part of one of our conversations (e.g. traffic between two other stations).
///
/// [sender] is the originating station, [outgoing] whether we sent it. APRS SMS
/// gateway traffic (`@<phone> <text>`) is threaded under the phone digits.
String? aprsConversationPeer({
  required String sender,
  required String addressee,
  required String text,
  required bool outgoing,
  required AprsLocalStation local,
}) {
  final forSelf =
      addressee == local.callsign || addressee == local.callsignWithId;
  String? peer;
  if (outgoing) {
    peer = aprsPeerKey(addressee);
  } else if (forSelf) {
    peer = aprsPeerKey(sender);
  }
  final fromSmsGateway = !outgoing && isAprsSmsGateway(sender);
  if ((addressee == 'SMS' || fromSmsGateway) && text.startsWith('@')) {
    final sp = text.indexOf(' ');
    if (sp > 1) {
      final phone = aprsDigitsOnly(text.substring(1, sp));
      if (phone.isNotEmpty) peer = phone;
    }
  }
  return peer;
}

/// Conversation key of a parsed APRS packet, or null when it is not a chat
/// message (ACK/REJ, position, ...) or not part of one of our conversations.
String? aprsPacketConversationPeer(
  AprsPacket aprs, {
  required bool outgoing,
  required AprsLocalStation local,
}) {
  if (aprs.dataType != PacketDataType.message) return null;
  final type = aprs.messageData.msgType;
  if (type == MessageType.mtAck || type == MessageType.mtRej) return null;
  final packet = aprs.packet;
  if (packet == null || packet.addresses.isEmpty) return null;
  return aprsConversationPeer(
    sender: aprs.sourceCallsignWithId,
    addressee: aprs.messageData.addressee,
    text: aprs.messageData.msgText,
    outgoing: outgoing,
    local: local,
  );
}

/// Conversation key of a stored RF frame, decoded the same way the APRS handler
/// loads it, or null when it is not one of our conversation messages.
String? aprsFrameConversationPeer(
  TncDataFragment frame, {
  required AprsLocalStation local,
}) {
  final ax25 = AX25Packet.decode(frame);
  if (ax25 == null) return null;
  if (ax25.type != FrameType.uFrameUi && ax25.type != FrameType.uFrame) {
    return null;
  }
  final aprs = AprsPacket.parse(ax25);
  if (aprs == null) return null;
  return aprsPacketConversationPeer(
    aprs,
    outgoing: !ax25.incoming,
    local: local,
  );
}
