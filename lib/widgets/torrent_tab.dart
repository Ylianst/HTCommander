import 'package:flutter/material.dart';
import '../services/window_service.dart';

/// Torrent file mode
enum TorrentMode { pause, sharing, request, error }

/// Torrent compression type
enum TorrentCompression { unknown, none, brotli, deflate }

/// Torrent file data
class TorrentFile {
  final String id;
  final String fileName;
  final String? description;
  final String callsign;
  final int stationId;
  final int size;
  final int compressedSize;
  final TorrentCompression compression;
  final TorrentMode mode;
  final bool completed;
  final int totalBlocks;
  final int receivedBlocks;

  const TorrentFile({
    required this.id,
    required this.fileName,
    this.description,
    required this.callsign,
    this.stationId = 0,
    required this.size,
    this.compressedSize = 0,
    this.compression = TorrentCompression.unknown,
    this.mode = TorrentMode.pause,
    this.completed = false,
    this.totalBlocks = 0,
    this.receivedBlocks = 0,
  });

  String get source => stationId > 0 ? '$callsign-$stationId' : callsign;

  double get progress => totalBlocks > 0 ? receivedBlocks / totalBlocks : 0.0;
}

/// Torrent tab - file transfer functionality
class TorrentTab extends StatefulWidget {
  const TorrentTab({super.key});

  @override
  State<TorrentTab> createState() => _TorrentTabState();
}

