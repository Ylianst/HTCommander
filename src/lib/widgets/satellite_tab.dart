/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../dialogs/aprs_location_dialog.dart';
import '../l10n/app_localizations.dart';
import '../satellite/satellite_models.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import '../services/window_service.dart';

/// Tab that lists workable amateur (FM) satellites, shows the selected bird's
/// live look-angle and Doppler-corrected up/downlink, and lists its upcoming
/// passes. Data is produced by the [SatelliteHandler] and delivered over the
/// Data Broker; this widget is display + selection only.
class SatelliteTab extends StatefulWidget {
  const SatelliteTab({super.key});

  @override
  State<SatelliteTab> createState() => _SatelliteTabState();
}

class _SatelliteTabState extends State<SatelliteTab> {
  static const int _deviceId = 0;

  final DataBrokerClient _broker = DataBrokerClient();
  Timer? _clock;

  final Map<int, SatelliteInfo> _catalog = {};
  final Map<int, SatellitePosition> _positions = {};
  final Map<int, SatellitePass> _nextPass = {};
  List<SatellitePass> _selectedPasses = const [];
  bool _observerKnown = false;
  int? _selectedId;

  // Fraction of the height given to the list in the stacked (narrow) layout.
  double _listHeightRatio = 0.5;
  static const double _minListRatio = 0.2;
  static const double _maxListRatio = 0.8;

  // Live marker feed for an open "show on map" dialog and the sat it tracks.
  ValueNotifier<LatLng>? _mapLiveNotifier;
  int? _mapDialogNoradId;

  @override
  void initState() {
    super.initState();
    _selectedId = DataBroker.getValue<int>(_deviceId, 'SelectedSatelliteId', null);

    _broker.subscribe(
      deviceId: _deviceId,
      name: 'SatelliteCatalog',
      callback: _onCatalog,
    );
    _broker.subscribe(
      deviceId: _deviceId,
      name: 'SatellitePositions',
      callback: _onPositions,
    );
    _broker.subscribe(
      deviceId: _deviceId,
      name: 'SatelliteNextPasses',
      callback: _onNextPasses,
    );
    _broker.subscribe(
      deviceId: _deviceId,
      name: 'SatellitePasses',
      callback: _onSelectedPasses,
    );
    _broker.subscribe(
      deviceId: _deviceId,
      name: 'SatelliteObserverKnown',
      callback: _onObserverKnown,
    );

    // Ask the handler to re-emit the current snapshot (events are broadcast).
    _broker.dispatch(
      deviceId: _deviceId,
      name: 'SatelliteResync',
      data: DateTime.now().millisecondsSinceEpoch,
      store: false,
    );

    // Repaint countdowns once per second even between position pushes.
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _broker.dispose();
    super.dispose();
  }

  // --- Broker callbacks -----------------------------------------------------

  void _onCatalog(int deviceId, String name, Object? data) {
    if (data is! List) return;
    setState(() {
      _catalog
        ..clear()
        ..addEntries(
          data.whereType<SatelliteInfo>().map((s) => MapEntry(s.noradId, s)),
        );
    });
  }

  void _onPositions(int deviceId, String name, Object? data) {
    if (data is! List) return;
    setState(() {
      _positions
        ..clear()
        ..addEntries(
          data
              .whereType<SatellitePosition>()
              .map((p) => MapEntry(p.noradId, p)),
        );
    });
    // Drive the open map dialog's marker as the tracked satellite moves.
    final id = _mapDialogNoradId;
    if (id != null) {
      final p = _positions[id];
      if (p != null) {
        _mapLiveNotifier?.value = LatLng(p.latitudeDeg, p.longitudeDeg);
      }
    }
  }

  void _onNextPasses(int deviceId, String name, Object? data) {
    if (data is! List) return;
    setState(() {
      _nextPass
        ..clear()
        ..addEntries(
          data.whereType<SatellitePass>().map((p) => MapEntry(p.noradId, p)),
        );
    });
  }

  void _onSelectedPasses(int deviceId, String name, Object? data) {
    if (data is! List) return;
    setState(() => _selectedPasses = data.whereType<SatellitePass>().toList());
  }

  void _onObserverKnown(int deviceId, String name, Object? data) {
    if (data is! bool) return;
    setState(() => _observerKnown = data);
  }

