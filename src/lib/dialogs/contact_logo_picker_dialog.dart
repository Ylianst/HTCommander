import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../widgets/contact_avatar.dart';
import 'dialog_utils.dart';

/// Shows a grid of the built-in contact logos and returns the chosen logo name,
/// or null if cancelled.
Future<String?> showContactLogoPicker(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (context) {
      final l10n = AppLocalizations.of(context);
      final scheme = Theme.of(context).colorScheme;
      final entries = kContactLogos.entries.toList();
      return AlertDialog(
        title: Text(l10n.contactAvatarChooseLogo),
        content: SizedBox(
          width: 320,
          child: GridView.builder(
            shrinkWrap: true,
            itemCount: entries.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemBuilder: (context, index) {
              final entry = entries[index];
              return InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () => Navigator.of(context).pop(entry.key),
                child: CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(entry.value, color: scheme.onPrimaryContainer),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: DialogStyles.secondaryButtonStyle(context),
            child: Text(l10n.commonCancel),
          ),
        ],
      );
    },
  );
}
