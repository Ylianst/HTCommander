import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'app_settings.dart';
import 'dialog_utils.dart';

/// Dialog for editing APRS routes
class AprsRouteDialog extends StatefulWidget {
  final AprsRoute? route;

  /// Names of other routes that already exist. The OK button is disabled when
  /// the entered name matches one of these (case-insensitive), preventing
  /// duplicate route names.
  final List<String> existingNames;

  const AprsRouteDialog({super.key, this.route, this.existingNames = const []});

  @override
  State<AprsRouteDialog> createState() => _AprsRouteDialogState();
}

class _AprsRouteDialogState extends State<AprsRouteDialog> {
  late TextEditingController _nameController;
  late TextEditingController _pathController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.route?.name ?? '');
    _pathController = TextEditingController(text: widget.route?.path ?? '');
    _nameController.addListener(_onChanged);
    _pathController.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _nameController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  /// Whether the entered name duplicates an existing route name.
  bool get _isDuplicateName {
    final name = _nameController.text.trim().toLowerCase();
    if (name.isEmpty) return false;
    return widget.existingNames.any((n) => n.trim().toLowerCase() == name);
  }

  /// Whether the current input is valid and the route can be saved.
  bool get _canSave =>
      _nameController.text.trim().isNotEmpty &&
      _pathController.text.trim().isNotEmpty &&
      !_isDuplicateName;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return HTDialog(
      title: widget.route == null
          ? l10n.settingsAddAprsRoute
          : l10n.settingsEditAprsRoute,
      maxWidth: 400,
      maxHeight: 320,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.settingsName, style: DialogStyles.labelStyle),
          const SizedBox(height: 4),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              hintText: l10n.settingsNameHint,
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
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
              ),
            ),
          ),
          if (_isDuplicateName) ...[
            const SizedBox(height: 4),
            Text(
              l10n.settingsDuplicateRoute,
              style: TextStyle(color: Colors.red.shade700, fontSize: 12),
            ),
          ],
          const SizedBox(height: 16),
          Text(l10n.settingsPath, style: DialogStyles.labelStyle),
          const SizedBox(height: 4),
          TextField(
            controller: _pathController,
            decoration: InputDecoration(
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              hintText: 'e.g. APN000,WIDE1-1,WIDE2-2',
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
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          style: DialogStyles.secondaryButtonStyle(context),
          child: Text(l10n.commonCancel),
        ),
        ElevatedButton(
          onPressed: _canSave
              ? () {
                  Navigator.of(context).pop(
                    AprsRoute(
                      name: _nameController.text.trim(),
                      path: _pathController.text.trim(),
                    ),
                  );
                }
              : null,
          style: DialogStyles.primaryButtonStyle(context),
          child: Text(l10n.commonOk),
        ),
      ],
    );
  }
}
