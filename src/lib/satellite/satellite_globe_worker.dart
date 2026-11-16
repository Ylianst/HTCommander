// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:satellite_observer/satellite_observer.dart' as so;

import '../services/decoder_worker.dart';
import 'satellite_models.dart';

/// Earth-fixed kilometres: current position followed by the sampled orbit.
class GlobeOrbit {
  const GlobeOrbit(this.points, this.orbitEpoch);
  final Float64List points;
  final DateTime orbitEpoch;
}

typedef GlobeSnapshot = Map<int, GlobeOrbit>;
typedef GlobeSnapshotLoader =
    Future<GlobeSnapshot> Function(List<SatelliteTle> satellites, DateTime utc);

/// One ordered request at a time; the globe coalesces updates while busy.
/// Engines and inertial orbit samples remain on the worker between snapshots.
class SatelliteGlobeWorker {
  SatelliteGlobeWorker() {
    _worker = DecoderWorker(
      name: 'satellite-globe',
      factory: _createProcessor,
      maxPendingCommands: 2,
      onEvent: (event) {
        final pending = _pending;
        _pending = null;
        pending?.complete(event as GlobeSnapshot);
      },
      onError: (error, stack) {
        final pending = _pending;
        _pending = null;
        _key = null;
        pending?.completeError(error, stack);
      },
    );
  }

  late final DecoderWorker _worker;
  Completer<GlobeSnapshot>? _pending;
  String? _key;
  Future<GlobeSnapshot>? _cached;
  bool _disposed = false;
  bool _started = false;

  Future<GlobeSnapshot> snapshot(List<SatelliteTle> satellites, DateTime utc) {
    if (_disposed) return Future.error(StateError('Globe worker disposed'));
    final key =
        '${utc.microsecondsSinceEpoch}\n${satellites.map((s) => '${s.noradId}\n${s.line1}\n${s.line2}').join('\n')}';
    if (_key == key) return _cached!;
    if (_pending != null) {
      return Future.error(StateError('Globe snapshot already in flight'));
    }
    _key = key;
    if (satellites.isEmpty && !_started) {
      return _cached = Future<GlobeSnapshot>.value({});
    }
    _started = true;
    final pending = Completer<GlobeSnapshot>();
    _pending = pending;
    _cached = pending.future;
    _worker.add((satellites, utc));
    return pending.future;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _worker.dispose();
    _pending?.completeError(StateError('Globe worker disposed'));
    _pending = null;
    _cached = null;
  }
}

DecoderProcessor _createProcessor(
  Object? config,
  void Function(Object?) emit,
) => _GlobeProcessor(emit);

class _OrbitEntry {
  _OrbitEntry(this.tle)
    : engine = so.Sgp4Engine(
        so.GpElements.fromTle(tle.line1, tle.line2, name: tle.name),
      );
  final SatelliteTle tle;
  final so.Sgp4Engine engine;
  DateTime? epoch;
  Float64List? orbit;
  DateTime? snapshotUtc;
  GlobeOrbit? snapshot;
}

class _GlobeProcessor implements DecoderProcessor {
  _GlobeProcessor(this.emit);
  final void Function(Object?) emit;
  final Map<int, _OrbitEntry> _entries = {};

  @override
  Future<void> process(Object? command) async {
    final (satellites, utc) = command as (List<SatelliteTle>, DateTime);
    final ids = satellites.map((s) => s.noradId).toSet();
    _entries.removeWhere((id, _) => !ids.contains(id));
    final result = <int, GlobeOrbit>{};
    final angle = _gmstRad(utc);
    final c = math.cos(angle), s = math.sin(angle);
    for (final tle in satellites) {
      try {
        var entry = _entries[tle.noradId];
        if (entry == null ||
            entry.tle.line1 != tle.line1 ||
            entry.tle.line2 != tle.line2) {
          entry = _OrbitEntry(tle);
          _entries[tle.noradId] = entry;
        }
        if (entry.snapshotUtc == utc) {
          result[tle.noradId] = entry.snapshot!;
          continue;
        }
        if (entry.epoch == null ||
            utc.difference(entry.epoch!).abs() >=
                const Duration(seconds: 120)) {
          final n = tle.line2.length >= 63
              ? double.tryParse(tle.line2.substring(52, 63).trim())
              : null;
          final period = n != null && n > 0 ? 1440 / n : 95.0;
          final samples = period > 300 ? 240 : 160;
          final orbit = Float64List((samples + 1) * 3);
          for (var i = 0; i <= samples; i++) {
            final p = entry.engine
                .propagate(
                  utc.add(
                    Duration(
                      milliseconds: (period * 60000 * i / samples).round(),
                    ),
                  ),
                )
                .position;
            orbit[i * 3] = p.x;
            orbit[i * 3 + 1] = p.y;
            orbit[i * 3 + 2] = p.z;
            // Web uses the ordered local fallback; yield within long orbits.
            if (!DecoderWorker.usesIsolates && i % 32 == 31) {
              await Future<void>.delayed(Duration.zero);
            }
          }
          entry.orbit = orbit;
          entry.epoch = utc;
        }
        final p = entry.engine.propagate(utc).position;
        final orbit = entry.orbit!;
        final points = Float64List(orbit.length + 3);
        points[0] = c * p.x + s * p.y;
        points[1] = -s * p.x + c * p.y;
        points[2] = p.z;
        for (var i = 0; i < orbit.length; i += 3) {
          points[i + 3] = c * orbit[i] + s * orbit[i + 1];
          points[i + 4] = -s * orbit[i] + c * orbit[i + 1];
          points[i + 5] = orbit[i + 2];
        }
        final snapshot = GlobeOrbit(points, entry.epoch!);
        entry.snapshotUtc = utc;
        entry.snapshot = snapshot;
        result[tle.noradId] = snapshot;
      } catch (_) {
        // A bad TLE must not hide the rest of the catalog.
        _entries.remove(tle.noradId);
      }
    }
    emit(result);
  }

  @override
  void dispose() => _entries.clear();
}

/// Greenwich Mean Sidereal Time (IAU-1982), treating UTC as UT1.
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
