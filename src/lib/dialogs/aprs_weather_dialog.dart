/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from the C# `HTCommander.AprsWeatherForm` dialog.
*/

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../services/data_broker_client.dart';

/// Time options for the weather request (matches the C# `timeComboBox`).
const List<String> _timeOptions = [
  'Today',
  'Tonight',
  'Tomorrow',
  'Tomorrow night',
  'Monday',
  'Monday night',
  'Tuesday',
  'Tuesday night',
  'Wednesday',
  'Wednesday night',
  'Thursday',
  'Thursday night',
  'Friday',
  'Friday night',
  'Saturday',
  'Saturday night',
  'Sunday',
  'Sunday night',
];

/// Report options for the weather request. The first word (before the comma)
/// is used to build the APRS message (matches the C# `reportComboBox`).
const List<String> _reportOptions = [
  'Brief, Short forecast, US only',
  'Full, More complete forecast, US only',
  'Current, Nearest NWS station, US only',
  'METAR, ICAO station in METAR form',
  'CWOP, Nearest CWOP station',
];

/// Shows the "Request Weather Report" dialog. Returns the crafted APRS message
/// body (e.g. "94089 today brief") or `null` if cancelled.
Future<String?> showAprsWeatherDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const _AprsWeatherDialog(),
  );
}

class _AprsWeatherDialog extends StatefulWidget {
  const _AprsWeatherDialog();

  @override
  State<_AprsWeatherDialog> createState() => _AprsWeatherDialogState();
}

class _AprsWeatherDialogState extends State<_AprsWeatherDialog> {
  final DataBrokerClient _broker = DataBrokerClient();

  late final TextEditingController _locationController;
  int _timeIndex = 0;
  int _reportIndex = 0;

  @override
  void initState() {
    super.initState();
    // Restore saved settings from device 0.
    final savedLocation =
        _broker.getValue<String>(0, 'WxBotLocation', '') ?? '';
    _locationController = TextEditingController(text: savedLocation);
    _locationController.addListener(_onChanged);

    final savedTime = _broker.getValue<int>(0, 'WxBotTime', 0) ?? 0;
    if (savedTime >= 0 && savedTime < _timeOptions.length) {
      _timeIndex = savedTime;
    }
    final savedReport = _broker.getValue<int>(0, 'WxBotReport', 0) ?? 0;
    if (savedReport >= 0 && savedReport < _reportOptions.length) {
      _reportIndex = savedReport;
    }
  }

  @override
  void dispose() {
    _locationController.dispose();
    _broker.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  /// Localized display labels for the time options. The order MUST match
  /// [_timeOptions], which is used to build the (English) APRS message.
  List<String> _timeLabels(AppLocalizations l10n) => [
        l10n.wxToday,
        l10n.wxTonight,
        l10n.wxTomorrow,
        l10n.wxTomorrowNight,
        l10n.wxMonday,
        l10n.wxMondayNight,
        l10n.wxTuesday,
        l10n.wxTuesdayNight,
        l10n.wxWednesday,
        l10n.wxWednesdayNight,
        l10n.wxThursday,
        l10n.wxThursdayNight,
        l10n.wxFriday,
        l10n.wxFridayNight,
        l10n.wxSaturday,
        l10n.wxSaturdayNight,
        l10n.wxSunday,
        l10n.wxSundayNight,
      ];

  /// Localized display labels for the report options. The order MUST match
  /// [_reportOptions], which is used to build the (English) APRS message.
  List<String> _reportLabels(AppLocalizations l10n) => [
        l10n.wxReportBrief,
        l10n.wxReportFull,
        l10n.wxReportCurrent,
        l10n.wxReportMetar,
        l10n.wxReportCwop,
      ];

  /// Location must be non-empty (matches the C# `UpdateInfo`).
  bool get _isValid => _locationController.text.isNotEmpty;

  /// Builds the APRS message body: `<location> <time> <report>` lowercased,
  /// where `<report>` is the first word of the selected report option.
  String _buildAprsMessage() {
    final time = _timeOptions[_timeIndex].toLowerCase();
    final report = _reportOptions[_reportIndex].split(',')[0].toLowerCase();
    return '${_locationController.text} $time $report';
  }

  void _onOk() {
    // Persist settings (matches the C# okButton_Click).
    _broker.dispatch(
      deviceId: 0,
      name: 'WxBotLocation',
      data: _locationController.text,
    );
    _broker.dispatch(deviceId: 0, name: 'WxBotTime', data: _timeIndex);
    _broker.dispatch(deviceId: 0, name: 'WxBotReport', data: _reportIndex);
    Navigator.of(context).pop(_buildAprsMessage());
  }

  Future<void> _launchInfoLink() async {
    final uri = Uri.parse('https://sites.google.com/site/ki6wjp/wxbot');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final timeLabels = _timeLabels(l10n);
    final reportLabels = _reportLabels(l10n);
    return AlertDialog(
      title: Text(l10n.wxTitle),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildIntro(),
              const SizedBox(height: 16),
              TextField(
                controller: _locationController,
                maxLength: 32,
                inputFormatters: [
                  // Restricted characters from the C# form (incl. space).
                  FilteringTextInputFormatter.deny(RegExp(r'[~|{} ]')),
                  LengthLimitingTextInputFormatter(32),
                ],
                decoration: _inputDecoration(
                  labelText: l10n.wxLocation,
                  helperText: l10n.wxLocationHelper,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _timeIndex,
                decoration: _inputDecoration(labelText: l10n.wxTime),
                items: [
                  for (int i = 0; i < _timeOptions.length; i++)
                    DropdownMenuItem(value: i, child: Text(timeLabels[i])),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _timeIndex = value);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _reportIndex,
                decoration: _inputDecoration(labelText: l10n.wxReport),
                items: [
                  for (int i = 0; i < _reportOptions.length; i++)
                    DropdownMenuItem(value: i, child: Text(reportLabels[i])),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _reportIndex = value);
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        ElevatedButton(
          onPressed: _isValid ? _onOk : null,
          child: Text(l10n.commonOk),
        ),
      ],
    );
  }

  Widget _buildIntro() {
    return Text.rich(
      TextSpan(
        style: Theme.of(context).textTheme.bodyMedium,
        children: [
          TextSpan(text: AppLocalizations.of(context).wxIntro),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: InkWell(
              onTap: _launchInfoLink,
              child: const Text(
                'sites.google.com/site/ki6wjp/wxbot',
                style: TextStyle(
                  color: Colors.blue,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Filled, borderless input decoration matching the other dialogs.
  InputDecoration _inputDecoration({
    required String labelText,
    String? helperText,
  }) {
    return InputDecoration(
      filled: true,
      fillColor: Colors.grey.shade100,
      labelText: labelText,
      helperText: helperText,
      isDense: true,
      contentPadding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.blue, width: 2),
      ),
    );
  }
}
