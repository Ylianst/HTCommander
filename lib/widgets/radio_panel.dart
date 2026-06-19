import 'package:flutter/material.dart';

/// Radio channel info
class RadioChannelInfo {
  final int channelId;
  final String name;
  final int rxFreq;
  final int txFreq;

  RadioChannelInfo({
    required this.channelId,
    required this.name,
    required this.rxFreq,
    this.txFreq = 0,
  });

  String get frequencyDisplay {
    if (rxFreq == 0) return '';
    return (rxFreq / 1000000).toStringAsFixed(3);
  }
}

/// Radio panel control widget - displays radio image, VFO frequencies, and status
class RadioPanelControl extends StatefulWidget {
  const RadioPanelControl({super.key});

  @override
  State<RadioPanelControl> createState() => _RadioPanelControlState();
}

class _RadioPanelControlState extends State<RadioPanelControl> {
  // Connection state
  bool _isConnected = false;
  bool _isConnecting = false;
  String _connectionState = 'Disconnected';
  String _friendlyName = '';

  // Radio display state
  String _vfo1Label = '';
  String _vfo1Freq = '';
  String _vfo1Status = '';
  String _vfo2Label = '';
  String _vfo2Freq = '';
  String _vfo2Status = '';
  String _gpsStatus = '';
  bool _voiceProcessing = false;
  int _rssi = 0;
  bool _isTransmitting = false;

  // VFO colors
  Color _vfo1Color = const Color(0xFFD3D3D3); // LightGray
  Color _vfo2Color = const Color(0xFFD3D3D3); // LightGray

  // Channels
  List<RadioChannelInfo> _channels = [];
  int _selectedChannelA = -1;
  int _selectedChannelB = -1;
  bool _dualChannel = false;
  bool _showAllChannels = true;

  // Display panel background color (same as C# app)
  static const Color _displayBgColor = Color(0xFF565658);
  static const Color _activeVfoColor = Color(0xFFDDD300); // Yellow when active

  @override
  void initState() {
    super.initState();
    // Initialize with some demo data
    _initDemoData();
  }

  void _initDemoData() {
    // Demo channels
    _channels = [
      RadioChannelInfo(channelId: 0, name: 'APRS', rxFreq: 144390000),
      RadioChannelInfo(channelId: 1, name: 'Simplex', rxFreq: 146520000),
      RadioChannelInfo(channelId: 2, name: 'Repeater', rxFreq: 146940000),
      RadioChannelInfo(channelId: 3, name: 'Weather', rxFreq: 162550000),
      RadioChannelInfo(channelId: 4, name: 'FRS 1', rxFreq: 462562500),
      RadioChannelInfo(channelId: 5, name: 'GMRS 1', rxFreq: 462550000),
    ];
  }

