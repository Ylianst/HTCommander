/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../satellite/orientation_service.dart';
import '../satellite/satellite_models.dart';
import '../services/data_broker_client.dart';
import 'antenna_aim_overlay.dart';

/// Full-screen guide that helps aim a handheld antenna at a satellite by
/// comparing the phone's live orientation (compass heading + tilt) against the
/// satellite's computed azimuth/elevation. Point the phone's TOP EDGE along the
/// antenna boom, screen facing up.
///
/// Only useful on Android/iOS; callers gate the entry point with
/// [OrientationService.isSupported].
class AntennaPointerPage extends StatefulWidget {
  final int noradId;
  final String satelliteName;

  const AntennaPointerPage({
    super.key,
    required this.noradId,
    required this.satelliteName,
  });

  @override
  State<AntennaPointerPage> createState() => _AntennaPointerPageState();
}

class _AntennaPointerPageState extends State<AntennaPointerPage> {
  static const int _deviceId = 0;
  // Considered "on target" when both axes are within this many degrees.
  static const double _alignToleranceDeg = 6;

  final DataBrokerClient _broker = DataBrokerClient();
  final OrientationService _orientation = OrientationService();
  StreamSubscription<DeviceOrientation>? _orientationSub;

  SatellitePosition? _target;
  DeviceOrientation? _device;
  final bool _sensorSupported = OrientationService.isSupported;

  @override
  void initState() {
    super.initState();
    _broker.subscribe(
      deviceId: _deviceId,
      name: 'SatellitePositions',
      callback: _onPositions,
    );
    _broker.subscribe(
      deviceId: _deviceId,
      name: 'SatelliteObserverLocation',
      callback: _onObserverLocation,
    );
    if (_sensorSupported) {
      _orientationSub = _orientation.stream.listen((o) {
        if (mounted) setState(() => _device = o);
      });
      _orientation.start();
    }
    // Ask the handler to re-emit its cached snapshot (broker events broadcast).
    _broker.dispatch(
      deviceId: _deviceId,
      name: 'SatelliteResync',
      data: DateTime.now().millisecondsSinceEpoch,
      store: false,
    );
  }

  @override
  void dispose() {
    _orientationSub?.cancel();
    _orientation.dispose();
    _broker.dispose();
    super.dispose();
  }

  void _onPositions(int deviceId, String name, Object? data) {
    if (data is! List) return;
    SatellitePosition? found;
    for (final p in data.whereType<SatellitePosition>()) {
      if (p.noradId == widget.noradId) {
        found = p;
        break;
      }
    }
    if (found != null && mounted) setState(() => _target = found);
  }

  void _onObserverLocation(int deviceId, String name, Object? data) {
    if (data is! Map) return;
    final lat = data['lat'];
    final lon = data['lon'];
    if (lat is num && lon is num) {
      _orientation.magneticDeclinationDeg = estimateMagneticDeclination(
        lat.toDouble(),
        lon.toDouble(),
      );
    }
  }

  /// Shortest signed difference b - a wrapped to [-180, 180].
  double _azDelta(double a, double b) {
    var d = (b - a) % 360;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    return d;
  }

