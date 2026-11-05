import 'dart:convert';

import 'package:crypto/crypto.dart';

const customMapEnabledKey = 'MapCustomSourceEnabled';
const customMapUrlKey = 'MapCustomSourceUrl';
const customMapAttributionKey = 'MapCustomSourceAttribution';

class MapTileSource {
  const MapTileSource.openStreetMap()
    : urlTemplate = openStreetMapUrl,
      isCustom = false,
      attribution = '© OpenStreetMap contributors';

  factory MapTileSource.custom(String url, {String attribution = ''}) {
    final template = url.trim();
    if (!isValidUrl(template)) {
      throw const FormatException('Invalid custom raster XYZ map URL.');
    }
    return MapTileSource._(template, attribution.trim());
  }

  const MapTileSource._(this.urlTemplate, this.attribution) : isCustom = true;

  static const openStreetMapUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  final String urlTemplate;
  final bool isCustom;
  final String attribution;

  static bool isValidUrl(String value, {bool requireHttps = false}) {
    final template = value.trim();
    if (RegExp(r'\s').hasMatch(template)) return false;
    var expanded = template;
    for (final placeholder in ['{z}', '{x}', '{y}']) {
      if (!template.contains(placeholder)) return false;
      expanded = expanded.replaceAll(placeholder, '0');
    }
    if (expanded.contains('{') || expanded.contains('}')) return false;
    final uri = Uri.tryParse(expanded);
    if (uri == null ||
        (uri.scheme != 'https' && (requireHttps || uri.scheme != 'http')) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        !uri.hasAuthority) {
      return false;
    }
    // Coordinates must not change the origin or port.
    final alternate = template
        .replaceAll('{z}', '1')
        .replaceAll('{x}', '1')
        .replaceAll('{y}', '1');
    final other = Uri.tryParse(alternate);
    if (other == null || other.authority != uri.authority) return false;
    return !uri.path.toLowerCase().endsWith('.pbf');
  }

  String tileUrl(int z, int x, int y) => urlTemplate
      .replaceAll('{z}', '$z')
      .replaceAll('{x}', '$x')
      .replaceAll('{y}', '$y');

  // Preserve the legacy OSM cache; never put a URL or credential in a path.
  String get cacheKey => urlTemplate == openStreetMapUrl
      ? ''
      : sha256.convert(utf8.encode(urlTemplate)).toString();

  String get label =>
      isCustom ? Uri.parse(tileUrl(0, 0, 0)).host : 'OpenStreetMap';

  String get attributionText => attribution.isNotEmpty ? attribution : label;
}
