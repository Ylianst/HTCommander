import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:htcommander/l10n/app_localizations.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/host_bridge.dart';
import 'package:htcommander/services/weather_radar_service.dart';
import 'package:htcommander/widgets/tab_visibility.dart';
import 'package:htcommander/widgets/weather_radar_layer.dart';
import 'package:latlong2/latlong.dart';

String _metadata(DateTime time) {
  final utc = DateTime.utc(
    time.year,
    time.month,
    time.day,
    time.hour,
    time.minute,
  );
  final stamp = utc
      .toIso8601String()
      .substring(0, 16)
      .replaceAll(RegExp('[-:T]'), '');
  return jsonEncode({
    'services': [
      {'id': 'other', 'layername': 'ignored'},
      {
        'id': 'ridge_uscomp_n0q',
        'layername': 'ridge::USCOMP-N0Q-$stamp',
        'utc_valid': utc.toIso8601String(),
      },
    ],
  });
}

Widget _app({bool enabled = true, bool offline = false, bool visible = true}) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: TabVisibility(
          visible: visible,
          child: FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(39, -98),
              initialZoom: 4,
            ),
            children: [
              WeatherRadarLayer(
                enabled: enabled,
                offline: offline,
                foregroundLayers: const [
                  MarkerLayer(key: ValueKey('foregroundMarkers'), markers: []),
                ],
              ),
            ],
          ),
        ),
      ),
    );

