/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

//
// notification_router.dart - Turns a tapped notification's payload into the
// Messaging-tab conversation it belongs to.
//
// Payload formats:
//   aprs:<peer>                  APRS conversation (callsign, or SMS digits)
//   meshcore:<kind>:<peer>       MeshCore conversation (kind user|group)
//

import 'package:flutter/widgets.dart';

import 'data_broker.dart';

const String _aprsPrefix = 'aprs:';
const String _meshCorePrefix = 'meshcore:';

/// Data Broker device that owns the APRS tab's `AprsOpenConversation` signal.
const int _aprsDeviceId = 1;

/// Data Broker device of the MeshCore manager (see meshcore_manager.dart).
const int _meshCoreDeviceId = 204;

String aprsNotificationPayload(String peer) => '$_aprsPrefix$peer';

String meshCoreNotificationPayload(String conversationKey) =>
    '$_meshCorePrefix$conversationKey';

/// Where a notification tap should lead: a tab, plus an optional retained
/// open-conversation signal for that tab.
class NotificationRoute {
  final String tab;
  final int? deviceId;
  final String? signal;
  final String? conversation;

  const NotificationRoute(
    this.tab, {
    this.deviceId,
    this.signal,
    this.conversation,
  });
}

/// Parses [payload] into a route, or null when it does not target a
/// conversation.
NotificationRoute? parseNotificationPayload(String? payload) {
  if (payload == null) return null;
  if (payload.startsWith(_aprsPrefix)) {
    final peer = payload.substring(_aprsPrefix.length).trim();
    if (peer.isEmpty) return const NotificationRoute('APRS');
    return NotificationRoute(
      'APRS',
      deviceId: _aprsDeviceId,
      signal: 'AprsOpenConversation',
      conversation: peer,
    );
  }
  if (payload.startsWith(_meshCorePrefix)) {
    final key = payload.substring(_meshCorePrefix.length).trim();
    final sep = key.indexOf(':');
    if (sep <= 0 || sep == key.length - 1) {
      return const NotificationRoute('APRS');
    }
    return NotificationRoute(
      'APRS',
      deviceId: _meshCoreDeviceId,
      signal: 'MeshCoreOpenConversation',
      conversation: key,
    );
  }
  // Legacy payload without a peer.
  if (payload == 'aprs') return const NotificationRoute('APRS');
  return null;
}

/// Switches to the Messaging tab and asks it to open the conversation. The
/// request is retained (store: true) so a tab that is only being built because
/// of the switch still picks it up; the tab clears it once consumed.
void routeNotificationTap(String? payload) {
  final route = parseNotificationPayload(payload);
  if (route == null) return;
  DataBroker.dispatch(
    deviceId: 0,
    name: 'RequestSelectTab',
    data: route.tab,
    store: false,
  );
  final signal = route.signal;
  if (signal == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    DataBroker.dispatch(
      deviceId: route.deviceId!,
      name: signal,
      data: route.conversation,
      store: true,
    );
  });
}
