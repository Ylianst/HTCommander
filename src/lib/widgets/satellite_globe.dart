/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:satellite_observer/satellite_observer.dart' as so;

import '../satellite/satellite_models.dart';

/// Mean Earth radius used for display (a sphere is plenty for a overview).
const double _earthRadiusKm = 6371.0;

/// Interactive 3D globe showing the observer, every catalog satellite with its
/// current orbit, and the observer's visibility cone. Satellites inside the
/// cone (elevation at or above [minElevationDeg]) are drawn bold and green.
///
/// Satellites are propagated locally with SGP4 so the globe works even when no
/// observer location is known. The view is Earth-fixed at the current instant;
/// orbits are drawn as the inertial ring rotated into that frame.
class SatelliteGlobe extends StatefulWidget {
  final List<SatelliteInfo> satellites;

  /// Live look-angles from the satellite handler (only present when the
  /// observer is known); used to decide which birds are visible.
  final Map<int, SatellitePosition> positions;

  /// Observer latitude/longitude in degrees, or null when unknown.
  final double? observerLatDeg;
  final double? observerLonDeg;

  /// Elevation threshold for the visibility cone and highlight.
  final double minElevationDeg;

  final int? selectedId;

  /// Single click/tap on a satellite.
  final ValueChanged<int>? onSatelliteTap;

  /// Double click/tap on a satellite (fires after [onSatelliteTap] for the
  /// first click).
  final ValueChanged<int>? onSatelliteDoubleTap;

  const SatelliteGlobe({
    super.key,
    required this.satellites,
    required this.positions,
    required this.observerLatDeg,
    required this.observerLonDeg,
    required this.minElevationDeg,
    this.selectedId,
    this.onSatelliteTap,
    this.onSatelliteDoubleTap,
  });

  @override
  State<SatelliteGlobe> createState() => _SatelliteGlobeState();
}

class _SatelliteGlobeState extends State<SatelliteGlobe> {
  static Future<List<Float64List>>? _landFuture;
  List<Float64List>? _land;

  final Map<int, _EngineEntry> _engines = {};
  final Map<int, List<_V3>> _orbitsTeme = {};
  DateTime? _orbitsComputedAt;

  double _centerLatDeg = 20;
  double _centerLonDeg = 0;
  double _zoom = 1;
  bool _userMovedView = false;