  void _onConnect() {
    setState(() {
      _isConnecting = true;
      _connectionState = 'Connecting...';
    });

    // Simulate connection
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _isConnected = true;
          _connectionState = 'Connected';
          _friendlyName = 'VR-N76';

          // Set demo VFO data
          _vfo1Label = 'APRS';
          _vfo1Freq = '144.390 MHz';
          _vfo1Status = '';
          _vfo2Label = 'Simplex';
          _vfo2Freq = '146.520 MHz';
          _vfo2Status = '';
          _gpsStatus = 'GPS: 3D Fix';
          _rssi = 8;
          _selectedChannelA = 0;
          _selectedChannelB = 1;
          _dualChannel = true;
          _vfo1Color = _activeVfoColor;
          _vfo2Color = const Color(0xFFD3D3D3);
        });
      }
    });
  }

  void _onDisconnect() {
    setState(() {
      _isConnected = false;
      _isConnecting = false;
      _connectionState = 'Disconnected';
      _friendlyName = '';
      _vfo1Label = '';
      _vfo1Freq = '';
      _vfo1Status = '';
      _vfo2Label = '';
      _vfo2Freq = '';
      _vfo2Status = '';
      _gpsStatus = '';
      _rssi = 0;
      _isTransmitting = false;
      _voiceProcessing = false;
    });
  }

  void _onChannelTap(int channelId) {
    setState(() {
      _selectedChannelA = channelId;
      if (_channels.isNotEmpty && channelId < _channels.length) {
        final channel = _channels[channelId];
        _vfo1Label = channel.name;
        _vfo1Freq = '${channel.frequencyDisplay} MHz';
      }
    });
  }

  void _setChannelA(int channelId) {
    setState(() {
      _selectedChannelA = channelId;
      if (_channels.isNotEmpty && channelId < _channels.length) {
        final channel = _channels[channelId];
        _vfo1Label = channel.name;
        _vfo1Freq = '${channel.frequencyDisplay} MHz';
        _vfo1Color = _activeVfoColor;
      }
    });
  }

  void _setChannelB(int channelId) {
    setState(() {
      _selectedChannelB = channelId;
      _dualChannel = true;
      if (_channels.isNotEmpty && channelId < _channels.length) {
        final channel = _channels[channelId];
        _vfo2Label = channel.name;
        _vfo2Freq = '${channel.frequencyDisplay} MHz';
      }
    });
  }

  void _showChannelDetails(RadioChannelInfo channel) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          channel.name.isNotEmpty
              ? channel.name
              : 'Channel ${channel.channelId + 1}',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Channel ID: ${channel.channelId + 1}'),
            if (channel.rxFreq > 0)
              Text('RX Frequency: ${channel.frequencyDisplay} MHz'),
            if (channel.txFreq > 0)
              Text(
                'TX Frequency: ${(channel.txFreq / 1000000).toStringAsFixed(3)} MHz',
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showChannelContextMenu(
    BuildContext context,
    Offset position,
    RadioChannelInfo channel,
  ) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem<String>(value: 'show', child: Text('Show')),
        PopupMenuItem<String>(
          value: 'setA',
          enabled: channel.channelId != _selectedChannelA,
          child: const Text('Set VFO A'),
        ),
        PopupMenuItem<String>(
          value: 'setB',
          enabled: channel.channelId != _selectedChannelB,
          child: const Text('Set VFO B'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'showAll',
          child: Row(
            children: [
              if (_showAllChannels)
                const Icon(Icons.check, size: 18)
              else
                const SizedBox(width: 18),
              const SizedBox(width: 8),
              const Text('Show All Channels'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'show':
          _showChannelDetails(channel);
          break;
        case 'setA':
          _setChannelA(channel.channelId);
          break;
        case 'setB':
          _setChannelB(channel.channelId);
          break;
        case 'showAll':
          setState(() {
            _showAllChannels = !_showAllChannels;
          });
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF808080), // 50% gray
      child: Column(
        children: [
          // Radio image with overlaid display
          Expanded(child: _buildRadioDisplay()),
          // Bottom panel - connect button or channels
          _buildBottomPanel(),
        ],
      ),
    );
  }

  Widget _buildRadioDisplay() {
    // Radio.png dimensions: 341x848, aspect ratio ~2.486
    // Display panel position in original image: (84, 215) size (205, 189)
    const double imageAspectRatio = 848 / 341;
    const double displayLeft = 84 / 341;
    const double displayTop = 215 / 848;
    const double displayWidth = 205 / 341;
    const double displayHeight = 189 / 848;
    const double friendlyNameTop =
        106 / 848; // Approximate position above display

    // Fixed radio width for consistent appearance
    const double fixedImageWidth = 280.0;

    // Pixel adjustments for fine-tuning
    const double displayLeftOffset = -8.0;
    const double friendlyNameTopOffset = 8.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Use fixed image width, centered in container
        final double imageWidth = fixedImageWidth;
        // Calculate left margin to center the radio
        final double leftMargin = (constraints.maxWidth - imageWidth) / 2;
        // Calculate scaled image height based on fixed width
        final double scaledImageHeight = imageWidth * imageAspectRatio;

        // RSSI bar position: just below GPS text
        final double rssiTop =
            scaledImageHeight * (displayTop + displayHeight) + 2 - 50;

        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // Radio background image - fixed width, centered
            Positioned(
              top: 0,
              left: leftMargin,
              width: imageWidth,
              height: scaledImageHeight,
              child: Image.asset(
                'assets/images/Radio.png',
                fit: BoxFit.fitWidth,
                alignment: Alignment.topCenter,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.grey.shade800,
                    child: const Center(
                      child: Icon(
                        Icons.radio,
                        size: 100,
                        color: Colors.white54,
                      ),
                    ),
                  );
                },
              ),
            ),

            // Overlay the display panel on top of the radio LCD area
            Positioned(
              left: leftMargin + (imageWidth * displayLeft) + displayLeftOffset,
              top: scaledImageHeight * displayTop,
              width: imageWidth * displayWidth,
              child: _buildDisplayPanel(),
            ),

            // Friendly name overlay (above the display)
            if (_friendlyName.isNotEmpty)
              Positioned(
                left: leftMargin,
                width: imageWidth,
                top:
                    scaledImageHeight * friendlyNameTop + friendlyNameTopOffset,
                child: Center(
                  child: Text(
                    _friendlyName,
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ),

            // RSSI / Transmit bar
            if (_isConnected && (_rssi > 0 || _isTransmitting))
              Positioned(
                left:
                    leftMargin + (imageWidth * displayLeft) + displayLeftOffset,
                top: rssiTop,
                width: imageWidth * displayWidth,
                height: 6,
                child: _isTransmitting
                    ? Container(color: Colors.red)
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(1),
                        child: LinearProgressIndicator(
                          value: _rssi / 15,
                          backgroundColor: _displayBgColor,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Colors.green,
                          ),
                        ),
                      ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildDisplayPanel() {
    if (!_isConnected) {
      // Show connection state when not connected
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _displayBgColor,
          borderRadius: BorderRadius.circular(2),
        ),
        child: Center(
          child: Text(
            _connectionState,
            style: const TextStyle(
              color: Color(0xFFD3D3D3),
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // Connected panel with VFO info
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: _displayBgColor,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // VFO 1 - shifted up 20px
          Transform.translate(
            offset: const Offset(0, -20),
            child: _buildVfo1Row(),
          ),
          // Divider line - shifted up 14px
          Transform.translate(
            offset: const Offset(0, -14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Container(height: 1, color: const Color(0xFF999999)),
            ),
          ),
          // VFO 2 - shifted up 14px
          Transform.translate(
            offset: const Offset(0, -14),
            child: _buildVfo2Row(),
          ),
          // Bottom row: Voice indicator and GPS status - shifted up 12px
          Transform.translate(
            offset: const Offset(0, -12),
            child: _buildStatusRow(),
          ),
        ],
      ),
    );
  }

  Widget _buildVfo1Row() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // VFO1 main label (channel name) - large font
        SizedBox(
          height: 32,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _vfo1Label.isEmpty ? '' : _vfo1Label,
                style: TextStyle(
                  color: _vfo1Color,
                  fontSize: 22,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
        // Frequency and status row
        Row(
          children: [
            Expanded(
              child: Text(
                _vfo1Freq,
                style: TextStyle(color: _vfo1Color, fontSize: 10),
              ),
            ),
            Text(
              _vfo1Status,
              style: TextStyle(color: _vfo1Color, fontSize: 10),
              textAlign: TextAlign.right,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildVfo2Row() {
    if (_vfo2Label.isEmpty && _vfo2Freq.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // VFO2 main label (channel name) - large font
        SizedBox(
          height: 32,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _vfo2Label.isEmpty ? '' : _vfo2Label,
                style: TextStyle(
                  color: _vfo2Color,
                  fontSize: 22,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
        // Frequency and status row
        Row(
          children: [
            Expanded(
              child: Text(
                _vfo2Freq,
                style: TextStyle(color: _vfo2Color, fontSize: 10),
              ),
            ),
            Text(
              _vfo2Status,
              style: TextStyle(color: _vfo2Color, fontSize: 10),
              textAlign: TextAlign.right,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusRow() {
    return Row(
      children: [
        // Voice processing indicator
        if (_voiceProcessing)
          const Text(
            '●',
            style: TextStyle(color: Color(0xFFD3D3D3), fontSize: 12),
          ),
        const Spacer(),
        // GPS status
        Text(
          _gpsStatus,
          style: TextStyle(color: Colors.grey.shade500, fontSize: 10),
          textAlign: TextAlign.right,
        ),
      ],
    );
  }

  Widget _buildBottomPanel() {
    if (_isConnected) {
      // Show channels panel when connected
      return _buildChannelsPanel();
    } else {
      // Show connect button when disconnected
      return _buildConnectPanel();
    }
  }

  Widget _buildConnectPanel() {
    return Container(
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        width: double.infinity,
        height: 44,
        child: ElevatedButton(
          onPressed: _isConnecting ? null : _onConnect,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          child: Text(_isConnecting ? 'Connecting...' : 'Connect'),
        ),
      ),
    );
  }

  Widget _buildChannelsPanel() {
    if (_channels.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      color: const Color(0xFFBDB76B), // DarkKhaki
      constraints: const BoxConstraints(maxHeight: 150),
      child: GridView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.all(4),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 2.5,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemCount: _channels.length,
        itemBuilder: (context, index) {
          final channel = _channels[index];
          final isChannelA = channel.channelId == _selectedChannelA;
          final isChannelB =
              _dualChannel && channel.channelId == _selectedChannelB;

          Color bgColor;
          if (isChannelA) {
            bgColor = const Color(0xFFEEE8AA); // PaleGoldenrod
          } else if (isChannelB) {
            bgColor = const Color(0xFFF0E68C); // Khaki
          } else {
            bgColor = const Color(0xFFBDB76B); // DarkKhaki
          }

          return GestureDetector(
            onTap: () => _onChannelTap(channel.channelId),
            onSecondaryTapDown: (details) {
              _showChannelContextMenu(context, details.globalPosition, channel);
            },
            onLongPressStart: (details) {
              _showChannelContextMenu(context, details.globalPosition, channel);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(2),
                border: Border.all(color: Colors.grey.shade600, width: 0.5),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    channel.name.isNotEmpty
                        ? channel.name
                        : 'Ch ${channel.channelId + 1}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (channel.rxFreq > 0)
                    Text(
                      '${channel.frequencyDisplay} MHz',
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.grey.shade700,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
