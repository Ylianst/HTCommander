import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/l10n/app_localizations.dart';
import 'package:htcommander/gps/gps_data.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';
import 'package:htcommander/utils/map_tile_downloader_io.dart';
import 'package:htcommander/utils/map_tile_provider_io.dart';
import 'package:htcommander/utils/map_tile_source.dart';
import 'package:htcommander/widgets/map_tab.dart';
import 'package:latlong2/latlong.dart';

Future<Uint8List> _png(Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(color, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(4, 4);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List();
}

Future<ui.Image> _load(CachedMapTileProvider provider, int z, int x, int y) {
  final completed = Completer<ui.Image>();
  final stream = provider
      .getImage(
        TileCoordinates(x, y, z),
        TileLayer(urlTemplate: provider.source.urlTemplate),
      )
      .resolve(ImageConfiguration.empty);
  late ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      completed.complete(info.image.clone());
      stream.removeListener(listener);
    },
    onError: (Object error, StackTrace? stack) {
      completed.completeError(error, stack);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return completed.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late HttpOverrides? originalHttpOverrides;
  late HttpServer server;
  late MapTileSource first;
  late MapTileSource second;
  final requests = <Uri>[];
  var status = 200;
  late Uint8List red;
  late Uint8List blue;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('htcommander-map-test-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async {
            if (call.method == 'getApplicationSupportDirectory') {
              return root.path;
            }
            throw MissingPluginException();
          },
        );
    originalHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    red = await _png(const Color(0xFFFF0000));
    blue = await _png(const Color(0xFF0000FF));
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add(request.uri);
      request.response.statusCode = status;
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add(request.uri.path.startsWith('/second') ? blue : red);
      await request.response.close();
    });
    first = MapTileSource.custom(
      'http://127.0.0.1:${server.port}/first?z={z}&x={x}&y={y}&key=test',
    );
    second = MapTileSource.custom(
      'http://127.0.0.1:${server.port}/second/{z}/{x}/{y}.png',
    );
  });
  tearDownAll(() async {
    await server.close(force: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    HttpOverrides.global = originalHttpOverrides;
    await root.delete(recursive: true);
  });
  setUp(() {
    status = 200;
    requests.clear();
    DataBroker.reset();
  });

  test(
    'downloads resolve query URLs and isolate caches from OSM and each other',
    () async {
      final cancel = ValueNotifier(false);
      addTearDown(cancel.dispose);
      for (final source in [first, second]) {
        final progress = <(int, int)>[];
        final result = await downloadTilesInBounds(
          sw: const LatLng(0, 0),
          ne: const LatLng(0, 0),
          minZoom: 0,
          maxZoom: 0,
          source: source,
          cancel: cancel,
          onProgress: (done, total) => progress.add((done, total)),
        );
        expect(result, 1);
        expect(progress, [(1, 1)]);
        final dir = await CachedMapTileProvider.cacheDir(source: source);
        expect(
          await File('${dir.path}/0_0_0.png').readAsBytes(),
          source == first ? red : blue,
        );
      }
      expect(requests.first.queryParameters, {
        'z': '0',
        'x': '0',
        'y': '0',
        'key': 'test',
      });
      expect(requests.last.path, '/second/0/0/0.png');
      final osm = await CachedMapTileProvider.cacheDir();
      expect(osm.path, endsWith('map_tile_cache'));
      expect(await File('${osm.path}/0_0_0.png').exists(), isFalse);
      expect(
        (await CachedMapTileProvider.cacheDir(source: first)).path,
        isNot((await CachedMapTileProvider.cacheDir(source: second)).path),
      );
    },
  );

  test(
    'offline exact and ancestor tiles stay in the selected source cache',
    () async {
      // This test creates its own fixtures rather than depending on downloads.
      for (final (source, bytes) in [(first, red), (second, blue)]) {
        final dir = await CachedMapTileProvider.cacheDir(source: source);
        await File('${dir.path}/0_0_0.png').writeAsBytes(bytes);
        final provider = CachedMapTileProvider(offline: true, source: source);
        for (final (z, x, y) in [(0, 0, 0), (1, 0, 0)]) {
          final image = await _load(provider, z, x, y);
          final pixel = await image.toByteData();
          expect(pixel!.getUint8(0), source == first ? 255 : 0);
          expect(pixel.getUint8(2), source == first ? 0 : 255);
          image.dispose();
        }
        provider.dispose();
      }
      expect(requests, isEmpty);
    },
  );

  test(
    'failed download is not counted or cached and does not expose the key',
    () async {
      final logs = <String>[];
      final broker = DataBrokerClient();
      broker.subscribe(
        deviceId: 1,
        name: 'LogError',
        callback: (_, _, data) => logs.add(data! as String),
      );
      addTearDown(broker.dispose);
      status = 403;
      final source = MapTileSource.custom('${first.urlTemplate}&different=1');
      final cancel = ValueNotifier(false);
      addTearDown(cancel.dispose);
      final progress = <(int, int)>[];
      await expectLater(
        downloadTilesInBounds(
          sw: const LatLng(0, 0),
          ne: const LatLng(0, 0),
          minZoom: 0,
          maxZoom: 0,
          source: source,
          cancel: cancel,
          onProgress: (done, total) => progress.add((done, total)),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(progress, isEmpty);
      final dir = await CachedMapTileProvider.cacheDir(source: source);
      expect(await File('${dir.path}/0_0_0.png').exists(), isFalse);
      final log = logs.join('\n');
      expect(log, contains('HTTP 403'));
      expect(log, isNot(contains('key=test')));
    },
  );

  testWidgets(
    'saved source switches live, preserving map camera and overlays',
    (tester) async {
      DataBroker.dispatch(deviceId: 0, name: 'MapOfflineMode', data: 1);
      DataBroker.dispatch(
        deviceId: 1,
        name: 'GpsData',
        data: GpsData(latitude: 39, longitude: -98, isFixed: true),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: MapTab()),
        ),
      );
      await tester.pump();
      final controller = tester
          .widget<FlutterMap>(find.byType(FlutterMap))
          .mapController!;
      final center = controller.camera.center;
      final zoom = controller.camera.zoom;
      expect(find.byType(MarkerLayer), findsWidgets);
      expect(find.byType(ColorFiltered), findsOneWidget);
      DataBroker.dispatch(
        deviceId: 0,
        name: customMapUrlKey,
        data: first.urlTemplate,
      );
      DataBroker.dispatch(
        deviceId: 0,
        name: customMapAttributionKey,
        data: 'Example Maps',
      );
      DataBroker.dispatch(deviceId: 0, name: customMapEnabledKey, data: 1);
      await tester.pump();
      await tester.pump();
      expect(
        tester.widget<TileLayer>(find.byType(TileLayer)).urlTemplate,
        first.urlTemplate,
      );
      expect(find.text('Example Maps'), findsOneWidget);
      expect(find.byType(ColorFiltered), findsNothing);
      expect(controller.camera.center, center);
      expect(controller.camera.zoom, zoom);
      expect(find.byType(MarkerLayer), findsWidgets);
      DataBroker.dispatch(deviceId: 0, name: customMapEnabledKey, data: 0);
      await tester.pump();
      await tester.pump();
      expect(
        tester.widget<TileLayer>(find.byType(TileLayer)).urlTemplate,
        MapTileSource.openStreetMapUrl,
      );
      expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
      expect(find.byType(ColorFiltered), findsOneWidget);
      DataBroker.dispatch(
        deviceId: 0,
        name: customMapUrlKey,
        data: 'invalid-url-with-key',
      );
      DataBroker.dispatch(deviceId: 0, name: customMapEnabledKey, data: 1);
      await tester.pump();
      await tester.pump();
      expect(find.byType(TileLayer), findsNothing);
      expect(find.textContaining('Enter a valid HTTP/HTTPS'), findsOneWidget);
      expect(find.byType(MarkerLayer), findsWidgets);
      expect(requests, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
