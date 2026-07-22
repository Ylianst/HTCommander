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
// echolink_credential_test.dart - Verifies EchoLink credentials against the
// directory server.
//
// The directory login ('l' command) only returns a short "OK<version>" ack and
// does NOT report a bad password directly. The password check surfaces on the
// following station-list request ('s'): the server correlates the two by source
// IP, so after a bad-password login the list response is a small server-message
// block containing "INCORRECT PASSWORD" (or "being validated" for an
// unvalidated call sign). A good login yields the real (large) station list, of
// which we only read a bounded prefix.
//
// Test flow: send an ONLINE login, then request the list and interpret it.
//

import 'dart:convert';
import 'dart:typed_data';

import 'echolink_directory.dart';
import 'echolink_network.dart';
import 'echolink_network_io.dart';

/// Outcome of an EchoLink credential test.
enum EchoLinkCredentialStatus {
  valid,
  incorrectPassword,
  validationPending,
  unreachable,
  unknown,
}

class EchoLinkCredentialResult {
  final EchoLinkCredentialStatus status;

  /// Raw server message (when the server returned one), for diagnostics.
  final String detail;

  const EchoLinkCredentialResult(this.status, [this.detail = '']);

  bool get ok => status == EchoLinkCredentialStatus.valid;
}

String _nowHHmm() {
  final DateTime n = DateTime.now();
  String p(int v) => v.toString().padLeft(2, '0');
  return '${p(n.hour)}:${p(n.minute)}';
}

/// Tests [callsign]/[password] against an EchoLink directory server.
///
/// Pass a [network] to unit-test; otherwise a real [DartIoEchoLinkNetwork] is
/// used and closed automatically.
Future<EchoLinkCredentialResult> testEchoLinkCredentials({
  required String callsign,
  required String password,
  String location = '',
  List<String>? servers,
  EchoLinkNetwork? network,
  String? nowHHmm,
}) async {
  final EchoLinkNetwork net = network ?? DartIoEchoLinkNetwork();
  final bool ownsNet = network == null;
  final List<String> serverList = servers ?? defaultDirectoryServers;
  final String time = nowHHmm ?? _nowHHmm();

  Uint8List login(DirectoryStatus status) => buildLoginCommand(
        callsign: callsign,
        password: password,
        description: location,
        status: status,
        timeHHmm: time,
      );

  try {
    // Step 1: OFFLINE login first. The directory caches an authenticated
    // session by source IP + call sign, so a station that is already online
    // (e.g. from an earlier successful login) is not re-checked. Taking it
    // offline first forces the following ONLINE login to be validated again.
    try {
      await net.directoryExchange(serverList, login(DirectoryStatus.offline),
          maxBytes: 16);
    } catch (_) {}

    // Step 2: ONLINE login. The reply is only a short "OK<ver>" ack; a bad
    // password is not reported here.
    await net.directoryExchange(serverList, login(DirectoryStatus.online),
        maxBytes: 16);

    // Step 3: request the station list. After a bad-password login this is a
    // small "INCORRECT PASSWORD" block; after a good login it is the real list
    // (of which we read only a prefix).
    final Uint8List listResp = await net.directoryExchange(
        serverList, buildListRequest(),
        maxBytes: 16384);

    final EchoLinkCredentialResult result = interpretDirectoryResponse(listResp);

    // Step 4: clean up - take the station back offline so a credential test
    // does not leave it advertised as online.
    try {
      await net.directoryExchange(serverList, login(DirectoryStatus.offline),
          maxBytes: 16);
    } catch (_) {}

    return result;
  } catch (e) {
    return EchoLinkCredentialResult(
        EchoLinkCredentialStatus.unreachable, e.toString());
  } finally {
    if (ownsNet) {
      try {
        await net.close();
      } catch (_) {}
    }
  }
}

/// Interprets a directory station-list response. Exposed for testing.
EchoLinkCredentialResult interpretDirectoryResponse(Uint8List response) {
  if (response.isEmpty) {
    return const EchoLinkCredentialResult(EchoLinkCredentialStatus.unknown);
  }

  final String text = latin1.decode(response, allowInvalid: true);
  final String upper = text.toUpperCase();

  // Prefer the structured server-message lines when the reply is a call list.
  String detail = text.trim();
  bool isCallList = false;
  try {
    final DirectoryListing listing = parseStationList(response);
    isCallList = true;
    if (listing.message.trim().isNotEmpty) {
      detail = listing.message.trim();
    }
  } catch (_) {
    // Not a call-list framed response; fall back to the raw text.
  }

  if (upper.contains('INCORRECT PASSWORD') || upper.contains('BAD PASSWORD')) {
    return EchoLinkCredentialResult(
        EchoLinkCredentialStatus.incorrectPassword, detail);
  }
  if (upper.contains('VALIDAT')) {
    return EchoLinkCredentialResult(
        EchoLinkCredentialStatus.validationPending, detail);
  }

  // Only treat the reply as valid when it is a well-formed directory call list
  // (starts with the "@@@" marker). Anything else is inconclusive, so we do not
  // report a false positive.
  if (isCallList || text.trimLeft().startsWith('@@@')) {
    return EchoLinkCredentialResult(EchoLinkCredentialStatus.valid, detail);
  }
  return EchoLinkCredentialResult(EchoLinkCredentialStatus.unknown, detail);
}
