/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart';

/// A single APRS symbol definition: the two characters that appear in a
/// position report (a table identifier plus a symbol code), a human readable
/// name, and an optional Flutter [IconData] we can render for it.
///
/// The symbol tables are the standard APRS set documented in
/// `reference/direwolf/data/symbolsX.txt`. Not every symbol has a good
/// Material icon equivalent; those entries have a `null` [icon] and callers
/// should fall back to a generic marker (e.g. `Icons.location_pin`).
class AprsSymbol {
  /// Table identifier character: `/` (primary) or `\` (alternate).
  final String table;

  /// Symbol code character (0x21..0x7E).
  final String code;

  /// Human readable name of the symbol.
  final String name;

  /// Best-effort Material icon for this symbol, or `null` when no good
  /// equivalent exists.
  final IconData? icon;

  /// When set, the symbol is rendered as a rounded square containing this
  /// short text (used for the numbered primary symbols `/0`..`/9`) instead of
  /// a Material [icon].
  final String? badgeText;

  /// When set, the symbol is rendered by this custom builder (used for symbols
  /// with no good Material equivalent, e.g. the straight-wing small aircraft).
  /// Takes precedence over [icon] and [badgeText].
  final Widget Function(double size, Color color)? builder;

  const AprsSymbol(
    this.table,
    this.code,
    this.name, [
    this.icon,
    this.badgeText,
    this.builder,
  ]);

  /// The two-character identifier as it appears in a report, e.g. `/>`.
  String get id => '$table$code';

  /// Whether we can render something meaningful for this symbol.
  bool get hasVisual => icon != null || badgeText != null || builder != null;
}

/// Looks up a symbol by its table identifier and symbol code characters.
/// Returns `null` when the pair is not in the standard table.
///
/// The primary table is only used when [table] is `/`. Any other identifier
/// (the alternate `\` table, or an overlay digit/letter) resolves to the
/// alternate table, since overlay symbols are drawn on top of alternate-table
/// base symbols.
AprsSymbol? aprsSymbolFor(String table, String code) {
  final list = table == '/' ? kAprsPrimarySymbols : kAprsAlternateSymbols;
  for (final s in list) {
    if (s.code == code) return s;
  }
  return null;
}

/// The overlay characters that may replace the table identifier (`0`-`9` and
/// `A`-`Z`). When one of these is used as the table character, it is drawn on
/// top of the alternate-table base symbol.
const List<String> kAprsOverlayChars = [
  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', //
  'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', //
  'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
];

/// The alternate-table symbol codes that support an overlay character drawn on
/// top. This is the subset we currently render as "combo" symbols.
const Set<String> kAprsOverlayableCodes = {
  '#', '&', '0', 'A', 'W', '^', '_', 'a', 'c', 'n', 's', 'u', 'v', 'z',
};

/// The alternate-table base symbols that support an overlay character.
List<AprsSymbol> get aprsOverlayableSymbols => [
      for (final s in kAprsAlternateSymbols)
        if (kAprsOverlayableCodes.contains(s.code)) s,
    ];

/// True when [table] is an overlay identifier (a digit `0`-`9` or capital
/// letter `A`-`Z`) rather than the primary `/` or alternate `\` table.
bool aprsIsOverlay(String table) =>
    table.length == 1 &&
    ((table.codeUnitAt(0) >= 0x30 && table.codeUnitAt(0) <= 0x39) ||
        (table.codeUnitAt(0) >= 0x41 && table.codeUnitAt(0) <= 0x5A));

/// Convenience: the Material icon for a symbol pair, or a generic fallback.
IconData aprsIconFor(String table, String code,
    {IconData fallback = Icons.location_pin}) {
  return aprsSymbolFor(table, code)?.icon ?? fallback;
}

/// Builds a renderable widget for a symbol: either its Material icon or, for
/// the numbered primary symbols, a rounded square containing the digit. Falls
/// back to [Icons.location_pin] when the symbol has no visual.
Widget aprsSymbolWidget(
  AprsSymbol? symbol, {
  double size = 22,
  required Color color,
}) {
  if (symbol?.builder != null) {
    return symbol!.builder!(size, color);
  }
  if (symbol?.badgeText != null) {
    return _AprsBadge(text: symbol!.badgeText!, size: size, color: color);
  }
  return Icon(symbol?.icon ?? Icons.location_pin, size: size, color: color);
}

