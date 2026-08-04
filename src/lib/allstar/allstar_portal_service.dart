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
// allstar_portal_service.dart - Obtains an AllStarLink "Web Transceiver" (WT)
// access token from the operator's portal account. The token is later sent as
// the CallerID name of an IAX2 call into a node's [allstar-public] context,
// which validates it server-side and lets the call through (public auth).
//
// Wire contract (allstarlink.org /api/v2/auth-wt-legacy):
//   POST, Content-Type: application/json, body {"username":..,"password":..}
//   Response JSON: {"status":"OK"|"ERR","auth":0|1,"token":"..","msg":".."}
//

import 'dart:convert';

import 'package:http/http.dart' as http;

/// Outcome of a portal token request.
class AllStarWtAuthResult {
  final bool success;
  final String token;
  final String message;

  const AllStarWtAuthResult({
    required this.success,
    required this.token,
    required this.message,
  });
}

/// Exchanges an AllStarLink portal callsign + password for a Web Transceiver
/// token via the legacy auth endpoint.
class AllStarPortalService {
  static const String endpoint =
      'https://www.allstarlink.org/api/v2/auth-wt-legacy';

  final http.Client _client;
  final bool _ownsClient;

  AllStarPortalService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  /// Requests a WT token for [username] (the portal callsign) and [password].
  /// Never throws for HTTP/auth errors; failures are reported in the result.
  Future<AllStarWtAuthResult> fetchToken({
    required String username,
    required String password,
  }) async {
    http.Response resp;
    try {
      resp = await _client
          .post(
            Uri.parse(endpoint),
            headers: const <String, String>{
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(<String, String>{
              'username': username,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      return AllStarWtAuthResult(
          success: false, token: '', message: 'Network error: $e');
    }

    String token = '';
    String message = '';
    bool authed = false;
    try {
      final Object? body = jsonDecode(resp.body);
      if (body is Map) {
        token = (body['token'] ?? '').toString();
        message = (body['msg'] ?? '').toString();
        final Object? auth = body['auth'];
        authed = auth == 1 || auth == true || auth == '1';
      }
    } catch (_) {
      // Fall through to status-code handling with an empty token.
    }

    final bool success =
        resp.statusCode == 200 && authed && token.isNotEmpty;
    if (!success && message.isEmpty) {
      message = 'HTTP ${resp.statusCode}';
    }
    return AllStarWtAuthResult(
        success: success, token: token, message: message);
  }

  /// Releases the underlying HTTP client if this service created it.
  void dispose() {
    if (_ownsClient) _client.close();
  }
}
