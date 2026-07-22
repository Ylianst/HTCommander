/*
Copyright 2026 Ylian Saint-Hilaire

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

//
// echolink_credentials_test.dart - Tests for EchoLink credential validation.
//

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/echolink/echolink_credential_test.dart';
import 'package:htcommander/echolink/echolink_network.dart';

class _FakeNetwork implements EchoLinkNetwork {
  /// Ack returned for the login ('l') command.
  Uint8List loginAck = Uint8List.fromList(latin1.encode('OK2.5\n'));

  /// Response returned for the station-list ('s') command.
  Uint8List listResponse = Uint8List(0);

  Object? throwError;
  final List<Uint8List> requests = <Uint8List>[];

  @override
  Future<Uint8List> directoryExchange(List<String> servers, Uint8List request,
      {int? maxBytes}) async {
    requests.add(request);
    if (throwError != null) throw throwError!;
    if (request.isNotEmpty && request[0] == 0x73) return listResponse; // 's'
    return loginAck; // 'l'
  }

  @override
  Stream<EchoLinkDatagram> get audioIn => const Stream<EchoLinkDatagram>.empty();
  @override
  Stream<EchoLinkDatagram> get controlIn =>
      const Stream<EchoLinkDatagram>.empty();
  @override
  Future<void> open() async {}
  @override
  void sendAudio(String host, Uint8List data) {}
  @override
  void sendControl(String host, Uint8List data) {}
  @override
  Future<void> close() async {}
}

Uint8List _resp(List<String> lines) =>
    Uint8List.fromList(latin1.encode(lines.join('\n')));

void main() {
  group('interpretDirectoryResponse', () {
    test('detects an incorrect password from the server message block', () {
      final Uint8List r = _resp(<String>[
        '@@@',
        '3',
        '.', 'Incorrect password [   ]', '0000', '127.0.0.1',
        ' ', 'INCORRECT PASSWORD           ', '    ', '127.0.0.1',
        ' ', 'Please check the password    ', '    ', '127.0.0.1',
        '+++',
      ]);
      final EchoLinkCredentialResult res = interpretDirectoryResponse(r);
      expect(res.status, EchoLinkCredentialStatus.incorrectPassword);
      expect(res.ok, isFalse);
    });

    test('detects a pending call-sign validation', () {
      final Uint8List r = _resp(<String>[
        '@@@',
        '1',
        ' ', 'Your callsign is being validated', '    ', '127.0.0.1',
        '+++',
      ]);
      expect(interpretDirectoryResponse(r).status,
          EchoLinkCredentialStatus.validationPending);
    });

    test('treats a normal station list as valid credentials', () {
      final Uint8List r = _resp(<String>[
        '@@@',
        '1',
        'W1AW', 'Newington, CT [ON 10:00]', '1234', '1.2.3.4',
        '+++',
      ]);
      final EchoLinkCredentialResult res = interpretDirectoryResponse(r);
      expect(res.status, EchoLinkCredentialStatus.valid);
      expect(res.ok, isTrue);
    });

    test('a truncated (prefix) station list is still valid', () {
      final Uint8List r = _resp(<String>[
        '@@@',
        '2039',
        '*ECSEA*', 'Panama City, Fl. [ON 16:08]', '172277', '24.214.38.68',
        'IW2LXR', 'Vittorio Milano [ON 23:07]', '29136', '219.113.182.1',
      ]); // no +++ (truncated prefix of a large list)
      expect(interpretDirectoryResponse(r).status,
          EchoLinkCredentialStatus.valid);
    });

    test('empty response is unknown', () {
      expect(interpretDirectoryResponse(Uint8List(0)).status,
          EchoLinkCredentialStatus.unknown);
    });

    test('a non call-list reply is unknown, not valid', () {
      final Uint8List r = Uint8List.fromList(latin1.encode('unexpected junk'));
      expect(interpretDirectoryResponse(r).status,
          EchoLinkCredentialStatus.unknown);
    });
  });

  group('testEchoLinkCredentials', () {
    test('resets, logs in, requests the list and reports incorrect password',
        () async {
      final _FakeNetwork net = _FakeNetwork()
        ..listResponse = _resp(<String>[
          '@@@',
          '1',
          ' ', 'INCORRECT PASSWORD    ', '    ', '127.0.0.1',
          '+++',
        ]);

      final EchoLinkCredentialResult res = await testEchoLinkCredentials(
        callsign: 'N0CALL',
        password: 'wrong',
        network: net,
        nowHHmm: '08:30',
      );

      expect(res.status, EchoLinkCredentialStatus.incorrectPassword);

      // An OFFLINE reset precedes the ONLINE login, then get-calls ('s').
      final List<String> texts =
          net.requests.map((Uint8List r) => latin1.decode(r)).toList();
      expect(texts.any((String t) => t.contains('OFF-V3.40')), isTrue);
      expect(texts.any((String t) => t.contains('ONLINE3.38(')), isTrue);
      expect(net.requests.any((Uint8List r) => r.length == 1 && r[0] == 0x73),
          isTrue);
    });

    test('network failure reports unreachable', () async {
      final _FakeNetwork net = _FakeNetwork()
        ..throwError = StateError('no route');
      final EchoLinkCredentialResult res = await testEchoLinkCredentials(
        callsign: 'N0CALL',
        password: 'x',
        network: net,
      );
      expect(res.status, EchoLinkCredentialStatus.unreachable);
    });

    test('valid credentials are reported ok', () async {
      final _FakeNetwork net = _FakeNetwork()
        ..listResponse = _resp(<String>[
          '@@@',
          '1',
          'W1AW', 'Newington, CT [ON 10:00]', '1234', '1.2.3.4',
          '+++',
        ]);
      final EchoLinkCredentialResult res = await testEchoLinkCredentials(
        callsign: 'N0CALL',
        password: 'right',
        network: net,
      );
      expect(res.ok, isTrue);
    });
  });
}