void main() {
  setUp(DataBroker.reset);
  tearDown(DataBroker.reset);

  test(
    'metadata selects N0Q, uses immutable URLs, and expires at 15 minutes',
    () {
      final time = DateTime.utc(2026, 11, 28, 6, 35);
      final frame = WeatherRadarFrame.parse(_metadata(time), now: time);
      expect(
        frame.urlTemplate,
        'https://mesonet.agron.iastate.edu/c/tile.py/1.0.0/'
        'ridge::USCOMP-N0Q-202611280635/{z}/{x}/{y}.png',
      );
      expect(
        frame.isStale(time.add(const Duration(minutes: 14, seconds: 59))),
        isFalse,
      );
      expect(frame.isStale(time.add(const Duration(minutes: 15))), isTrue);
      final next = WeatherRadarFrame.parse(
        _metadata(time.add(const Duration(minutes: 5))),
        now: time.add(const Duration(minutes: 5)),
      );
      expect(next.urlTemplate, isNot(frame.urlTemplate));
    },
  );

  test(
    'invalid, missing, inconsistent and future radar metadata is rejected',
    () {
      final time = DateTime.utc(2026, 11, 28, 6, 35);
      final valid = _metadata(time);
      for (final body in [
        'not json',
        '[]',
        '{"services":{}}',
        '{"services":[]}',
        valid.replaceAll('ridge::USCOMP-N0Q-202611280635', '../../other'),
        valid.replaceAll('202611280635', '202611280630'),
        valid.replaceAll('2026-11-28T06:35:00.000Z', 'bad time'),
        valid.replaceAll('2026-11-28T06:35:00.000Z', '2026-11-28T06:35:00'),
        _metadata(time.add(const Duration(minutes: 11))),
      ]) {
        expect(
          () => WeatherRadarFrame.parse(body, now: time),
          throwsFormatException,
          reason: body,
        );
      }
    },
  );

  test(
    'metadata HTTP rejection is not interpreted as an empty radar',
    () async {
      final client = MockClient((_) async => http.Response('unavailable', 503));
      addTearDown(client.close);
      await expectLater(
        fetchWeatherRadarFrame(client, now: DateTime.now()),
        throwsA(
          isA<WeatherRadarHttpException>().having(
            (error) => error.statusCode,
            'status',
            503,
          ),
        ),
      );
    },
  );

  test('radar preferences stay local to the host or browser', () {
    for (final key in [weatherRadarEnabledKey, weatherRadarOpacityKey]) {
      expect(HostBridge.isLocalOnlySetting(key), isTrue);
      expect(HostBridge.isSyncedSetting(key), isFalse);
    }
  });

  testWidgets('radar requests are opt-in and stop offline, hidden or paused', (
    tester,
  ) async {
    var metadataRequests = 0;
    var tileRequests = 0;
    await http.runWithClient(
      () async {
        await tester.pumpWidget(_app(enabled: false));
        await tester.pump();
        expect(metadataRequests, 0);
        expect(tileRequests, 0);
        expect(find.byType(Slider), findsNothing);

        await tester.pumpWidget(_app());
        await tester.pumpAndSettle();
        expect(metadataRequests, 1);
        expect(tileRequests, greaterThan(0));
        expect(find.byType(TileLayer), findsOneWidget);
        final layer = tester.widget<TileLayer>(find.byType(TileLayer));
        final provider = layer.tileProvider;
        final stack = tester.widget<Stack>(
          find
              .descendant(
                of: find.byType(WeatherRadarLayer),
                matching: find.byType(Stack),
              )
              .first,
        );
        expect(stack.children.first, isA<Opacity>());
        expect(stack.children[1], isA<MarkerLayer>());
        expect(stack.children.last, isA<Align>());

        await tester.drag(find.byType(Slider), const Offset(40, 0));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TileLayer>(find.byType(TileLayer)).tileProvider,
          same(provider),
        );
        expect(
          DataBroker.getValue<int>(0, weatherRadarOpacityKey, 0),
          greaterThan(60),
        );
        expect(metadataRequests, 1);

        await tester.pump(const Duration(minutes: 5));
        await tester.pumpAndSettle();
        expect(metadataRequests, 2);

        await tester.pumpWidget(_app(offline: true));
        await tester.pumpAndSettle();
        expect(find.byType(TileLayer), findsNothing);
        expect(find.text('Radar hidden in offline mode'), findsOneWidget);
        final stoppedTiles = tileRequests;
        await tester.pump(const Duration(minutes: 10));
        expect(metadataRequests, 2);
        expect(tileRequests, stoppedTiles);

        await tester.pumpWidget(_app(visible: false));
        await tester.pump(const Duration(minutes: 10));
        expect(metadataRequests, 2);
        expect(find.byType(TileLayer), findsNothing);

        await tester.pumpWidget(_app());
        await tester.pumpAndSettle();
        expect(metadataRequests, 3);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.scheduleForcedFrame();
        await tester.pumpAndSettle();
        expect(find.byType(TileLayer), findsNothing);
        await tester.pump(const Duration(minutes: 10));
        expect(metadataRequests, 3);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(metadataRequests, 4);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      () => MockClient((request) async {
        if (request.url.path == '/json/tms.json') {
          metadataRequests++;
          return http.Response(_metadata(DateTime.now().toUtc()), 200);
        }
        tileRequests++;
        return http.Response.bytes(TileProvider.transparentImage, 200);
      }),
    );
  });

  testWidgets('late metadata after disabling radar cannot restore tiles', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    var requests = 0;
    await http.runWithClient(
      () async {
        await tester.pumpWidget(_app());
        await tester.pump();
        expect(requests, 1);
        await tester.pumpWidget(_app(enabled: false));
        pending.complete(http.Response(_metadata(DateTime.now().toUtc()), 200));
        await tester.pumpAndSettle();
        expect(find.byType(TileLayer), findsNothing);
        expect(find.byType(Slider), findsNothing);
        expect(requests, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      () => MockClient((_) {
        requests++;
        return pending.future;
      }),
    );
  });

  testWidgets('stale metadata is labelled and never requests radar tiles', (
    tester,
  ) async {
    var tiles = 0;
    await http.runWithClient(
      () async {
        await tester.pumpWidget(_app());
        await tester.pumpAndSettle();
        expect(find.text('Radar is 15+ minutes old; hidden'), findsOneWidget);
        expect(find.byType(TileLayer), findsNothing);
        expect(tiles, 0);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      () => MockClient((request) async {
        if (request.url.path != '/json/tms.json') tiles++;
        return http.Response(
          _metadata(
            DateTime.now().toUtc().subtract(const Duration(minutes: 20)),
          ),
          200,
        );
      }),
    );
  });

  testWidgets(
    'metadata failures show unavailable status and recover on refresh',
    (tester) async {
      var metadataRequests = 0;
      await http.runWithClient(
        () async {
          await tester.pumpWidget(_app());
          await tester.pumpAndSettle();
          expect(
            find.text('Radar unavailable; retrying every 5 minutes'),
            findsOneWidget,
          );
          expect(find.byType(TileLayer), findsNothing);
          await tester.pump(const Duration(minutes: 5));
          await tester.pumpAndSettle();
          expect(find.byType(TileLayer), findsOneWidget);
          expect(find.textContaining('Observed:'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient((request) async {
          if (request.url.path == '/json/tms.json') {
            metadataRequests++;
            return metadataRequests == 1
                ? http.Response('failed', 503)
                : http.Response(_metadata(DateTime.now().toUtc()), 200);
          }
          return http.Response.bytes(TileProvider.transparentImage, 200);
        }),
      );
    },
  );
}
