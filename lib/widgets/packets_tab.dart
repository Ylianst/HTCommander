import 'package:flutter/material.dart';

/// Packet direction
enum PacketDirection { incoming, outgoing }

/// Captured packet data
class CapturedPacket {
  final String id;
  final DateTime time;
  final String channel;
  final PacketDirection direction;
  final List<int> data;
  final String? decodedSummary;
  final Map<String, String> decodeDetails;

  const CapturedPacket({
    required this.id,
    required this.time,
    required this.channel,
    required this.direction,
    required this.data,
    this.decodedSummary,
    this.decodeDetails = const {},
  });

  String get dataHex => data
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(' ');

  String get dataAscii => String.fromCharCodes(
    data.map((b) => (b >= 32 && b < 127) ? b : 46),
  ); // Replace non-printable with '.'
}

/// Packets tab - packet inspection and analysis
class PacketsTab extends StatefulWidget {
  const PacketsTab({super.key});

  @override
  State<PacketsTab> createState() => _PacketsTabState();
}

class _PacketsTabState extends State<PacketsTab>
    with AutomaticKeepAliveClientMixin {
  final List<CapturedPacket> _packets = [];
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
    _addSamplePackets();
  }

  void _addSamplePackets() {
    // Sample packets for demonstration
    _packets.addAll([
      CapturedPacket(
        id: '1',
        time: DateTime.now().subtract(const Duration(minutes: 5)),
        channel: 'APRS',
        direction: PacketDirection.incoming,
        data: [
          0x82, 0xA0, 0x9C, 0x66, 0x60, 0x62, 0x60, // Address
          0x96, 0x68, 0x6C, 0x86, 0xA6, 0x40, 0xE1, // Address
          0x03, 0xF0, // Control & PID
          0x3D, 0x34, 0x30, 0x32, 0x33, 0x2E, 0x35, 0x34, // Position
        ],
        decodedSummary: 'KC3SLD>APRS: =4023.54N/07958.23W-PHG2360',
        decodeDetails: {
          'Channel': 'Received on APRS',
          'Time': DateTime.now()
              .subtract(const Duration(minutes: 5))
              .toString(),
          'Size': '24 bytes',
          'Address 1': 'APRS-0  ---',
          'Address 2': 'KC3SLD-0  --X',
          'Type': 'U-FRAME',
          'Protocol ID': '240',
        },
      ),
      CapturedPacket(
        id: '2',
        time: DateTime.now().subtract(const Duration(minutes: 3)),
        channel: 'APRS',
        direction: PacketDirection.outgoing,
        data: [
          0x82,
          0xA0,
          0x9C,
          0x66,
          0x60,
          0x62,
          0x60,
          0x96,
          0x6A,
          0x6A,
          0x8E,
          0xAE,
          0xB4,
          0xE1,
          0x03,
          0xF0,
          0x21,
          0x34,
          0x30,
          0x32,
          0x33,
          0x2E,
          0x35,
          0x34,
        ],
        decodedSummary: 'KK7VZT>APRS: !4023.54N/07958.23W-',
        decodeDetails: {
          'Channel': 'Sent on APRS',
          'Time': DateTime.now()
              .subtract(const Duration(minutes: 3))
              .toString(),
          'Size': '24 bytes',
          'Address 1': 'APRS-0  ---',
          'Address 2': 'KK7VZT-0  --X',
          'Type': 'U-FRAME',
          'Protocol ID': '240',
        },
      ),
      CapturedPacket(
        id: '3',
        time: DateTime.now().subtract(const Duration(minutes: 1)),
        channel: 'TNC',
        direction: PacketDirection.incoming,
        data: [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08],
        decodedSummary: 'BSS: Test packet',
        decodeDetails: {
          'Channel': 'Received on TNC',
          'Time': DateTime.now()
              .subtract(const Duration(minutes: 1))
              .toString(),
          'Size': '8 bytes',
          'Encoding': 'Hardware AFSK 1200 baud, AX.25, No Corrections',
        },
      ),
    ]);
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

  void _clearPackets() {
    setState(() {
      _packets.clear();
      _selectedPacketIndex = null;
    });
  }

  void _onSaveToFile() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Save to file not implemented yet')),
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
      _packets.sort((a, b) {
        int result;
        switch (columnIndex) {
          case 0:
            result = a.time.compareTo(b.time);
            break;
          case 1:
            result = a.channel.compareTo(b.channel);
            break;
          case 2:
            result = (a.decodedSummary ?? a.dataHex).compareTo(
              b.decodedSummary ?? b.dataHex,
            );
            break;
          default:
            result = 0;
        }
        return _sortAscending ? result : -result;
      });
    });
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
            child: ListView.builder(
              itemCount: _packets.length,
              itemBuilder: (context, index) {
                final packet = _packets[index];
                final isSelected = _selectedPacketIndex == index;
                return InkWell(
                  onTap: () => _onPacketSelected(index),
                  child: Container(
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
                                  packet.direction == PacketDirection.incoming
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
                              packet.decodedSummary ?? packet.dataHex,
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

    final packet = _selectedPacket!;
    final details = <MapEntry<String, String>>[
      MapEntry(
        'Direction',
        packet.direction == PacketDirection.incoming ? 'Received' : 'Sent',
      ),
      MapEntry('Time', packet.time.toString()),
      MapEntry('Size', '${packet.data.length} bytes'),
      ...packet.decodeDetails.entries,
      MapEntry('Data ASCII', packet.dataAscii),
      MapEntry('Data HEX', packet.dataHex),
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
                'Packet Decode',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ),
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
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
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
}