/// Builds a renderable widget for a raw table+code pair. When [table] is an
/// overlay identifier, the base alternate-table symbol is drawn with the
/// overlay character on top; otherwise this is equivalent to
/// [aprsSymbolWidget] for the looked-up symbol.
///
/// [haloColor] sets the outline colour drawn behind the overlay character so it
/// can be blended with a coloured background (e.g. a chat bubble). When null a
/// contrasting colour is derived from [color].
Widget aprsSymbolWidgetFor(
  String table,
  String code, {
  double size = 22,
  required Color color,
  Color? haloColor,
}) {
  final base = aprsSymbolFor(table, code);
  final baseWidget = aprsSymbolWidget(base, size: size, color: color);
  if (!aprsIsOverlay(table)) return baseWidget;
  return Stack(
    alignment: Alignment.center,
    children: [
      baseWidget,
      _AprsOverlayChar(
        text: table,
        size: size,
        color: color,
        haloColor: haloColor,
      ),
    ],
  );
}

/// A human readable name for a raw table+code pair, appending the overlay
/// character in brackets for overlay symbols.
String aprsSymbolNameFor(String table, String code) {
  final name = aprsSymbolFor(table, code)?.name ?? 'Unknown symbol';
  if (aprsIsOverlay(table)) return '$name [overlay $table]';
  return name;
}


/// A top-down light aircraft with straight wings, used to distinguish the
/// small aircraft symbol from the swept-wing [Icons.flight] used for large
/// aircraft (Material Icons has no straight-wing plane glyph).
Widget aprsSmallAircraftIcon(double size, Color color) {
  return SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _SmallAircraftPainter(color)),
  );
}

class _SmallAircraftPainter extends CustomPainter {
  final Color color;
  const _SmallAircraftPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    RRect bar(double left, double top, double right, double bottom, double r) {
      return RRect.fromRectAndRadius(
        Rect.fromLTRB(left, top, right, bottom),
        Radius.circular(r),
      );
    }

    // Fuselage (nose up, tail down).
    canvas.drawRRect(
      bar(cx - w * 0.07, h * 0.05, cx + w * 0.07, h * 0.95, w * 0.07),
      paint,
    );
    // Single straight wing across the fuselage.
    canvas.drawRRect(
      bar(w * 0.05, h * 0.40, w * 0.95, h * 0.53, h * 0.06),
      paint,
    );
    // Straight horizontal tailplane near the tail.
    canvas.drawRRect(
      bar(w * 0.30, h * 0.80, w * 0.70, h * 0.90, h * 0.05),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _SmallAircraftPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// A side-profile horse silhouette, used for the equestrian symbol (Material
/// Icons has no horse glyph).
Widget aprsHorseIcon(double size, Color color) {
  return SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _HorsePainter(color)),
  );
}

