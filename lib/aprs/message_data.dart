/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// APRS message subtype. Mirrors the C# `MessageType` enum.
enum MessageType {
  mtUnknown,
  mtGeneral,
  mtBulletin,
  mtAnnouncement,
  mtNWS,
  mtAck,
  mtRej,
  mtAutoAnswer,
}

/// Parsed APRS message fields. Mirrors the C# `MessageData` class.
class MessageData {
  String addressee = '';
  String seqId = '';
  String msgText = '';
  MessageType msgType = MessageType.mtUnknown;
  int msgIndex = 0;
}
