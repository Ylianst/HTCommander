import 'dart:io' show File;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../radio/packet_decoder.dart';
import '../radio/tnc_data_fragment.dart';
import '../radio/utils.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import '../services/window_service.dart';

/// Packet direction
enum PacketDirection { incoming, outgoing }

/// A captured packet wrapping a [TncDataFragment], with a cached single-line
/// summary used for the packet list.
class CapturedPacket {
  final TncDataFragment fragment;
  final String summary;

  CapturedPacket(this.fragment)
    : summary = PacketDecoder.fragmentToShortString(fragment);

  DateTime get time => fragment.time;
  String get channel => fragment.channelName;
  PacketDirection get direction =>
      fragment.incoming ? PacketDirection.incoming : PacketDirection.outgoing;
  String get dataHex => RadioUtils.bytesToHex(fragment.data);
}

/// Packets tab - packet inspection and analysis. Subscribes to UniqueDataFrame
/// events (produced by the FrameDeduplicator) and decodes them for display.
class PacketsTab extends StatefulWidget {
  const PacketsTab({super.key});

  @override
  State<PacketsTab> createState() => _PacketsTabState();
}

class _PacketsTabState extends State<PacketsTab>
    with AutomaticKeepAliveClientMixin {
  /// Maximum number of packets to keep in memory.
  static const int _maxPackets = 2000;

  /// Device id used by the PacketStore for its broker messages.
  static const int _storeDeviceId = 1;

  final List<CapturedPacket> _packets = [];
  final DataBrokerClient _broker = DataBrokerClient();

  int? _selectedPacketIndex;
  bool _showDecode = true;
  int _sortColumnIndex = 0;
  bool _sortAscending = false; // Descending by default for time
  double _decodeHeightRatio = 0.35;
  static const double _minDecodeRatio = 0.15;
  static const double _maxDecodeRatio = 0.60;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    // The PacketStore (device 1) owns the packet history and persistence.
    // Subscribe to its events instead of raw UniqueDataFrame events so that
    // packets persisted from previous sessions are replayed here.
    _broker.subscribe(
      deviceId: _storeDeviceId,
      name: 'PacketList',
      callback: _onPacketList,
    );
    _broker.subscribe(
      deviceId: _storeDeviceId,
      name: 'PacketStored',
      callback: _onPacketStored,
    );
    _broker.subscribe(
      deviceId: _storeDeviceId,
      name: 'PacketStoreReady',
      callback: _onPacketStoreReady,
    );

    // If the store is already ready (it was created before this tab), request
    // the loaded packet list right away. Otherwise the request is sent when the
    // PacketStoreReady event arrives.
    final ready = DataBroker.getValue<bool>(
      _storeDeviceId,
      'PacketStoreReady',
      false,
    );
    if (ready == true) {
      _requestPacketList();
    }
  }

  @override
  void dispose() {
    _broker.dispose();
    super.dispose();
  }

  void _requestPacketList() {
    _broker.dispatch(
      deviceId: _storeDeviceId,
      name: 'RequestPacketList',
      data: null,
      store: false,
    );
  }

  void _onPacketStoreReady(int deviceId, String name, Object? data) {
    if (!mounted) return;
    if (data == true) _requestPacketList();
  }

  void _onPacketList(int deviceId, String name, Object? data) {
    if (data is! List<TncDataFragment>) return;
    if (!mounted) return;

    setState(() {
      _packets
        ..clear()
        ..addAll(data.map(CapturedPacket.new));
      _selectedPacketIndex = null;
      _applySort(null);
    });
  }

  void _onPacketStored(int deviceId, String name, Object? data) {
    if (data is! TncDataFragment) return;
    if (!mounted) return;

    setState(() {
      final selected = _selectedPacket;
      _packets.add(CapturedPacket(data));
      if (_packets.length > _maxPackets) {
        _packets.removeAt(0);
      }
      _applySort(selected);
    });
  }

  CapturedPacket? get _selectedPacket {
    if (_selectedPacketIndex == null ||
        _selectedPacketIndex! >= _packets.length) {
      return null;
    }
    return _packets[_selectedPacketIndex!];
  }

  void _onPacketSelected(int index) {
    setState(() {
      _selectedPacketIndex = index;
    });
  }

  void _showPacketContextMenu(
    BuildContext context,
    int index,
    Offset globalPosition,
  ) {
    _onPacketSelected(index);
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        overlay.size.width - globalPosition.dx,
        overlay.size.height - globalPosition.dy,
      ),
      items: const [
        PopupMenuItem<String>(value: 'copyHex', child: Text('Copy HEX packet')),
      ],
    ).then((value) {
      if (value == 'copyHex') {
        _copyPacketHex(index);
      }
    });
  }

  void _copyPacketHex(int index) {
    if (index < 0 || index >= _packets.length) return;
    final hex = _packets[index].dataHex;
    Clipboard.setData(ClipboardData(text: hex));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('HEX packet copied to clipboard')),
      );
    }
  }

  void _clearPackets() {
    // Ask the PacketStore to clear its memory and truncate the file. It will
    // respond with an empty PacketList which updates the UI.
    _broker.dispatch(
      deviceId: _storeDeviceId,
      name: 'ClearPackets',
      data: null,
      store: false,
    );
    setState(() {
      _packets.clear();
      _selectedPacketIndex = null;
    });
  }

  Future<void> _onSaveToFile() async {
    if (_packets.isEmpty) return;

    // Serialize every packet using the same line format the PacketStore uses
    // for persistence: `{microsecondsSinceEpoch},{incoming?1:0},{fragment}`.
    final buffer = StringBuffer();
    for (final packet in _packets) {
      final fragment = packet.fragment;
      buffer
        ..write(fragment.time.microsecondsSinceEpoch)
        ..write(',')
        ..write(fragment.incoming ? 1 : 0)
        ..write(',')
        ..write(fragment.toString())
        ..write('\n');
    }

    String? outputPath;
    try {
      outputPath = await FilePicker.saveFile(
        dialogTitle: 'Save Packet Capture',
        fileName: 'packets',
        type: FileType.custom,
        allowedExtensions: const ['ptcap'],
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening file dialog: $e')),
        );
      }
      return;
    }

    if (outputPath == null) return;

    try {
      await File(outputPath).writeAsString(buffer.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Packet capture saved to $outputPath')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving file: $e')));
      }
    }
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
          value: 'showDecode',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: _showDecode
                    ? const Text('✓', style: TextStyle(fontSize: 14))
                    : null,
              ),
              const Text('Show Packet Decode'),
            ],
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(
          value: 'saveToFile',
          height: menuItemHeight,
          padding: menuItemPadding,
          enabled: _packets.isNotEmpty,
          child: const Row(
            children: [SizedBox(width: 20), Text('Save to File...')],
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(
          value: 'clear',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: const Row(children: [SizedBox(width: 20), Text('Clear')]),
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
        case 'showDecode':
          setState(() => _showDecode = !_showDecode);
          break;
        case 'saveToFile':
          _onSaveToFile();
          break;
        case 'clear':
          _clearPackets();
          break;
        case 'detach':
          windowService.createWindow('packets');
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
        _sortAscending = columnIndex != 0; // Descending for time by default
      }
      _applySort(_selectedPacket);
    });
  }

  void _applySort(CapturedPacket? keepSelected) {
    _packets.sort((a, b) {
      int result;
      switch (_sortColumnIndex) {
        case 0:
          result = a.time.compareTo(b.time);
          break;
        case 1:
          result = a.channel.compareTo(b.channel);
          break;
        case 2:
          result = a.summary.compareTo(b.summary);
          break;
        default:
          result = 0;
      }
      return _sortAscending ? result : -result;
    });
    // Keep the selection pointing at the same packet after sorting.
    if (keepSelected != null) {
      final newIndex = _packets.indexOf(keepSelected);
      _selectedPacketIndex = newIndex >= 0 ? newIndex : null;
    }
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: _showDecode
              ? LayoutBuilder(
                  builder: (context, constraints) {
                    final totalHeight = constraints.maxHeight;
                    final decodeHeight = totalHeight * _decodeHeightRatio;
                    final listHeight = totalHeight - decodeHeight - 8;
                    return Column(
                      children: [
                        SizedBox(height: listHeight, child: _buildPacketList()),
                        _buildSplitter(totalHeight),
                        SizedBox(
                          height: decodeHeight,
                          child: _buildDecodePanel(),
                        ),
                      ],
                    );
                  },
                )
              : _buildPacketList(),
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
          const Text(
            'Packets',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
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
            final newRatio = _decodeHeightRatio - (delta / totalHeight);
            _decodeHeightRatio = newRatio.clamp(
              _minDecodeRatio,
              _maxDecodeRatio,
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

  Widget _buildPacketList() {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          _buildPacketListHeaders(),
          Expanded(
            child: _packets.isEmpty
                ? const Center(
                    child: Text(
                      'No packets captured',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: _packets.length,
                    itemBuilder: (context, index) {
                      final packet = _packets[index];
                      final isSelected = _selectedPacketIndex == index;
                      return InkWell(
                        onTap: () => _onPacketSelected(index),
                        onSecondaryTapDown: (details) => _showPacketContextMenu(
                          context,
                          index,
                          details.globalPosition,
                        ),
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
                              // Direction icon
                              SizedBox(
                                width: 32,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 6,
                                  ),
                                  child: Icon(
                                    packet.direction == PacketDirection.incoming
                                        ? Icons.arrow_downward
                                        : Icons.arrow_upward,
                                    size: 16,
                                    color:
                                        packet.direction ==
                                            PacketDirection.incoming
                                        ? Colors.green
                                        : Colors.blue,
                                  ),
                                ),
                              ),
                              // Time
                              SizedBox(
                                width: 80,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 6,
                                  ),
                                  child: Text(
                                    _formatTime(packet.time),
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                              // Channel
                              SizedBox(
                                width: 80,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 6,
                                  ),
                                  child: Text(
                                    packet.channel,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              ),
                              // Data summary
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 6,
                                  ),
                                  child: Text(
                                    packet.summary,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                    ),
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

  Widget _buildPacketListHeaders() {
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        border: Border(bottom: BorderSide(color: Colors.grey.shade400)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 32), // Icon column
          _buildColumnHeader('Time', 0, width: 80),
          _buildColumnHeader('Channel', 1, width: 80),
          _buildColumnHeader('Data', 2, flex: 1),
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

  Widget _buildDecodePanel() {
    if (_selectedPacket == null) {
      return Container(
        color: Colors.white,
        child: const Center(
          child: Text(
            'Select a packet to view decode',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    final sections = PacketDecoder.decode(_selectedPacket!.fragment);

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
                'Packet Decode',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ),
          // Details list grouped into sections
          Expanded(
            child: ListView(
              children: [
                for (final section in sections) ...[
                  _buildSectionHeader(section.title),
                  for (final entry in section.lines)
                    _buildDetailRow(entry.key, entry.value),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: Colors.grey.shade100,
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 11,
          color: Colors.grey.shade800,
        ),
      ),
    );
  }

  Widget _buildDetailRow(String key, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              key,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
