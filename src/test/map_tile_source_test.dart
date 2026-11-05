import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/dialogs/app_settings.dart';
import 'package:htcommander/handlers/agent_api.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/host_bridge.dart';
import 'package:htcommander/utils/map_tile_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(DataBroker.reset);
  tearDown(() {
    DataBroker.setDevice0RemoteMode(false);
    DataBroker.onDevice0Write = null;
    DataBroker.reset();
  });

  test('custom maps default off and round-trip through settings', () {
    final defaults = AppSettings.loadFromDataBroker();
    expect(defaults.customMapSourceEnabled, isFalse);
    expect(defaults.customMapSourceUrl, isEmpty);
    expect(defaults.customMapSourceAttribution, isEmpty);
    final custom = defaults.copyWith(
      customMapSourceEnabled: true,
      customMapSourceUrl: 'https://example.com/{z}/{x}/{y}.png?key=test',
      customMapSourceAttribution: 'Example Maps',
    );
    custom.saveToDataBroker();
    final loaded = AppSettings.loadFromDataBroker().copyWith();
    expect(loaded.customMapSourceEnabled, isTrue);
    expect(loaded.customMapSourceUrl, custom.customMapSourceUrl);
    expect(loaded.customMapSourceAttribution, 'Example Maps');
    loaded.copyWith(customMapSourceEnabled: false).saveToDataBroker();
    expect(
      AppSettings.loadFromDataBroker().customMapSourceUrl,
      custom.customMapSourceUrl,
    );
  });

  test('XYZ paths and query parameters expand without changing API keys', () {
    final source = MapTileSource.custom(
      ' https://example.com/tile.t?z={z}&x={x}&y={y}&key=a%2Bb ',
    );
    expect(
      source.tileUrl(5, 3, 9),
      'https://example.com/tile.t?z=5&x=3&y=9&key=a%2Bb',
    );
    expect(source.label, 'example.com');
    expect(source.attributionText, 'example.com');
    expect(
      MapTileSource.custom(
        source.urlTemplate,
        attribution: ' Example Maps ',
      ).attributionText,
      'Example Maps',
    );
    expect(
      MapTileSource.isValidUrl('http://localhost:8080/{z}/{x}/{y}'),
      isTrue,
    );
    expect(
      MapTileSource.isValidUrl(
        'http://localhost/{z}/{x}/{y}',
        requireHttps: true,
      ),
      isFalse,
    );
  });

  test('invalid and unsupported URLs are rejected without exposing values', () {
    for (final url in [
      '',
      'file:///maps/{z}/{x}/{y}.png',
      'https://example.com/{z}/{x}.png',
      'https://example.com/{s}/{z}/{x}/{y}.png',
      'https://example.com/{z}/{x}/{y}.pbf',
      'https://example.com/{z}/{x}/{y}.png#fragment',
      'https://user:secret@example.com/{z}/{x}/{y}.png',
      'https://{z}.example.com/{x}/{y}.png',
      'https://example.com:{z}/{x}/{y}.png',
      'https://example.com/{z}/{x}/{y} stray',
      'https://example.com/{z}/{x}/{y}{',
      'https:///{z}/{x}/{y}.png',
    ]) {
      expect(MapTileSource.isValidUrl(url), isFalse, reason: url);
      expect(() => MapTileSource.custom(url), throwsFormatException);
    }
  });

  test('source identity is stable, isolated, and preserves the OSM cache', () {
    const osm = MapTileSource.openStreetMap();
    expect(osm.cacheKey, isEmpty);
    final first = MapTileSource.custom(
      'https://example.com/{z}/{x}/{y}.png?key=first',
    );
    final second = MapTileSource.custom(
      'https://example.com/{z}/{x}/{y}.png?key=second',
    );
    expect(first.cacheKey, matches(RegExp(r'^[a-f0-9]{64}$')));
    expect(first.cacheKey, isNot(second.cacheKey));
    expect(MapTileSource.custom(first.urlTemplate).cacheKey, first.cacheKey);
    expect(
      MapTileSource.custom(
        first.urlTemplate,
        attribution: 'Other text',
      ).cacheKey,
      first.cacheKey,
    );
  });

  test('custom settings stay local in remote mode and URL is agent-secret', () {
    final forwarded = <String>[];
    DataBroker.setDevice0RemoteMode(true);
    DataBroker.onDevice0Write = (name, data) => forwarded.add(name);
    for (final name in [
      customMapEnabledKey,
      customMapUrlKey,
      customMapAttributionKey,
    ]) {
      expect(HostBridge.isLocalOnlySetting(name), isTrue);
      expect(HostBridge.isSyncedSetting(name), isFalse);
      DataBroker.dispatch(
        deviceId: 0,
        name: name,
        data: name == customMapEnabledKey ? 1 : 'local',
      );
      expect(DataBroker.hasValue(0, name), isTrue);
    }
    expect(forwarded, isEmpty);
    expect(AgentApi.isSecretSetting(customMapUrlKey), isTrue);
  });
}