class _TorrentTabState extends State<TorrentTab>
    with AutomaticKeepAliveClientMixin {
  final List<TorrentFile> _torrents = [];
  int? _selectedTorrentIndex;
  bool _showDetails = true;
  bool _isActivated = false;
  int _sortColumnIndex = 0;
  bool _sortAscending = true;
  double _detailsHeightRatio = 0.35;
  static const double _minDetailsRatio = 0.15;
  static const double _maxDetailsRatio = 0.60;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _addSampleTorrents();
  }

  void _addSampleTorrents() {
    _torrents.addAll([
      const TorrentFile(
        id: '1',
        fileName: 'weather_map.png',
        description: 'Regional weather map',
        callsign: 'KC3SLD',
        stationId: 0,
        size: 45678,
        compressedSize: 32000,
        compression: TorrentCompression.brotli,
        mode: TorrentMode.sharing,
        completed: true,
        totalBlocks: 20,
        receivedBlocks: 20,
      ),
      const TorrentFile(
        id: '2',
        fileName: 'bulletin.txt',
        description: 'Weekly ARES bulletin',
        callsign: 'KC3SLD',
        stationId: 1,
        size: 2048,
        compressedSize: 1500,
        compression: TorrentCompression.deflate,
        mode: TorrentMode.sharing,
        completed: true,
        totalBlocks: 2,
        receivedBlocks: 2,
      ),
      const TorrentFile(
        id: '3',
        fileName: 'emergency_plan.pdf',
        description: 'Emergency response plan v2',
        callsign: 'KK7VZT',
        stationId: 0,
        size: 125000,
        compressedSize: 98000,
        compression: TorrentCompression.brotli,
        mode: TorrentMode.request,
        completed: false,
        totalBlocks: 50,
        receivedBlocks: 35,
      ),
      const TorrentFile(
        id: '4',
        fileName: 'frequency_list.csv',
        description: 'Local repeater frequencies',
        callsign: 'N0CALL',
        stationId: 0,
        size: 4096,
        mode: TorrentMode.pause,
        completed: false,
        totalBlocks: 4,
        receivedBlocks: 0,
      ),
    ]);
  }

  TorrentFile? get _selectedTorrent {
    if (_selectedTorrentIndex == null ||
        _selectedTorrentIndex! >= _torrents.length) {
      return null;
    }
    return _torrents[_selectedTorrentIndex!];
  }

  // Group torrents by callsign
  Map<String, List<TorrentFile>> get _groupedTorrents {
    final groups = <String, List<TorrentFile>>{};
    for (final torrent in _torrents) {
      final key = torrent.source;
      groups.putIfAbsent(key, () => []).add(torrent);
    }
    return groups;
  }

  void _onTorrentSelected(int index) {
    setState(() {
      _selectedTorrentIndex = index;
    });
  }

  void _onAddFile() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Add file dialog not implemented yet')),
    );
  }

  void _onActivate() {
    setState(() {
      _isActivated = !_isActivated;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isActivated ? 'Torrent mode activated' : 'Torrent mode deactivated',
        ),
      ),
    );
  }

  void _onDelete() {
    if (_selectedTorrentIndex == null) return;
    setState(() {
      _torrents.removeAt(_selectedTorrentIndex!);
      _selectedTorrentIndex = null;
    });
  }

  void _onSaveAs() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Save as not implemented yet')),
    );
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
          value: 'showDetails',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: _showDetails
                    ? const Text('✓', style: TextStyle(fontSize: 14))
                    : null,
              ),
              const Text('Show Details'),
            ],
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(
          value: 'saveAs',
          height: menuItemHeight,
          padding: menuItemPadding,
          enabled: _selectedTorrent?.completed == true,
          child: const Row(children: [SizedBox(width: 20), Text('Save As...')]),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(
          value: 'delete',
          height: menuItemHeight,
          padding: menuItemPadding,
          enabled: _selectedTorrent != null,
          child: const Row(children: [SizedBox(width: 20), Text('Delete')]),
        ),
        if (windowService.canDetach) ...[
          const PopupMenuDivider(height: 8),
          PopupMenuItem<String>(
            value: 'detach',
            height: menuItemHeight,
            padding: menuItemPadding,
            child: const Row(
              children: [SizedBox(width: 20), Text('Detach...')],
            ),
          ),
        ],
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'showDetails':
          setState(() => _showDetails = !_showDetails);
          break;
        case 'saveAs':
          _onSaveAs();
          break;
        case 'delete':
          _onDelete();
          break;
        case 'detach':
          windowService.createWindow('torrent');
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
      _torrents.sort((a, b) {
        int result;
        switch (columnIndex) {
          case 0:
            result = a.fileName.compareTo(b.fileName);
            break;
          case 1:
            result = a.mode.index.compareTo(b.mode.index);
            break;
          case 2:
            result = (a.description ?? '').compareTo(b.description ?? '');
            break;
          default:
            result = 0;
        }
        return _sortAscending ? result : -result;
      });
    });
  }

  String _modeToString(TorrentMode mode) {
    switch (mode) {
      case TorrentMode.pause:
        return 'Paused';
      case TorrentMode.sharing:
        return 'Sharing';
      case TorrentMode.request:
        return 'Requesting';
      case TorrentMode.error:
        return 'Error';
    }
  }

  String _compressionToString(TorrentCompression compression) {
    switch (compression) {
      case TorrentCompression.unknown:
        return 'Unknown';
      case TorrentCompression.none:
        return 'None';
      case TorrentCompression.brotli:
        return 'Brotli';
      case TorrentCompression.deflate:
        return 'Deflate';
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: _showDetails
              ? LayoutBuilder(
                  builder: (context, constraints) {
                    final totalHeight = constraints.maxHeight;
                    final detailsHeight = totalHeight * _detailsHeightRatio;
                    final listHeight = totalHeight - detailsHeight - 8;
                    return Column(
                      children: [
                        SizedBox(
                          height: listHeight,
                          child: _buildTorrentList(),
                        ),
                        _buildSplitter(totalHeight),
                        SizedBox(
                          height: detailsHeight,
                          child: _buildDetailsPanel(),
                        ),
                      ],
                    );
                  },
                )
              : _buildTorrentList(),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 40,
      decoration: const BoxDecoration(color: Color(0xFFC0C0C0)),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      clipBehavior: Clip.hardEdge,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showButtons = constraints.maxWidth > 300;
          return Row(
            children: [
              const Text(
                'Torrent',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              if (showButtons) ...[
                SizedBox(
                  height: 28,
                  child: ElevatedButton(
                    onPressed: _onAddFile,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    child: const Text('Add File'),
                  ),
                ),
                const SizedBox(width: 8),
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
            final newRatio = _detailsHeightRatio - (delta / totalHeight);
            _detailsHeightRatio = newRatio.clamp(
              _minDetailsRatio,
              _maxDetailsRatio,
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

  Widget _buildTorrentList() {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          _buildTorrentListHeaders(),
          Expanded(
            child: ListView.builder(
              itemCount: _torrents.length,
              itemBuilder: (context, index) {
                final torrent = _torrents[index];
                final isSelected = _selectedTorrentIndex == index;
                return InkWell(
                  onTap: () => _onTorrentSelected(index),
                  child: Container(
                    clipBehavior: Clip.hardEdge,
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.blue.shade100 : null,
                      border: Border(
                        bottom: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    child: Row(
                      children: [
                        // Status icon
                        SizedBox(
                          width: 32,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 6,
                            ),
                            child: Icon(
                              torrent.completed
                                  ? Icons.check_circle
                                  : Icons.downloading,
                              size: 18,
                              color: torrent.completed
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                          ),
                        ),
                        // File name
                        Expanded(
                          flex: 2,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 6,
                            ),
                            child: Text(
                              torrent.fileName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                        // Mode
                        SizedBox(
                          width: 80,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 6,
                            ),
                            child: Text(
                              _modeToString(torrent.mode),
                              style: TextStyle(
                                fontSize: 12,
                                color: torrent.mode == TorrentMode.error
                                    ? Colors.red
                                    : null,
                              ),
                            ),
                          ),
                        ),
                        // Description
                        Expanded(
                          flex: 2,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 6,
                            ),
                            child: Text(
                              torrent.description ?? '',
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

  Widget _buildTorrentListHeaders() {
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        border: Border(bottom: BorderSide(color: Colors.grey.shade400)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 32), // Icon column
          _buildColumnHeader('File', 0, flex: 2),
          _buildColumnHeader('Mode', 1, width: 80),
          _buildColumnHeader('Description', 2, flex: 2),
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

  Widget _buildDetailsPanel() {
    if (_selectedTorrent == null) {
      return Container(
        color: Colors.white,
        child: const Center(
          child: Text(
            'Select a torrent to view details',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    final torrent = _selectedTorrent!;
    final details = <MapEntry<String, String>>[
      MapEntry('File name', torrent.fileName),
      if (torrent.description != null)
        MapEntry('Description', torrent.description!),
      MapEntry('Source', torrent.source),
      MapEntry('File size', '${torrent.size} bytes'),
      if (torrent.compression != TorrentCompression.unknown)
        MapEntry(
          'Compression',
          torrent.compressedSize > 0
              ? '${_compressionToString(torrent.compression)}, ${torrent.compressedSize} bytes'
              : _compressionToString(torrent.compression),
        ),
      MapEntry('Mode', _modeToString(torrent.mode)),
      if (torrent.totalBlocks > 0)
        MapEntry(
          'Blocks',
          '${torrent.receivedBlocks} / ${torrent.totalBlocks}',
        ),
    ];

    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            height: 28,
            color: Colors.grey.shade200,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Torrent Details',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ),
          // Progress bar
          if (torrent.totalBlocks > 0) _buildProgressBar(torrent),
          // Details list
          Expanded(
            child: ListView.builder(
              itemCount: details.length,
              itemBuilder: (context, index) {
                final entry = details[index];
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 100,
                        child: Text(
                          entry.key,
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(
                        child: SelectableText(
                          entry.value,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(TorrentFile torrent) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: torrent.progress,
                backgroundColor: Colors.grey.shade300,
                valueColor: AlwaysStoppedAnimation<Color>(
                  torrent.completed ? Colors.green : Colors.blue,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${(torrent.progress * 100).toStringAsFixed(0)}%',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
