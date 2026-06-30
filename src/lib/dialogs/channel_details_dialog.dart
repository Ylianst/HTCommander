/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart';

import '../radio/radio_models.dart';

/// Opens a read-only details view for a [channel].
///
/// Unlike the channel editor ([showRadioChannelDialog]) this dialog only
/// displays information and provides no way to change or write the channel.
Future<void> showChannelDetailsDialog(
  BuildContext context, {
  required RadioChannelInfo channel,
  String? title,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => ChannelDetailsDialog(channel: channel, title: title),
  );
}

/// Simple, read-only channel information dialog.
class ChannelDetailsDialog extends StatelessWidget {
  final RadioChannelInfo channel;
  final String? title;

  const ChannelDetailsDialog({super.key, required this.channel, this.title});

  static String _freq(int hz) =>
      hz == 0 ? '--' : '${(hz / 1000000).toStringAsFixed(4)} MHz';

  static String _mod(RadioModulationType m) {
    switch (m) {
      case RadioModulationType.fm:
        return 'FM';
      case RadioModulationType.am:
        return 'AM';
      case RadioModulationType.dmr:
        return 'DMR';
      case RadioModulationType.reserved:
        return 'Reserved';
    }
  }

  /// Sub-audio values >= 1000 are CTCSS tones stored as Hz x 100, smaller
  /// non-zero values are DCS/DTCS codes.
  static String _subAudio(int value) {
    if (value == 0) return 'None';
    if (value >= 1000) return 'CTCSS ${(value / 100).toStringAsFixed(1)} Hz';
    return 'DCS $value';
  }

  static String _power(RadioChannelInfo c) {
    if (c.txAtMaxPower) return 'High';
    if (c.txAtMedPower) return 'Medium';
    return 'Low';
  }

  @override
  Widget build(BuildContext context) {
    final displayName = channel.name.isNotEmpty
        ? channel.name
        : 'Ch ${channel.channelId + 1}';

    return AlertDialog(
      title: Text(title ?? displayName),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _row('Name', channel.name.isNotEmpty ? channel.name : '(empty)'),
            _row('RX Frequency', _freq(channel.rxFreq)),
            _row('TX Frequency', _freq(channel.txFreq)),
            _row('RX Modulation', _mod(channel.rxMod)),
            _row('TX Modulation', _mod(channel.txMod)),
            _row(
              'Bandwidth',
              channel.bandwidth == RadioBandwidthType.wide
                  ? '25 kHz (Wide)'
                  : '12.5 kHz (Narrow)',
            ),
            _row('Power', _power(channel)),
            _row('RX Tone', _subAudio(channel.rxSubAudio)),
            _row('TX Tone', _subAudio(channel.txSubAudio)),
            _row('Scan', channel.scan ? 'On' : 'Off'),
            _row('Talk Around', channel.talkAround ? 'On' : 'Off'),
            _row('TX Disabled', channel.txDisable ? 'Yes' : 'No'),
            _row('Mute', channel.mute ? 'On' : 'Off'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