class _HorsePainter extends CustomPainter {
  final Color color;
  const _HorsePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      // Nose / muzzle (facing left).
      ..moveTo(w * 0.04, h * 0.42)
      // Up the face to the forehead.
      ..quadraticBezierTo(w * 0.06, h * 0.34, w * 0.13, h * 0.28)
      // Ear.
      ..lineTo(w * 0.15, h * 0.15)
      ..lineTo(w * 0.21, h * 0.28)
      // Crest of the neck down to the withers.
      ..quadraticBezierTo(w * 0.30, h * 0.21, w * 0.42, h * 0.30)
      // Back.
      ..lineTo(w * 0.68, h * 0.30)
      // Croup up to the tail base.
      ..quadraticBezierTo(w * 0.76, h * 0.27, w * 0.80, h * 0.32)
      // Tail hanging down and back to the hindquarter.
      ..lineTo(w * 0.95, h * 0.35)
      ..quadraticBezierTo(w * 0.86, h * 0.50, w * 0.93, h * 0.72)
      ..quadraticBezierTo(w * 0.82, h * 0.54, w * 0.80, h * 0.46)
      // Hind leg.
      ..lineTo(w * 0.76, h * 0.46)
      ..lineTo(w * 0.76, h * 0.92)
      ..lineTo(w * 0.69, h * 0.92)
      ..lineTo(w * 0.68, h * 0.58)
      // Belly.
      ..quadraticBezierTo(w * 0.55, h * 0.64, w * 0.42, h * 0.60)
      // Front leg.
      ..lineTo(w * 0.40, h * 0.60)
      ..lineTo(w * 0.40, h * 0.92)
      ..lineTo(w * 0.33, h * 0.92)
      ..lineTo(w * 0.32, h * 0.56)
      // Chest.
      ..quadraticBezierTo(w * 0.20, h * 0.54, w * 0.17, h * 0.46)
      // Throat back to the nose.
      ..quadraticBezierTo(w * 0.11, h * 0.46, w * 0.04, h * 0.42)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HorsePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// A lighthouse with a tapered tower, lantern room, roof and light beams,
/// used for the lighthouse symbol (Material Icons has no lighthouse glyph).
Widget aprsLighthouseIcon(double size, Color color) {
  return SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _LighthousePainter(color)),
  );
}

class _LighthousePainter extends CustomPainter {
  final Color color;
  const _LighthousePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Light beams radiating from the lantern.
    final beams = Path()
      ..moveTo(w * 0.42, h * 0.22)
      ..lineTo(w * 0.08, h * 0.14)
      ..lineTo(w * 0.08, h * 0.30)
      ..close()
      ..moveTo(w * 0.58, h * 0.22)
      ..lineTo(w * 0.92, h * 0.14)
      ..lineTo(w * 0.92, h * 0.30)
      ..close();
    canvas.drawPath(
      beams,
      Paint()
        ..color = color.withValues(alpha: 0.35)
        ..style = PaintingStyle.fill,
    );

    // Roof.
    final roof = Path()
      ..moveTo(w * 0.50, h * 0.05)
      ..lineTo(w * 0.37, h * 0.17)
      ..lineTo(w * 0.63, h * 0.17)
      ..close();
    canvas.drawPath(roof, paint);

    RRect rr(double l, double t, double r, double b, double radius) =>
        RRect.fromRectAndRadius(
          Rect.fromLTRB(l * w, t * h, r * w, b * h),
          Radius.circular(radius),
        );

    // Lantern room (light housing).
    canvas.drawRRect(rr(0.42, 0.17, 0.58, 0.27, 1), paint);
    // Gallery platform below the lantern.
    canvas.drawRRect(rr(0.35, 0.27, 0.65, 0.31, 1), paint);

    // Tapered tower.
    final tower = Path()
      ..moveTo(w * 0.41, h * 0.31)
      ..lineTo(w * 0.59, h * 0.31)
      ..lineTo(w * 0.67, h * 0.84)
      ..lineTo(w * 0.33, h * 0.84)
      ..close();
    canvas.drawPath(tower, paint);

    // Base.
    canvas.drawRRect(rr(0.27, 0.84, 0.73, 0.93, 2), paint);
  }

  @override
  bool shouldRepaint(covariant _LighthousePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// A rounded square containing short text, used for numbered APRS symbols.
class _AprsBadge extends StatelessWidget {
  final String text;
  final double size;
  final Color color;

  const _AprsBadge({
    required this.text,
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1.6),
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: size * 0.62,
          fontWeight: FontWeight.w700,
          height: 1.0,
        ),
      ),
    );
  }
}

/// The overlay character drawn on top of a base symbol for combo symbols.
/// A contrasting halo (via text shadows) keeps it readable over any icon.
class _AprsOverlayChar extends StatelessWidget {
  final String text;
  final double size;
  final Color color;
  final Color? haloColor;

  const _AprsOverlayChar({
    required this.text,
    required this.size,
    required this.color,
    this.haloColor,
  });

