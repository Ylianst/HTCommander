import 'package:flutter/material.dart';
import '../handlers/bbs_handler.dart';
import '../l10n/app_localizations.dart';
import '../radio/radio_models.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import '../services/window_service.dart';

/// BBS traffic entry
class BbsTrafficEntry {
  final String callsign;
  final bool outgoing;
  final String message;
  final bool isControl;

  const BbsTrafficEntry({
    required this.callsign,
    required this.message,
    this.outgoing = false,
    this.isControl = false,
  });
}

/// BBS tab - Bulletin Board System
class BbsTab extends StatefulWidget {
  const BbsTab({super.key});

  @override
  State<BbsTab> createState() => _BbsTabState();
}

class _BbsTabState extends State<BbsTab> with AutomaticKeepAliveClientMixin {
  final DataBrokerClient _broker = DataBrokerClient();
  final List<MergedStationStats> _stations = [];
  final List<BbsTrafficEntry> _traffic = [];
  final ScrollController _trafficScrollController = ScrollController();

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

    // BBS conversation traffic and control/error messages (dispatched on dev 0).
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'BbsTraffic',
      callback: _onBbsTraffic,
    );
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'BbsControlMessage',
      callback: _onBbsControlMessage,
    );
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'BbsError',
      callback: _onBbsError,
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
  }

  @override
  void dispose() {
    _broker.dispose();
    _trafficScrollController.dispose();
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

  bool get _buttonEnabled => _isActive || _availableRadios.isNotEmpty;

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
  // Traffic
  // ---------------------------------------------------------------------------

  void _onBbsTraffic(int deviceId, String name, Object? data) {
    if (data is! BbsTrafficData) return;
    _addTrafficEntry(
      BbsTrafficEntry(
        callsign: data.callsign,
        outgoing: data.outgoing,
        message: data.message,
      ),
    );
  }

  void _onBbsControlMessage(int deviceId, String name, Object? data) {
    if (data is! BbsControlMessageData) return;
    _addTrafficEntry(
      BbsTrafficEntry(callsign: '', message: data.message, isControl: true),
    );
  }

  void _onBbsError(int deviceId, String name, Object? data) {
    if (data is! BbsErrorEventData) return;
    _addTrafficEntry(
      BbsTrafficEntry(
        callsign: '',
        message: 'Error: ${data.error}',
        isControl: true,
      ),
    );
  }

  void _onStationSelected(int index) {
    setState(() {
      _selectedStationIndex = index;
    });
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
                  : AppLocalizations.of(context).riRadioFallback(
                      r['DeviceId'] as int,
                    ),
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

  void _addTrafficEntry(BbsTrafficEntry entry) {
    setState(() {
      _traffic.add(entry);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_trafficScrollController.hasClients) {
        _trafficScrollController.animateTo(
          _trafficScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clearTraffic() {
    setState(() {
      _traffic.clear();
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
        case 'detach':
          windowService.createWindow('bbs');
          break;
      }
    });
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
          return Column(
            children: [
              _buildStationListHeaders(),
              Expanded(
                child: ListView.builder(
                  itemCount: _stations.length,
                  itemBuilder: (context, index) {
                    final station = _stations[index];
                    final isSelected = _selectedStationIndex == index;
                    return InkWell(
                      onTap: () => _onStationSelected(index),
                      child: Container(
                        clipBehavior: Clip.hardEdge,
                        decoration: BoxDecoration(
                          color: isSelected ? scheme.primaryContainer : null,
                          border: Border(
                            bottom: BorderSide(color: scheme.outlineVariant),
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
                    );
                  },
                ),
              ),
            ],
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
          _buildColumnHeader(AppLocalizations.of(context).bbsColCallSign, 0, width: 100),
          _buildColumnHeader(AppLocalizations.of(context).bbsColLastSeen, 1, width: 80),
          if (!_isCompact)
            _buildColumnHeader(AppLocalizations.of(context).bbsColStats, 2, flex: 1),
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
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                AppLocalizations.of(context).bbsTraffic,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: Colors.white,
                ),
              ),
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
                    children: _traffic.map((entry) {
                      if (entry.isControl) {
                        return TextSpan(
                          text: '${entry.message}\n',
                          style: const TextStyle(
                            color: Colors.yellow,
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
}
