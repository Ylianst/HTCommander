/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';

import 'package:flutter/material.dart';

import '../satellite/orientation_service.dart';
import '../satellite/satellite_models.dart';
import '../services/data_broker_client.dart';
import 'antenna_pointer_page.dart';

/// A small, draggable "picture-in-picture" antenna aiming guide.
///
/// It floats above every tab (inserted into the root [Overlay]) so the operator
/// can keep aligning the antenna while watching an incoming SSTV/APRS signal on
/// another tab. Drag it anywhere, tap it to expand back to the full aim page,
/// or tap the close button to dismiss it.
class AntennaAimOverlay {
  AntennaAimOverlay._();

  static OverlayEntry? _entry;
  // Remembered across hide/show so it reappears where the user left it.
  static Offset? _position;

  static bool get isVisible => _entry != null;

  /// Shows the floating overlay for the given satellite. No-op if one is already
  /// visible or no root overlay can be found from [context].
  static void show(
    BuildContext context, {
    required int noradId,
    required String satelliteName,
  }) {
    final navigator = Navigator.of(context, rootNavigator: true);
    final overlay = navigator.overlay;
    if (overlay == null || _entry != null) return;

    final entry = OverlayEntry(
      builder: (_) => _AntennaAimOverlayWidget(
        noradId: noradId,
        satelliteName: satelliteName,
        initialPosition: _position,
        onMove: (p) => _position = p,
        onClose: hide,
        onExpand: () {
          hide();
          navigator.push(
            MaterialPageRoute<void>(
              builder: (_) => AntennaPointerPage(
                noradId: noradId,
                satelliteName: satelliteName,
              ),
            ),
          );
        },
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }

  /// Removes the floating overlay if present.
  static void hide() {
    _entry?.remove();
    _entry = null;
  }
}

class _AntennaAimOverlayWidget extends StatefulWidget {
  final int noradId;
  final String satelliteName;
  final Offset? initialPosition;
  final ValueChanged<Offset> onMove;
  final VoidCallback onClose;
  final VoidCallback onExpand;

  const _AntennaAimOverlayWidget({
    required this.noradId,
    required this.satelliteName,
    required this.initialPosition,
    required this.onMove,
    required this.onClose,
    required this.onExpand,
  });

  @override
  State<_AntennaAimOverlayWidget> createState() =>
      _AntennaAimOverlayWidgetState();
}

class _AntennaAimOverlayWidgetState extends State<_AntennaAimOverlayWidget> {
  static const int _deviceId = 0;
  static const double _alignToleranceDeg = 6;
  static const double _cardWidth = 148;
  static const double _cardHeight = 172;

  final DataBrokerClient _broker = DataBrokerClient();
  final OrientationService _orientation = OrientationService();
  StreamSubscription<DeviceOrientation>? _orientationSub;

  SatellitePosition? _target;
  DeviceOrientation? _device;
  Offset? _offset;

  @override
  void initState() {
    super.initState();
    _offset = widget.initialPosition;
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
    if (OrientationService.isSupported) {
      _orientationSub = _orientation.stream.listen((o) {
        if (mounted) setState(() => _device = o);
      });
      _orientation.start();
    }
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
    for (final p in data.whereType<SatellitePosition>()) {
      if (p.noradId == widget.noradId) {
        if (mounted) setState(() => _target = p);
        return;
      }
    }
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

  double _azDelta(double a, double b) {
    var d = (b - a) % 360;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    return d;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    // Default to the top-right corner, below any status bar.
    final defaultOffset = Offset(
      size.width - _cardWidth - 16,
      media.padding.top + 16,
    );
    final offset = _clamp(_offset ?? defaultOffset, size);

    return Positioned(
      left: offset.dx,
      top: offset.dy,
      child: _buildCard(context),
    );
  }

  Offset _clamp(Offset o, Size screen) {
    final maxX = (screen.width - _cardWidth).clamp(0.0, double.infinity);
    final maxY = (screen.height - _cardHeight).clamp(0.0, double.infinity);
    return Offset(o.dx.clamp(0.0, maxX), o.dy.clamp(0.0, maxY));
  }

  Widget _buildCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final target = _target;
    final device = _device;
    final belowHorizon = target != null && target.elevationDeg < 0;

    final double? azErr = (target == null || device == null)
        ? null
        : _azDelta(device.azimuthDeg, target.azimuthDeg);
    final double? elErr = (target == null || device == null)
        ? null
        : target.elevationDeg - device.elevationDeg;
    final aligned = !belowHorizon &&
        azErr != null &&
        elErr != null &&
        azErr.abs() <= _alignToleranceDeg &&
        elErr.abs() <= _alignToleranceDeg;

    return GestureDetector(
      onTap: widget.onExpand,
      onPanUpdate: (d) {
        final media = MediaQuery.of(context);
        setState(() {
          _offset = _clamp(
            (_offset ?? Offset.zero) + d.delta,
            media.size,
          );
        });
        widget.onMove(_offset!);
      },
      child: Material(
        elevation: 10,
        borderRadius: BorderRadius.circular(14),
        color: scheme.surface.withValues(alpha: 0.96),
        child: Container(
          width: _cardWidth,
          height: _cardHeight,
          padding: const EdgeInsets.fromLTRB(10, 6, 6, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: aligned
                  ? Colors.green
                  : scheme.outlineVariant.withValues(alpha: 0.6),
              width: aligned ? 1.6 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context, scheme),
              Expanded(
                child: _buildArrows(
                  context,
                  scheme,
                  azErr,
                  elErr,
                  aligned,
                  belowHorizon,
                ),
              ),
              _buildFooter(context, scheme, azErr, elErr, aligned,
                  belowHorizon, device),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme scheme) {
    return Row(
      children: [
        Icon(Icons.satellite_alt, size: 14, color: scheme.primary),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            widget.satelliteName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
        InkWell(
          onTap: widget.onClose,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Icon(Icons.close, size: 16, color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  Widget _buildArrows(
    BuildContext context,
    ColorScheme scheme,
    double? azErr,
    double? elErr,
    bool aligned,
    bool belowHorizon,
  ) {
    final tol = _alignToleranceDeg;
    final upActive = elErr != null && elErr > tol;
    final downActive = elErr != null && elErr < -tol;
    final rightActive = azErr != null && azErr > tol;
    final leftActive = azErr != null && azErr < -tol;

    return Center(
      child: SizedBox(
        width: 96,
        height: 96,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: _arrow(scheme, Icons.keyboard_arrow_up, upActive),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: _arrow(scheme, Icons.keyboard_arrow_down, downActive),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: _arrow(scheme, Icons.keyboard_arrow_left, leftActive),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: _arrow(scheme, Icons.keyboard_arrow_right, rightActive),
            ),
            _buildCenter(scheme, aligned, belowHorizon, azErr, elErr),
          ],
        ),
      ),
    );
  }

  Widget _arrow(ColorScheme scheme, IconData icon, bool active) {
    return Icon(
      icon,
      size: 30,
      color: active
          ? scheme.primary
          : scheme.onSurfaceVariant.withValues(alpha: 0.25),
    );
  }

  Widget _buildCenter(
    ColorScheme scheme,
    bool aligned,
    bool belowHorizon,
    double? azErr,
    double? elErr,
  ) {
    if (aligned) {
      return const Icon(Icons.check_circle, size: 30, color: Colors.green);
    }
    if (belowHorizon) {
      return Icon(Icons.south, size: 22, color: scheme.onSurfaceVariant);
    }
    if (azErr == null || elErr == null) {
      return SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: scheme.primary,
        ),
      );
    }
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scheme.outlineVariant,
      ),
    );
  }

  Widget _buildFooter(
    BuildContext context,
    ColorScheme scheme,
    double? azErr,
    double? elErr,
    bool aligned,
    bool belowHorizon,
    DeviceOrientation? device,
  ) {
    String text;
    Color color = scheme.onSurfaceVariant;
    if (belowHorizon) {
      text = 'Below horizon';
    } else if (aligned) {
      text = 'On target';
      color = Colors.green;
    } else if (device == null || azErr == null || elErr == null) {
      text = 'Reading sensors\u2026';
    } else {
      final az = azErr.abs();
      final el = elErr.abs();
      final parts = <String>[];
      if (az > _alignToleranceDeg) {
        parts.add('${azErr > 0 ? "R" : "L"} ${az.toStringAsFixed(0)}\u00b0');
      }
      if (el > _alignToleranceDeg) {
        parts.add('${elErr > 0 ? "U" : "D"} ${el.toStringAsFixed(0)}\u00b0');
      }
      text = parts.isEmpty ? 'Almost there' : parts.join('   ');
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (device != null && device.needsCalibration && !belowHorizon) ...[
          Icon(Icons.threesixty, size: 13, color: scheme.error),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              'Calibrate',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: scheme.error),
            ),
          ),
        ] else
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
      ],
    );
  }
}
