/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../radio/xara_modem.dart' show XaraModemConfig;
import '../services/data_broker_client.dart';
import '../services/host_bridge.dart';
import 'dialog_utils.dart';

Future<void> showXaraSettingsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const XaraSettingsDialog(),
  );
}

class XaraSettingsDialog extends StatefulWidget {
  const XaraSettingsDialog({super.key});

  @override
  State<XaraSettingsDialog> createState() => _XaraSettingsDialogState();
}

class _XaraSettingsDialogState extends State<XaraSettingsDialog> {
  final _broker = DataBrokerClient();
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _keyUp;
  late final TextEditingController _latency;

  @override
  void initState() {
    super.initState();
    _keyUp = TextEditingController(
      text: _read('XaraTxKeyUpMs', XaraModemConfig.defaultTxKeyUpMs).toString(),
    );
    _latency = TextEditingController(
      text: _read(
        'XaraTxLatencyMs',
        XaraModemConfig.defaultTxLatencyMs,
      ).toString(),
    );
  }

  int _read(String setting, int defaultValue) =>
      _broker.getValue<int>(0, setting, defaultValue) ?? defaultValue;

  @override
  void dispose() {
    _keyUp.dispose();
    _latency.dispose();
    _broker.dispose();
    super.dispose();
  }

  void _restoreDefaults() {
    _formKey.currentState!.reset();
    _keyUp.text = XaraModemConfig.defaultTxKeyUpMs.toString();
    _latency.text = XaraModemConfig.defaultTxLatencyMs.toString();
  }

  void _apply(String setting, int value, int defaultValue) {
    if (_read(setting, defaultValue) == value) return;
    if (HostBridge.isHosted) {
      _broker.dispatch(deviceId: 0, name: setting, data: value, store: true);
    } else {
      _broker.dispatch(
        deviceId: 0,
        name: 'Set$setting',
        data: value,
        store: false,
      );
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    _apply(
      'XaraTxKeyUpMs',
      int.parse(_keyUp.text.trim()),
      XaraModemConfig.defaultTxKeyUpMs,
    );
    _apply(
      'XaraTxLatencyMs',
      int.parse(_latency.text.trim()),
      XaraModemConfig.defaultTxLatencyMs,
    );
    Navigator.of(context).pop();
  }

  Widget _timingField(
    TextEditingController controller,
    String label,
    int defaultValue,
  ) {
    final l10n = AppLocalizations.of(context);
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: DialogStyles.inputDecoration(
        context,
        labelText: label,
        helperText: l10n.xaraSettingsDefaultMs(defaultValue),
      ),
      validator: (text) {
        final value = int.tryParse(text?.trim() ?? '');
        if (value == null || value < 0 || value > 5000) {
          return l10n.xaraSettingsTimingInvalid;
        }
        return null;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.xaraSettingsTitle),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _timingField(
                  _keyUp,
                  l10n.xaraSettingsKeyUp,
                  XaraModemConfig.defaultTxKeyUpMs,
                ),
                const SizedBox(height: 8),
                Text(l10n.xaraSettingsKeyUpHelp),
                const SizedBox(height: 20),
                _timingField(
                  _latency,
                  l10n.xaraSettingsLatency,
                  XaraModemConfig.defaultTxLatencyMs,
                ),
                const SizedBox(height: 8),
                Text(l10n.xaraSettingsLatencyHelp),
                const SizedBox(height: 20),
                Text(l10n.xaraSettingsLinkWarning),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _restoreDefaults,
          style: DialogStyles.secondaryButtonStyle(context),
          child: Text(l10n.xaraSettingsRestoreDefaults),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: DialogStyles.secondaryButtonStyle(context),
          child: Text(l10n.commonCancel),
        ),
        ElevatedButton(
          onPressed: _save,
          style: DialogStyles.primaryButtonStyle(context),
          child: Text(l10n.xaraSettingsSave),
        ),
      ],
    );
  }
}
