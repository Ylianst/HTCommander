/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// Entry point for importing a radio channel from a dropped web page URL.
///
/// [WebChannelImport.fetchFromUrl] downloads the page and hands it to the first
/// registered [WebChannelSiteParser] that recognises the URL. The whole
/// fetch/parse layer is isolated here so the UI only deals with a
/// [WebChannelImportResult].
library;

import 'package:http/http.dart' as http;

import '../../radio/radio_models.dart';
import 'web_channel_site_parser.dart';

/// Why a web-channel import did not produce a channel (or that it succeeded).
enum WebChannelImportStatus {
  ok,

  /// No registered parser recognises the URL's site.
  unsupportedSite,

  /// The page could not be downloaded (network error, non-200 response, ...).
  fetchFailed,

  /// The page was downloaded but the parser could not extract a channel.
  parseFailed,
}

/// Outcome of a web-channel import attempt.
class WebChannelImportResult {
  final WebChannelImportStatus status;
  final RadioChannelInfo? channel;

  /// Name of the site the URL matched, when known (for messages).
  final String? siteName;

  const WebChannelImportResult(this.status, {this.channel, this.siteName});

  bool get isSuccess =>
      status == WebChannelImportStatus.ok && channel != null;
}

class WebChannelImport {
  WebChannelImport._();

  /// Sent with the GET request. Some sites reject requests without a
  /// browser-like agent.
  static const String _userAgent =
      'Mozilla/5.0 (compatible; HTCommander/1.0; +https://github.com/)';

  static const Duration _timeout = Duration(seconds: 20);

  /// Returns true when [url] is a well-formed http(s) URL handled by one of the
  /// registered site parsers.
  static bool isSupportedUrl(String url) => _parserFor(url) != null;

  /// Downloads [url] and parses it into a channel.
  ///
  /// Never throws; failures are reported through [WebChannelImportResult.status].
  static Future<WebChannelImportResult> fetchFromUrl(String url) async {
    final parser = _parserFor(url);
    if (parser == null) {
      return const WebChannelImportResult(
        WebChannelImportStatus.unsupportedSite,
      );
    }

    final uri = Uri.parse(url.trim());
    String body;
    try {
      final response = await http
          .get(uri, headers: const {'User-Agent': _userAgent})
          .timeout(_timeout);
      if (response.statusCode != 200 || response.body.isEmpty) {
        return WebChannelImportResult(
          WebChannelImportStatus.fetchFailed,
          siteName: parser.siteName,
        );
      }
      body = response.body;
    } catch (_) {
      return WebChannelImportResult(
        WebChannelImportStatus.fetchFailed,
        siteName: parser.siteName,
      );
    }

    RadioChannelInfo? channel;
    try {
      channel = parser.parse(body, uri);
    } catch (_) {
      channel = null;
    }

    if (channel == null) {
      return WebChannelImportResult(
        WebChannelImportStatus.parseFailed,
        siteName: parser.siteName,
      );
    }

    return WebChannelImportResult(
      WebChannelImportStatus.ok,
      channel: channel,
      siteName: parser.siteName,
    );
  }

  /// Returns the first parser that handles [url], or null.
  static WebChannelSiteParser? _parserFor(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    for (final parser in kWebChannelSiteParsers) {
      if (parser.canHandle(uri)) return parser;
    }
    return null;
  }
}
