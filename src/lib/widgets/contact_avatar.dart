import 'dart:convert';

import 'package:flutter/material.dart';

/// Shared contact avatar rendering used by the Contacts dialog and the APRS
/// messaging conversation list.
///
/// Display precedence: a custom base64 image, then a chosen/automatic logo
/// icon, then the last three letters of the callsign on a coloured circle.

/// Built-in avatar logos, keyed by a stable name persisted in [StationInfo].
/// The order here is the order shown in the logo picker.
const Map<String, IconData> kContactLogos = {
  // Service icons (mirror the automatic APRS service avatars).
  'mail': Icons.mail,
  'weather': Icons.wb_cloudy,
  'sms': Icons.sms,
  'email': Icons.alternate_email,
  'group': Icons.groups,
  'announce': Icons.campaign,
  'search': Icons.person_search,
  'repeat': Icons.repeat,
  // Generic icons.
  'person': Icons.person,
  'radio': Icons.radio,
  'star': Icons.star,
  'home': Icons.home,
  'satellite': Icons.satellite_alt,
  'location': Icons.location_on,
  'work': Icons.work,
  'favorite': Icons.favorite,
  'flag': Icons.flag,
  'shield': Icons.shield,
};

/// Well-known APRS service / bot callsigns (SSID-stripped) mapped to a logo
/// name, used to pick an automatic avatar when the contact has no custom one.
const Map<String, String> _botLogos = {
  'WLNK': 'mail',
  'WXBOT': 'weather',
  'WXSVR': 'weather',
  'SMSGTE': 'sms',
  'SMS': 'sms',
  'EMAIL': 'email',
  'ANSRVR': 'group',
  'CQSRVR': 'announce',
  'WHO-IS': 'search',
  'REPEAT': 'repeat',
};

/// Strips a trailing "-NN" SSID from a callsign.
String contactCallsignBase(String callsign) {
  final dash = callsign.indexOf('-');
  return dash >= 0 ? callsign.substring(0, dash) : callsign;
}

/// Up to three characters for the placeholder avatar. Email addresses show the
/// first three letters (e.g. "john@x.com" -> "JOH"); callsigns show the last
/// three letters (e.g. "KK7VZT" -> "VZT"); phone numbers (no letters) show the
/// first three digits so SMS contacts render consistently everywhere.
String contactInitials(String callsign) {
  if (callsign.contains('@')) {
    final letters =
        callsign.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
    if (letters.isEmpty) return '?';
    return letters.length <= 3 ? letters : letters.substring(0, 3);
  }
  final base = contactCallsignBase(callsign).toUpperCase();
  final letters = base.replaceAll(RegExp(r'[^A-Z]'), '');
  if (letters.isEmpty) {
    final digits = callsign.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '?';
    return digits.length <= 3 ? digits : digits.substring(0, 3);
  }
  return letters.length <= 3
      ? letters
      : letters.substring(letters.length - 3);
}

/// Deterministic avatar colour derived from the callsign.
Color contactColorForCallsign(String callsign) {
  var hash = 0;
  for (final code in callsign.toUpperCase().codeUnits) {
    hash = (hash * 31 + code) & 0x7fffffff;
  }
  return HSLColor.fromAHSL(1.0, (hash % 360).toDouble(), 0.55, 0.45).toColor();
}

/// The automatic logo name for a known APRS service callsign, or null.
String? autoContactLogo(String callsign) {
  final upper = callsign.toUpperCase();
  return _botLogos[upper] ?? _botLogos[contactCallsignBase(upper)];
}

/// The effective icon for a contact: an explicitly chosen [avatarIcon] logo,
/// otherwise an automatic service logo derived from the callsign, or null.
IconData? contactLogoIcon(String callsign, String? avatarIcon) {
  final name = (avatarIcon != null && kContactLogos.containsKey(avatarIcon))
      ? avatarIcon
      : autoContactLogo(callsign);
  return name == null ? null : kContactLogos[name];
}

/// A round contact avatar. Renders [avatarImage] (base64 PNG) if present, else a
/// chosen/automatic logo icon, else the callsign initials.
class ContactAvatar extends StatelessWidget {
  final String callsign;
  final String? avatarIcon;
  final String? avatarImage;
  final double radius;

  const ContactAvatar({
    super.key,
    required this.callsign,
    this.avatarIcon,
    this.avatarImage,
    this.radius = 22,
  });

  @override
  Widget build(BuildContext context) {
    final image = avatarImage;
    if (image != null && image.isNotEmpty) {
      try {
        final bytes = base64Decode(image);
        return CircleAvatar(
          radius: radius,
          backgroundImage: MemoryImage(bytes),
        );
      } catch (_) {
        // Fall through to icon/initials on a malformed image.
      }
    }
    final icon = contactLogoIcon(callsign, avatarIcon);
    return CircleAvatar(
      radius: radius,
      backgroundColor: contactColorForCallsign(callsign),
      child: icon != null
          ? Icon(icon, color: Colors.white, size: radius)
          : Text(
              contactInitials(callsign),
              style: TextStyle(
                color: Colors.white,
                fontSize: radius * 0.6,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
  }
}
