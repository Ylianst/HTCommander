import 'package:flutter/material.dart';

/// Radio panel control widget - displays radio image, VFO frequencies, and status
class RadioPanelControl extends StatefulWidget {
  const RadioPanelControl({super.key});

  @override
  State<RadioPanelControl> createState() => _RadioPanelControlState();
}

class _RadioPanelControlState extends State<RadioPanelControl> {
  bool _connected = false;
  final String _vfo1Freq = '144.390';
  final String _vfo2Freq = '432.100';
  final String _vfo1Status = 'RX';
  final String _vfo2Status = 'RX';
  int _rssi = 0;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF565658), // Dark gray like C# app
      child: Column(
        children: [
          // Radio image
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Radio picture
                  Expanded(
                    child: Image.asset(
                      'assets/images/VR-N75.png',
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade800,
                            borderRadius: BorderRadius.circular(8),
                          ),
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
                  const SizedBox(height: 16),
                  // Connected panel with VFO info
                  if (_connected) _buildConnectedPanel(),
                  if (!_connected) _buildDisconnectedPanel(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectedPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF565658),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          // VFO 1
          _buildVfoRow('VFO 1', _vfo1Freq, _vfo1Status),
          const SizedBox(height: 4),
          Container(height: 1, color: Colors.grey),
          const SizedBox(height: 4),
          // VFO 2
          _buildVfoRow('VFO 2', _vfo2Freq, _vfo2Status),
          const SizedBox(height: 8),
          // RSSI Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: _rssi / 15,
              minHeight: 8,
              backgroundColor: Colors.grey.shade700,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVfoRow(String label, String freq, String status) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$freq MHz',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: status == 'TX' ? Colors.red : Colors.green,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Text(
            status,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDisconnectedPanel() {
    return Column(
      children: [
        const Text(
          'Not Connected',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: () {
            setState(() {
              _connected = true;
              _rssi = 7;
            });
          },
          icon: const Icon(Icons.bluetooth),
          label: const Text('Connect'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}
