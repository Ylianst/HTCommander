/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from the C# `HTCommander.AprsSmsForm` dialog and extended to cover the
full set of NA7Q (aprs.wiki) APRS/SMS gateway operations.
*/

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import 'dialog_utils.dart';
import '../services/data_broker_client.dart';

/// The guided operations the APRS/SMS gateway supports. Every operation is sent
/// as a plain APRS message to the "SMS" gateway callsign.
enum SmsOperation {
  sendPhone,
  sendAlias,
  createAlias,
  removeAlias,
  checkMissed,
  deleteMissed,
}

/// Result of the APRS SMS dialog: the full message body to send to the "SMS"
/// gateway for the chosen operation.
class AprsSmsResult {
  final String gatewayMessage;
  const AprsSmsResult(this.gatewayMessage);
}

/// Shows the APRS/SMS gateway dialog. Returns the entered [AprsSmsResult] or
/// `null` if cancelled.
Future<AprsSmsResult?> showAprsSmsDialog(BuildContext context) {
  return showDialog<AprsSmsResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const _AprsSmsDialog(),
  );
}

class _AprsSmsDialog extends StatefulWidget {
  const _AprsSmsDialog();

  @override
  State<_AprsSmsDialog> createState() => _AprsSmsDialogState();
}

class _AprsSmsDialogState extends State<_AprsSmsDialog> {
  final DataBrokerClient _broker = DataBrokerClient();

  late final TextEditingController _phoneController;
  late final TextEditingController _aliasController;
  late final TextEditingController _messageController;

  SmsOperation _operation = SmsOperation.sendPhone;