  @override
  Widget build(BuildContext context) {
    final halo = haloColor ??
        (color.computeLuminance() > 0.5 ? Colors.black : Colors.white);
    final o = size * 0.055;
    return Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: size * 0.5,
        fontWeight: FontWeight.w800,
        height: 1.0,
        shadows: [
          Shadow(color: halo, offset: Offset(-o, -o)),
          Shadow(color: halo, offset: Offset(o, -o)),
          Shadow(color: halo, offset: Offset(o, o)),
          Shadow(color: halo, offset: Offset(-o, o)),
        ],
      ),
    );
  }
}

/// Primary symbol table (`/` identifier) - mostly stations.
const List<AprsSymbol> kAprsPrimarySymbols = [
  AprsSymbol('/', '!', 'Police / Sheriff', Icons.local_police),
  AprsSymbol('/', '"', 'reserved', null),
  AprsSymbol('/', '#', 'Digipeater (white center)', Icons.settings_input_antenna),
  AprsSymbol('/', '\$', 'Phone', Icons.phone),
  AprsSymbol('/', '%', 'DX Cluster', Icons.hub),
  AprsSymbol('/', '&', 'HF Gateway', Icons.router),
  AprsSymbol('/', "'", 'Small Aircraft', null, null, aprsSmallAircraftIcon),
  AprsSymbol('/', '(', 'Mobile Satellite Station', Icons.satellite_alt),
  AprsSymbol('/', ')', 'Wheelchair (handicapped)', Icons.accessible),
  AprsSymbol('/', '*', 'SnowMobile', Icons.ac_unit),
  AprsSymbol('/', '+', 'Red Cross', Icons.local_hospital),
  AprsSymbol('/', ',', 'Boy Scouts', null),
  AprsSymbol('/', '-', 'House QTH (VHF)', Icons.house),
  AprsSymbol('/', '.', 'X', Icons.close),
  AprsSymbol('/', '/', 'Red Dot', Icons.circle),
  AprsSymbol('/', '0', 'Numbered circle 0', null, '0'),
  AprsSymbol('/', '1', 'Numbered circle 1', null, '1'),
  AprsSymbol('/', '2', 'Numbered circle 2', null, '2'),
  AprsSymbol('/', '3', 'Numbered circle 3', null, '3'),
  AprsSymbol('/', '4', 'Numbered circle 4', null, '4'),
  AprsSymbol('/', '5', 'Numbered circle 5', null, '5'),
  AprsSymbol('/', '6', 'Numbered circle 6', null, '6'),
  AprsSymbol('/', '7', 'Numbered circle 7', null, '7'),
  AprsSymbol('/', '8', 'Numbered circle 8', null, '8'),
  AprsSymbol('/', '9', 'Numbered circle 9', null, '9'),
  AprsSymbol('/', ':', 'Fire', Icons.local_fire_department),
  AprsSymbol('/', ';', 'Campground (Portable ops)', Icons.cabin),
  AprsSymbol('/', '<', 'Motorcycle', Icons.two_wheeler),
  AprsSymbol('/', '=', 'Railroad Engine', Icons.train),
  AprsSymbol('/', '>', 'Car', Icons.directions_car),
  AprsSymbol('/', '?', 'File Server', Icons.dns),
  AprsSymbol('/', '@', 'HC Future predict (dot)', null),
  AprsSymbol('/', 'A', 'Aid Station', Icons.medical_services),
  AprsSymbol('/', 'B', 'BBS or PBBS', Icons.forum),
  AprsSymbol('/', 'C', 'Canoe', Icons.kayaking),
  AprsSymbol('/', 'D', 'avail', null),
  AprsSymbol('/', 'E', 'Eyeball (Events)', Icons.visibility),
  AprsSymbol('/', 'F', 'Farm Vehicle (tractor)', Icons.agriculture),
  AprsSymbol('/', 'G', 'Grid Square (6 digit)', Icons.grid_on),
  AprsSymbol('/', 'H', 'Hotel', Icons.hotel),
  AprsSymbol('/', 'I', 'TcpIp on air network stn', Icons.lan),
  AprsSymbol('/', 'J', 'avail', null),
  AprsSymbol('/', 'K', 'School', Icons.school),
  AprsSymbol('/', 'L', 'PC user', Icons.computer),
  AprsSymbol('/', 'M', 'MacAPRS', Icons.laptop_mac),
  AprsSymbol('/', 'N', 'NTS Station', Icons.markunread_mailbox),
  AprsSymbol('/', 'O', 'Balloon', Icons.air),
  AprsSymbol('/', 'P', 'Police', Icons.local_police),
  AprsSymbol('/', 'Q', 'TBD', null),
  AprsSymbol('/', 'R', 'Recreational Vehicle', Icons.rv_hookup),
  AprsSymbol('/', 'S', 'Shuttle', Icons.rocket_launch),
  AprsSymbol('/', 'T', 'SSTV', Icons.tv),
  AprsSymbol('/', 'U', 'Bus', Icons.directions_bus),
  AprsSymbol('/', 'V', 'ATV (Amateur TV)', Icons.videocam),
  AprsSymbol('/', 'W', 'National WX Service Site', Icons.cloud),
  AprsSymbol('/', 'X', 'Helicopter', Icons.flight),
  AprsSymbol('/', 'Y', 'Yacht (sail)', Icons.sailing),
  AprsSymbol('/', 'Z', 'WinAPRS', Icons.desktop_windows),
  AprsSymbol('/', '[', 'Human / Person', Icons.directions_walk),
  AprsSymbol('/', r'\', 'Triangle (DF station)', Icons.change_history),
  AprsSymbol('/', ']', 'Mail / Post Office', Icons.local_post_office),
  AprsSymbol('/', '^', 'Large Aircraft', Icons.flight),
  AprsSymbol('/', '_', 'Weather Station', Icons.cloud),
  AprsSymbol('/', '`', 'Dish Antenna', Icons.satellite_alt),
  AprsSymbol('/', 'a', 'Ambulance', Icons.emergency),
  AprsSymbol('/', 'b', 'Bike', Icons.directions_bike),
  AprsSymbol('/', 'c', 'Incident Command Post', Icons.campaign),
  AprsSymbol('/', 'd', 'Fire dept', Icons.local_fire_department),
  AprsSymbol('/', 'e', 'Horse (equestrian)', null, null, aprsHorseIcon),
  AprsSymbol('/', 'f', 'Fire Truck', Icons.fire_truck),
  AprsSymbol('/', 'g', 'Glider', Icons.paragliding),
  AprsSymbol('/', 'h', 'Hospital', Icons.local_hospital),
  AprsSymbol('/', 'i', 'IOTA (islands on the air)', Icons.beach_access),
  AprsSymbol('/', 'j', 'Jeep', Icons.directions_car),
  AprsSymbol('/', 'k', 'Truck', Icons.local_shipping),
  AprsSymbol('/', 'l', 'Laptop', Icons.laptop),
  AprsSymbol('/', 'm', 'Mic-E Repeater', Icons.settings_input_antenna),
  AprsSymbol('/', 'n', 'Node (black bulls-eye)', Icons.hub),
  AprsSymbol('/', 'o', 'EOC', Icons.business),
  AprsSymbol('/', 'p', 'Rover (dog)', Icons.pets),
  AprsSymbol('/', 'q', 'Grid Square (above 128 m)', Icons.grid_on),
  AprsSymbol('/', 'r', 'Repeater', Icons.cell_tower),
  AprsSymbol('/', 's', 'Ship (power boat)', Icons.directions_boat),
  AprsSymbol('/', 't', 'Truck Stop', Icons.local_shipping),
  AprsSymbol('/', 'u', 'Truck (18 wheeler)', Icons.local_shipping),
  AprsSymbol('/', 'v', 'Van', Icons.airport_shuttle),
  AprsSymbol('/', 'w', 'Water station', Icons.water_drop),
  AprsSymbol('/', 'x', 'xAPRS (Unix)', Icons.terminal),
  AprsSymbol('/', 'y', 'Yagi @ QTH', Icons.settings_input_antenna),
  AprsSymbol('/', 'z', 'TBD', null),
  AprsSymbol('/', '{', 'reserved', null),
  AprsSymbol('/', '|', 'TNC Stream Switch', null),
  AprsSymbol('/', '}', 'reserved', null),
  AprsSymbol('/', '~', 'TNC Stream Switch', null),
];

/// Alternate symbol table (`\` identifier) - mostly objects.
const List<AprsSymbol> kAprsAlternateSymbols = [
  AprsSymbol(r'\', '!', 'Emergency', Icons.warning),
  AprsSymbol(r'\', '"', 'reserved', null),
  AprsSymbol(r'\', '#', 'Overlay Digi (green star)', Icons.star),
  AprsSymbol(r'\', '\$', 'Bank or ATM', Icons.local_atm),
  AprsSymbol(r'\', '%', 'Power Plant', Icons.factory),
  AprsSymbol(r'\', '&', 'IGate (I/R/T)', Icons.router),
  AprsSymbol(r'\', "'", 'Crash / Incident site', Icons.car_crash),
  AprsSymbol(r'\', '(', 'Cloudy', Icons.cloud),
  AprsSymbol(r'\', ')', 'Firenet MEO / MODIS', Icons.public),
  AprsSymbol(r'\', '*', 'Snow', Icons.ac_unit),
  AprsSymbol(r'\', '+', 'Church', Icons.church),
  AprsSymbol(r'\', ',', 'Girl Scouts', null),
  AprsSymbol(r'\', '-', 'House (HF / Op present)', Icons.house),
  AprsSymbol(r'\', '.', 'Ambiguous (big question mark)', Icons.help),
  AprsSymbol(r'\', '/', 'Waypoint Destination', Icons.place),
  AprsSymbol(r'\', '0', 'Circle (IRLP / Echolink / WIRES)', Icons.circle),
  AprsSymbol(r'\', '1', 'avail', null),
  AprsSymbol(r'\', '2', 'avail', null),
  AprsSymbol(r'\', '3', 'avail', null),
  AprsSymbol(r'\', '4', 'avail', null),
  AprsSymbol(r'\', '5', 'avail', null),
  AprsSymbol(r'\', '6', 'avail', null),
  AprsSymbol(r'\', '7', 'avail', null),
  AprsSymbol(r'\', '8', '802.11 or network node', Icons.wifi),
  AprsSymbol(r'\', '9', 'Gas Station', Icons.local_gas_station),
  AprsSymbol(r'\', ':', 'Hail', null),
  AprsSymbol(r'\', ';', 'Park / Picnic', Icons.park),
  AprsSymbol(r'\', '<', 'Advisory (one WX flag)', Icons.flag),
  AprsSymbol(r'\', '=', 'avail overlay group', null),
  AprsSymbol(r'\', '>', 'Overlayed Cars / Vehicles', Icons.directions_car),
  AprsSymbol(r'\', '?', 'Info Kiosk', Icons.info),
  AprsSymbol(r'\', '@', 'Hurricane / Trop-Storm', Icons.cyclone),
  AprsSymbol(r'\', 'A', 'Overlay Box (DTMF / RFID)', Icons.crop_square),
  AprsSymbol(r'\', 'B', 'avail', null),
  AprsSymbol(r'\', 'C', 'Coast Guard', Icons.anchor),
  AprsSymbol(r'\', 'D', 'Depots', Icons.warehouse),
  AprsSymbol(r'\', 'E', 'Smoke', Icons.cloud),
  AprsSymbol(r'\', 'F', 'Freezing Rain', null),
  AprsSymbol(r'\', 'G', 'Snow Shower', null),
  AprsSymbol(r'\', 'H', 'Haze / Hazards', Icons.warning),
  AprsSymbol(r'\', 'I', 'Rain Shower', Icons.water_drop),
  AprsSymbol(r'\', 'J', 'Lightning', null),
  AprsSymbol(r'\', 'K', 'Kenwood HT', Icons.radio),
  AprsSymbol(r'\', 'L', 'Lighthouse', null, null, aprsLighthouseIcon),
  AprsSymbol(r'\', 'M', 'MARS (Army/Navy/AF)', Icons.military_tech),
  AprsSymbol(r'\', 'N', 'Navigation Buoy', Icons.anchor),
  AprsSymbol(r'\', 'O', 'Rocket', Icons.rocket_launch),
  AprsSymbol(r'\', 'P', 'Parking', Icons.local_parking),
  AprsSymbol(r'\', 'Q', 'Quake', Icons.vibration),
  AprsSymbol(r'\', 'R', 'Restaurant', Icons.restaurant),
  AprsSymbol(r'\', 'S', 'Satellite / Pacsat', Icons.satellite_alt),
  AprsSymbol(r'\', 'T', 'Thunderstorm', Icons.thunderstorm),
  AprsSymbol(r'\', 'U', 'Sunny', Icons.wb_sunny),
  AprsSymbol(r'\', 'V', 'VORTAC Nav Aid', Icons.navigation),
  AprsSymbol(r'\', 'W', 'NWS site', Icons.cloud),
  AprsSymbol(r'\', 'X', 'Pharmacy Rx', Icons.local_pharmacy),
  AprsSymbol(r'\', 'Y', 'Radios and devices', Icons.radio),
  AprsSymbol(r'\', 'Z', 'avail', null),
  AprsSymbol(r'\', '[', 'W.Cloud / humans', Icons.directions_walk),
  AprsSymbol(r'\', r'\', 'GPS symbol', Icons.gps_fixed),
  AprsSymbol(r'\', ']', 'avail', null),
  AprsSymbol(r'\', '^', 'Other Aircraft', Icons.flight),
  AprsSymbol(r'\', '_', 'WX site (green digi)', Icons.cloud),
  AprsSymbol(r'\', '`', 'Rain', Icons.water_drop),
  AprsSymbol(r'\', 'a', 'ARRL / ARES / WinLink / D-Star', Icons.hub),
  AprsSymbol(r'\', 'b', 'Blowing Dust / Sand', null),
  AprsSymbol(r'\', 'c', 'CD triangle (RACES / SATERN)', Icons.change_history),
  AprsSymbol(r'\', 'd', 'DX spot by callsign', Icons.wifi_tethering),
  AprsSymbol(r'\', 'e', 'Sleet', Icons.grain),
  AprsSymbol(r'\', 'f', 'Funnel Cloud', Icons.cyclone),
  AprsSymbol(r'\', 'g', 'Gale Flags', Icons.flag),
  AprsSymbol(r'\', 'h', 'Store / Hamfest', Icons.store),
  AprsSymbol(r'\', 'i', 'Points of Interest', Icons.location_on),
  AprsSymbol(r'\', 'j', 'WorkZone (Steam Shovel)', Icons.construction),
  AprsSymbol(r'\', 'k', 'Special Vehicle (SUV/ATV/4x4)', Icons.directions_car),
  AprsSymbol(r'\', 'l', 'Areas (box/circle/etc)', Icons.crop_square),
  AprsSymbol(r'\', 'm', 'Value Sign (3 digit display)', Icons.pin),
  AprsSymbol(r'\', 'n', 'Overlay Triangle', Icons.change_history),
  AprsSymbol(r'\', 'o', 'Small circle', Icons.circle),
  AprsSymbol(r'\', 'p', 'Partly Cloudy', null),
  AprsSymbol(r'\', 'q', 'avail', null),
  AprsSymbol(r'\', 'r', 'Restrooms', Icons.wc),
  AprsSymbol(r'\', 's', 'Ship / boats (overlay)', Icons.directions_boat),
  AprsSymbol(r'\', 't', 'Tornado', Icons.cyclone),
  AprsSymbol(r'\', 'u', 'Truck (overlay)', Icons.local_shipping),
  AprsSymbol(r'\', 'v', 'Van (overlay)', Icons.airport_shuttle),
  AprsSymbol(r'\', 'w', 'Flooding', Icons.water),
  AprsSymbol(r'\', 'x', 'Wreck or Obstruction', Icons.dangerous),
  AprsSymbol(r'\', 'y', 'Skywarn', Icons.warning),
  AprsSymbol(r'\', 'z', 'Shelter', Icons.night_shelter),
  AprsSymbol(r'\', '{', 'Fog', null),
  AprsSymbol(r'\', '|', 'TNC Stream Switch', null),
  AprsSymbol(r'\', '}', 'avail', null),
  AprsSymbol(r'\', '~', 'TNC Stream Switch', null),
];
