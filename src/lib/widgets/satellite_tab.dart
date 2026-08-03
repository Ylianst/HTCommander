/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../dialogs/aprs_location_dialog.dart';
import '../l10n/app_localizations.dart';
import '../radio/radio.dart';
import '../radio/radio_models.dart';
import '../satellite/orientation_service.dart';
import '../satellite/satellite_models.dart';
import '../services/data_broker.dart';
import 'antenna_pointer_page.dart';
import 'satellite_aim_indicators.dart';
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

  // Preferred (audible) radio and the lock state of each connected radio, used
  // to start/stop native Satellite tracking on the selected radio.
  int _preferredRadioId = -1;
  final Map<int, RadioLockState> _lockStates = {};

  // Usage index (into the selected satellite's transponders) currently being
  // tracked, for highlighting; null when not tracking.
  int? _trackingUsageIndex;
  int? _trackingNoradId;

  // Keyboard navigation of the satellite list (arrows / page up-down / home-end).
  final FocusNode _listFocusNode = FocusNode(debugLabel: 'SatelliteList');
  final ScrollController _listScrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};

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
    _selectedId = DataBroker.getValue<int>(
      _deviceId,
      'SelectedSatelliteId',
      null,
    );

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

    _preferredRadioId =
        DataBroker.getValue<int>(1, 'SelectedRadioDeviceId', -1) ?? -1;
    _hydrateLockState(_preferredRadioId);
    _broker.subscribe(
      deviceId: 1,
      name: 'SelectedRadioDeviceId',
      callback: _onPreferredRadioChanged,
    );
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'LockState',
      callback: _onLockStateChanged,
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
    _listFocusNode.dispose();
    _listScrollController.dispose();
    super.dispose();
  }

  // --- Broker callbacks -----------------------------------------------------

  /// setState that defers to the next frame when a broker event is delivered
  /// while the tree is building (e.g. the initState `SatelliteResync` makes the
  /// handler re-emit its cached snapshot synchronously during the parent build).
  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      setState(fn);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(fn);
      });
    }
  }

  void _onCatalog(int deviceId, String name, Object? data) {
    if (data is! List) return;
    _safeSetState(() {
      _catalog
        ..clear()
        ..addEntries(
          data.whereType<SatelliteInfo>().map((s) => MapEntry(s.noradId, s)),
        );
    });
  }

  void _onPositions(int deviceId, String name, Object? data) {
    if (data is! List) return;
    _safeSetState(() {
      _positions
        ..clear()
        ..addEntries(
          data.whereType<SatellitePosition>().map(
            (p) => MapEntry(p.noradId, p),
          ),
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
    _safeSetState(() {
      _nextPass
        ..clear()
        ..addEntries(
          data.whereType<SatellitePass>().map((p) => MapEntry(p.noradId, p)),
        );
    });
  }

  void _onSelectedPasses(int deviceId, String name, Object? data) {
    if (data is! List) return;
    _safeSetState(
      () => _selectedPasses = data.whereType<SatellitePass>().toList(),
    );
  }

  void _onObserverKnown(int deviceId, String name, Object? data) {
    if (data is! bool) return;
    _safeSetState(() => _observerKnown = data);
  }

  void _onPreferredRadioChanged(int deviceId, String name, Object? data) {
    if (data is! int) return;
    _safeSetState(() {
      _preferredRadioId = data;
      _hydrateLockState(data);
    });
  }

  /// Loads the current (broker-persisted) lock state and tracking marker for
  /// [radioId] into local state, so the Disconnect button and the tracked-usage
  /// highlight survive tab rebuilds (LockState events are only received while
  /// the tab is mounted, but the value is retained in the broker).
  void _hydrateLockState(int radioId) {
    if (radioId < 0) return;
    final stored = DataBroker.getValue<Object?>(radioId, 'LockState', null);
    if (stored is! Map) return;
    final lock = RadioLockState.fromJson(Map<String, dynamic>.from(stored));
    if (!lock.isLocked) return;
    _lockStates[radioId] = lock;
    if (kSatelliteLockUsages.contains(lock.usage)) {
      final marker =
          DataBroker.getValue<Object?>(_deviceId, 'SatelliteTrackingMarker', null);
      if (marker is Map) {
        _trackingNoradId = (marker['noradId'] as num?)?.toInt();
        _trackingUsageIndex = (marker['usageIndex'] as num?)?.toInt();
      }
    }
  }

  void _onLockStateChanged(int deviceId, String name, Object? data) {
    if (data is! Map) return;
    final lock = RadioLockState.fromJson(Map<String, dynamic>.from(data));
    _safeSetState(() {
      if (lock.isLocked) {
        _lockStates[deviceId] = lock;
      } else {
        _lockStates.remove(deviceId);
        if (deviceId == _preferredRadioId) {
          _trackingUsageIndex = null;
          _trackingNoradId = null;
        }
      }
    });
  }

  /// Lock state of the preferred radio, or null when none/unlocked.
  RadioLockState? get _preferredLock =>
      _preferredRadioId >= 0 ? _lockStates[_preferredRadioId] : null;

  /// True while the preferred radio is locked in a satellite tracking mode
  /// (Satellite or APRSSat).
  bool get _satelliteActive =>
      kSatelliteLockUsages.contains(_preferredLock?.usage);

  /// True when the preferred radio is locked to some other usage (BBS,
  /// Terminal, …) and so cannot be taken over for satellite tracking.
  bool get _radioBusyOther {
    final lock = _preferredLock;
    return lock != null && !kSatelliteLockUsages.contains(lock.usage);
  }

  /// Locks the preferred radio in Satellite mode and starts steering it toward
  /// the selected bird's [usageIndex] transponder.
  void _startTracking(int usageIndex) {
    final id = _selectedId;
    final sat = id == null ? null : _catalog[id];
    final radioId = _preferredRadioId;
    if (sat == null || radioId < 0 || _radioBusyOther) return;
    if (usageIndex < 0 || usageIndex >= sat.transponders.length) return;

    // APRS/packet digipeater usages lock the radio in the dedicated APRSSat
    // mode; every other usage uses the generic Satellite mode. Both behave
    // identically for now.
    final lockUsage = _lockUsageFor(sat.transponders[usageIndex]);

    _broker.dispatch(
      deviceId: radioId,
      name: 'SetLock',
      data: SetLockData(usage: lockUsage),
      store: false,
    );
    _broker.dispatch(
      deviceId: _deviceId,
      name: 'SatelliteTrackTarget',
      data: {
        'radioDeviceId': radioId,
        'noradId': sat.noradId,
        'usageIndex': usageIndex,
      },
      store: false,
    );
    // Persist a marker so the tracked-usage highlight survives tab rebuilds.
    _broker.dispatch(
      deviceId: _deviceId,
      name: 'SatelliteTrackingMarker',
      data: {'noradId': sat.noradId, 'usageIndex': usageIndex},
      store: true,
    );
    setState(() {
      _trackingUsageIndex = usageIndex;
      _trackingNoradId = sat.noradId;
    });
  }

  /// The lock usage to claim for a given transponder: [kAprsSatLockUsage] for
  /// APRS/packet digipeater usages, [kSatelliteLockUsage] otherwise.
  String _lockUsageFor(SatelliteTransponder t) =>
      t.usage.toLowerCase() == 'aprs'
          ? kAprsSatLockUsage
          : kSatelliteLockUsage;

  /// Stops satellite tracking: drops the radio back to normal mode and clears
  /// the Satellite usage lock.
  void _stopTracking() {
    final radioId = _preferredRadioId;
    // Unlock with whichever satellite usage currently holds the lock so the
    // usage matches (the radio only unlocks on a matching usage).
    final lockUsage = _preferredLock?.usage ?? kSatelliteLockUsage;
    _broker.dispatch(
      deviceId: _deviceId,
      name: 'SatelliteTrackTarget',
      data: null,
      store: false,
    );
    _broker.dispatch(
      deviceId: _deviceId,
      name: 'SatelliteTrackingMarker',
      data: null,
      store: true,
    );
    if (radioId >= 0) {
      _broker.dispatch(
        deviceId: radioId,
        name: 'SetUnlock',
        data: SetUnlockData(usage: lockUsage),
        store: false,
      );
    }
    setState(() {
      _trackingUsageIndex = null;
      _trackingNoradId = null;
    });
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

  // --- Keyboard navigation --------------------------------------------------

  List<SatelliteInfo> _sortedSats() =>
      _catalog.values.toList()..sort(_compareForList);

  /// Rows that fit a viewport, used as the page-up/down step (keeps one row of
  /// overlap for context); falls back to a fixed step before first layout.
  int _pageStep() {
    if (_listScrollController.hasClients) {
      final rows = (_listScrollController.position.viewportDimension / 52)
          .floor();
      if (rows > 1) return rows - 1;
    }
    return 5;
  }

  KeyEventResult _handleListKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveSelection(1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _moveSelection(-1);
    } else if (key == LogicalKeyboardKey.pageDown) {
      _moveSelection(_pageStep());
    } else if (key == LogicalKeyboardKey.pageUp) {
      _moveSelection(-_pageStep());
    } else if (key == LogicalKeyboardKey.home) {
      _selectAtIndex(0);
    } else if (key == LogicalKeyboardKey.end) {
      _selectAtIndex(_sortedSats().length - 1);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _moveSelection(int delta) {
    final sats = _sortedSats();
    if (sats.isEmpty) return;
    final idx = sats.indexWhere((s) => s.noradId == _selectedId);
    if (idx < 0) {
      _selectAtIndex(delta > 0 ? 0 : sats.length - 1);
      return;
    }
    _selectAtIndex(idx + delta);
  }

  void _selectAtIndex(int index) {
    final sats = _sortedSats();
    if (sats.isEmpty) return;
    final i = index.clamp(0, sats.length - 1);
    _select(sats[i].noradId);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollSelectedIntoView(),
    );
  }

  void _scrollSelectedIntoView() {
    final id = _selectedId;
    if (id == null) return;
    final ctx = _itemKeys[id]?.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject();
    if (box == null || !_listScrollController.hasClients) return;
    // Scroll only the list's own viewport (not ancestor Scrollables such as the
    // enclosing TabBarView, which would otherwise slide the whole tab sideways
    // trying to reveal this row).
    final viewport = RenderAbstractViewport.of(box);
    final position = _listScrollController.position;
    final target = viewport
        .getOffsetToReveal(box, 0.5)
        .offset
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    position.animateTo(
      target,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeInOut,
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
    final notifier = ValueNotifier<LatLng>(
      LatLng(pos.latitudeDeg, pos.longitudeDeg),
    );
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

  void _openAntennaPointer(int noradId, String name) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            AntennaPointerPage(noradId: noradId, satelliteName: name),
      ),
    );
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
            _listHeightRatio =
                (_listHeightRatio + details.delta.dy / totalHeight).clamp(
                  _minListRatio,
                  _maxListRatio,
                );
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
                    height: (constraints.maxHeight * _listHeightRatio).clamp(
                      80.0,
                      constraints.maxHeight - 120.0,
                    ),
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
          if (_satelliteActive)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.tonalIcon(
                onPressed: _stopTracking,
                icon: const Icon(Icons.link_off, size: 16),
                label: const Text('Disconnect'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            ),
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
          Icon(
            Icons.location_off,
            size: 18,
            color: scheme.onSecondaryContainer,
          ),
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
    final sats = _sortedSats();
    return Focus(
      focusNode: _listFocusNode,
      onKeyEvent: _handleListKey,
      child: ListView.separated(
        controller: _listScrollController,
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
          final itemKey = _itemKeys.putIfAbsent(sat.noradId, () => GlobalKey());
          return Material(
            key: itemKey,
            color: selected ? scheme.primaryContainer : Colors.transparent,
            child: InkWell(
              // Keep keyboard focus on the list's Focus node (not the row) so
              // arrow/page keys drive selection instead of leaking to the
              // enclosing TabBarView's directional focus traversal.
              canRequestFocus: false,
              onTap: () {
                _listFocusNode.requestFocus();
                _select(sat.noradId);
              },
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
                      child: Builder(
                        builder: (context) {
                          final subtitle = _listSubtitle(sat);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: subtitle.isEmpty
                                ? MainAxisAlignment.center
                                : MainAxisAlignment.start,
                            children: [
                              Text(
                                sat.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: selected
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                  color: selected
                                      ? scheme.onPrimaryContainer
                                      : null,
                                ),
                              ),
                              if (subtitle.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: selected
                                        ? scheme.onPrimaryContainer.withValues(
                                            alpha: 0.8,
                                          )
                                        : scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
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
      ),
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
    if (next == null) return _observerKnown ? 'No pass in 48 h' : '';
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
          title: 'Usages & frequencies (Doppler-corrected)',
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
          if (OrientationService.isSupported)
            IconButton(
              icon: Icon(
                Icons.explore,
                color: pos != null ? scheme.primary : theme.disabledColor,
              ),
              tooltip: 'Point antenna',
              onPressed: pos != null
                  ? () => _openAntennaPointer(sat.noradId, sat.name)
                  : null,
            ),
        ],
      ),
    );
  }

  Widget _pill(
    BuildContext context,
    String text, {
    Color? color,
    VoidCallback? onTap,
  }) {
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

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return;
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
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
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
    final textColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _kv(context, 'Azimuth', '${pos.azimuthDeg.toStringAsFixed(1)}\u00b0'),
        _kv(
          context,
          'Elevation',
          '${pos.elevationDeg.toStringAsFixed(1)}\u00b0',
        ),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        // Only show the aim indicators when there is room to the right of the text.
        if (constraints.maxWidth < 300) return textColumn;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: textColumn),
            const SizedBox(width: 12),
            _buildAimIndicator(
              context,
              CompassIndicator(azimuthDeg: pos.azimuthDeg),
              'Direction',
            ),
            const SizedBox(width: 8),
            _buildAimIndicator(
              context,
              ElevationIndicator(elevationDeg: pos.elevationDeg),
              'Elevation',
            ),
          ],
        );
      },
    );
  }

  Widget _buildAimIndicator(
    BuildContext context,
    Widget indicator,
    String label,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        indicator,
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildFrequencySection(
    BuildContext context,
    SatelliteInfo sat,
    SatellitePosition? pos,
  ) {
    final rate = pos?.rangeRateKmS ?? 0;
    final scheme = Theme.of(context).colorScheme;
    final usages = sat.transponders;
    final blocks = <Widget>[];
    if (!_satelliteActive) {
      final String? note = _preferredRadioId < 0
          ? 'Select a radio to enable satellite tracking.'
          : _radioBusyOther
              ? 'The selected radio is busy with '
                  '${_preferredLock?.usage} and cannot track a satellite.'
              : null;
      if (note != null) {
        blocks.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              note,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ),
        );
      }
    }
    for (var i = 0; i < usages.length; i++) {
      if (i > 0) {
        blocks.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        );
      }
      blocks.add(_buildUsageBlock(context, usages[i], rate, i));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }

  Widget _buildUsageBlock(
    BuildContext context,
    SatelliteTransponder t,
    double rate,
    int index,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final downBase = t.downlinkHz;
    final upBase = t.uplinkHz;
    final downCorr = t.correctedDownlinkHz(rate);
    final upCorr = t.correctedUplinkHz(rate);
    final tone = t.ctcssHz;

    final active = _satelliteActive &&
        _trackingNoradId == t.noradId &&
        _trackingUsageIndex == index;
    // A usage can be tracked when a preferred radio is available, that radio is
    // not already locked to another usage, the usage has a downlink to tune, and
    // a GPS location is known (required to compute the Doppler correction).
    final trackable =
        !_satelliteActive &&
        _preferredRadioId >= 0 &&
        !_radioBusyOther &&
        downBase != null &&
        _observerKnown;

    final block = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _usageChip(context, t.usage),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                t.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            if (active)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.podcasts, size: 12, color: Colors.green),
                    SizedBox(width: 4),
                    Text(
                      'Tracking',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              )
            else if (trackable)
              Icon(Icons.satellite_alt, size: 16, color: scheme.primary),
            if (t.infoUrl != null)
              IconButton(
                icon: const Icon(Icons.open_in_new, size: 16),
                tooltip: 'Open ${t.usage} info',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _openUrl(t.infoUrl!),
              ),
          ],
        ),
        const SizedBox(height: 6),
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
          upCorr == null
              ? 'Receive only'
              : '${_mhz(upCorr)}  (${_mhz(upBase!)})',
        ),
        _kv(
          context,
          'CTCSS',
          tone == null ? 'None' : '${tone.toStringAsFixed(1)} Hz',
        ),
        if (trackable)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Tap to track on the radio',
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: scheme.primary,
              ),
            ),
          ),
      ],
    );

    if (!trackable) {
      if (!active) return block;
      // Highlight the actively tracked usage.
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
        ),
        child: block,
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _startTracking(index),
        borderRadius: BorderRadius.circular(10),
        child: Padding(padding: const EdgeInsets.all(4), child: block),
      ),
    );
  }

  Widget _usageChip(BuildContext context, String usage) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (usage.toLowerCase()) {
      'aprs' => Colors.orange,
      'sstv' => Colors.purple,
      'voice' => Colors.teal,
      _ => scheme.primary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        usage,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  List<Widget> _buildPassRows(BuildContext context) {
    if (_selectedPasses.isEmpty) {
      return [
        Text(
          _observerKnown
              ? 'No passes predicted in the next 48 hours.'
              : 'A GPS location is needed to predict passes.',
        ),
      ];
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
        title: Text('${_formatLocal(p.aos)} \u2192 ${_formatLocal(p.los)}'),
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