  @override
  void initState() {
    super.initState();
    // Restore the last-used phone number and alias from device 0.
    final savedPhone = _broker.getValue<String>(0, 'SmsPhone', '') ?? '';
    final savedAlias = _broker.getValue<String>(0, 'SmsAlias', '') ?? '';
    _phoneController = TextEditingController(text: savedPhone);
    _aliasController = TextEditingController(text: savedAlias);
    _messageController = TextEditingController();
    _phoneController.addListener(_onChanged);
    _aliasController.addListener(_onChanged);
    _messageController.addListener(_onChanged);
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _aliasController.dispose();
    _messageController.dispose();
    _broker.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  bool get _showPhone =>
      _operation == SmsOperation.sendPhone ||
      _operation == SmsOperation.createAlias ||
      _operation == SmsOperation.removeAlias;

  bool get _showAlias =>
      _operation == SmsOperation.sendAlias ||
      _operation == SmsOperation.createAlias ||
      _operation == SmsOperation.removeAlias;

  bool get _showMessage =>
      _operation == SmsOperation.sendPhone ||
      _operation == SmsOperation.sendAlias;

  // The opt-in notice only applies when a raw phone number is used with the
  // service for messaging or alias registration.
  bool get _showOptIn =>
      _operation == SmsOperation.sendPhone ||
      _operation == SmsOperation.createAlias;

  // Gateway phone numbers are 10 digits (US/CA/PR), 11 (AU) or 12 (UK), with no
  // leading 1.
  bool get _phoneValid {
    final p = _phoneController.text;
    return p.length >= 10 && p.length <= 12;
  }

  bool get _aliasValid => _aliasController.text.trim().isNotEmpty;

  bool get _isValid {
    switch (_operation) {
      case SmsOperation.sendPhone:
        return _phoneValid && _messageController.text.isNotEmpty;
      case SmsOperation.sendAlias:
        return _aliasValid && _messageController.text.isNotEmpty;
      case SmsOperation.createAlias:
      case SmsOperation.removeAlias:
        return _aliasValid && _phoneValid;
      case SmsOperation.checkMissed:
      case SmsOperation.deleteMissed:
        return true;
    }
  }

  String _buildGatewayMessage() {
    final phone = _phoneController.text.trim();
    final alias = _aliasController.text.trim();
    final message = _messageController.text;
    switch (_operation) {
      case SmsOperation.sendPhone:
        return '@$phone $message';
      case SmsOperation.sendAlias:
        return '@$alias $message';
      case SmsOperation.createAlias:
        return '#alias #add $alias $phone';
      case SmsOperation.removeAlias:
        return '#alias #remove $alias $phone';
      case SmsOperation.checkMissed:
        return 'APRSM';
      case SmsOperation.deleteMissed:
        return 'del';
    }
  }

  void _onOk() {
    if (_showPhone) {
      _broker.dispatch(
        deviceId: 0,
        name: 'SmsPhone',
        data: _phoneController.text.trim(),
      );
    }
    if (_showAlias) {
      _broker.dispatch(
        deviceId: 0,
        name: 'SmsAlias',
        data: _aliasController.text.trim(),
      );
    }
    Navigator.of(context).pop(AprsSmsResult(_buildGatewayMessage()));
  }

  String _operationLabel(AppLocalizations l10n, SmsOperation op) {
    switch (op) {
      case SmsOperation.sendPhone:
        return l10n.smsOpSendPhone;
      case SmsOperation.sendAlias:
        return l10n.smsOpSendAlias;
      case SmsOperation.createAlias:
        return l10n.smsOpCreateAlias;
      case SmsOperation.removeAlias:
        return l10n.smsOpRemoveAlias;
      case SmsOperation.checkMissed:
        return l10n.smsOpCheckMissed;
      case SmsOperation.deleteMissed:
        return l10n.smsOpDeleteMissed;
    }
  }

  String _operationHelp(AppLocalizations l10n) {
    switch (_operation) {
      case SmsOperation.sendPhone:
        return l10n.smsHelpSendPhone;
      case SmsOperation.sendAlias:
        return l10n.smsHelpSendAlias;
      case SmsOperation.createAlias:
        return l10n.smsHelpCreateAlias;
      case SmsOperation.removeAlias:
        return l10n.smsHelpRemoveAlias;
      case SmsOperation.checkMissed:
        return l10n.smsHelpCheckMissed;
      case SmsOperation.deleteMissed:
        return l10n.smsHelpDeleteMissed;
    }
  }

  Future<void> _launchOptInLink() async {
    final uri = Uri.parse('https://aprs.wiki');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.smsTitle),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<SmsOperation>(
                initialValue: _operation,
                isExpanded: true,
                decoration: _inputDecoration(labelText: l10n.smsOperation),
                items: [
                  for (final op in SmsOperation.values)
                    DropdownMenuItem(
                      value: op,
                      child: Text(
                        _operationLabel(l10n, op),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (op) {
                  if (op == null) return;
                  setState(() => _operation = op);
                },
              ),
              const SizedBox(height: 12),
              Text(
                _operationHelp(l10n),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).hintColor,
                    ),
              ),
              if (_showOptIn) ...[
                const SizedBox(height: 12),
                _buildIntro(),
              ],
              if (_showAlias) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _aliasController,
                  keyboardType: TextInputType.text,
                  inputFormatters: [
                    // Aliases are a single token without whitespace or the
                    // command/APRS-restricted characters.
                    FilteringTextInputFormatter.deny(RegExp(r'[\s@#~|}]')),
                    LengthLimitingTextInputFormatter(32),
                  ],
                  decoration: _inputDecoration(labelText: l10n.smsAliasLabel),
                ),
              ],
              if (_showPhone) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(12),
                  ],
                  decoration: _inputDecoration(labelText: l10n.smsPhoneNumber),
                ),
              ],
              if (_showMessage) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _messageController,
                  minLines: 4,
                  maxLines: 6,
                  maxLength: 150,
                  inputFormatters: [
                    // Restricted characters from the C# form.
                    FilteringTextInputFormatter.deny(RegExp(r'[~|}]')),
                    LengthLimitingTextInputFormatter(150),
                  ],
                  decoration: _inputDecoration(labelText: l10n.mailMessageLabel),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: DialogStyles.secondaryButtonStyle(context),
          child: Text(l10n.commonCancel),
        ),
        ElevatedButton(
          onPressed: _isValid ? _onOk : null,
          style: DialogStyles.primaryButtonStyle(context),
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
          TextSpan(
            text: AppLocalizations.of(context).smsIntro,
          ),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: InkWell(
              onTap: _launchOptInLink,
              child: const Text(
                'aprs.wiki',
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
  InputDecoration _inputDecoration({required String labelText}) {
    return DialogStyles.inputDecoration(
      context,
      labelText: labelText,
      focusColor: Colors.blue,
    );
  }
}
