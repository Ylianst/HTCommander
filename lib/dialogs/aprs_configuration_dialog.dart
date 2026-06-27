/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dialog_utils.dart';
import '../radio/radio_models.dart';

/// Result returned by [showAprsConfigurationDialog] when the user confirms.
class AprsConfigurationResult {
  /// The channel id of the channel that will be overwritten with APRS settings.
  final int channelId;

  /// The APRS frequency, in MHz.
  final double frequencyMhz;

  const AprsConfigurationResult({
    required this.channelId,
    required this.frequencyMhz,
  });
}

/// Opens the APRS channel setup dialog and returns the user's selection, or
/// `null` if the dialog is cancelled. Mirrors the C# `AprsConfigurationForm`.
Future<AprsConfigurationResult?> showAprsConfigurationDialog(
  BuildContext context, {
  required List<RadioChannelInfo> channels,
}) {
  return showDialog<AprsConfigurationResult>(
    context: context,
    builder: (context) => AprsConfigurationDialog(channels: channels),
  );
}

/// APRS channel setup dialog. Lets the user pick a frequency and a channel slot
/// to overwrite with an "APRS" channel. Mirrors the C# `AprsConfigurationForm`:
/// a frequency field (default 144.39, valid 144-148 MHz) and a channel dropdown
/// whose selected channel will be overwritten.
class AprsConfigurationDialog extends StatefulWidget {
  final List<RadioChannelInfo> channels;

  const AprsConfigurationDialog({super.key, required this.channels});

  @override
  State<AprsConfigurationDialog> createState() =>
      _AprsConfigurationDialogState();
}

class _AprsConfigurationDialogState extends State<AprsConfigurationDialog> {
  late final TextEditingController _freqController;
  int? _selectedChannelId;

  @override
  void initState() {
    super.initState();
    _freqController = TextEditingController(text: '144.39');
    // Default to the last channel, matching the C# form.
    if (widget.channels.isNotEmpty) {
      _selectedChannelId = widget.channels.last.channelId;
    }
  }

  @override
  void dispose() {
    _freqController.dispose();
    super.dispose();
  }

  /// Mirrors the C# `UpdateInfo` validity check: 144-148 MHz and a selected
  /// channel.
  bool get _isFrequencyValid {
    final freq = double.tryParse(_freqController.text);
    if (freq == null) return false;
    return freq >= 144 && freq <= 148;
  }

  bool get _canConfirm => _isFrequencyValid && _selectedChannelId != null;

  String _channelLabel(RadioChannelInfo channel) {
    final number = channel.channelId + 1;
    if (channel.name.isNotEmpty) return '$number - ${channel.name}';
    return '$number';
  }

  Future<void> _openAprsOrg() async {
    final uri = Uri.parse('https://aprs.org');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _onConfirm() {
    final freq = double.tryParse(_freqController.text);
    final channelId = _selectedChannelId;
    if (freq == null || channelId == null) return;
    Navigator.of(
      context,
    ).pop(AprsConfigurationResult(channelId: channelId, frequencyMhz: freq));
  }

  @override
  Widget build(BuildContext context) {
    return HTDialog(
      title: 'Set up APRS Channel',
      maxWidth: 460,
      maxHeight: 460,
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.place, color: Colors.red, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'The APRS frequency changes depending on the region of '
                        'the world. Use this site to find the right frequency to '
                        'configure the APRS channel.',
                        style: DialogStyles.bodyStyle,
                      ),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: _openAprsOrg,
                        child: const Text(
                          'aprs.org',
                          style: DialogStyles.linkStyle,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'APRS Configuration',
                    style: DialogStyles.labelStyle,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(
                        width: 90,
                        child: Padding(
                          padding: EdgeInsets.only(top: 10),
                          child: Text(
                            'Frequency',
                            style: DialogStyles.bodyStyle,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: _freqController,
                              maxLength: 6,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9.]'),
                                ),
                              ],
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                isDense: true,
                                counterText: '',
                                border: const OutlineInputBorder(),
                                errorText:
                                    _freqController.text.isEmpty ||
                                        _isFrequencyValid
                                    ? null
                                    : '144 - 148 MHz',
                                filled: true,
                                fillColor:
                                    _freqController.text.isEmpty ||
                                        _isFrequencyValid
                                    ? Colors.white
                                    : const Color(0xFFFFCCCC),
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              '144.39 in North America\n144.80 in Europe',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(
                        width: 90,
                        child: Padding(
                          padding: EdgeInsets.only(top: 10),
                          child: Text('Channel', style: DialogStyles.bodyStyle),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DropdownButtonFormField<int>(
                              initialValue: _selectedChannelId,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                isDense: true,
                                border: OutlineInputBorder(),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                              items: [
                                for (final channel in widget.channels)
                                  DropdownMenuItem<int>(
                                    value: channel.channelId,
                                    child: Text(
                                      _channelLabel(channel),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: (value) =>
                                  setState(() => _selectedChannelId = value),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'The selected channel will be overwritten',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: DialogStyles.secondaryButtonStyle(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _canConfirm ? _onConfirm : null,
          style: DialogStyles.primaryButtonStyle(context),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