  void _select(int noradId) {
    setState(() => _selectedId = noradId);
    _broker.dispatch(
      deviceId: _deviceId,
      name: 'SelectSatellite',
      data: noradId,
      store: false,
    );
  }

  void _requestRefresh() {
    _broker.dispatch(
      deviceId: _deviceId,
      name: 'SatelliteRefresh',
      data: DateTime.now().millisecondsSinceEpoch,
      store: false,
    );
  }

  void _showOnMap(String name, int noradId, SatellitePosition pos) {
    final notifier =
        ValueNotifier<LatLng>(LatLng(pos.latitudeDeg, pos.longitudeDeg));
    _mapLiveNotifier = notifier;
    _mapDialogNoradId = noradId;
    showAprsLocationDialog(
      context,
      latitude: pos.latitudeDeg,
      longitude: pos.longitudeDeg,
      title: name,
      // Satellites need a much wider view than an APRS message; keep their own
      // persisted zoom so the two dialogs don't fight over one level.
      zoomStorageKey: 'SatelliteLocationZoom',
      defaultZoom: 4.0,
      // The marker follows the satellite as it moves across its orbit.
      livePosition: notifier,
    ).whenComplete(() {
      _mapDialogNoradId = null;
      _mapLiveNotifier = null;
      notifier.dispose();
    });
  }

