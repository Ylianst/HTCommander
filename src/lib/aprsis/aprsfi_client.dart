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
// aprsfi_client.dart - Minimal client for the aprs.fi HTTP API.
//
// Fetches the most recent APRS messages addressed to a station so the app can
// backfill messages it missed while it was not connected to APRS-IS. See
// https://aprs.fi/page/api for the API description.
//

import 'dart:convert';

import 'package:http/http.dart' as http;

/// A single APRS message returned by the aprs.fi `what=msg` query.
class AprsFiMessage {
  /// aprs.fi's own stable identifier for the message (used for de-duplication).
  final String messageId;

  /// When aprs.fi recorded the message.
  final DateTime time;

  /// Callsign (with SSID) that sent the message.
  final String srcCall;

  /// Callsign (with SSID) the message was addressed to.
  final String dst;

  /// The message text.
  final String message;

  const AprsFiMessage({
    required this.messageId,
    required this.time,
    required this.srcCall,
    required this.dst,
    required this.message,
  });
}

/// Outcome of an aprs.fi query. On success [ok] is true and [messages] holds
/// the returned entries; on failure [error] describes the problem.
class AprsFiResult {
  final bool ok;
  final String? error;
  final List<AprsFiMessage> messages;

  const AprsFiResult({
    required this.ok,
    this.error,
    this.messages = const [],
  });

  factory AprsFiResult.failure(String error) =>
      AprsFiResult(ok: false, error: error);
}

/// Pure client for the aprs.fi API. Stateless: a single static [fetchMessages]
/// call performs one HTTP request and decodes the JSON response.
class AprsFiClient {
  AprsFiClient._();

  /// Queries aprs.fi for the most recent messages addressed to [dstCallsign].
  ///
  /// [apiKey] is the user's personal aprs.fi API key. A descriptive
  /// [userAgent] is required by the aprs.fi API. An optional [client] can be
  /// supplied for testing; otherwise a short-lived one is created and closed.
  static Future<AprsFiResult> fetchMessages({
    required String apiKey,
    required String dstCallsign,
    String userAgent = 'HTCommander',
    http.Client? client,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final key = apiKey.trim();
    final dst = dstCallsign.trim();
    if (key.isEmpty) return AprsFiResult.failure('Missing API key');
    if (dst.isEmpty) return AprsFiResult.failure('Missing destination callsign');

    final uri = Uri.https('api.aprs.fi', '/api/get', {
      'what': 'msg',
      'dst': dst,
      'apikey': key,
      'format': 'json',
    });

    final ownsClient = client == null;
    final http.Client httpClient = client ?? http.Client();
    try {
      final response = await httpClient
          .get(uri, headers: {'User-Agent': userAgent}).timeout(timeout);
      if (response.statusCode != 200) {
        return AprsFiResult.failure('HTTP ${response.statusCode}');
      }
      return _parseResponse(response.body);
    } catch (e) {
      return AprsFiResult.failure(e.toString());
    } finally {
      if (ownsClient) httpClient.close();
    }
  }

  /// Parses the aprs.fi JSON body into an [AprsFiResult].
  static AprsFiResult _parseResponse(String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return AprsFiResult.failure('Invalid response');
    }
    if (decoded is! Map) return AprsFiResult.failure('Invalid response');

    final result = decoded['result']?.toString();
    if (result != 'ok') {
      // aprs.fi reports errors in the "description" field.
      final desc = decoded['description']?.toString();
      return AprsFiResult.failure(
        desc != null && desc.isNotEmpty ? desc : 'aprs.fi request failed',
      );
    }

    final entries = decoded['entries'];
    final messages = <AprsFiMessage>[];
    if (entries is List) {
      for (final entry in entries) {
        if (entry is! Map) continue;
        final message = entry['message']?.toString() ?? '';
        if (message.isEmpty) continue;
        final seconds = int.tryParse(entry['time']?.toString() ?? '') ?? 0;
        messages.add(AprsFiMessage(
          messageId: entry['messageid']?.toString() ?? '',
          time: seconds > 0
              ? DateTime.fromMillisecondsSinceEpoch(seconds * 1000)
              : DateTime.now(),
          srcCall: (entry['srccall']?.toString() ?? '').toUpperCase(),
          dst: (entry['dst']?.toString() ?? '').toUpperCase(),
          message: message,
        ));
      }
    }
    return AprsFiResult(ok: true, messages: _dedupeKeepOldest(messages));
  }

  /// Collapses retransmitted duplicates. APRS senders repeat a message until it
  /// is acked, so aprs.fi can return several copies with the same source,
  /// destination and text but different timestamps. Keeps only the oldest copy
  /// of each `(srcCall, dst, message)` group, sorted newest-first.
  static List<AprsFiMessage> _dedupeKeepOldest(List<AprsFiMessage> messages) {
    final oldest = <String, AprsFiMessage>{};
    for (final m in messages) {
      final key = '${m.srcCall}\u0000${m.dst}\u0000${m.message}';
      final existing = oldest[key];
      if (existing == null || m.time.isBefore(existing.time)) {
        oldest[key] = m;
      }
    }
    final result = oldest.values.toList()
      ..sort((a, b) => b.time.compareTo(a.time));
    return result;
  }
}
