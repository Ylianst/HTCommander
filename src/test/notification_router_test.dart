import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/services/notification_router.dart';

void main() {
  test('APRS payload opens the sender conversation', () {
    final route = parseNotificationPayload(aprsNotificationPayload('K1ABC-7'))!;
    expect(route.tab, 'APRS');
    expect(route.deviceId, 1);
    expect(route.signal, 'AprsOpenConversation');
    expect(route.conversation, 'K1ABC-7');
  });

  test('MeshCore payload opens the user or group conversation', () {
    final user = parseNotificationPayload(
      meshCoreNotificationPayload('user:0a1b2c3d4e5f'),
    )!;
    expect(user.tab, 'APRS');
    expect(user.deviceId, 204);
    expect(user.signal, 'MeshCoreOpenConversation');
    expect(user.conversation, 'user:0a1b2c3d4e5f');
    expect(
      parseNotificationPayload('meshcore:group:abcd')!.conversation,
      'group:abcd',
    );
  });

  test('payloads without a peer only switch tabs', () {
    for (final p in ['aprs', 'aprs:', 'meshcore:', 'meshcore:user:']) {
      final route = parseNotificationPayload(p)!;
      expect(route.tab, 'APRS', reason: p);
      expect(route.signal, isNull, reason: p);
    }
  });

  test('other payloads are not routed', () {
    expect(parseNotificationPayload(null), isNull);
    expect(parseNotificationPayload('mail'), isNull);
    expect(parseNotificationPayload('comms'), isNull);
  });
}
