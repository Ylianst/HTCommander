/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// Parser for repeater "repeaters/details.php" pages.
///
/// Any URL whose path contains `repeaters/details.php` is handled, regardless
/// of host, so mirror/clone sites with the same page format work too.
///
/// Extracts a single channel from the page, which lays the technical data out
/// as a label/value table, e.g.:
///
///   DOWNLINK        145.11000   (repeater output  -> radio RX frequency)
///   UPLINK          144.51000   (repeater input   -> radio TX frequency)
///   OFFSET          -0.600
///   UPLINK TONE     136.5       (tone the radio must transmit -> TX sub-audio)
///   DOWNLINK TONE   91.5        (tone the repeater transmits  -> RX sub-audio)
///   Bandwidth       25.0 kHz    (>= ~20 kHz -> wide, otherwise narrow)
///
/// Because scraped markup changes often, parsing is deliberately tolerant: the
/// HTML is reduced to plain text first and then label-anchored regular
/// expressions pull each value out. Anything that cannot be understood yields
/// null rather than throwing.
library;

import '../../radio/radio_models.dart';
import 'web_channel_site_parser.dart';

class RepeatersDetailsParser extends WebChannelSiteParser {
  const RepeatersDetailsParser();

  @override
  String get siteName => 'Repeater details page';

  @override
  bool canHandle(Uri url) {
    // Key off the page path so any site using the same "repeaters/details.php"
    // format is supported, not just one specific host.
    return url.path.toLowerCase().contains('repeaters/details.php');
  }

  @override
  RadioChannelInfo? parse(String html, Uri url) {
    // The page title still carries the raw HTML; grab the callsign from it
    // before tags are stripped.
    final title = _extractTitle(html);
    final text = _htmlToText(html);

    // --- Frequencies -------------------------------------------------------
    // "DOWNLINK" and "UPLINK" labels are followed by help text and then the
    // MHz value; capture the first frequency-looking number after each label.
    // The negative lookahead keeps "UPLINK"/"DOWNLINK" from matching the
    // "... TONE" rows.
    final downlinkMHz = _firstNumberAfter(
      text,
      RegExp(r'DOWNLINK(?!\s*TONE).{0,200}?(\d{2,3}\.\d{3,5})',
          caseSensitive: false, dotAll: true),
    );
    final uplinkMHz = _firstNumberAfter(
      text,
      RegExp(r'UPLINK(?!\s*TONE).{0,200}?(\d{2,3}\.\d{3,5})',
          caseSensitive: false, dotAll: true),
    );
    final offsetMHz = _firstNumberAfter(
      text,
      RegExp(r'OFFSET.{0,80}?([-+]?\d+\.\d+)',
          caseSensitive: false, dotAll: true),
    );

    int rxFreq = downlinkMHz != null ? (downlinkMHz * 1000000).round() : 0;
    int txFreq = uplinkMHz != null ? (uplinkMHz * 1000000).round() : 0;

    // Derive the missing side from the offset when only one is present.
    if (txFreq == 0 && rxFreq != 0 && offsetMHz != null) {
      txFreq = rxFreq + (offsetMHz * 1000000).round();
    }
    if (rxFreq == 0 && txFreq != 0 && offsetMHz != null) {
      rxFreq = txFreq - (offsetMHz * 1000000).round();
    }
    if (rxFreq == 0) rxFreq = txFreq;
    if (txFreq == 0) txFreq = rxFreq;
    if (rxFreq == 0 && txFreq == 0) return null; // Nothing usable.

    // --- Tones -------------------------------------------------------------
    // Uplink tone -> what the radio must transmit -> TX sub-audio.
    // Downlink tone -> what the repeater transmits -> RX sub-audio.
    final uplinkTone = _firstNumberAfter(
      text,
      RegExp(r'UPLINK\s*TONE.{0,120}?(\d{2,3}\.\d)',
          caseSensitive: false, dotAll: true),
    );
    final downlinkTone = _firstNumberAfter(
      text,
      RegExp(r'DOWNLINK\s*TONE.{0,120}?(\d{2,3}\.\d)',
          caseSensitive: false, dotAll: true),
    );
    final txSubAudio = uplinkTone != null ? (uplinkTone * 100).round() : 0;
    final rxSubAudio = downlinkTone != null ? (downlinkTone * 100).round() : 0;

    // --- Bandwidth ---------------------------------------------------------
    // Repeater details reports "25.0 kHz" (wide) or "12.5 kHz" (narrow).
    final bandwidthKHz = _firstNumberAfter(
      text,
      RegExp(r'(\d{1,2}(?:\.\d)?)\s*kHz', caseSensitive: false),
    );
    final bandwidth = (bandwidthKHz != null && bandwidthKHz <= 15)
        ? RadioBandwidthType.narrow
        : RadioBandwidthType.wide;

    // --- Name / callsign ---------------------------------------------------
    final name = _clampName(_extractCallsign(title) ?? _extractCallsign(text) ?? '');

    // Only FM analog is represented here; Repeater detail pages that are
    // pure digital (DMR, etc.) are uncommon for this workflow and fall back to
    // FM, which the user can adjust in the confirmation dialog.
    const mod = RadioModulationType.fm;

    return RadioChannelInfo(
      channelId: 0,
      name: name,
      rxFreq: rxFreq,
      txFreq: txFreq,
      rxMod: mod,
      txMod: mod,
      rxSubAudio: rxSubAudio,
      txSubAudio: txSubAudio,
      bandwidth: bandwidth,
      txAtMaxPower: true,
      txAtMedPower: false,
    );
  }

  // --- Helpers -------------------------------------------------------------

  /// Returns the first capture group of [pattern] in [text] parsed as a double,
  /// or null when there is no match or it does not parse.
  static double? _firstNumberAfter(String text, RegExp pattern) {
    final match = pattern.firstMatch(text);
    if (match == null) return null;
    return double.tryParse(match.group(1)!.trim());
  }

  /// Extracts the contents of the first `<title>` element, or '' when absent.
  static String _extractTitle(String html) {
    final match = RegExp(r'<title[^>]*>(.*?)</title>',
            caseSensitive: false, dotAll: true)
        .firstMatch(html);
    return match != null ? _decodeEntities(match.group(1)!.trim()) : '';
  }

  /// Finds the first amateur-radio callsign-looking token (e.g. `AB7BS`).
  static String? _extractCallsign(String value) {
    final match = RegExp(r'\b([A-Z]{1,2}[0-9][A-Z]{1,4})\b').firstMatch(value);
    return match?.group(1);
  }

  /// Reduces HTML to readable plain text: drops script/style blocks, converts
  /// tags to whitespace, decodes a handful of common entities and collapses
  /// runs of whitespace.
  static String _htmlToText(String html) {
    var s = html;
    s = s.replaceAll(
        RegExp(r'<script[^>]*>.*?</script>',
            caseSensitive: false, dotAll: true),
        ' ');
    s = s.replaceAll(
        RegExp(r'<style[^>]*>.*?</style>', caseSensitive: false, dotAll: true),
        ' ');
    s = s.replaceAll(RegExp(r'<[^>]+>'), ' ');
    s = _decodeEntities(s);
    s = s.replaceAll(RegExp(r'[ \t\f\v]+'), ' ');
    return s;
  }

  /// Decodes the small set of HTML entities that appear in the fields we read.
  static String _decodeEntities(String s) {
    return s
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ');
  }

  /// Channel names are limited to 10 characters on the radio.
  static String _clampName(String name) {
    final trimmed = name.trim();
    return trimmed.length > 10 ? trimmed.substring(0, 10) : trimmed;
  }
}
