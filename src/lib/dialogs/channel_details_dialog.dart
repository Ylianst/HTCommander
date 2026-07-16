/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'dialog_utils.dart';
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
  static String _subAudio(AppLocalizations l10n, int value) {
    if (value == 0) return l10n.commonNone;
    if (value >= 1000) return 'CTCSS ${(value / 100).toStringAsFixed(1)} Hz';
    return 'DCS $value';
  }

  static String _power(AppLocalizations l10n, RadioChannelInfo c) {
    if (c.txAtMaxPower) return l10n.chPowerHigh;
    if (c.txAtMedPower) return l10n.chPowerMedium;
    return l10n.chPowerLow;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final displayName = channel.name.isNotEmpty
        ? channel.name
        : l10n.chChShort(channel.channelId + 1);

    return AlertDialog(
      title: Text(title ?? displayName),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _row(l10n.contactsColName,
                channel.name.isNotEmpty ? channel.name : l10n.cdEmpty),
            _row(l10n.cdRxFrequency, _freq(channel.rxFreq)),
            _row(l10n.cdTxFrequency, _freq(channel.txFreq)),
            _row(l10n.cdRxModulation, _mod(channel.rxMod)),
            _row(l10n.cdTxModulation, _mod(channel.txMod)),
            _row(
              l10n.chBandwidth,
              channel.bandwidth == RadioBandwidthType.wide
                  ? l10n.cdBandwidthWide
                  : l10n.cdBandwidthNarrow,
            ),
            _row(l10n.chPower, _power(l10n, channel)),
            _row(l10n.cdRxTone, _subAudio(l10n, channel.rxSubAudio)),
            _row(l10n.cdTxTone, _subAudio(l10n, channel.txSubAudio)),
            _row(l10n.chScan, channel.scan ? l10n.commonOn : l10n.commonOff),
            _row(l10n.cdTalkAround,
                channel.talkAround ? l10n.commonOn : l10n.commonOff),
            _row(l10n.cdTxDisabled,
                channel.txDisable ? l10n.commonYes : l10n.commonNo),
            _row(l10n.chMute, channel.mute ? l10n.commonOn : l10n.commonOff),
          ],
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: DialogStyles.primaryButtonStyle(context),
          child: Text(l10n.commonClose),
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
