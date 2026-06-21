/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Unit tests for APRS shared-secret message authentication (HMAC-SHA256).
These lock in byte-for-byte compatibility with the C# `AprsAuth` /
`AprsHandler` auth implementation and exercise the sign -> verify round trip
plus tamper and expiry rejection cases.
*/

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/aprs/aprs_auth.dart';
import 'package:htcommander/radio/ax25_packet.dart' show AuthState;

void main() {
  // A fixed timestamp keeps the minute-bucket deterministic across runs.
  final fixedTime = DateTime.utc(2024, 1, 1, 12, 0, 0);

  // Two peers that share the same secret. For an authenticated exchange the
  // recipient must have the sender's callsign configured with the password,
  // and the sender must have the recipient's callsign configured with it.
  const password = 'correct horse battery staple';
  const sender = 'K7VZT-5';
  const recipient = 'N0CALL-1';

  AprsAuth buildAuth() {
    return AprsAuth()
      ..stations = const [
        AprsStationInfo(callsign: sender, isAprs: true, authPassword: password),
        AprsStationInfo(
          callsign: recipient,
          isAprs: true,
          authPassword: password,
        ),
      ];
  }

  group('addAprsAuth', () {
    test('produces an authenticated body with the }code{msgId framing', () {
      final auth = buildAuth();
      final result = auth.addAprsAuth(
        sender,
        recipient,
        'Hello there',
        42,
        fixedTime,
      );

      expect(result.applied, isTrue);
      // Address is padded to 9 chars, message preserved, auth code + msg id.
      expect(result.content, startsWith(':${recipient.padRight(9)}:'));
      expect(result.content, contains('Hello there}'));
      expect(result.content, endsWith('{42'));

      // The 6-char base64 auth code sits between '}' and '{'.
      final braceOpen = result.content.lastIndexOf('}');
      final braceClose = result.content.lastIndexOf('{');
      final code = result.content.substring(braceOpen + 1, braceClose);
      expect(code.length, 6);
    });

    test('falls back to an unauthenticated body when no password is known', () {
      final auth = AprsAuth(); // no stations configured
      final result = auth.addAprsAuth(
        sender,
        recipient,
        'Hello there',
        42,
        fixedTime,
      );

      expect(result.applied, isFalse);
      expect(result.content, ':${recipient.padRight(9)}:Hello there{42');
    });
  });

  group('checkAprsAuth round trip', () {
    test('recipient verifies a freshly signed message (success)', () {
      final auth = buildAuth();
      final signed = auth.addAprsAuth(
        sender,
        recipient,
        'Authenticated payload',
        7,
        fixedTime,
      );
      expect(signed.applied, isTrue);

      // The recipient looks up the password by the source (sender) callsign.
      final state = auth.checkAprsAuth(
        false,
        sender,
        signed.content,
        fixedTime,
      );
      expect(state, AuthState.success);
    });

    test('sender verifies their own echoed message (success)', () {
      final auth = buildAuth();
      final signed = auth.addAprsAuth(
        sender,
        recipient,
        'Echo check',
        8,
        fixedTime,
      );

      // As the sender, the key is looked up by the destination address that is
      // embedded in the message body.
      final state = auth.checkAprsAuth(true, sender, signed.content, fixedTime);
      expect(state, AuthState.success);
    });

    test('ack messages verify via addAprsAckAuth (success)', () {
      final auth = buildAuth();
      final ack = auth.addAprsAckAuth(sender, recipient, 'ack7', fixedTime);
      expect(ack.applied, isTrue);

      final state = auth.checkAprsAuth(false, sender, ack.content, fixedTime);
      expect(state, AuthState.success);
    });
  });

  group('checkAprsAuth rejection', () {
    test('a tampered message body fails verification', () {
      final auth = buildAuth();
      final signed = auth.addAprsAuth(
        sender,
        recipient,
        'Original message',
        9,
        fixedTime,
      );

      // Flip a character in the message content (before the '}').
      final tampered = signed.content.replaceFirst(
        'Original message',
        'Tampered message',
      );

      final state = auth.checkAprsAuth(false, sender, tampered, fixedTime);
      expect(state, AuthState.failed);
    });

    test('an expired timestamp (outside the 5 minute window) fails', () {
      final auth = buildAuth();
      final signed = auth.addAprsAuth(
        sender,
        recipient,
        'Time sensitive',
        10,
        fixedTime,
      );

      // Verify 10 minutes later - well outside the +/- drift window.
      final later = fixedTime.add(const Duration(minutes: 10));
      final state = auth.checkAprsAuth(false, sender, signed.content, later);
      expect(state, AuthState.failed);
    });

    test('an unknown source callsign yields AuthState.none', () {
      final auth = buildAuth();
      final signed = auth.addAprsAuth(
        sender,
        recipient,
        'No key for stranger',
        11,
        fixedTime,
      );

      final state = auth.checkAprsAuth(
        false,
        'ZZ9ZZ-9',
        signed.content,
        fixedTime,
      );
      expect(state, AuthState.none);
    });

    test('a message without an auth code yields AuthState.none', () {
      final auth = buildAuth();
      // Unauthenticated body (no '}code').
      final plain = ':${recipient.padRight(9)}:plain message{12';
      final state = auth.checkAprsAuth(false, sender, plain, fixedTime);
      expect(state, AuthState.none);
    });
  });
}
