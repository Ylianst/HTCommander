// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
// ignore_for_file: implementation_imports
import 'dart:typed_data';

import 'package:satellite_observer/satellite_observer.dart' as so;
import 'package:satellite_observer/src/passes/pass_finder.dart' show findPasses;

import 'native_satellite.dart';
import 'satellite_coefficients.dart';

/// Batched SGP4/SDP4, retaining the package's original initialiser and pass
/// refinement. Native is the default on supported platforms; pass
/// useNative:false for the unmodified Dart engine.
/// One instance belongs to one worker/observer; never share native handles.
class SatelliteComputation implements so.PropagationEngine {
  SatelliteComputation(so.GpElements elements, {bool useNative = true})
    : epoch = elements.epoch.toUtc() {
    // Element parsing/initialisation errors are deliberately not swallowed.
    if (useNative && NativeSatellite.supported) {
      _native = NativeSatellite.create(satelliteCoefficients(elements));
    }
    if (_native == null) _reference = so.Sgp4Engine(elements);
  }

  @override
  final DateTime epoch;
  NativeSatellite? _native;
  so.Sgp4Engine? _reference;
  final Map<int, Object> _prefetched = {};
  so.EciState? _last;
  bool _disposed = false;

  bool get isNative => _native != null;

  void _checkAlive() {
    if (_disposed) throw StateError('Satellite engine disposed');
  }

  @override
  so.EciState propagate(DateTime utc) {
    _checkAlive();
    final cached = _prefetched[utc.microsecondsSinceEpoch];
    if (cached is so.EciState) return cached;
    if (cached is so.PropagationException) throw cached;
    if (_native == null) return _reference!.propagate(utc);
    if (_last?.utc.isAtSameMomentAs(utc) == true) return _last!;
    return _last = propagateBatch([utc]).single;
  }

  List<so.EciState> propagateBatch(List<DateTime> times) {
    _checkAlive();
    if (_native == null) {
      return [for (final time in times) _reference!.propagate(time)];
    }
    final rows = _calculate(times);
    return [for (var i = 0; i < times.length; i++) _state(rows, i, times[i])];
  }

  Float64List _calculate(List<DateTime> times) {
    final minutes = Float64List(times.length);
    for (var i = 0; i < times.length; i++) {
      minutes[i] = times[i].toUtc().difference(epoch).inMicroseconds / 6.0e7;
    }
    return _native!.propagate(minutes);
  }

  so.EciState _state(Float64List rows, int index, DateTime utc) {
    final i = index * 7;
    _checkStatus(rows[i].toInt(), utc);
    return so.EciState(
      position: so.Vector3(rows[i + 1], rows[i + 2], rows[i + 3]),
      velocity: so.Vector3(rows[i + 4], rows[i + 5], rows[i + 6]),
      utc: utc.toUtc(),
    );
  }

  void _checkStatus(int code, DateTime utc) {
    if (code != 0) {
      if (code == 100) {
        throw const so.GeometryException(
          'Degenerate look geometry: zero or non-finite slant range '
          '(satellite coincides with observer)',
        );
      }
      if (code == so.PropagationException.nonFiniteOutputCode) {
        throw so.PropagationException(
          code,
          'SGP4 produced a non-finite position or velocity',
        );
      }
      final minutes = utc.toUtc().difference(epoch).inMicroseconds / 6.0e7;
      throw so.PropagationException(
        code,
        'SGP4 propagation failed at tsince=$minutes min',
      );
    }
  }

  /// Prefetch only the expensive fixed grid; the original package still owns
  /// every crossing/peak decision and all adaptive refinement evaluations.
  /// Errors stay at their sample index, so a failed coarse sample surfaces
  /// when the package reaches it, not at a later prefetch/refinement boundary.
  void prefetch(List<DateTime> times) {
    _checkAlive();
    if (!isNative) return;
    clearPrefetch();
    final rows = _calculate(times);
    for (var i = 0; i < times.length; i++) {
      try {
        _prefetched[times[i].microsecondsSinceEpoch] = _state(
          rows,
          i,
          times[i],
        );
      } on so.PropagationException catch (error) {
        _prefetched[times[i].microsecondsSinceEpoch] = error;
      }
    }
  }

  void clearPrefetch() => _prefetched.clear();

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    clearPrefetch();
    _native?.dispose();
    _native = null;
  }
}

/// Observer facade with native propagation/topocentric coarse-grid batching.
/// Package geometry remains the source of truth for scalar/refined samples;
/// threshold validation, UTC handling, endpoint inclusion and fully-bracketed
/// pass policy remain unchanged.
class SatelliteObservation {
  SatelliteObservation({
    required so.GpElements elements,
    required so.Observer observer,
    bool useNative = true,
  }) : engine = SatelliteComputation(elements, useNative: useNative),
       _observer = observer {
    reference = so.SatelliteObserver(
      elements: elements,
      observer: observer,
      engine: engine,
    );
  }

  final SatelliteComputation engine;
  final so.Observer _observer;
  late final so.SatelliteObserver reference;
  bool get isNative => engine.isNative;
  so.LookAngle lookAngleAt(DateTime utc) => reference.lookAngleAt(utc);
  so.SubSatellitePoint subPointAt(DateTime utc) => reference.subPointAt(utc);

  List<so.Pass> passes({
    required DateTime from,
    required DateTime to,
    double minElevationDeg = 10,
    Duration sampleStep = const Duration(seconds: 30),
  }) {
    // Leave the reference path and invalid-input errors in the original facade.
    if (!isNative ||
        !from.isBefore(to) ||
        sampleStep <= Duration.zero ||
        !(minElevationDeg >= 0 && minElevationDeg < 90)) {
      return reference.passes(
        from: from,
        to: to,
        minElevationDeg: minElevationDeg,
        sampleStep: sampleStep,
      );
    }
    engine._checkAlive();
    engine.clearPrefetch();
    final rows = engine._native!.lookGrid(
      epochUs: engine.epoch.microsecondsSinceEpoch,
      fromUs: from.microsecondsSinceEpoch,
      toUs: to.microsecondsSinceEpoch,
      stepUs: sampleStep.inMicroseconds,
      latitudeDeg: _observer.latitudeDeg,
      longitudeDeg: _observer.longitudeDeg,
      altitudeMeters: _observer.altitudeMeters,
    );
    var coarseIndex = 0;
    try {
      // satellite_observer 1.0.1 evaluates its entire fixed grid first, in
      // order, then performs every crossing/peak/event refinement. Feed that
      // initial phase directly from flat native rows, without a DateTime
      // prepass, EciState/Vector3 graph, hash cache or duplicate transforms.
      // All subsequent evaluations go through the original scalar geometry.
      return findPasses(
        from: from,
        to: to,
        minElevationDeg: minElevationDeg,
        sampleStep: sampleStep,
        lookAngleAt: (utc) {
          if (coarseIndex * 5 >= rows.length) return lookAngleAt(utc);
          final i = coarseIndex++ * 5;
          engine._checkStatus(rows[i].toInt(), utc);
          return so.LookAngle(
            azimuthDeg: rows[i + 1],
            elevationDeg: rows[i + 2],
            rangeKm: rows[i + 3],
            rangeRateKmS: rows[i + 4],
            utc: utc,
          );
        },
      );
    } finally {
      engine.clearPrefetch();
    }
  }

  void dispose() => engine.dispose();
}
