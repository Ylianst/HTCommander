import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'tab_visibility.dart';
import '../dialogs/bbs_files_dialog.dart';
import '../dialogs/callsign_lookup_dialog.dart';
import '../handlers/bbs_handler.dart';
import '../handlers/bbs_monitor.dart';
import '../l10n/app_localizations.dart';
import '../radio/radio_models.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import '../services/host_bridge.dart';
import '../services/window_service.dart';
import 'host_managed_banner.dart';

/// BBS tab - Bulletin Board System
class BbsTab extends StatefulWidget {
  const BbsTab({super.key});

  @override
  State<BbsTab> createState() => _BbsTabState();
}

class _BbsTabState extends State<BbsTab>
    with AutomaticKeepAliveClientMixin, TabVisibilityStateMixin {
  final DataBrokerClient _broker = DataBrokerClient();
  final List<MergedStationStats> _stations = [];

  /// Traffic of every session, oldest first (see BbsMonitor).
  final List<BbsTrafficRecord> _traffic = [];
  final Set<int> _trafficSeqs = {};
  static const int _maxTraffic = 5000;

  /// Sessions currently connected to any BBS, in the order they started.
  List<BbsSessionInfo> _sessions = [];

  /// The session shown in the traffic panel, or null for all of them. Kept
  /// after the session ends so its last lines can still be read.
  BbsSessionInfo? _selectedSession;

  /// Sessions with traffic not seen yet while another session was shown.
  final Set<String> _unreadSessions = {};
  final ScrollController _trafficScrollController = ScrollController();

  // Keyboard navigation for the station list.
  final FocusNode _stationFocusNode = FocusNode();
  final ScrollController _stationScrollController = ScrollController();
  static const double _stationRowHeight = 30;

  /// Connected radios, each a map with 'DeviceId' and 'FriendlyName'.
  final List<Map<String, dynamic>> _connectedRadios = [];

  /// Latest lock state reported for each radio device id.
  final Map<int, RadioLockState> _lockStates = {};

  int? _selectedStationIndex;
  bool _viewTraffic = true;
  int _sortColumnIndex = 0;
  bool _sortAscending = true;
  double _trafficHeightRatio = 0.35;
  static const double _minTrafficRatio = 0.15;
  static const double _maxTrafficRatio = 0.60;

  /// Whether the station list is too narrow to show the "Stats" column.
  bool _isCompact = false;
  static const double _compactWidthThreshold = 360;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    // Connected radios and lock state drive the Activate/Deactivate button.
    _broker.subscribe(
      deviceId: 1,
      name: 'ConnectedRadios',
      callback: _onConnectedRadiosChanged,
    );
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'LockState',
      callback: _onLockStateChanged,
    );

    // Live sessions and their traffic, recorded by the host's BbsMonitor.
    _broker.subscribe(
      deviceId: 1,
      name: 'BbsActiveSessions',
      callback: (_, _, data) => setState(() => _applySessions(data)),
    );
    _broker.subscribe(
      deviceId: 1,
      name: 'BbsTrafficEntry',
      callback: _onTrafficEntry,
    );
    _broker.subscribe(
      deviceId: 1,
      name: 'BbsTrafficHistory',
      callback: _onTrafficHistory,
    );

    // Merged per-station statistics from the BBS manager (device 1).
    _broker.subscribe(
      deviceId: 1,
      name: 'BbsMergedStats',
      callback: _onBbsMergedStats,
    );

    // Persisted "View Traffic" setting (device 0).
    _viewTraffic = (_broker.getValue<int>(0, 'ViewBbsTraffic', 1) ?? 1) == 1;

    // Seed current state from the broker.
    _loadConnectedRadios();
    _applyMergedStats(DataBroker.getValueDynamic(1, 'BbsMergedStats'));
    _applySessions(DataBroker.getValueDynamic(1, 'BbsActiveSessions'));
    // Fetch what was said before this view opened (e.g. a detached window).
    _broker.dispatch(
      deviceId: 1,
      name: 'RequestBbsTraffic',
      data: null,
      store: false,
    );
  }

  @override
  void dispose() {
    _broker.dispose();
    _trafficScrollController.dispose();
    _stationFocusNode.dispose();
    _stationScrollController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Radio / lock state
  // ---------------------------------------------------------------------------

  void _loadConnectedRadios() {
    _setConnectedRadios(DataBroker.getValueDynamic(1, 'ConnectedRadios'));
  }

  void _setConnectedRadios(Object? data) {
    _connectedRadios.clear();
    if (data is List) {
      for (final r in data) {
        if (r is Map && r['DeviceId'] != null) {
          _connectedRadios.add({
            'DeviceId': r['DeviceId'],
            'FriendlyName': r['FriendlyName'],
          });
        }
      }
    }
  }

  void _onConnectedRadiosChanged(int deviceId, String name, Object? data) {
    setState(() => _setConnectedRadios(data));
  }

  void _onLockStateChanged(int deviceId, String name, Object? data) {
    if (data is! Map) return;
    setState(() {
      _lockStates[deviceId] = RadioLockState.fromJson(
        Map<String, dynamic>.from(data),
      );
    });
  }

  /// The radio currently locked to BBS usage, or -1 if none.
  int get _activeBbsRadioId {
    for (final r in _connectedRadios) {
      final id = r['DeviceId'] as int;
      final ls = _lockStates[id];
      if (ls != null && ls.isLocked && ls.usage == 'BBS') return id;
    }
    return -1;
  }

  bool get _isActive => _activeBbsRadioId > 0;

  /// Connected radios that are not locked to any usage.
  List<Map<String, dynamic>> get _availableRadios {
    final result = <Map<String, dynamic>>[];
    for (final r in _connectedRadios) {
      final id = r['DeviceId'] as int;
      final ls = _lockStates[id];
      if (ls == null || !ls.isLocked) result.add(r);
    }
    return result;
  }

  bool get _buttonEnabled =>
      !HostBridge.isHosted && (_isActive || _availableRadios.isNotEmpty);

  // ---------------------------------------------------------------------------
  // Stats
  // ---------------------------------------------------------------------------

  void _onBbsMergedStats(int deviceId, String name, Object? data) {
    setState(() => _applyMergedStats(data));
  }

  void _applyMergedStats(Object? data) {
    if (data is! List) return;
    _stations
      ..clear()
      ..addAll(data.whereType<MergedStationStats>());
    _applySort();
    if (_selectedStationIndex != null &&
        _selectedStationIndex! >= _stations.length) {
      _selectedStationIndex = null;
    }
  }

  // ---------------------------------------------------------------------------
  // Sessions and traffic
  // ---------------------------------------------------------------------------

  void _applySessions(Object? data) {
    if (data is! List) return;
    _sessions = [for (final s in data) ?BbsSessionInfo.fromJson(s)];
    final active = _sessions.map((s) => s.key).toSet();
    // Unread marks only matter for sessions that can still be picked.
    _unreadSessions.removeWhere(
      (k) => !active.contains(k) && k != _selectedSession?.key,
    );
  }

  bool _isVisible(BbsTrafficRecord r) {
    final selected = _selectedSession;
    return selected == null || r.key == selected.key;
  }

  /// Adds [records] not seen yet; returns whether any was added.
  bool _mergeTraffic(Iterable<BbsTrafficRecord> records) {
    var added = false;
    var outOfOrder = false;
    for (final r in records) {
      if (!_trafficSeqs.add(r.seq)) continue;
      if (_traffic.isNotEmpty && r.seq < _traffic.last.seq) outOfOrder = true;
      _traffic.add(r);
      added = true;
    }
    if (outOfOrder) _traffic.sort((a, b) => a.seq.compareTo(b.seq));
    if (_traffic.length > _maxTraffic) {
      final drop = _traffic.length - _maxTraffic;
      _trafficSeqs.removeAll(_traffic.take(drop).map((r) => r.seq));
      _traffic.removeRange(0, drop);
    }
    return added;
  }

  void _onTrafficEntry(int deviceId, String name, Object? data) {
    final record = BbsTrafficRecord.fromJson(data);
    if (record == null) return;
    setState(() {
      if (!_mergeTraffic([record])) return;
      final key = record.key;
      if (key != null &&
          _selectedSession != null &&
          key != _selectedSession!.key) {
        _unreadSessions.add(key);
      }
    });
    if (_isVisible(record)) _scrollTrafficToEnd();
  }

  void _onTrafficHistory(int deviceId, String name, Object? data) {
    if (data is! List) return;
    setState(() {
      _mergeTraffic([for (final r in data) ?BbsTrafficRecord.fromJson(r)]);
    });
    _scrollTrafficToEnd(animate: false);
  }

  void _selectSession(BbsSessionInfo? session) {
    setState(() {
      _selectedSession = session;
      if (session != null) _unreadSessions.remove(session.key);
    });
    _scrollTrafficToEnd(animate: false);
  }

  /// The active session of [callsign] (any BBS), if any.
  BbsSessionInfo? _sessionOf(String callsign) {
    final call = callsign.toUpperCase();
    return _sessions.where((s) => s.callsign == call).firstOrNull;
  }

  /// Display name of [session]: callsign and [_sessionDetail].
  String _sessionLabel(BbsSessionInfo session) =>
      '${session.callsign} · ${_sessionDetail(session)}';

  /// How [session] is connected, plus the radio when the same station is
  /// connected the same way to several radios.
  String _sessionDetail(BbsSessionInfo session) {
    final ambiguous = _sessions.any(
      (s) =>
          s.key != session.key &&
          s.callsign == session.callsign &&
          s.protocol == session.protocol,
    );
    if (!ambiguous) return session.protocol;
    final radio = _connectedRadios
        .where((r) => r['DeviceId'] == session.deviceId)
        .map((r) => r['FriendlyName'] as String?)
        .firstOrNull;
    return '${session.protocol} · '
        '${radio?.isNotEmpty == true ? radio : session.deviceId}';
  }

  void _onStationSelected(int index) {
    setState(() {
      _selectedStationIndex = index;
    });
  }

  /// Handles arrow up/down and page up/down while the station list has focus,
  /// moving the selection between stations and scrolling to keep it visible.
  KeyEventResult _handleStationKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final count = _stations.length;
    if (count == 0) return KeyEventResult.ignored;

    int page = 10;
    if (_stationScrollController.hasClients) {
      final viewport = _stationScrollController.position.viewportDimension;
      page = (viewport / _stationRowHeight).floor().clamp(1, count);
    }

    final current = _selectedStationIndex ?? -1;
    int next;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      next = current + 1;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      next = current < 0 ? count - 1 : current - 1;
    } else if (key == LogicalKeyboardKey.pageDown) {
      next = current + page;
    } else if (key == LogicalKeyboardKey.pageUp) {
      next = (current < 0 ? count - 1 : current) - page;
    } else if (key == LogicalKeyboardKey.home) {
      next = 0;
    } else if (key == LogicalKeyboardKey.end) {
      next = count - 1;
    } else {
      return KeyEventResult.ignored;
    }
    next = next.clamp(0, count - 1);
    if (next != current) {
      _onStationSelected(next);
      _scrollStationIntoView(next);
    }
    return KeyEventResult.handled;
  }

  /// Scrolls the station list so the station at [index] is fully visible.
  void _scrollStationIntoView(int index) {
    if (!_stationScrollController.hasClients) return;
    final position = _stationScrollController.position;
    final itemTop = index * _stationRowHeight;
    final itemBottom = itemTop + _stationRowHeight;
    final viewTop = position.pixels;
    final viewBottom = viewTop + position.viewportDimension;
    double? target;
    if (itemTop < viewTop) {
      target = itemTop;
    } else if (itemBottom > viewBottom) {
      target = itemBottom - position.viewportDimension;
    }
    if (target != null) {
      _stationScrollController.jumpTo(
        target.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Activate / deactivate
  // ---------------------------------------------------------------------------

  void _onActivate(BuildContext buttonContext) {
    final activeId = _activeBbsRadioId;
    if (activeId > 0) {
      // Deactivate the active BBS.
      _broker.dispatch(
        deviceId: 1,
        name: 'RemoveBbs',
        data: RemoveBbsData(radioDeviceId: activeId),
        store: false,
      );
      _broker.logInfo('[BbsTab] Deactivating BBS on radio $activeId');
      return;
    }

    final available = _availableRadios;
    if (available.isEmpty) return;
    if (available.length > 1) {
      _showRadioSelectionMenu(buttonContext, available);
      return;
    }
    _activateBbsOnRadio(available.first['DeviceId'] as int);
  }

  void _showRadioSelectionMenu(
    BuildContext buttonContext,
    List<Map<String, dynamic>> radios,
  ) {
    final box = buttonContext.findRenderObject() as RenderBox;
    final offset = box.localToGlobal(Offset.zero);
    showMenu<int>(
      context: buttonContext,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + box.size.height,
        offset.dx + box.size.width,
        offset.dy,
      ),
      items: [
        for (final r in radios)
          PopupMenuItem<int>(
            value: r['DeviceId'] as int,
            child: Text(
              (r['FriendlyName'] as String?)?.isNotEmpty == true
                  ? r['FriendlyName'] as String
                  : AppLocalizations.of(
                      context,
                    ).riRadioFallback(r['DeviceId'] as int),
            ),
          ),
      ],
    ).then((id) {
      if (id != null) _activateBbsOnRadio(id);
    });
  }

  void _activateBbsOnRadio(int radioId) {
    if (radioId <= 0) return;

    // Region from HtStatus, channel from Settings (both stored as JSON maps).
    final htStatus = DataBroker.getValueDynamic(radioId, 'HtStatus');
    final regionId =
        (htStatus is Map ? htStatus['currRegion'] as int? : null) ?? 0;
    final settings = DataBroker.getValueDynamic(radioId, 'Settings');
    final channelId =
        (settings is Map ? settings['channelA'] as int? : null) ?? 0;

    _broker.dispatch(
      deviceId: 1,
      name: 'CreateBbs',
      data: CreateBbsData(
        radioDeviceId: radioId,
        channelId: channelId,
        regionId: regionId,
      ),
      store: false,
    );
    _broker.logInfo(
      '[BbsTab] Activating BBS on radio $radioId (Region: $regionId, Channel: $channelId)',
    );
  }

  void _scrollTrafficToEnd({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_trafficScrollController.hasClients) return;
      final end = _trafficScrollController.position.maxScrollExtent;
      if (animate) {
        _trafficScrollController.animateTo(
          end,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      } else {
        _trafficScrollController.jumpTo(end);
      }
    });
  }

  void _clearTraffic() {
    // Also clear the host's history so reopened views start empty.
    _broker.dispatch(
      deviceId: 1,
      name: 'ClearBbsTraffic',
      data: null,
      store: false,
    );
    setState(() {
      _traffic.clear();
      _trafficSeqs.clear();
      _unreadSessions.clear();
    });
  }

  void _clearStats() {
    // Ask the BBS manager (device 1) to clear all aggregated stats.
    _broker.dispatch(
      deviceId: 1,
      name: 'BbsClearAllStats',
      data: null,
      store: false,
    );
    setState(() {
      _stations.clear();
      _selectedStationIndex = null;
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
        PopupMenuItem<String>(
          value: 'viewTraffic',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: _viewTraffic
                    ? const Text('✓', style: TextStyle(fontSize: 14))
                    : null,
              ),
              Text(l10n.bbsViewTraffic),
            ],
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(
          value: 'clearTraffic',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: Row(
            children: [const SizedBox(width: 20), Text(l10n.bbsClearTraffic)],
          ),
        ),
        PopupMenuItem<String>(
          value: 'clearStats',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: Row(
            children: [const SizedBox(width: 20), Text(l10n.bbsClearStats)],
          ),
        ),
        if (!HostBridge.isHosted) ...[
          const PopupMenuDivider(height: 8),
          PopupMenuItem<String>(
            value: 'files',
            height: menuItemHeight,
            padding: menuItemPadding,
            child: Row(
              children: [
                const SizedBox(width: 20),
                Text('${l10n.bbsFilesTitle}...'),
              ],
            ),
          ),
        ],
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
        case 'viewTraffic':
          setState(() => _viewTraffic = !_viewTraffic);
          _broker.dispatch(
            deviceId: 0,
            name: 'ViewBbsTraffic',
            data: _viewTraffic ? 1 : 0,
            store: true,
          );
          break;
        case 'clearTraffic':
          _clearTraffic();
          break;
        case 'clearStats':
          _clearStats();
          break;
        case 'files':
          if (mounted) BbsFilesDialog.show(this.context);
          break;
        case 'detach':
          windowService.createWindow('bbs');
          break;
      }
    });
  }

  /// Shows a right-click / long-press menu for a station row, offering an
  /// offline callsign database lookup.
  void _showStationContextMenu(Offset globalPosition, String callsign) async {
    final l10n = AppLocalizations.of(context);
    final session = _sessionOf(callsign);
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(1, 1),
        Offset.zero & MediaQuery.of(context).size,
      ),
      items: [
        PopupMenuItem<String>(
          enabled: false,
          height: 28,
          child: Text(callsign, style: Theme.of(context).textTheme.labelSmall),
        ),
        const PopupMenuDivider(height: 8),
        if (session != null && _viewTraffic)
          PopupMenuItem<String>(
            value: 'session',
            child: Text(l10n.bbsShowSessionTraffic),
          ),
        PopupMenuItem<String>(
          value: 'lookup',
          child: Text(l10n.callsignLookup),
        ),
      ],
    );
    if (selected == null || !mounted) return;
    if (selected == 'session') {
      _selectSession(session);
    } else if (selected == 'lookup') {
      CallsignLookupDialog.show(context, initialCallsign: callsign);
    }
  }

  void _sort(int columnIndex) {
    setState(() {
      if (_sortColumnIndex == columnIndex) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumnIndex = columnIndex;
        _sortAscending = true;
      }
      _applySort();
    });
  }

  void _applySort() {
    _stations.sort((a, b) {
      int result;
      switch (_sortColumnIndex) {
        case 0:
          result = a.callsign.compareTo(b.callsign);
          break;
        case 1:
          result = a.lastSeen.compareTo(b.lastSeen);
          break;
        case 2:
          result = a.statsString.compareTo(b.statsString);
          break;
        default:
          result = 0;
      }
      return _sortAscending ? result : -result;
    });
  }

  String _formatLastSeen(DateTime lastSeen) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final diff = now.difference(lastSeen);
    if (diff.inMinutes < 1) {
      return l10n.bbsJustNow;
    } else if (diff.inMinutes < 60) {
      return l10n.bbsMinAgo(diff.inMinutes);
    } else if (diff.inHours < 24) {
      return l10n.bbsHoursAgo(diff.inHours);
    } else {
      return l10n.bbsDaysAgo(diff.inDays);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        _buildHeader(),
        if (HostBridge.isHosted)
          const HostManagedBanner(
            message:
                'The BBS runs on the desktop HTCommander host. Start or stop it '
                'there; this page only mirrors the host.',
          ),
        Expanded(
          child: _viewTraffic
              ? LayoutBuilder(
                  builder: (context, constraints) {
                    final totalHeight = constraints.maxHeight;
                    final trafficHeight = totalHeight * _trafficHeightRatio;
                    final listHeight = totalHeight - trafficHeight - 8;
                    return Column(
                      children: [
                        SizedBox(
                          height: listHeight,
                          child: _buildStationList(),
                        ),
                        _buildSplitter(totalHeight),
                        SizedBox(
                          height: trafficHeight,
                          child: _buildTrafficPanel(),
                        ),
                      ],
                    );
                  },
                )
              : _buildStationList(),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      clipBehavior: Clip.hardEdge,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showButton = constraints.maxWidth > 200;
          return Row(
            children: [
              Text(
                _isActive
                    ? AppLocalizations.of(context).bbsHeaderActive
                    : AppLocalizations.of(context).tabBbs,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              if (constraints.maxWidth > 320 && !HostBridge.isHosted) ...[
                SizedBox(
                  height: 28,
                  child: OutlinedButton(
                    onPressed: () => BbsFilesDialog.show(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    child: Text(AppLocalizations.of(context).bbsFiles),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (showButton) ...[
                SizedBox(
                  height: 28,
                  child: Builder(
                    builder: (btnContext) => ElevatedButton(
                      onPressed: _buttonEnabled
                          ? () => _onActivate(btnContext)
                          : null,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      child: Text(
                        _isActive
                            ? AppLocalizations.of(context).bbsDeactivate
                            : AppLocalizations.of(context).bbsActivate,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
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
          );
        },
      ),
    );
  }

  Widget _buildSplitter(double totalHeight) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (details) {
          setState(() {
            final delta = details.delta.dy;
            final newRatio = _trafficHeightRatio - (delta / totalHeight);
            _trafficHeightRatio = newRatio.clamp(
              _minTrafficRatio,
              _maxTrafficRatio,
            );
          });
        },
        child: Container(
          height: 8,
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          child: Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStationList() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _isCompact = constraints.maxWidth < _compactWidthThreshold;
          return Focus(
            focusNode: _stationFocusNode,
            onKeyEvent: _handleStationKey,
            child: Column(
              children: [
                _buildStationListHeaders(),
                Expanded(
                  child: ListView.builder(
                    controller: _stationScrollController,
                    itemExtent: _stationRowHeight,
                    itemCount: _stations.length,
                    itemBuilder: (context, index) {
                      final station = _stations[index];
                      final isSelected = _selectedStationIndex == index;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onSecondaryTapUp: (d) => _showStationContextMenu(
                          d.globalPosition,
                          station.callsign,
                        ),
                        onLongPressStart: (d) => _showStationContextMenu(
                          d.globalPosition,
                          station.callsign,
                        ),
                        child: InkWell(
                          onTap: () {
                            _stationFocusNode.requestFocus();
                            _onStationSelected(index);
                          },
                          child: Container(
                            clipBehavior: Clip.hardEdge,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? scheme.primaryContainer
                                  : null,
                              border: Border(
                                bottom: BorderSide(
                                  color: scheme.outlineVariant,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                // Icon
                                SizedBox(
                                  width: 32,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 6,
                                    ),
                                    child: Icon(
                                      Icons.person,
                                      size: 18,
                                      color: Colors.blue.shade700,
                                    ),
                                  ),
                                ),
                                // Call sign
                                SizedBox(
                                  width: 100,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 6,
                                    ),
                                    child: Text(
                                      station.callsign,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                // Last seen
                                SizedBox(
                                  width: 80,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 6,
                                    ),
                                    child: Text(
                                      _formatLastSeen(station.lastSeen),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                                // Stats (hidden in compact mode)
                                if (!_isCompact)
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 6,
                                      ),
                                      child: Text(
                                        station.statsString,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12),
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
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStationListHeaders() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: scheme.outline)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 32), // Icon column
          _buildColumnHeader(
            AppLocalizations.of(context).bbsColCallSign,
            0,
            width: 100,
          ),
          _buildColumnHeader(
            AppLocalizations.of(context).bbsColLastSeen,
            1,
            width: 80,
          ),
          if (!_isCompact)
            _buildColumnHeader(
              AppLocalizations.of(context).bbsColStats,
              2,
              flex: 1,
            ),
        ],
      ),
    );
  }

  Widget _buildColumnHeader(
    String title,
    int index, {
    double? width,
    int? flex,
  }) {
    final content = InkWell(
      onTap: () => _sort(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            Flexible(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_sortColumnIndex == index)
              Icon(
                _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 14,
              ),
          ],
        ),
      ),
    );

    if (width != null) {
      return SizedBox(width: width, child: content);
    }
    return Expanded(flex: flex ?? 1, child: content);
  }

  Widget _buildTrafficPanel() {
    final visible = _traffic.where(_isVisible).toList();
    final showCallsign = _selectedSession == null;
    return Container(
      color: Colors.black87,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            height: 28,
            color: Colors.grey.shade800,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Text(
                  AppLocalizations.of(context).bbsTraffic,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(child: _buildSessionPicker()),
              ],
            ),
          ),
          // Traffic content
          Expanded(
            child: SingleChildScrollView(
              controller: _trafficScrollController,
              padding: const EdgeInsets.all(8),
              child: SizedBox(
                width: double.infinity,
                child: SelectableText.rich(
                  TextSpan(
                    children: visible.map((entry) {
                      if (entry.kind != BbsTrafficKind.traffic) {
                        final message = entry.kind == BbsTrafficKind.error
                            ? 'Error: ${entry.message}'
                            : entry.message;
                        // Name the station when several sessions are shown.
                        final text =
                            !showCallsign ||
                                entry.callsign.isEmpty ||
                                message.toUpperCase().contains(entry.callsign)
                            ? message
                            : '${entry.callsign}: $message';
                        return TextSpan(
                          text: '$text\n',
                          style: TextStyle(
                            color: entry.kind == BbsTrafficKind.error
                                ? Colors.redAccent
                                : Colors.yellow,
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        );
                      } else {
                        return TextSpan(
                          children: [
                            TextSpan(
                              text: entry.outgoing
                                  ? '${entry.callsign} < '
                                  : '${entry.callsign} > ',
                              style: const TextStyle(
                                color: Colors.green,
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                            TextSpan(
                              text: '${entry.message}\n',
                              style: TextStyle(
                                color: entry.outgoing
                                    ? Colors.lightBlue
                                    : Colors.grey.shade300,
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          ],
                        );
                      }
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Drop-down next to "Traffic" choosing which session the panel follows.
  Widget _buildSessionPicker() {
    final l10n = AppLocalizations.of(context);
    final selected = _selectedSession;
    final selectedActive =
        selected != null && _sessions.any((s) => s.key == selected.key);
    final label = selected == null
        ? l10n.bbsAllSessionsCount(_sessions.length)
        : selectedActive
        ? _sessionLabel(selected)
        : '${_sessionLabel(selected)} (${l10n.bbsSessionEnded})';
    final anyUnread = _unreadSessions.isNotEmpty;
    const itemStyle = TextStyle(fontSize: 13);

    Widget dot(bool on) => Container(
      width: 8,
      height: 8,
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? Colors.lightGreenAccent : Colors.transparent,
      ),
    );

    String time(DateTime t) =>
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';

    PopupMenuItem<String> sessionItem(BbsSessionInfo s, {bool ended = false}) {
      return PopupMenuItem<String>(
        value: s.key,
        height: 36,
        child: Row(
          children: [
            dot(_unreadSessions.contains(s.key)),
            Text(
              s.callsign,
              style: itemStyle.copyWith(
                fontWeight: s.key == selected?.key ? FontWeight.bold : null,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                ended
                    ? '${_sessionDetail(s)} · ${l10n.bbsSessionEnded}'
                    : '${_sessionDetail(s)} · ${time(s.since)}',
                style: itemStyle.copyWith(color: Colors.grey),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    return PopupMenuButton<String>(
      tooltip: l10n.bbsSessionPickerTooltip,
      position: PopupMenuPosition.under,
      onSelected: (key) => _selectSession(
        key.isEmpty
            ? null
            : _sessions.where((s) => s.key == key).firstOrNull ?? selected,
      ),
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: '',
          height: 36,
          child: Row(
            children: [
              dot(false),
              Text(
                l10n.bbsAllSessions,
                style: itemStyle.copyWith(
                  fontWeight: selected == null ? FontWeight.bold : null,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 8),
        if (_sessions.isEmpty && selected == null)
          PopupMenuItem<String>(
            enabled: false,
            height: 32,
            child: Text(l10n.bbsNoActiveSessions, style: itemStyle),
          ),
        for (final s in _sessions) sessionItem(s),
        if (selected != null && !selectedActive)
          sessionItem(selected, ended: true),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (anyUnread)
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(right: 6),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.lightGreenAccent,
              ),
            ),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ),
          const Icon(Icons.arrow_drop_down, size: 18, color: Colors.white70),
        ],
      ),
    );
  }
}