  /// Collapses the full page into the draggable floating overlay so the operator
  /// can keep aiming while using another tab.
  void _minimizeToOverlay() {
    final navigator = Navigator.of(context);
    final noradId = widget.noradId;
    final name = widget.satelliteName;
    navigator.pop();
    AntennaAimOverlay.show(
      navigator.context,
      noradId: noradId,
      satelliteName: name,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('Aim: ${widget.satelliteName}'),
        actions: [
          if (_sensorSupported)
            IconButton(
              icon: const Icon(Icons.picture_in_picture_alt),
              tooltip: 'Floating aim overlay',
              onPressed: _minimizeToOverlay,
            ),
        ],
      ),
      body: SafeArea(
        child: !_sensorSupported
            ? _buildUnsupported(context)
            : _target == null
            ? _buildWaiting(context, 'Waiting for satellite tracking data\u2026')
            : _buildGuide(context, scheme),
      ),
    );
  }

  Widget _buildUnsupported(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.explore_off, size: 48, color: theme.disabledColor),
            const SizedBox(height: 12),
            Text(
              'Antenna aiming needs a compass and tilt sensor, which are only '
              'available on phones and tablets.',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.hintColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaiting(BuildContext context, String message) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(message, style: TextStyle(color: theme.hintColor)),
        ],
      ),
    );
  }

  Widget _buildGuide(BuildContext context, ColorScheme scheme) {
    final target = _target!;
    final device = _device;
    final belowHorizon = target.elevationDeg < 0;

    final double? azErr = device == null
        ? null
        : _azDelta(device.azimuthDeg, target.azimuthDeg);
    final double? elErr = device == null
        ? null
        : target.elevationDeg - device.elevationDeg;
    final aligned =
        azErr != null &&
        elErr != null &&
        !belowHorizon &&
        azErr.abs() <= _alignToleranceDeg &&
        elErr.abs() <= _alignToleranceDeg;

    return Column(
      children: [
        if (device != null && device.needsCalibration)
          _calibrationBanner(context),
        if (belowHorizon) _belowHorizonBanner(context),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: AspectRatio(
                aspectRatio: 1,
                child: CustomPaint(
                  painter: _SkyPlotPainter(
                    targetAzimuthDeg: target.azimuthDeg,
                    targetElevationDeg: target.elevationDeg,
                    deviceAzimuthDeg: device?.azimuthDeg,
                    deviceElevationDeg: device?.elevationDeg,
                    aligned: aligned,
                    scheme: scheme,
                  ),
                ),
              ),
            ),
          ),
        ),
        _buildReadout(context, scheme, target, device, azErr, elErr, aligned),
      ],
    );
  }

  Widget _calibrationBanner(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.threesixty, color: scheme.onErrorContainer, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Compass needs calibration. Move the phone in a figure-8 a few '
              'times until this message clears.',
              style: TextStyle(color: scheme.onErrorContainer, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _belowHorizonBanner(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.arrow_downward, color: scheme.onSurfaceVariant, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This satellite is below the horizon right now. Wait for the next '
              'pass before aiming.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadout(
    BuildContext context,
    ColorScheme scheme,
    SatellitePosition target,
    DeviceOrientation? device,
    double? azErr,
    double? elErr,
    bool aligned,
  ) {
    final theme = Theme.of(context);
    String azHint;
    String elHint;
    if (device == null || azErr == null || elErr == null) {
      azHint = 'Reading compass\u2026';
      elHint = 'Reading tilt\u2026';
    } else {
      final az = azErr.abs();
      final el = elErr.abs();
      azHint = az <= _alignToleranceDeg
          ? 'Azimuth aligned'
          : 'Turn ${azErr > 0 ? "right" : "left"} ${az.toStringAsFixed(0)}\u00b0';
      elHint = el <= _alignToleranceDeg
          ? 'Elevation aligned'
          : 'Tilt ${elErr > 0 ? "up" : "down"} ${el.toStringAsFixed(0)}\u00b0';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: aligned
            ? Colors.green.withValues(alpha: 0.15)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (aligned)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 8),
                Text(
                  'On target',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(child: _hintTile(context, Icons.turn_right, azHint)),
                Expanded(child: _hintTile(context, Icons.swap_vert, elHint)),
              ],
            ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _readoutColumn(
                context,
                'Target',
                target.azimuthDeg,
                target.elevationDeg,
                scheme.primary,
              ),
              _readoutColumn(
                context,
                'Phone',
                device?.azimuthDeg,
                device?.elevationDeg,
                scheme.tertiary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _hintTile(BuildContext context, IconData icon, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: scheme.primary),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _readoutColumn(
    BuildContext context,
    String label,
    double? azimuthDeg,
    double? elevationDeg,
    Color color,
  ) {
    final theme = Theme.of(context);
    String fmt(double? v) => v == null ? '\u2013' : '${v.toStringAsFixed(0)}\u00b0';
    return Column(
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text('Az ${fmt(azimuthDeg)}   El ${fmt(elevationDeg)}'),
      ],
    );
  }
}

/// Polar sky-plot: centre = zenith (elevation 90), rim = horizon (elevation 0),
/// North at the top with azimuth increasing clockwise. Draws the satellite
/// target and, when available, the live phone-pointing indicator.
class _SkyPlotPainter extends CustomPainter {
  final double targetAzimuthDeg;
  final double targetElevationDeg;
  final double? deviceAzimuthDeg;
  final double? deviceElevationDeg;
  final bool aligned;
  final ColorScheme scheme;

  _SkyPlotPainter({
    required this.targetAzimuthDeg,
    required this.targetElevationDeg,
    required this.deviceAzimuthDeg,
    required this.deviceElevationDeg,
    required this.aligned,
    required this.scheme,
  });

  Offset _project(Offset center, double radius, double azDeg, double elDeg) {
    final r = (1 - (elDeg.clamp(0.0, 90.0)) / 90) * radius;
    final a = (azDeg - 90) * math.pi / 180; // 0 deg at top (North), clockwise.
    return center + Offset(math.cos(a), math.sin(a)) * r;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 18;

    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = scheme.outlineVariant;

    // Elevation rings at 0, 30, 60 deg (90 is the centre point).
    for (final el in [0, 30, 60]) {
      final r = (1 - el / 90) * radius;
      canvas.drawCircle(center, r, gridPaint);
      final tp = _text('$el\u00b0', scheme.onSurfaceVariant.withValues(alpha: 0.7), 10);
      tp.paint(canvas, center + Offset(4, -r - tp.height));
    }

    // Azimuth spokes every 30 deg.
    for (var az = 0; az < 360; az += 30) {
      final a = (az - 90) * math.pi / 180;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(center + dir * (radius * 0.02), center + dir * radius, gridPaint);
    }

    // Cardinal labels.
    const cardinals = {0: 'N', 90: 'E', 180: 'S', 270: 'W'};
    cardinals.forEach((az, label) {
      final a = (az - 90) * math.pi / 180;
      final dir = Offset(math.cos(a), math.sin(a));
      final p = center + dir * (radius + 12);
      final tp = _text(
        label,
        az == 0 ? scheme.primary : scheme.onSurface,
        13,
        bold: true,
      );
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    });

    // Device pointing indicator (where the phone is currently aimed).
    if (deviceAzimuthDeg != null && deviceElevationDeg != null) {
      final dp = _project(center, radius, deviceAzimuthDeg!, deviceElevationDeg!);
      final devColor = aligned ? Colors.green : scheme.tertiary;
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..color = devColor;
      canvas.drawCircle(dp, 16, ring);
      // Crosshair.
      canvas.drawLine(dp + const Offset(-10, 0), dp + const Offset(10, 0), ring);
      canvas.drawLine(dp + const Offset(0, -10), dp + const Offset(0, 10), ring);
    }

    // Target (satellite) marker.
    final tp2 = _project(center, radius, targetAzimuthDeg, targetElevationDeg);
    final targetColor = aligned ? Colors.green : scheme.primary;
    canvas.drawCircle(tp2, 9, Paint()..color = targetColor);
    canvas.drawCircle(
      tp2,
      9,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = scheme.surface,
    );

    // Line from device to target to show the path to move.
    if (deviceAzimuthDeg != null && deviceElevationDeg != null && !aligned) {
      final dp = _project(center, radius, deviceAzimuthDeg!, deviceElevationDeg!);
      final guide = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = scheme.primary.withValues(alpha: 0.5);
      canvas.drawLine(dp, tp2, guide);
    }
  }

  TextPainter _text(String s, Color color, double size, {bool bold = false}) {
    return TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: bold ? FontWeight.bold : FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  @override
  bool shouldRepaint(covariant _SkyPlotPainter old) =>
      old.targetAzimuthDeg != targetAzimuthDeg ||
      old.targetElevationDeg != targetElevationDeg ||
      old.deviceAzimuthDeg != deviceAzimuthDeg ||
      old.deviceElevationDeg != deviceElevationDeg ||
      old.aligned != aligned ||
      old.scheme != scheme;
}
