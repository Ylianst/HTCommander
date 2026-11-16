// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:async';

import 'package:satellite_observer/satellite_observer.dart' as so;

import '../services/decoder_worker.dart';
import 'satellite_computation.dart';
import 'satellite_models.dart';

/// Shares bounded, five-minute pass snapshots between catalog, detail and radio
/// consumers. Propagators live in the worker, never in the tracking loop.
class SatellitePredictor {
  SatellitePredictor({
    required so.Observer observer,
    required List<SatelliteInfo> satellites,
    bool useNative = true,
  }) {
    _worker = DecoderWorker(
      name: 'satellite-prediction',
      factory: _createProcessor,
      config: (observer, satellites, useNative),
      maxPendingCommands: satellites.length + 4,
      onEvent: _onEvent,
      onError: _onError,
    );
  }

  late final DecoderWorker _worker;
  final Map<int, Completer<Object>> _pending = {};
  final Map<int, _PassCache> _passes = {};
  int _serial = 0;
  bool _disposed = false;

  Future<List<SatellitePass>> passes(
    int noradId,
    DateTime now,
    double minElevationDeg,
  ) {
    final cached = _passes[noradId];
    if (cached != null &&
        cached.minElevationDeg == minElevationDeg &&
        (!cached.complete ||
            now.difference(cached.from) < const Duration(minutes: 5))) {
      return cached.future;
    }
    final future = _request(
      _PassRequest(noradId, now, minElevationDeg),
    ).then((value) => value as List<SatellitePass>);
    final entry = _PassCache(now, minElevationDeg, future);
    _passes[noradId] = entry;
    unawaited(
      future.then<void>(
        (_) {
          entry.complete = true;
        },
        onError: (Object error, StackTrace stack) {
          if (identical(_passes[noradId], entry)) _passes.remove(noradId);
        },
      ),
    );
    return future;
  }

  Future<DateTime?> los(int noradId, DateTime now) => _request(
    _LosRequest(noradId, now),
  ).then((value) => (value as _LosResult).utc);

  Future<Object> _request(Object request) {
    if (_disposed) return Future.error(StateError('Predictor disposed'));
    final id = _serial++;
    final completer = Completer<Object>();
    _pending[id] = completer;
    _worker.add((id, request));
    return completer.future;
  }

  void _onEvent(Object? event) {
    final (id, result) = event as (int, Object);
    final pending = _pending.remove(id);
    if (result is _PredictionError) {
      pending?.completeError(
        StateError(result.message),
        StackTrace.fromString(result.stack),
      );
    } else {
      pending?.complete(result);
    }
  }

  void _onError(Object error, StackTrace stack) {
    for (final pending in _pending.values) {
      pending.completeError(error, stack);
    }
    _pending.clear();
    _passes.clear();
    _worker.dispose();
    _disposed = true;
  }

  void dispose() {
    if (_disposed) return;
    _onError(StateError('Predictor disposed'), StackTrace.current);
  }
}

class _PassCache {
  _PassCache(this.from, this.minElevationDeg, this.future);
  final DateTime from;
  final double minElevationDeg;
  final Future<List<SatellitePass>> future;
  bool complete = false;
}

class _PassRequest {
  _PassRequest(this.noradId, this.now, this.minElevationDeg);
  final int noradId;
  final DateTime now;
  final double minElevationDeg;
}

class _LosRequest {
  _LosRequest(this.noradId, this.now);
  final int noradId;
  final DateTime now;
}

class _LosResult {
  _LosResult(this.utc);
  final DateTime? utc;
}

class _PredictionError {
  _PredictionError(this.message, this.stack);
  final String message;
  final String stack;
}

DecoderProcessor _createProcessor(Object? config, void Function(Object?) emit) {
  final (observer, satellites, useNative) =
      config as (so.Observer, List<SatelliteInfo>, bool);
  return _PredictionProcessor(observer, satellites, useNative, emit);
}

class _PredictionProcessor implements DecoderProcessor {
  _PredictionProcessor(
    this.observer,
    List<SatelliteInfo> satellites,
    this.useNative,
    this.emit,
  ) : satellites = {for (final s in satellites) s.noradId: s};

