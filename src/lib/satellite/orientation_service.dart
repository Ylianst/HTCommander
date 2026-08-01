import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Live orientation of the device, used to guide an antenna toward a satellite.
///
/// [azimuthDeg] is the compass heading of the phone's top edge corrected to TRUE
/// north (0 = north, clockwise). [elevationDeg] is how far that same top edge is
/// tilted above the horizon (0 = level, 90 = pointing at the zenith).
@immutable
class DeviceOrientation {
  final double azimuthDeg;
  final double magneticAzimuthDeg;
  final double elevationDeg;

  /// Reported heading error in degrees (lower is better). Negative means the
  /// platform could not estimate it.
  final double headingAccuracyDeg;
  final bool needsCalibration;

  const DeviceOrientation({
    required this.azimuthDeg,
    required this.magneticAzimuthDeg,
    required this.elevationDeg,
    required this.headingAccuracyDeg,
    required this.needsCalibration,
  });
}

/// Streams the phone's pointing direction (heading + tilt) from the magnetometer
/// and accelerometer. Only meaningful on Android/iOS; [isSupported] is false
/// elsewhere and no sensor streams are opened.
class OrientationService {
  OrientationService({double? magneticDeclinationDeg})
    : _declinationDeg = magneticDeclinationDeg ?? 0;

  // Heading accuracy worse than this (deg) asks the user to re-calibrate.
  static const double _calibrationThresholdDeg = 25;
  // Low-pass smoothing for the accelerometer-derived pitch (0..1, lower = smoother).
  static const double _pitchSmoothing = 0.15;

  double _declinationDeg;
  final StreamController<DeviceOrientation> _controller =
      StreamController<DeviceOrientation>.broadcast();
  StreamSubscription<CompassEvent>? _compassSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;

  double? _magneticHeadingDeg;
  double _headingAccuracyDeg = -1;
  double? _pitchDeg;

  static bool get isSupported =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  Stream<DeviceOrientation> get stream => _controller.stream;

  /// Sets the local magnetic declination (degrees east) so magnetic headings can
  /// be corrected to true north.
  set magneticDeclinationDeg(double value) {
    _declinationDeg = value;
    _emit();
  }

  void start() {
    if (!isSupported) return;
    final compass = FlutterCompass.events;
    if (compass != null) {
      _compassSub = compass.listen(_onCompass);
    }
    _accelSub = accelerometerEventStream().listen(_onAccel);
  }

  void _onCompass(CompassEvent event) {
    final heading = event.heading;
    if (heading == null) return;
    _magneticHeadingDeg = _normalize(heading);
    _headingAccuracyDeg = event.accuracy ?? -1;
    _emit();
  }

  void _onAccel(AccelerometerEvent event) {
    // Gravity (at rest) points along world-up; project the device +y (top edge)
    // onto it to get how far the top edge is raised above the horizon.
    final norm = math.sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );
    if (norm < 1e-3) return;
    final raw = math.asin((event.y / norm).clamp(-1.0, 1.0)) * 180 / math.pi;
    _pitchDeg = _pitchDeg == null
        ? raw
        : _pitchDeg! + (raw - _pitchDeg!) * _pitchSmoothing;
    _emit();
  }

  void _emit() {
    if (_magneticHeadingDeg == null || _pitchDeg == null) return;
    final trueHeading = _normalize(_magneticHeadingDeg! + _declinationDeg);
    _controller.add(
      DeviceOrientation(
        azimuthDeg: trueHeading,
        magneticAzimuthDeg: _magneticHeadingDeg!,
        elevationDeg: _pitchDeg!,
        headingAccuracyDeg: _headingAccuracyDeg,
        needsCalibration:
            _headingAccuracyDeg < 0 ||
            _headingAccuracyDeg > _calibrationThresholdDeg,
      ),
    );
  }

  static double _normalize(double deg) {
    var d = deg % 360;
    if (d < 0) d += 360;
    return d;
  }

  void dispose() {
    _compassSub?.cancel();
    _accelSub?.cancel();
    _controller.close();
  }
}

/// First-order (tilted centred dipole) estimate of magnetic declination in
/// degrees east for the given observer position. The horizontal field of a
/// dipole points toward the geomagnetic north pole, so declination equals the
/// initial great-circle bearing to that pole. Accurate to a few degrees over
/// most of the globe — enough to point a wide-beam handheld antenna.
double estimateMagneticDeclination(double latDeg, double lonDeg) {
  // Geomagnetic (dipole) north pole, epoch ~2020.
  const poleLatDeg = 80.65;
  const poleLonDeg = -72.68;
  final phi = latDeg * math.pi / 180;
  final lambda = lonDeg * math.pi / 180;
  final phiP = poleLatDeg * math.pi / 180;
  final lambdaP = poleLonDeg * math.pi / 180;
  final dLon = lambdaP - lambda;
  final y = math.sin(dLon) * math.cos(phiP);
  final x =
      math.cos(phi) * math.sin(phiP) -
      math.sin(phi) * math.cos(phiP) * math.cos(dLon);
  return math.atan2(y, x) * 180 / math.pi;
}