  // Gesture state.
  Offset _lastFocal = Offset.zero;
  Offset _downLocal = Offset.zero;
  double _startZoom = 1;
  double _moved = 0;
  int _maxPointers = 0;
  DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);
  int? _lastTapId;

  // Last painted scene, used for hit-testing taps.
  _GlobeScene? _scene;

  @override
  void initState() {
    super.initState();
    _landFuture ??= _loadLand();
    _landFuture!.then((land) {
      if (mounted) setState(() => _land = land);
    });
    _centerOnObserver();
  }

  @override
  void didUpdateWidget(covariant SatelliteGlobe oldWidget) {
    super.didUpdateWidget(oldWidget);
    final observerAppeared =
        oldWidget.observerLatDeg == null && widget.observerLatDeg != null;
    if (observerAppeared && !_userMovedView) _centerOnObserver();
  }

  void _centerOnObserver() {
    final lat = widget.observerLatDeg;
    final lon = widget.observerLonDeg;
    if (lat == null || lon == null) return;
    // Look from slightly south of the observer so the visibility cone reads
    // as 3D rather than a flat ring seen from straight above.
    _centerLatDeg = (lat - 25).clamp(-80.0, 80.0);
    _centerLonDeg = lon;
  }

  static Future<List<Float64List>> _loadLand() async {
    try {
      final text = await rootBundle.loadString(
        'assets/satellites/world_land_110m.json',
      );
      final json = jsonDecode(text) as Map<String, dynamic>;
      final rings = <Float64List>[];
      for (final ring in (json['rings'] as List)) {
        var flat = (ring as List).cast<num>().toList();
        // Normalise to counter-clockwise (land on the left) in lon/lat; the
        // limb-clipping fill relies on a consistent winding.
        var area = 0.0;
        for (var k = 0; k + 3 < flat.length; k += 2) {
          area += flat[k] * flat[k + 3] - flat[k + 2] * flat[k + 1];
        }
        if (area < 0) {
          flat = [
            for (var k = flat.length - 2; k >= 0; k -= 2) ...[
              flat[k],
              flat[k + 1],
            ],
          ];
        }
        // Store as unit-sphere x,y,z triples.
        final out = Float64List((flat.length ~/ 2) * 3);
        for (var i = 0, j = 0; i + 1 < flat.length; i += 2, j += 3) {
          final lon = flat[i] * math.pi / 180;
          final lat = flat[i + 1] * math.pi / 180;
          out[j] = math.cos(lat) * math.cos(lon);
          out[j + 1] = math.cos(lat) * math.sin(lon);
          out[j + 2] = math.sin(lat);
        }
        rings.add(out);
      }
      return rings;
    } catch (e) {
      debugPrint('SatelliteGlobe: failed to load land outlines: $e');
      return const [];
    }
  }

  // --- Propagation ----------------------------------------------------------

  void _syncEngines() {
    final ids = <int>{};
    var changed = false;
    for (final sat in widget.satellites) {
      if (sat.isStatic) continue;
      ids.add(sat.noradId);
      final key = '${sat.tle.line1}\n${sat.tle.line2}';
      final existing = _engines[sat.noradId];
      if (existing != null && existing.key == key) continue;
      changed = true;
      try {
        final elements = so.GpElements.fromTle(
          sat.tle.line1,
          sat.tle.line2,
          name: sat.tle.name,
        );
        _engines[sat.noradId] = _EngineEntry(
          key,
          so.Sgp4Engine(elements),
          _periodMinutes(sat.tle.line2),
        );
      } catch (_) {
        _engines.remove(sat.noradId);
      }
    }
    final stale = _engines.keys.where((id) => !ids.contains(id)).toList();
    for (final id in stale) {
      _engines.remove(id);
      _orbitsTeme.remove(id);
      changed = true;
    }
    if (changed) _orbitsComputedAt = null;
  }

  static double _periodMinutes(String line2) {
    if (line2.length >= 63) {
      final n = double.tryParse(line2.substring(52, 63).trim());
      if (n != null && n > 0) return 1440 / n;
    }
    return 95;
  }

  void _refreshOrbits(DateTime now) {
    final at = _orbitsComputedAt;
    if (at != null && now.difference(at).inSeconds.abs() < 120) return;
    _orbitsComputedAt = now;
    _orbitsTeme.clear();
    for (final entry in _engines.entries) {
      final period = entry.value.periodMinutes;
      final samples = period > 300 ? 240 : 160;
      final pts = <_V3>[];
      try {
        for (var i = 0; i <= samples; i++) {
          final t = now.add(
            Duration(milliseconds: (period * 60000 * i / samples).round()),
          );
          final p = entry.value.engine.propagate(t).position;
          pts.add(_V3(p.x, p.y, p.z));
        }
      } catch (_) {
        continue;
      }
      _orbitsTeme[entry.key] = pts;
    }
  }

  _GlobeScene _buildScene(Size size) {
    final now = DateTime.now().toUtc();
    _syncEngines();
    _refreshOrbits(now);
    final rot = _Rot.fromGmst(_gmstRad(now));

    final sats = <_SatGlyph>[];
    var maxAltKm = 0.0;
    for (final sat in widget.satellites) {
      final entry = _engines[sat.noradId];
      if (entry == null) continue;
      _V3 p;
      try {
        final s = entry.engine.propagate(now).position;
        p = rot.apply(_V3(s.x, s.y, s.z));
      } catch (_) {
        continue;
      }
      final altKm = p.length - _earthRadiusKm;
      if (altKm < 3000) maxAltKm = math.max(maxAltKm, altKm);
      final look = widget.positions[sat.noradId];
      final visible =
          look != null && look.elevationDeg >= widget.minElevationDeg;
      final orbit = _orbitsTeme[sat.noradId];
      sats.add(
        _SatGlyph(
          id: sat.noradId,
          name: sat.name,
          position: p,
          orbit: orbit == null
              ? const []
              : [for (final o in orbit) rot.apply(o)],
          visible: visible,
          selected: sat.noradId == widget.selectedId,
        ),
      );
    }

    _V3? observer;
    final lat = widget.observerLatDeg;
    final lon = widget.observerLonDeg;
    if (lat != null && lon != null) {
      observer = _V3.fromLatLon(lat, lon) * _earthRadiusKm;
    }

    final coneTopKm = (maxAltKm <= 0 ? 1000.0 : maxAltKm).clamp(500.0, 3000.0) *
        1.05;
    final fitRadiusKm = _earthRadiusKm + 1500;
    final halfSize = math.min(size.width, size.height) / 2 - 6;
    final pxPerKm = math.max(1.0, halfSize) / fitRadiusKm * _zoom;
    final view = _GlobeView(
      centerLatDeg: _centerLatDeg,
      centerLonDeg: _centerLonDeg,
      center: size.center(Offset.zero),
      pxPerKm: pxPerKm,
    );

    // Draw selected/visible birds last so they sit on top.
    sats.sort((a, b) => a.rank.compareTo(b.rank));

    return _GlobeScene(
      view: view,
      land: _land ?? const [],
      satellites: sats,
      observer: observer,
      minElevationDeg: widget.minElevationDeg,
      coneTopKm: coneTopKm,
    );
  }

  // --- Gestures -------------------------------------------------------------

  double get _globeRadiusPx {
    final s = _scene;
    if (s == null) return 100;
    return math.max(20.0, _earthRadiusKm * s.view.pxPerKm);
  }

  void _onScaleStart(ScaleStartDetails d) {
    _lastFocal = d.focalPoint;
    _downLocal = d.localFocalPoint;
    _startZoom = _zoom;
    _moved = 0;
    _maxPointers = d.pointerCount;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    _maxPointers = math.max(_maxPointers, d.pointerCount);
    final delta = d.focalPoint - _lastFocal;
    _lastFocal = d.focalPoint;
    _moved += delta.distance;
    if (d.scale != 1.0) _moved += 10;
    final r = _globeRadiusPx;
    setState(() {
      _userMovedView = true;
      if (d.scale != 1.0) _zoom = (_startZoom * d.scale).clamp(0.4, 8.0);
      _centerLonDeg -= delta.dx / r * 180 / math.pi;
      _centerLatDeg = (_centerLatDeg + delta.dy / r * 180 / math.pi).clamp(
        -89.0,
        89.0,
      );
      _centerLonDeg = ((_centerLonDeg + 540) % 360) - 180;
    });
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (_moved > 6 || _maxPointers > 1) return;
    final now = DateTime.now();
    final hit = _hitTest(_downLocal);
    final isDoubleTap =
        now.difference(_lastTap).inMilliseconds < 400 && hit == _lastTapId;
    // A third click starts a new sequence rather than another double.
    _lastTap = isDoubleTap ? DateTime.fromMillisecondsSinceEpoch(0) : now;
    _lastTapId = hit;
    if (hit != null) {
      if (isDoubleTap) {
        widget.onSatelliteDoubleTap?.call(hit);
      } else {
        widget.onSatelliteTap?.call(hit);
      }
    } else if (isDoubleTap) {
      _resetView();
    }
  }

  int? _hitTest(Offset local) {
    final s = _scene;
    if (s == null) return null;
    int? best;
    var bestDist = 14.0;
    for (final sat in s.satellites) {
      if (s.view.hidden(sat.position)) continue;
      final d = (s.view.project(sat.position) - local).distance;
      if (d <= bestDist) {
        bestDist = d;
        best = sat.id;
      }
    }
    return best;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (e) {
      final dy = (e as PointerScrollEvent).scrollDelta.dy;
      setState(() {
        _userMovedView = true;
        _zoom = (_zoom * math.exp(-dy / 400)).clamp(0.4, 8.0);
      });
    });
  }

  void _resetView() {
    setState(() {
      _zoom = 1;
      _userMovedView = false;
      if (widget.observerLatDeg != null) {
        _centerOnObserver();
      } else {
        _centerLatDeg = 20;
        _centerLonDeg = 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final scene = _buildScene(size);
          _scene = scene;
          return Stack(
            children: [
              Positioned.fill(
                child: Listener(
                  onPointerSignal: _onPointerSignal,
                  child: RawGestureDetector(
                    behavior: HitTestBehavior.opaque,
                    gestures: {
                      _ImmediateScaleGestureRecognizer:
                          GestureRecognizerFactoryWithHandlers<
                            _ImmediateScaleGestureRecognizer
                          >(
                            () => _ImmediateScaleGestureRecognizer(
                              debugOwner: this,
                            ),
                            (r) => r
                              ..onStart = _onScaleStart
                              ..onUpdate = _onScaleUpdate
                              ..onEnd = _onScaleEnd,
                          ),
                    },
                    child: MouseRegion(
                      cursor: SystemMouseCursors.grab,
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _GlobePainter(scene),
                          size: size,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(left: 8, top: 6, child: _buildLegend()),
              Positioned(
                right: 4,
                bottom: 4,
                child: IconButton(
                  tooltip: widget.observerLatDeg != null
                      ? 'Center on my location'
                      : 'Reset view',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  color: Colors.white70,
                  onPressed: _resetView,
                  icon: Icon(
                    widget.observerLatDeg != null
                        ? Icons.my_location
                        : Icons.public,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLegend() {
    const style = TextStyle(fontSize: 10, color: Colors.white70);
    Widget dot(Color c) => Container(
      width: 8,
      height: 8,
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
    );
    final threshold = widget.minElevationDeg.round();
    return IgnorePointer(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          dot(_GlobePainter.visibleColor),
          Text(
            widget.observerLatDeg != null
                ? 'Visible (≥$threshold°)'
                : 'Visible (no location)',
            style: style,
          ),
          const SizedBox(width: 10),
          dot(_GlobePainter.satColor),
          const Text('Below', style: style),
        ],
      ),
    );
  }
}

/// A scale recognizer that claims the gesture immediately, so dragging the
/// globe rotates it instead of swiping the enclosing tab view.
class _ImmediateScaleGestureRecognizer extends ScaleGestureRecognizer {
  _ImmediateScaleGestureRecognizer({super.debugOwner});

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolvePointer(event.pointer, GestureDisposition.accepted);
  }
}

class _EngineEntry {
  final String key;
  final so.Sgp4Engine engine;
  final double periodMinutes;
  _EngineEntry(this.key, this.engine, this.periodMinutes);
}

/// Greenwich Mean Sidereal Time (IAU-1982) in radians, treating UTC as UT1.
double _gmstRad(DateTime utc) {
  final jd = utc.millisecondsSinceEpoch / 86400000.0 + 2440587.5;
  final t = (jd - 2451545.0) / 36525.0;
  var seconds =
      67310.54841 +
      (876600.0 * 3600.0 + 8640184.812866) * t +
      0.093104 * t * t -
      6.2e-6 * t * t * t;
  seconds %= 86400;
  if (seconds < 0) seconds += 86400;
  return seconds / 86400 * 2 * math.pi;
}

class _V3 {
  final double x;
  final double y;
  final double z;
  const _V3(this.x, this.y, this.z);

  factory _V3.fromLatLon(double latDeg, double lonDeg) {
    final lat = latDeg * math.pi / 180;
    final lon = lonDeg * math.pi / 180;
    return _V3(
      math.cos(lat) * math.cos(lon),
      math.cos(lat) * math.sin(lon),
      math.sin(lat),
    );
  }

  _V3 operator +(_V3 o) => _V3(x + o.x, y + o.y, z + o.z);
  _V3 operator -(_V3 o) => _V3(x - o.x, y - o.y, z - o.z);
  _V3 operator *(double k) => _V3(x * k, y * k, z * k);
  double dot(_V3 o) => x * o.x + y * o.y + z * o.z;
  _V3 cross(_V3 o) =>
      _V3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(x * x + y * y + z * z);
}

/// Rotation from the TEME (quasi-inertial) frame into Earth-fixed axes.
class _Rot {
  final double c;
  final double s;
  const _Rot(this.c, this.s);
  factory _Rot.fromGmst(double g) => _Rot(math.cos(g), math.sin(g));
  _V3 apply(_V3 p) => _V3(c * p.x + s * p.y, -s * p.x + c * p.y, p.z);
}

/// Orthographic camera looking at the Earth's centre from above
/// ([centerLatDeg], [centerLonDeg]).
class _GlobeView {
  final Offset center;
  final double pxPerKm;
  late final _V3 east;
  late final _V3 north;
  late final _V3 forward;

  _GlobeView({
    required double centerLatDeg,
    required double centerLonDeg,
    required this.center,
    required this.pxPerKm,
  }) {
    final lat = centerLatDeg * math.pi / 180;
    final lon = centerLonDeg * math.pi / 180;
    forward = _V3.fromLatLon(centerLatDeg, centerLonDeg);
    east = _V3(-math.sin(lon), math.cos(lon), 0);
    north = _V3(
      -math.sin(lat) * math.cos(lon),
      -math.sin(lat) * math.sin(lon),
      math.cos(lat),
    );
  }

  double get radiusPx => _earthRadiusKm * pxPerKm;

  Offset project(_V3 p) =>
      Offset(center.dx + p.dot(east) * pxPerKm, center.dy - p.dot(north) * pxPerKm);

  /// True when [p] (km, Earth-fixed) is behind the Earth from the viewer.
  bool hidden(_V3 p) {
    if (p.dot(forward) >= 0) return false;
    final x = p.dot(east);
    final y = p.dot(north);
    return x * x + y * y < _earthRadiusKm * _earthRadiusKm;
  }
}

class _SatGlyph {
  final int id;
  final String name;
  final _V3 position;
  final List<_V3> orbit;
  final bool visible;
  final bool selected;

  const _SatGlyph({
    required this.id,
    required this.name,
    required this.position,
    required this.orbit,
    required this.visible,
    required this.selected,
  });

  int get rank => (visible ? 1 : 0) + (selected ? 2 : 0);
}

/// A visible run of a coastline ring between its limb entry and exit points.
class _LimbRun {
  final double entryAngle;
  double exitAngle = 0;
  final List<Offset> points = [];
  _LimbRun(this.entryAngle);
}

class _GlobeScene {
  final _GlobeView view;
  final List<Float64List> land;
  final List<_SatGlyph> satellites;
  final _V3? observer;
  final double minElevationDeg;
  final double coneTopKm;

  const _GlobeScene({
    required this.view,
    required this.land,
    required this.satellites,
    required this.observer,
    required this.minElevationDeg,
    required this.coneTopKm,
  });
}

class _GlobePainter extends CustomPainter {
  static const Color spaceColor = Color(0xFF070B18);
  static const Color oceanLight = Color(0xFF2B5C8F);
  static const Color oceanDark = Color(0xFF0C223D);
  static const Color landColor = Color(0xFF3F7A4A);
  static const Color coastColor = Color(0xFF8FC79A);
  static const Color satColor = Color(0xFF90CAF9);
  static const Color visibleColor = Color(0xFF69F0AE);
  static const Color selectedColor = Color(0xFFFFC107);
  static const Color observerColor = Color(0xFFFF7043);

  final _GlobeScene scene;
  _GlobePainter(this.scene);

  @override
  void paint(Canvas canvas, Size size) {
    final view = scene.view;
    canvas.drawRect(Offset.zero & size, Paint()..color = spaceColor);

    final r = view.radiusPx;
    final c = view.center;

    // Atmosphere glow and ocean.
    canvas.drawCircle(
      c,
      r * 1.04,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0x5542A5F5),
            const Color(0x0042A5F5),
          ],
          stops: const [0.93, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: r * 1.04)),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          radius: 1.1,
          colors: const [oceanLight, oceanDark],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );

    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
    _paintLand(canvas);
    _paintGraticule(canvas);
    canvas.restore();

    _paintCone(canvas);
    for (final sat in scene.satellites) {
      _paintOrbit(canvas, sat);
    }
    _paintObserver(canvas);
    for (final sat in scene.satellites) {
      _paintSatellite(canvas, sat);
    }
  }

  /// Fills land clipped exactly to the visible hemisphere. Each ring (counter-
  /// clockwise, land on the left) is split into visible runs that enter and
  /// leave through the limb; runs are joined by walking counter-clockwise
  /// along the limb to the next entry point, which keeps the land on the left.
  void _paintLand(Canvas canvas) {
    final view = scene.view;
    final fill = Paint()..color = landColor;
    final stroke = Paint()
      ..color = coastColor.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;
    final e = view.east;
    final n = view.north;
    final f = view.forward;
    final r = view.radiusPx;
    final cx = view.center.dx;
    final cy = view.center.dy;
    Offset toScreen(double u, double v) => Offset(cx + u * r, cy - v * r);

    final landPath = Path();
    final coastPath = Path();

    for (final ring in scene.land) {
      final count = ring.length ~/ 3;
      if (count < 3) continue;
      final us = Float64List(count);
      final vs = Float64List(count);
      final ds = Float64List(count);
      var visibleCount = 0;
      var hiddenIndex = -1;
      for (var i = 0; i < count; i++) {
        final x = ring[i * 3], y = ring[i * 3 + 1], z = ring[i * 3 + 2];
        us[i] = x * e.x + y * e.y + z * e.z;
        vs[i] = x * n.x + y * n.y + z * n.z;
        ds[i] = x * f.x + y * f.y + z * f.z;
        if (ds[i] >= 0) {
          visibleCount++;
        } else if (hiddenIndex < 0) {
          hiddenIndex = i;
        }
      }
      if (visibleCount == 0) continue;

      // Coastline strokes: visible edges, skipping the data's artificial seams
      // (the ±180° antimeridian cut and Antarctica's closure via the pole).
      for (var i = 0; i < count; i++) {
        final j = (i + 1) % count;
        if (ds[i] < 0 || ds[j] < 0) continue;
        final xi = ring[i * 3], yi = ring[i * 3 + 1], zi = ring[i * 3 + 2];
        final xj = ring[j * 3], yj = ring[j * 3 + 1], zj = ring[j * 3 + 2];
        final onAntimeridian =
            xi < 0 && xj < 0 && yi.abs() < 1e-4 && yj.abs() < 1e-4;
        final atPole = zi.abs() > 0.9999 && zj.abs() > 0.9999;
        if (onAntimeridian || atPole) continue;
        final a = toScreen(us[i], vs[i]);
        final b = toScreen(us[j], vs[j]);
        coastPath
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy);
      }

      if (hiddenIndex < 0) {
        final poly = [for (var i = 0; i < count; i++) toScreen(us[i], vs[i])];
        landPath.addPolygon(poly, true);
        continue;
      }

      // Split into visible runs, starting on a hidden vertex so no run wraps.
      final runs = <_LimbRun>[];
      _LimbRun? current;
      for (var k = 0; k < count; k++) {
        final i = (hiddenIndex + k) % count;
        final j = (i + 1) % count;
        final di = ds[i];
        final dj = ds[j];
        if (di < 0 && dj < 0) continue;
        if (di >= 0 && dj >= 0) {
          current?.points.add(toScreen(us[j], vs[j]));
          continue;
        }
        // Edge crosses the limb: interpolate to depth 0, then snap to it.
        final t = di / (di - dj);
        var cu = us[i] + t * (us[j] - us[i]);
        var cv = vs[i] + t * (vs[j] - vs[i]);
        final len = math.sqrt(cu * cu + cv * cv);
        if (len > 1e-12) {
          cu /= len;
          cv /= len;
        }
        final angle = math.atan2(cv, cu);
        if (di < 0) {
          current = _LimbRun(angle)
            ..points.add(toScreen(cu, cv))
            ..points.add(toScreen(us[j], vs[j]));
        } else if (current != null) {
          current.points.add(toScreen(cu, cv));
          current.exitAngle = angle;
          runs.add(current);
          current = null;
        }
      }
      if (runs.isEmpty) continue;

      final used = List<bool>.filled(runs.length, false);
      for (var s = 0; s < runs.length; s++) {
        if (used[s]) continue;
        var cur = s;
        landPath.moveTo(runs[s].points.first.dx, runs[s].points.first.dy);
        // Bounded: each run is visited at most once per polygon.
        for (var guard = 0; guard <= runs.length; guard++) {
          used[cur] = true;
          for (final p in runs[cur].points) {
            landPath.lineTo(p.dx, p.dy);
          }
          final from = runs[cur].exitAngle;
          var next = -1;
          var bestDelta = double.infinity;
          for (var t = 0; t < runs.length; t++) {
            if (used[t] && t != s) continue;
            var delta = (runs[t].entryAngle - from) % (2 * math.pi);
            if (delta < 0) delta += 2 * math.pi;
            if (delta < bestDelta) {
              bestDelta = delta;
              next = t;
            }
          }
          if (next < 0) break;
          // Counter-clockwise limb arc from the exit to the next entry.
          final steps = math.max(1, (bestDelta / (math.pi / 60)).ceil());
          for (var k = 1; k <= steps; k++) {
            final a = from + bestDelta * k / steps;
            final p = toScreen(math.cos(a), math.sin(a));
            landPath.lineTo(p.dx, p.dy);
          }
          if (next == s) break;
          cur = next;
        }
        landPath.close();
      }
    }

    canvas.drawPath(landPath, fill);
    canvas.drawPath(coastPath, stroke);

    // Soft shading toward the limb for a 3D look.
    canvas.drawCircle(
      view.center,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          radius: 1.15,
          colors: const [Color(0x00000000), Color(0x66000000)],
          stops: const [0.55, 1.0],
        ).createShader(Rect.fromCircle(center: view.center, radius: r)),
    );
  }

  void _paintGraticule(Canvas canvas) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    final path = Path();
    for (var lon = -180; lon < 180; lon += 30) {
      _addSurfaceLine(path, [
        for (var lat = -90; lat <= 90; lat += 5) _V3.fromLatLon(lat * 1.0, lon * 1.0),
      ]);
    }
    for (var lat = -60; lat <= 60; lat += 30) {
      _addSurfaceLine(path, [
        for (var lon = -180; lon <= 180; lon += 5) _V3.fromLatLon(lat * 1.0, lon * 1.0),
      ]);
    }
    canvas.drawPath(path, paint);
  }

  void _addSurfaceLine(Path path, List<_V3> unitPoints) {
    final view = scene.view;
    var pen = false;
    for (final u in unitPoints) {
      if (u.dot(view.forward) < 0) {
        pen = false;
        continue;
      }
      final o = view.project(u * _earthRadiusKm);
      if (pen) {
        path.lineTo(o.dx, o.dy);
      } else {
        path.moveTo(o.dx, o.dy);
        pen = true;
      }
    }
  }

  void _paintCone(Canvas canvas) {
    final obs = scene.observer;
    if (obs == null) return;
    final view = scene.view;

    final up = obs * (1 / obs.length);
    final lon = math.atan2(obs.y, obs.x);
    final east = _V3(-math.sin(lon), math.cos(lon), 0);
    final north = _V3(
      -up.z * math.cos(lon),
      -up.z * math.sin(lon),
      math.sqrt(math.max(0, 1 - up.z * up.z)),
    );

    final el = scene.minElevationDeg.clamp(0.0, 89.0) * math.pi / 180;
    final re = _earthRadiusKm;
    final rTop = re + scene.coneTopKm;
    final range =
        -re * math.sin(el) +
        math.sqrt(re * re * math.sin(el) * math.sin(el) + rTop * rTop - re * re);

    const steps = 72;
    final rim = <_V3>[];
    for (var i = 0; i < steps; i++) {
      final az = i * 2 * math.pi / steps;
      final dir =
          (east * (math.cos(el) * math.sin(az))) +
          (north * (math.cos(el) * math.cos(az))) +
          (up * math.sin(el));
      rim.add(obs + dir * range);
    }

    final apex = view.project(obs);
    final fill = Paint()
      ..color = _GlobePainter.visibleColor.withValues(alpha: 0.10)
      ..style = PaintingStyle.fill;
    final edge = Paint()
      ..color = _GlobePainter.visibleColor.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final ribs = Paint()
      ..color = _GlobePainter.visibleColor.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;

    // Light from the upper-left, toward the viewer, to shade cone facets.
    final light = (view.east * -0.5) + (view.north * 0.7) + (view.forward * 0.5);
    final lightN = light * (1 / light.length);

    // The apex sits on the surface; when it faces away from the viewer only
    // the unobstructed part of the rim is drawn.
    final apexVisible = obs.dot(view.forward) >= 0;
    final rimPath = Path();
    final ribPath = Path();
    for (var i = 0; i < steps; i++) {
      final a = rim[i];
      final b = rim[(i + 1) % steps];
      final pa = view.project(a);
      final pb = view.project(b);
      if (apexVisible && !view.hidden((obs + a + b) * (1 / 3))) {
        final normal = (a - obs).cross(b - obs);
        final shade = (normal.dot(lightN) / normal.length).abs();
        fill.color = _GlobePainter.visibleColor.withValues(
          alpha: 0.04 + 0.2 * shade,
        );
        canvas.drawPath(
          Path()
            ..moveTo(apex.dx, apex.dy)
            ..lineTo(pa.dx, pa.dy)
            ..lineTo(pb.dx, pb.dy)
            ..close(),
          fill,
        );
      }
      if (!view.hidden(a) && !view.hidden(b)) {
        rimPath
          ..moveTo(pa.dx, pa.dy)
          ..lineTo(pb.dx, pb.dy);
      }
      if (apexVisible &&
          i % 6 == 0 &&
          !view.hidden(a) &&
          !view.hidden((obs + a) * 0.5)) {
        ribPath
          ..moveTo(apex.dx, apex.dy)
          ..lineTo(pa.dx, pa.dy);
      }
    }
    canvas.drawPath(ribPath, ribs);
    canvas.drawPath(rimPath, edge);
  }

  void _paintOrbit(Canvas canvas, _SatGlyph sat) {
    if (sat.orbit.length < 2) return;
    final view = scene.view;
    final color = sat.visible
        ? visibleColor
        : (sat.selected ? selectedColor : satColor);
    final paint = Paint()
      ..color = color.withValues(
        alpha: sat.visible || sat.selected ? 0.85 : 0.28,
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = sat.visible ? 2.0 : (sat.selected ? 1.6 : 0.9);
    final path = Path();
    var pen = false;
    for (final p in sat.orbit) {
      if (view.hidden(p)) {
        pen = false;
        continue;
      }
      final o = view.project(p);
      if (pen) {
        path.lineTo(o.dx, o.dy);
      } else {
        path.moveTo(o.dx, o.dy);
        pen = true;
      }
    }
    canvas.drawPath(path, paint);
  }

  void _paintObserver(Canvas canvas) {
    final obs = scene.observer;
    if (obs == null || obs.dot(scene.view.forward) < 0) {
      return;
    }
    final o = scene.view.project(obs);
    canvas.drawCircle(o, 5, Paint()..color = Colors.white);
    canvas.drawCircle(o, 3.5, Paint()..color = observerColor);
  }

  void _paintSatellite(Canvas canvas, _SatGlyph sat) {
    final view = scene.view;
    if (view.hidden(sat.position)) return;
    final o = view.project(sat.position);
    final color = sat.visible
        ? visibleColor
        : (sat.selected ? selectedColor : satColor);
    final radius = sat.visible ? 5.0 : (sat.selected ? 4.5 : 3.0);
    if (sat.visible) {
      canvas.drawCircle(o, radius + 4, Paint()..color = color.withValues(alpha: 0.25));
    }
    if (sat.selected) {
      canvas.drawCircle(
        o,
        radius + 3,
        Paint()
          ..color = selectedColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
    canvas.drawCircle(o, radius, Paint()..color = color);

    final tp = TextPainter(
      text: TextSpan(
        text: sat.name,
        style: TextStyle(
          fontSize: sat.visible ? 11.5 : 10,
          fontWeight: sat.visible || sat.selected
              ? FontWeight.bold
              : FontWeight.normal,
          color: sat.visible || sat.selected
              ? color
              : Colors.white.withValues(alpha: 0.6),
          shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 140);
    tp.paint(canvas, o + Offset(radius + 3, -tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _GlobePainter oldDelegate) => true;
}
