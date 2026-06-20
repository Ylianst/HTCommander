/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from the C# `HTCommander.AprsSmsForm` dialog.
*/

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/data_broker_client.dart';

/// Result of the APRS SMS dialog: the recipient phone number and message text.
class AprsSmsResult {
  final String phoneNumber;
  final String message;
  const AprsSmsResult(this.phoneNumber, this.message);
}

/// Shows the "Send SMS Message" dialog. Returns the entered [AprsSmsResult] or
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
  late final TextEditingController _messageController;

  @override
  void initState() {
    super.initState();
    // Restore the last-used phone number from device 0.
    final savedPhone = _broker.getValue<String>(0, 'SmsPhone', '') ?? '';
    _phoneController = TextEditingController(text: savedPhone);
    _messageController = TextEditingController();
    _phoneController.addListener(_onChanged);
    _messageController.addListener(_onChanged);
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _messageController.dispose();
    _broker.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  /// Matches the C# `UpdateInfo`: message must be non-empty and the phone
  /// number must be at least 10 digits.
  bool get _isValid =>
      _messageController.text.isNotEmpty && _phoneController.text.length >= 10;

  void _onOk() {
    final phone = _phoneController.text;
    final message = _messageController.text;
    // Persist the phone number for next time (matches the C# okButton_Click).
    _broker.dispatch(deviceId: 0, name: 'SmsPhone', data: phone);
    Navigator.of(context).pop(AprsSmsResult(phone, message));
  }

  Future<void> _launchOptInLink() async {
    final uri = Uri.parse('https://aprs.wiki');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Send SMS Message'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildIntro(),
              const SizedBox(height: 16),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(12),
                ],
                decoration: _inputDecoration(labelText: 'Phone Number'),
              ),
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
                decoration: _inputDecoration(labelText: 'Message'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isValid ? _onOk : null,
          child: const Text('OK'),
        ),
      ],
    );
  }

  Widget _buildIntro() {
    return Text.rich(
      TextSpan(
        style: Theme.of(context).textTheme.bodyMedium,
        children: [
          const TextSpan(
            text:
                'You can send SMS messages to phones in the USA, Puerto Rico, '
                'Canada, Australia & UK as long as the phone number has already '
                'opted in to the service. You can opt-in at: ',
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
    return InputDecoration(
      filled: true,
      fillColor: Colors.grey.shade100,
      labelText: labelText,
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