  final so.Observer observer;
  final Map<int, SatelliteInfo> satellites;
  final void Function(Object?) emit;
  final bool useNative;
  final Map<int, SatelliteObservation> _observers = {};

  SatelliteObservation _observerFor(int id) => _observers.putIfAbsent(id, () {
    final tle = satellites[id]!.tle;
    return SatelliteObservation(
      elements: so.GpElements.fromTle(tle.line1, tle.line2, name: tle.name),
      observer: observer,
      useNative: useNative,
    );
  });

  @override
  Future<void> process(Object? command) async {
    final (id, request) = command as (int, Object);
    try {
      if (request is _PassRequest) {
        final info = satellites[request.noradId]!;
        final observer = _observerFor(request.noradId);
        final found = await _findPasses(observer, request);
        emit((
          id,
          <SatellitePass>[
            for (final p in found)
              SatellitePass(
                noradId: info.noradId,
                name: info.name,
                aos: p.rise.utc,
                los: p.set.utc,
                maxElevationDeg: p.peakElevationDeg,
                aosAzimuthDeg: p.rise.lookAngle.azimuthDeg,
                losAzimuthDeg: p.set.lookAngle.azimuthDeg,
              ),
          ],
        ));
      } else if (request is _LosRequest) {
        emit((
          id,
          _LosResult(
            await _findLos(_observerFor(request.noradId), request.now),
          ),
        ));
      } else {
        throw ArgumentError.value(request, 'request');
      }
    } catch (error, stack) {
      emit((id, _PredictionError(error.toString(), stack.toString())));
    }
  }

  Future<List<so.Pass>> _findPasses(
    SatelliteObservation observer,
    _PassRequest request,
  ) async {
    final end = request.now.add(const Duration(hours: 48));
    if (DecoderWorker.usesIsolates) {
      return observer.passes(
        from: request.now,
        to: end,
        minElevationDeg: request.minElevationDeg,
      );
    }
    // Web has no Dart isolates. Split only below-threshold sample boundaries,
    // so the package's fully-bracketed-pass policy and 30 s grid are preserved.
    final result = <so.Pass>[];
    var time = request.now;
    DateTime? riseStart;
    var samples = 0;
    var above =
        observer.lookAngleAt(time).elevationDeg >= request.minElevationDeg;
    while (time.isBefore(end)) {
      final previous = time;
      time = time.add(const Duration(seconds: 30));
      final nextAbove =
          observer.lookAngleAt(time).elevationDeg >= request.minElevationDeg;
      if (!above && nextAbove) riseStart = previous;
      if (riseStart != null && !nextAbove) {
        result.addAll(
          observer.passes(
            from: riseStart,
            to: time,
            minElevationDeg: request.minElevationDeg,
          ),
        );
        riseStart = null;
      }
      above = nextAbove;
      if (++samples % 20 == 0) await Future<void>.delayed(Duration.zero);
    }
    return result;
  }

  Future<DateTime?> _findLos(
    SatelliteObservation observer,
    DateTime now,
  ) async {
    var lo = now;
    try {
      for (var i = 0; i < 2880; i++) {
        if (observer.isNative && i % 64 == 0) {
          observer.engine.prefetch([
            for (var j = 1; j <= 64 && i + j <= 2880; j++)
              lo.add(Duration(seconds: 15 * j)),
          ]);
        }
        final hi = lo.add(const Duration(seconds: 15));
        if (observer.lookAngleAt(hi).elevationDeg <= 0) {
          var a = lo;
          var b = hi;
          while (b.difference(a).inMilliseconds > 1000) {
            final mid = a.add(
              Duration(milliseconds: b.difference(a).inMilliseconds ~/ 2),
            );
            if (observer.lookAngleAt(mid).elevationDeg > 0) {
              a = mid;
            } else {
              b = mid;
            }
          }
          return b;
        }
        lo = hi;
        if (!DecoderWorker.usesIsolates && i % 20 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }
      return null;
    } finally {
      observer.engine.clearPrefetch();
    }
  }

  @override
  void dispose() {
    for (final observer in _observers.values) {
      observer.dispose();
    }
    _observers.clear();
  }
}