  void _showMenu(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final RenderBox button = context.findRenderObject() as RenderBox;
    final Offset offset = button.localToGlobal(Offset.zero);

    const menuItemPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 4);
    const menuItemHeight = 32.0;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + button.size.height,
        offset.dx + button.size.width,
        offset.dy,
      ),
      items: [
        const PopupMenuItem<String>(
          value: 'refresh',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: Row(children: [SizedBox(width: 20), Text('Refresh')]),
        ),
        if (windowService.canDetach) ...[
          const PopupMenuDivider(height: 8),
          PopupMenuItem<String>(
            value: 'detach',
            height: menuItemHeight,
            padding: menuItemPadding,
            child: Row(
              children: [const SizedBox(width: 20), Text(l10n.tabDetach)],
            ),
          ),
        ],
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'refresh':
          _requestRefresh();
          break;
        case 'detach':
          windowService.createWindow('satellite');
          break;
      }
    });
  }

  // --- UI -------------------------------------------------------------------

  /// Draggable divider that lets the user resize the list vs. detail panes in
  /// the stacked (narrow) layout, mirroring the mail tab's splitter.
  Widget _buildHorizontalSplitter(double totalHeight) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (details) {
          if (totalHeight <= 0) return;
          setState(() {
            _listHeightRatio = (_listHeightRatio + details.delta.dy / totalHeight)
                .clamp(_minListRatio, _maxListRatio);
          });
        },
        child: Container(
          height: 8,
          color: scheme.surfaceContainerHigh,
          child: Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(context),
        if (!_observerKnown) _buildObserverBanner(context),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 720;
              final list = _buildSatelliteList(context);
              final detail = _buildDetailPanel(context);
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 320, child: list),
                    const VerticalDivider(width: 1),
                    Expanded(child: detail),
                  ],
                );
              }
              return Column(
                children: [
                  SizedBox(
                    height: (constraints.maxHeight * _listHeightRatio)
                        .clamp(80.0, constraints.maxHeight - 120.0),
                    child: list,
                  ),
                  _buildHorizontalSplitter(constraints.maxHeight),
                  Expanded(child: detail),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      height: 40,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Text(
            'Satellite',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const Spacer(),
          Builder(
            builder: (context) => InkWell(
              onTap: () => _showMenu(context),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Image.asset(
                  'assets/images/MenuIcon.png',
                  width: 24,
                  height: 24,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  colorBlendMode: BlendMode.srcIn,
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(Icons.menu, size: 24);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildObserverBanner(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.location_off, size: 18, color: scheme.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'No location — connect a GPS to see passes.',
              style: TextStyle(color: scheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSatelliteList(BuildContext context) {
    if (_catalog.isEmpty) {
      return const Center(child: Text('No satellite data.'));
    }
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final sats = _catalog.values.toList()..sort(_compareForList);
    return ListView.separated(
      itemCount: sats.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        color: scheme.outlineVariant.withValues(alpha: 0.4),
      ),
      itemBuilder: (context, i) {
        final sat = sats[i];
        final pos = _positions[sat.noradId];
        final selected = sat.noradId == _selectedId;
        final visible = pos != null && pos.isVisible;
        return Material(
          color: selected ? scheme.primaryContainer : Colors.transparent,
          child: InkWell(
            onTap: () => _select(sat.noradId),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: selected ? scheme.primary : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(9, 8, 12, 8),
              child: Row(
                children: [
                  _visibilityIcon(pos),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sat.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight:
                                selected ? FontWeight.bold : FontWeight.w500,
                            color:
                                selected ? scheme.onPrimaryContainer : null,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _listSubtitle(sat),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: selected
                                ? scheme.onPrimaryContainer
                                    .withValues(alpha: 0.8)
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (visible)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${pos.elevationDeg.round()}\u00b0',
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _visibilityIcon(SatellitePosition? pos) {
    final visible = pos != null && pos.isVisible;
    final color = visible ? Colors.green : Colors.grey;
    return CircleAvatar(
      radius: 14,
      backgroundColor: color.withValues(alpha: 0.15),
      child: Icon(
        visible ? Icons.satellite_alt : Icons.schedule,
        size: 16,
        color: color,
      ),
    );
  }

  int _compareForList(SatelliteInfo a, SatelliteInfo b) {
    final pa = _positions[a.noradId];
    final pb = _positions[b.noradId];
    final va = pa != null && pa.isVisible;
    final vb = pb != null && pb.isVisible;
    if (va != vb) return va ? -1 : 1; // visible first
    if (va && vb) return pb.elevationDeg.compareTo(pa.elevationDeg);
    // Both below horizon: order by next AOS, sats without a pass go last.
    final na = _nextPass[a.noradId];
    final nb = _nextPass[b.noradId];
    if (na == null && nb == null) return a.name.compareTo(b.name);
    if (na == null) return 1;
    if (nb == null) return -1;
    return na.aos.compareTo(nb.aos);
  }

  String _listSubtitle(SatelliteInfo sat) {
    final pos = _positions[sat.noradId];
    if (pos != null && pos.isVisible) {
      return 'Overhead \u2022 az ${pos.azimuthDeg.round()}\u00b0';
    }
    final next = _nextPass[sat.noradId];
    if (next == null) return 'No pass in 48 h';
    final delta = next.aos.difference(DateTime.now().toUtc());
    return 'AOS in ${_formatDuration(delta)} \u2022 max '
        '${next.maxElevationDeg.round()}\u00b0';
  }

  Widget _buildDetailPanel(BuildContext context) {
    final id = _selectedId;
    final sat = id == null ? null : _catalog[id];
    if (sat == null) {
      final theme = Theme.of(context);
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.satellite_alt, size: 48, color: theme.disabledColor),
            const SizedBox(height: 8),
            Text(
              'Select a satellite',
              style: TextStyle(color: theme.hintColor),
            ),
          ],
        ),
      );
    }
    final pos = _positions[sat.noradId];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildDetailHeader(context, sat, pos),
        const SizedBox(height: 12),
        _section(
          context,
          icon: Icons.my_location,
          title: 'Live tracking',
          child: _buildLiveSection(context, sat, pos),
        ),
        _section(
          context,
          icon: Icons.settings_input_antenna,
          title: 'Frequencies (Doppler-corrected)',
          child: _buildFrequencySection(context, sat, pos),
        ),
        _section(
          context,
          icon: Icons.schedule,
          title: 'Upcoming passes',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _buildPassRows(context),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailHeader(
    BuildContext context,
    SatelliteInfo sat,
    SatellitePosition? pos,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final visible = pos != null && pos.isVisible;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer,
            scheme.primaryContainer.withValues(alpha: 0.55),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: scheme.primary,
            child: Icon(Icons.satellite_alt, color: scheme.onPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sat.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _pill(
                      context,
                      'NORAD ${sat.noradId}',
                      onTap: () => _openN2yo(sat.noradId),
                    ),
                    _pill(
                      context,
                      visible ? 'Above horizon' : 'Below horizon',
                      color: visible ? Colors.green : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.location_pin,
              color: pos != null ? Colors.red : theme.disabledColor,
            ),
            tooltip: 'Show on map',
            onPressed: pos != null
                ? () => _showOnMap(sat.name, sat.noradId, pos)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _pill(BuildContext context, String text, {Color? color, VoidCallback? onTap}) {
    final scheme = Theme.of(context).colorScheme;
    final bg = (color ?? scheme.primary).withValues(alpha: 0.15);
    final fg = color ?? scheme.onPrimaryContainer;
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 3),
            Icon(Icons.open_in_new, size: 11, color: fg),
          ],
        ],
      ),
    );
    if (onTap == null) return child;
    return InkWell(
      onTap: onTap,
      mouseCursor: SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(10),
      child: child,
    );
  }

  Future<void> _openN2yo(int noradId) async {
    final uri = Uri.parse('https://www.n2yo.com/satellite/?s=$noradId');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _section(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _buildLiveSection(
    BuildContext context,
    SatelliteInfo sat,
    SatellitePosition? pos,
  ) {
    if (pos == null) {
      return const Text('Waiting for tracking data\u2026');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _kv(context, 'Azimuth', '${pos.azimuthDeg.toStringAsFixed(1)}\u00b0'),
        _kv(context, 'Elevation', '${pos.elevationDeg.toStringAsFixed(1)}\u00b0'),
        _kv(context, 'Range', '${pos.rangeKm.toStringAsFixed(0)} km'),
        _kv(
          context,
          'Sub-point',
          '${pos.latitudeDeg.toStringAsFixed(2)}, '
              '${pos.longitudeDeg.toStringAsFixed(2)}',
        ),
        _kv(context, 'Altitude', '${pos.altitudeKm.toStringAsFixed(0)} km'),
      ],
    );
  }

  Widget _buildFrequencySection(
    BuildContext context,
    SatelliteInfo sat,
    SatellitePosition? pos,
  ) {
    final rate = pos?.rangeRateKmS ?? 0;
    final downBase = sat.transponder.downlinkHz;
    final upBase = sat.transponder.uplinkHz;
    final downCorr = sat.correctedDownlinkHz(rate);
    final upCorr = sat.correctedUplinkHz(rate);
    final tone = sat.transponder.ctcssHz;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _kv(
          context,
          'Downlink (RX)',
          downCorr == null
              ? '\u2014'
              : '${_mhz(downCorr)}  (${_mhz(downBase!)})',
        ),
        _kv(
          context,
          'Uplink (TX)',
          upCorr == null ? '\u2014' : '${_mhz(upCorr)}  (${_mhz(upBase!)})',
        ),
        _kv(
          context,
          'CTCSS',
          tone == null ? 'None' : '${tone.toStringAsFixed(1)} Hz',
        ),
      ],
    );
  }

  List<Widget> _buildPassRows(BuildContext context) {
    if (_selectedPasses.isEmpty) {
      return const [Text('No passes predicted in the next 48 hours.')];
    }
    return _selectedPasses.take(10).map((p) {
      final now = DateTime.now().toUtc();
      final upcoming = p.aos.isAfter(now);
      final inPass = !upcoming && p.los.isAfter(now);
      final when = inPass
          ? 'now \u2022 LOS in ${_formatDuration(p.los.difference(now))}'
          : 'in ${_formatDuration(p.aos.difference(now))}';
      return ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          inPass ? Icons.satellite_alt : Icons.schedule,
          color: inPass ? Colors.green : null,
        ),
        title: Text(
          '${_formatLocal(p.aos)} \u2192 ${_formatLocal(p.los)}',
        ),
        subtitle: Text(
          'max ${p.maxElevationDeg.round()}\u00b0 \u2022 '
          'az ${p.aosAzimuthDeg.round()}\u00b0\u2192${p.losAzimuthDeg.round()}\u00b0 '
          '\u2022 $when',
        ),
      );
    }).toList();
  }

  Widget _kv(BuildContext context, String key, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              key,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  // --- Formatting -----------------------------------------------------------

  String _mhz(int hz) => '${(hz / 1e6).toStringAsFixed(4)} MHz';

  String _formatDuration(Duration d) {
    if (d.isNegative) return '0s';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  String _formatLocal(DateTime utc) {
    final local = utc.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}';
  }
}
