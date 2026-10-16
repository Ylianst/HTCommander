/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'dialog_utils.dart';
import '../callsign/callsign_record.dart';
import '../radio/radio_models.dart';
import '../widgets/callsign_license_line.dart';

/// Opens a read-only details view for a [channel].
///
/// Unlike the channel editor ([showRadioChannelDialog]) this dialog only
/// displays information and provides no way to change or write the channel.
Future<void> showChannelDetailsDialog(
  BuildContext context, {
  required RadioChannelInfo channel,
  String? title,
  String? callsign,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => ChannelDetailsDialog(
      channel: channel,
      title: title,
      callsign: callsign,
    ),
  );
}

/// Simple, read-only channel information dialog. When [callsign] is given and
/// the offline callsign database knows it, the license holder's details are
/// shown at the top.
class ChannelDetailsDialog extends StatefulWidget {
  final RadioChannelInfo channel;
  final String? title;
  final String? callsign;

  const ChannelDetailsDialog({
    super.key,
    required this.channel,
    this.title,
    this.callsign,
  });

  @override
  State<ChannelDetailsDialog> createState() => _ChannelDetailsDialogState();
}

class _ChannelDetailsDialogState extends State<ChannelDetailsDialog> {
  CallsignRecord? _license;

  RadioChannelInfo get channel => widget.channel;

  @override
  void initState() {
    super.initState();
    final callsign = widget.callsign;
    if (callsign != null && callsign.isNotEmpty) {
      lookupCallsignRecord(callsign).then((rec) {
        if (mounted && rec != null) setState(() => _license = rec);
      });
    }
  }

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

    final license = _license;
    return AlertDialog(
      title: Text(widget.title ?? displayName),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (license != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: buildCallsignLicenseBlock(
                      context, widget.callsign!, license),
                ),
              ),
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
