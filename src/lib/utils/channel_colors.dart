import 'package:flutter/material.dart';

/// Color palette for "channel" chips and tiles — the draggable yellow/gold
/// blocks shown in the radio panel, the import-channels dialog, and the
/// channel-share chips in the Comms/APRS chat.
///
/// The same palette is used in all three places so a channel looks consistent
/// wherever it appears. Light and dark variants are provided so the styling
/// adapts to the active theme (the classic DarkKhaki/PaleGoldenrod look in
/// light mode, a darker gold/olive set with light text in dark mode).
@immutable
class ChannelPalette {
  /// Background of a normal (unselected) channel.
  final Color base;

  /// Background of a selected / highlighted channel and of the shared "yellow
  /// block" chip.
  final Color selected;

  /// Background of the secondary (VFO B) channel in the radio panel.
  final Color channelB;

  /// Background of a staged / pending channel assignment in the import dialog.
  final Color pending;

  /// Primary text and icon color drawn on a channel background.
  final Color onChannel;

  /// Secondary text color on a channel (frequency, slot number).
  final Color onChannelSecondary;

  /// Border color of a normal channel tile.
  final Color border;

  /// Border color of a highlighted / selected channel tile.
  final Color borderHighlight;

  const ChannelPalette({
    required this.base,
    required this.selected,
    required this.channelB,
    required this.pending,
    required this.onChannel,
    required this.onChannelSecondary,
    required this.border,
    required this.borderHighlight,
  });

  /// Classic light-theme palette (DarkKhaki / PaleGoldenrod with dark text).
  static const ChannelPalette light = ChannelPalette(
    base: Color(0xFFBDB76B), // DarkKhaki
    selected: Color(0xFFEEE8AA), // PaleGoldenrod
    channelB: Color(0xFFF0E68C), // Khaki
    pending: Color(0xFFB5E0B5), // Soft green
    onChannel: Color(0xDD000000), // black87
    onChannelSecondary: Color(0xFF5A5A4A),
    border: Color(0xFF757575),
    borderHighlight: Color(0xDD000000),
  );

  /// Dark-theme palette (darker gold/olive with light text).
  static const ChannelPalette dark = ChannelPalette(
    base: Color(0xFF6E6733), // dark gold
    selected: Color(0xFF9C9142), // brighter gold
    channelB: Color(0xFF847A38), // mid gold
    pending: Color(0xFF46683F), // dark green
    onChannel: Color(0xFFF3EFD6), // pale text
    onChannelSecondary: Color(0xFFCDC7A2),
    border: Color(0xFF9A8F45),
    borderHighlight: Color(0xFFE4DCA0),
  );

  /// Resolves the palette for [context]'s active brightness.
  static ChannelPalette of(BuildContext context) =>
      forBrightness(Theme.of(context).brightness);

  /// Resolves the palette for an explicit [brightness].
  static ChannelPalette forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}
