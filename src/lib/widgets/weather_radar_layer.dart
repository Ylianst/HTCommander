/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../services/data_broker.dart';
import '../services/weather_radar_service.dart';
import 'tab_visibility.dart';

const weatherRadarEnabledKey = 'MapWeatherRadarEnabled';
const weatherRadarOpacityKey = 'MapWeatherRadarOpacity';

class WeatherRadarLayer extends StatefulWidget {
  const WeatherRadarLayer({
    super.key,
    required this.enabled,
    required this.offline,
    required this.foregroundLayers,
  });

  final bool enabled;
  final bool offline;
  final List<Widget> foregroundLayers;

  @override
  State<WeatherRadarLayer> createState() => _WeatherRadarLayerState();
}

class _WeatherRadarLayerState extends State<WeatherRadarLayer>
    with WidgetsBindingObserver {
  WeatherRadarFrame? _frame;
  http.Client? _client;
  http.Client? _tileClient;
  Timer? _refreshTimer;
  Timer? _ageTimer;
  bool _visible = true;
  bool _foreground = true;
  bool _active = false;
  bool _loading = false;
  bool _refreshFailed = false;
  bool _tilesFailed = false;
  int _generation = 0;
  double _opacity = 0.6;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    final saved = DataBroker.getValue<int>(0, weatherRadarOpacityKey, 60) ?? 60;
    _opacity = saved.clamp(10, 100) / 100;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TabVisibility.of(context);
    _syncActivity();
  }

  @override
  void didUpdateWidget(WeatherRadarLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _visible = TabVisibility.of(context);
    _syncActivity();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      _syncActivity();
    });
  }

  void _syncActivity() {
    final active = widget.enabled && _visible && _foreground && !widget.offline;
    if (active == _active) return;
    _active = active;
    _generation++;
    _refreshTimer?.cancel();
    _ageTimer?.cancel();
    _client?.close();
    _tileClient?.close();
    _client = null;
    _tileClient = null;
    _loading = false;
    if (!active) return;
    _client = http.Client();
    _tileClient = http.Client();
    unawaited(_refresh());
    _refreshTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => unawaited(_refresh()),
    );
    _ageTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => setState(() {}),
    );
  }

  Future<void> _refresh() async {
    final client = _client;
    if (!_active || _loading || client == null) return;
    _loading = true;
    final generation = _generation;
    try {
      final frame = await fetchWeatherRadarFrame(client, now: DateTime.now());
      if (!mounted || generation != _generation) return;
      setState(() {
        if (frame.layerName != _frame?.layerName) _tilesFailed = false;
        _frame = frame;
        _refreshFailed = false;
      });
    } on FormatException catch (error) {
      _onRefreshError(error, generation);
    } on WeatherRadarHttpException catch (error) {
      _onRefreshError(error, generation);
    } on TimeoutException catch (error) {
      // Closing the timed-out client also stops its pending request.
      if (mounted && generation == _generation) {
        client.close();
        _client = http.Client();
      }
      _onRefreshError(error, generation);
    } on http.ClientException catch (error) {
      _onRefreshError(error, generation);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _onRefreshError(Object error, int generation) {
    if (!mounted || generation != _generation) return;
    if (!_refreshFailed) {
      DataBroker.dispatch(
        deviceId: 1,
        name: 'LogError',
        data: 'Weather radar: $error',
        store: false,
      );
    }
    setState(() => _refreshFailed = true);
  }

  void _onTileError(String layerName, int generation, Object error) {
    if (!mounted ||
        _tilesFailed ||
        generation != _generation ||
        _frame?.layerName != layerName) {
      return;
    }
    _tilesFailed = true;
    DataBroker.dispatch(
      deviceId: 1,
      name: 'LogError',
      data: 'Weather radar tiles: $error',
      store: false,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          generation == _generation &&
          _frame?.layerName == layerName) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    _refreshTimer?.cancel();
    _ageTimer?.cancel();
    _client?.close();
    _tileClient?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final frame = _frame;
    final generation = _generation;
    final stale = frame?.isStale(DateTime.now()) ?? false;
    final String status;
    if (widget.offline) {
      status = l10n.mapWeatherRadarOffline;
    } else if (!_active) {
      status = l10n.mapWeatherRadarPaused;
    } else if (frame == null) {
      status = _refreshFailed
          ? l10n.mapWeatherRadarUnavailable
          : l10n.mapWeatherRadarLoading;
    } else if (stale) {
      status = l10n.mapWeatherRadarStale;
    } else if (_tilesFailed) {
      status = l10n.mapWeatherRadarTilesUnavailable;
    } else if (_refreshFailed) {
      status = l10n.mapWeatherRadarRefreshFailed;
    } else {
      status = l10n.mapWeatherRadarTime(
        DateFormat('yyyy-MM-dd HH:mm').format(frame.observedAt),
      );
    }
    return Stack(
      children: [
        if (_active && frame != null && !stale)
          Opacity(
            opacity: _opacity,
            child: _WeatherRadarTiles(
              key: ValueKey((
                'weatherRadarTiles',
                frame.layerName,
                _generation,
              )),
              frame: frame,
              client: _tileClient!,
              onError: (error) =>
                  _onTileError(frame.layerName, generation, error),
            ),
          ),
        ...widget.foregroundLayers,
        if (widget.enabled)
          Align(
            alignment: Alignment.topRight,
            child: LayoutBuilder(
              builder: (context, constraints) => SizedBox(
                width: math.min(240, math.max(0, constraints.maxWidth - 60)),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.mapWeatherRadar,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(status, style: const TextStyle(fontSize: 11)),
                        if (frame != null &&
                            (stale || _refreshFailed || _tilesFailed))
                          Text(
                            l10n.mapWeatherRadarTime(
                              DateFormat(
                                'yyyy-MM-dd HH:mm',
                              ).format(frame.observedAt),
                            ),
                            style: const TextStyle(fontSize: 11),
                          ),
                        Row(
                          children: [
                            Text(
                              l10n.mapWeatherRadarOpacity,
                              style: const TextStyle(fontSize: 11),
                            ),
                            Expanded(
                              child: Slider(
                                value: _opacity,
                                min: 0.1,
                                max: 1,
                                divisions: 9,
                                label: '${(_opacity * 100).round()}%',
                                onChanged: (value) =>
                                    setState(() => _opacity = value),
                                onChangeEnd: (value) => DataBroker.dispatch(
                                  deviceId: 0,
                                  name: weatherRadarOpacityKey,
                                  data: (value * 100).round(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        RotatedBox(
                          quarterTurns: 3,
                          child: Image.asset(
                            'assets/images/weather_radar_legend.png',
                            semanticLabel: l10n.mapWeatherRadarLegend,
                          ),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 28),
                            textStyle: const TextStyle(fontSize: 11),
                          ),
                          onPressed: () => launchUrl(
                            Uri.parse(
                              'https://mesonet.agron.iastate.edu/docs/nexrad_mosaic/',
                            ),
                            mode: LaunchMode.externalApplication,
                          ),
                          child: const Text(
                            'Radar: NWS / Iowa Environmental Mesonet',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _WeatherRadarTiles extends StatefulWidget {
  const _WeatherRadarTiles({
    super.key,
    required this.frame,
    required this.client,
    required this.onError,
  });

  final WeatherRadarFrame frame;
  final http.Client client;
  final ValueChanged<Object> onError;

  @override
  State<_WeatherRadarTiles> createState() => _WeatherRadarTilesState();
}

class _WeatherRadarTilesState extends State<_WeatherRadarTiles> {
  // The parent closes the shared tile client immediately on backgrounding,
  // even when paused rendering postpones TileLayer disposal.
  late final _provider = NetworkTileProvider(
    httpClient: widget.client,
    cachingProvider: const DisabledMapCachingProvider(),
    attemptDecodeOfHttpErrorResponses: false,
  );

  @override
  Widget build(BuildContext context) => TileLayer(
    urlTemplate: widget.frame.urlTemplate,
    userAgentPackageName: 'com.meshcentral.htcommander',
    tileProvider: _provider,
    // The mosaic covers the contiguous US; overzoom its ~1 km data.
    maxNativeZoom: 8,
    tileBounds: LatLngBounds(const LatLng(23, -126), const LatLng(50, -65)),
    panBuffer: 0,
    keepBuffer: 0,
    evictErrorTileStrategy: EvictErrorTileStrategy.dispose,
    errorTileCallback: (_, error, _) => widget.onError(error),
  );
}
