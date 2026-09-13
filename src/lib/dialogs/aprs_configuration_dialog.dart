/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dialog_utils.dart';
import '../l10n/app_localizations.dart';
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

class _AprsFrequencyOption {
  final String label;
  final double frequencyMhz;

  const _AprsFrequencyOption(this.label, this.frequencyMhz);
}

const _customFrequencyLabel = 'Custom';

const _aprsFrequencyOptions = [
  _AprsFrequencyOption(
    '144.390 MHz - North America, Mexico, Indonesia, Malaysia, Singapore, Thailand',
    144.390,
  ),
  _AprsFrequencyOption('144.575 MHz - New Zealand', 144.575),
  _AprsFrequencyOption('144.620 MHz - South Korea', 144.620),
  _AprsFrequencyOption(
    '144.640 MHz - China, Hong Kong, Taiwan',
    144.640,
  ),
  _AprsFrequencyOption('144.660 MHz - Japan', 144.660),
  _AprsFrequencyOption(
    '144.800 MHz - Europe, Russia, South Africa',
    144.800,
  ),
  _AprsFrequencyOption(
    '144.930 MHz - Argentina, Panama, Paraguay, Uruguay',
    144.930,
  ),
  _AprsFrequencyOption('145.175 MHz - Australia', 145.175),
  _AprsFrequencyOption('145.570 MHz - Brazil', 145.570),
  _AprsFrequencyOption('432.500 MHz - Netherlands (70 cm)', 432.500),
];

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
/// a frequency field (default 144.39, valid FM VHF/UHF ranges) and a channel dropdown
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
  late String _selectedFrequencyLabel;
  int? _selectedChannelId;

  @override
  void initState() {
    super.initState();
    final defaultFrequency = _defaultFrequencyOption;
    _selectedFrequencyLabel = defaultFrequency.label;
    _freqController = TextEditingController(
      text: defaultFrequency.frequencyMhz.toStringAsFixed(3),
    );
    // Default to the last channel, matching the C# form.
    if (widget.channels.isNotEmpty) {
      _selectedChannelId = widget.channels.last.channelId;
    }
  }

  _AprsFrequencyOption get _defaultFrequencyOption {
    final country = ui.PlatformDispatcher.instance.locale.countryCode
        ?.toUpperCase();
    final frequency = switch (country) {
      'AU' => 145.175,
      'NZ' => 144.575,
      'JP' => 144.660,
      'CN' || 'HK' || 'TW' => 144.640,
      'KR' => 144.620,
      'AR' || 'PA' || 'PY' || 'UY' => 144.930,
      'BR' => 145.570,
      'AT' || 'BE' || 'CH' || 'CZ' || 'DE' || 'DK' || 'ES' || 'FI' ||
      'FR' || 'GB' || 'GR' || 'HU' || 'IE' || 'IT' || 'NL' || 'NO' ||
      'PL' || 'PT' || 'RU' || 'SE' || 'SI' || 'TR' => 144.800,
      _ => 144.390,
    };
    return _aprsFrequencyOptions.firstWhere(
      (option) => option.frequencyMhz == frequency,
    );
  }

  bool get _isCustomFrequency =>
      _selectedFrequencyLabel == _customFrequencyLabel;

  @override
  void dispose() {
    _freqController.dispose();
    super.dispose();
  }

  /// Matches the radio channel editor's FM frequency ranges and requires a
  /// selected channel.
  bool get _isFrequencyValid {
    final freq = double.tryParse(_freqController.text);
    if (freq == null) return false;
    return (freq >= 136 && freq <= 174) ||
        (freq >= 300 && freq <= 550);
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

  BoxDecoration _sectionDecoration() {
    final theme = Theme.of(context);
    return BoxDecoration(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: theme.shadowColor.withValues(alpha: 0.05),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  TextStyle _sectionTitleStyle() {
    return TextStyle(
      fontWeight: FontWeight.bold,
      color: Theme.of(context).colorScheme.onSurface,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isFreqInvalid = _freqController.text.isNotEmpty && !_isFrequencyValid;

    return HTDialog(
      title: l10n.acfgTitle,
      maxWidth: 480,
      maxHeight: 520,
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header / Intro Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: _sectionDecoration(),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.cell_tower,
                      color: scheme.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.acfgIntro,
                          style: DialogStyles.bodyStyle.copyWith(
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: _openAprsOrg,
                          borderRadius: BorderRadius.circular(4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'aprs.org',
                                style: DialogStyles.linkStyle.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.open_in_new,
                                size: 14,
                                color: scheme.primary,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Configuration Section Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: _sectionDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.acfgConfiguration, style: _sectionTitleStyle()),
                  const SizedBox(height: 16),

                  DropdownButtonFormField<String>(
                    initialValue: _selectedFrequencyLabel,
                    isExpanded: true,
                    decoration: DialogStyles.inputDecoration(
                      context,
                      labelText: l10n.acfgFrequency,
                    ).copyWith(prefixIcon: const Icon(Icons.graphic_eq)),
                    items: [
                      for (final option in _aprsFrequencyOptions)
                        DropdownMenuItem<String>(
                          value: option.label,
                          child: Text(
                            option.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      const DropdownMenuItem<String>(
                        value: _customFrequencyLabel,
                        child: Text(_customFrequencyLabel),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      final option = _aprsFrequencyOptions.firstWhere(
                        (option) => option.label == value,
                        orElse: () => const _AprsFrequencyOption('', 0),
                      );
                      setState(() {
                        _selectedFrequencyLabel = value;
                        if (value != _customFrequencyLabel) {
                          _freqController.text = option.frequencyMhz
                              .toStringAsFixed(3);
                        }
                      });
                    },
                  ),
                  if (_isCustomFrequency) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _freqController,
                      maxLength: 7,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      onChanged: (_) => setState(() {}),
                      decoration:
                          DialogStyles.inputDecoration(
                            context,
                            labelText: l10n.acfgFrequency,
                            errorText: isFreqInvalid
                              ? '136 - 174 or 300 - 550 MHz'
                              : null,
                            invalid: isFreqInvalid,
                          ).copyWith(
                            counterText: '',
                            suffixText: 'MHz',
                            prefixIcon: const Icon(Icons.graphic_eq),
                          ),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Target Channel Field
                  DropdownButtonFormField<int>(
                    initialValue: _selectedChannelId,
                    isExpanded: true,
                    decoration: DialogStyles.inputDecoration(
                      context,
                      labelText: l10n.packetsColChannel,
                      helperText: l10n.acfgChannelOverwritten,
                    ).copyWith(prefixIcon: const Icon(Icons.tune)),
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
          child: Text(l10n.commonCancel),
        ),
        ElevatedButton(
          onPressed: _canConfirm ? _onConfirm : null,
          style: DialogStyles.primaryButtonStyle(context),
          child: Text(l10n.commonOk),
        ),
      ],
    );
  }
}
