import 'package:flutter/material.dart';

/// BBS station stats
class BbsStationStats {
  final String callsign;
  final DateTime lastSeen;
  final String protocol;
  final int packetsIn;
  final int packetsOut;
  final int bytesIn;
  final int bytesOut;

  const BbsStationStats({
    required this.callsign,
    required this.lastSeen,
    this.protocol = 'AX.25',
    this.packetsIn = 0,
    this.packetsOut = 0,
    this.bytesIn = 0,
    this.bytesOut = 0,
  });

  String get statsString =>
      '$protocol, $packetsIn in / $packetsOut out, $bytesIn bytes in / $bytesOut bytes out';
}

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
  final List<BbsStationStats> _stations = [];
  final List<BbsTrafficEntry> _traffic = [];
  final ScrollController _trafficScrollController = ScrollController();
  int? _selectedStationIndex;
  bool _viewTraffic = true;
  bool _isActivated = false;
  int _sortColumnIndex = 0;
  bool _sortAscending = true;
  double _trafficHeightRatio = 0.35;
  static const double _minTrafficRatio = 0.15;
  static const double _maxTrafficRatio = 0.60;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _addSampleData();
  }

  @override
  void dispose() {
    _trafficScrollController.dispose();
    super.dispose();
  }

  void _addSampleData() {
    _stations.addAll([
      BbsStationStats(
        callsign: 'KC3SLD',
        lastSeen: DateTime.now().subtract(const Duration(minutes: 5)),
        protocol: 'AX.25',
        packetsIn: 42,
        packetsOut: 38,
        bytesIn: 4200,
        bytesOut: 3800,
      ),
      BbsStationStats(
        callsign: 'KK7VZT',
        lastSeen: DateTime.now().subtract(const Duration(minutes: 15)),
        protocol: 'AX.25',
        packetsIn: 18,
        packetsOut: 22,
        bytesIn: 1800,
        bytesOut: 2200,
      ),
      BbsStationStats(
        callsign: 'N0CALL',
        lastSeen: DateTime.now().subtract(const Duration(hours: 1)),
        protocol: 'AX.25',
        packetsIn: 5,
        packetsOut: 3,
        bytesIn: 500,
        bytesOut: 300,
      ),
    ]);

    _traffic.addAll([
      const BbsTrafficEntry(
        callsign: '',
        message: 'BBS mode activated',
        isControl: true,
      ),
      const BbsTrafficEntry(
        callsign: 'KC3SLD',
        message: 'Hello, anyone there?',
        outgoing: false,
      ),
      const BbsTrafficEntry(
        callsign: 'KC3SLD',
        message: 'Yes, reading you loud and clear!',
        outgoing: true,
      ),
      const BbsTrafficEntry(
        callsign: 'KK7VZT',
        message: 'Good morning! Checking in.',
        outgoing: false,
      ),
      const BbsTrafficEntry(
        callsign: 'KK7VZT',
        message: 'Good morning! Welcome to the net.',
        outgoing: true,
      ),
    ]);
  }

  BbsStationStats? get _selectedStation {
    if (_selectedStationIndex == null ||
        _selectedStationIndex! >= _stations.length) {
      return null;
    }
    return _stations[_selectedStationIndex!];
  }

  void _onStationSelected(int index) {
    setState(() {
      _selectedStationIndex = index;
    });
  }

  void _onActivate() {
    setState(() {
      _isActivated = !_isActivated;
    });
    if (_isActivated) {
      _addTrafficEntry(
        const BbsTrafficEntry(
          callsign: '',
          message: 'BBS mode activated',
          isControl: true,
        ),
      );
    } else {
      _addTrafficEntry(
        const BbsTrafficEntry(
          callsign: '',
          message: 'BBS mode deactivated',
          isControl: true,
        ),
      );
    }
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
    setState(() {
      _stations.clear();
      _selectedStationIndex = null;
    });
  }

  void _showMenu(BuildContext context) {
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
              const Text('View Traffic'),
            ],
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(
          value: 'clearTraffic',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: const Row(
            children: [SizedBox(width: 20), Text('Clear Traffic')],
          ),
        ),
        PopupMenuItem<String>(
          value: 'clearStats',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: const Row(
            children: [SizedBox(width: 20), Text('Clear Stats')],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'viewTraffic':
          setState(() => _viewTraffic = !_viewTraffic);
          break;
        case 'clearTraffic':
          _clearTraffic();
          break;
        case 'clearStats':
          _clearStats();
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
      _stations.sort((a, b) {
        int result;
        switch (columnIndex) {
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
    });
  }

  String _formatLastSeen(DateTime lastSeen) {
    final now = DateTime.now();
    final diff = now.difference(lastSeen);
    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
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
      color: const Color(0xFFC0C0C0),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Text(
            _isActivated ? 'BBS - Active' : 'BBS',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const Spacer(),
          SizedBox(
            height: 28,
            child: ElevatedButton(
              onPressed: _onActivate,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                textStyle: const TextStyle(fontSize: 12),
              ),
              child: Text(_isActivated ? 'Deactivate' : 'Activate'),
            ),
          ),
          const SizedBox(width: 8),
          Builder(
            builder: (context) => InkWell(
              onTap: () => _showMenu(context),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Image.asset(
                  'assets/images/MenuIcon.png',
                  width: 24,
                  height: 24,
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
          color: const Color(0xFFC0C0C0),
          child: Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade600,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStationList() {
    return Container(
      color: Colors.white,
      child: Column(
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
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.blue.shade100 : null,
                      border: Border(
                        bottom: BorderSide(color: Colors.grey.shade300),
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
                        // Stats
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
      ),
    );
  }

  Widget _buildStationListHeaders() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        border: Border(bottom: BorderSide(color: Colors.grey.shade400)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 32), // Icon column
          _buildColumnHeader('Call Sign', 0, width: 100),
          _buildColumnHeader('Last Seen', 1, width: 80),
          _buildColumnHeader('Stats', 2, flex: 1),
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
            child: const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Traffic',
                style: TextStyle(
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
