import 'package:flutter/material.dart';

import '../echolink/echolink_credential_test.dart';
import '../l10n/app_localizations.dart';
import 'dialog_utils.dart';

/// Result of a successful EchoLink account creation.
class EchoLinkAccountResult {
  /// The password the user chose (and which was registered with the server).
  final String password;

  /// The email address the user entered (used for web validation).
  final String email;

  /// True when the call sign was already registered and validated with this
  /// password (nothing new was created); false when a new pending account was
  /// registered and still needs web validation.
  final bool alreadyValidated;

  const EchoLinkAccountResult({
    required this.password,
    required this.email,
    required this.alreadyValidated,
  });
}

/// Dialog that registers a new EchoLink account for a given call sign.
///
/// Collects an email address and a new password, then performs the directory
/// login that creates the (pending) account. Pops an [EchoLinkAccountResult]
/// on success, or null if cancelled.
class EchoLinkCreateAccountDialog extends StatefulWidget {
  final String callsign;
  final String location;

  const EchoLinkCreateAccountDialog({
    super.key,
    required this.callsign,
    required this.location,
  });

  @override
  State<EchoLinkCreateAccountDialog> createState() =>
      _EchoLinkCreateAccountDialogState();
}

class _EchoLinkCreateAccountDialogState
    extends State<EchoLinkCreateAccountDialog> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  static final RegExp _emailRegExp =
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  bool _busy = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_onChanged);
    _passwordController.addListener(_onChanged);
    _confirmController.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool get _emailValid => _emailRegExp.hasMatch(_emailController.text.trim());
  bool get _passwordsMatch =>
      _passwordController.text == _confirmController.text;

  bool get _canCreate =>
      !_busy &&
      _emailValid &&
      _passwordController.text.isNotEmpty &&
      _passwordsMatch;

  InputDecoration _decoration(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InputDecoration(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      isDense: true,
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
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    );
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = '';
    });

    final EchoLinkCredentialResult result = await testEchoLinkCredentials(
      callsign: widget.callsign,
      password: _passwordController.text,
      location: widget.location,
    );

    if (!mounted) return;

    switch (result.status) {
      case EchoLinkCredentialStatus.validationPending:
        Navigator.of(context).pop(
          EchoLinkAccountResult(
            password: _passwordController.text,
            email: _emailController.text.trim(),
            alreadyValidated: false,
          ),
        );
        return;
      case EchoLinkCredentialStatus.valid:
        Navigator.of(context).pop(
          EchoLinkAccountResult(
            password: _passwordController.text,
            email: _emailController.text.trim(),
            alreadyValidated: true,
          ),
        );
        return;
      case EchoLinkCredentialStatus.incorrectPassword:
        setState(() {
          _busy = false;
          _error = l10n.settingsEchoLinkAccountExists;
        });
        return;
      case EchoLinkCredentialStatus.unreachable:
        setState(() {
          _busy = false;
          _error = l10n.settingsEchoLinkTestUnreachable;
        });
        return;
      case EchoLinkCredentialStatus.unknown:
        setState(() {
          _busy = false;
          _error = l10n.settingsEchoLinkTestInconclusive;
        });
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return HTDialog(
      title: l10n.settingsEchoLinkCreateAccountTitle,
      maxWidth: 440,
      maxHeight: 520,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.settingsEchoLinkCreateAccountIntro(widget.callsign),
              style: DialogStyles.bodyStyle,
            ),
            const SizedBox(height: 16),
            Text(l10n.settingsEchoLinkEmail, style: DialogStyles.labelStyle),
            const SizedBox(height: 4),
            TextField(
              controller: _emailController,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: _decoration(context),
            ),
            if (_emailController.text.isNotEmpty && !_emailValid) ...[
              const SizedBox(height: 4),
              Text(
                l10n.settingsEchoLinkEmailInvalid,
                style: TextStyle(color: Colors.red.shade700, fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            Text(l10n.settingsEchoLinkNewPassword,
                style: DialogStyles.labelStyle),
            const SizedBox(height: 4),
            TextField(
              controller: _passwordController,
              enabled: !_busy,
              obscureText: true,
              decoration: _decoration(context),
            ),
            const SizedBox(height: 16),
            Text(l10n.settingsEchoLinkConfirmPassword,
                style: DialogStyles.labelStyle),
            const SizedBox(height: 4),
            TextField(
              controller: _confirmController,
              enabled: !_busy,
              obscureText: true,
              decoration: _decoration(context),
            ),
            if (_confirmController.text.isNotEmpty && !_passwordsMatch) ...[
              const SizedBox(height: 4),
              Text(
                l10n.settingsEchoLinkPasswordMismatch,
                style: TextStyle(color: Colors.red.shade700, fontSize: 12),
              ),
            ],
            if (_busy) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(l10n.settingsEchoLinkCreating,
                      style: DialogStyles.bodyStyle),
                ],
              ),
            ],
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                _error,
                style: TextStyle(color: scheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          style: DialogStyles.secondaryButtonStyle(context),
          child: Text(l10n.commonCancel),
        ),
        ElevatedButton(
          onPressed: _canCreate ? _submit : null,
          style: DialogStyles.primaryButtonStyle(context),
          child: Text(l10n.settingsEchoLinkCreateAccountButton),
        ),
      ],
    );
  }
}
