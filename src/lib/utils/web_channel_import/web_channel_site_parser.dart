/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// Pluggable site parsers for the "drop a web page URL onto a channel" feature.
///
/// Each supported web site (repeater "details" pages, and any future sources)
/// implements [WebChannelSiteParser]. The set of known parsers is exposed
/// through [kWebChannelSiteParsers] and consumed by `WebChannelImport`, which
/// fetches the page and hands the HTML to the first parser that claims the URL.
///
/// This layer is intentionally isolated from the UI: web pages change often, so
/// scraping/parsing lives here and can be edited without touching the radio or
/// dialog code.
library;

import '../../radio/radio_models.dart';
import 'repeaters_details_parser.dart';

/// A parser that knows how to extract a single radio channel from a specific
/// web site's page markup.
abstract class WebChannelSiteParser {
  const WebChannelSiteParser();

  /// A short, human-readable name for the site. Used for
  /// diagnostics and messages.
  String get siteName;

  /// Returns true when this parser recognises [url] and can attempt to parse a
  /// page fetched from it.
  bool canHandle(Uri url);

  /// Parses [html] (the raw page body fetched from [url]) into a channel.
  ///
  /// Returns null when the page could not be understood (e.g. required fields
  /// such as a frequency are missing). Implementations must not throw for
  /// malformed input; return null instead.
  RadioChannelInfo? parse(String html, Uri url);
}

/// The registry of known site parsers, tried in order.
const List<WebChannelSiteParser> kWebChannelSiteParsers = <WebChannelSiteParser>[
  RepeatersDetailsParser(),
];
