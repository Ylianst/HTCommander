import 'package:flutter/material.dart';

/// Common dialog styling constants and utilities
class DialogStyles {
  // Standard dialog background color (light gray like C# app)
  static const Color backgroundColor = Color(0xFFD3D3D3);

  // Standard padding
  static const EdgeInsets padding = EdgeInsets.all(16);

  // Standard button styles
  static ButtonStyle primaryButtonStyle(BuildContext context) {
    return ElevatedButton.styleFrom(
      backgroundColor: Colors.blue,
      foregroundColor: Colors.white,
    );
  }

  static ButtonStyle secondaryButtonStyle(BuildContext context) {
    return TextButton.styleFrom(
      foregroundColor: Theme.of(context).colorScheme.onSurface,
    );
  }

  // Standard text styles
  static const TextStyle titleStyle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle labelStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle bodyStyle = TextStyle(fontSize: 13);

  static const TextStyle linkStyle = TextStyle(
    fontSize: 13,
    color: Colors.blue,
    decoration: TextDecoration.underline,
  );

  /// Standard rounded, filled text-field decoration used across dialogs.
  ///
  /// [focusColor] defaults to the theme primary; some dialogs pass
  /// [Colors.blue] to match the app accent. [invalid] swaps the fill to the
  /// error container unless an explicit [fillColor] is supplied. Content
  /// padding widens at the top when a [labelText] is present so the floating
  /// label has room.
  static InputDecoration inputDecoration(
    BuildContext context, {
    String? hintText,
    String? labelText,
    String? errorText,
    String? helperText,
    String? counterText,
    Color? fillColor,
    Color? focusColor,
    bool invalid = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InputDecoration(
      filled: true,
      fillColor: fillColor ??
          (invalid ? scheme.errorContainer : scheme.surfaceContainerHighest),
      hintText: hintText,
      labelText: labelText,
      errorText: errorText,
      helperText: helperText,
      counterText: counterText,
      isDense: true,
      contentPadding: labelText != null
          ? const EdgeInsets.fromLTRB(12, 20, 12, 12)
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
        borderSide: BorderSide(color: focusColor ?? scheme.primary, width: 2),
      ),
    );
  }
}

/// Base dialog widget that provides consistent styling
class HTDialog extends StatelessWidget {
  final String? title;
  final Widget content;
  final List<Widget>? actions;
  final double? maxWidth;
  final double? maxHeight;
  final EdgeInsets? padding;

  const HTDialog({
    super.key,
    this.title,
    required this.content,
    this.actions,
    this.maxWidth,
    this.maxHeight,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: scheme.surface,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth ?? 500,
          maxHeight: maxHeight ?? 400,
        ),
        child: Padding(
          padding: padding ?? DialogStyles.padding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null) ...[
                Text(
                  title!,
                  style: DialogStyles.titleStyle.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Flexible(child: content),
              if (actions != null && actions!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: actions!
                      .map(
                        (action) => Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: action,
                        ),
                      )
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Helper functions for showing dialogs
class DialogHelper {
  /// Shows a confirmation dialog with OK/Cancel buttons
  static Future<bool> showConfirmDialog(
    BuildContext context, {
    required String title,
    required String message,
    String okText = 'OK',
    String cancelText = 'Cancel',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => HTDialog(
        title: title,
        content: Text(message, style: DialogStyles.bodyStyle),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: DialogStyles.secondaryButtonStyle(context),
            child: Text(cancelText),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: DialogStyles.primaryButtonStyle(context),
            child: Text(okText),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Shows an information dialog with just an OK button
  static Future<void> showInfoDialog(
    BuildContext context, {
    required String title,
    required String message,
    String okText = 'OK',
  }) async {
    await showDialog<void>(
      context: context,
      builder: (context) => HTDialog(
        title: title,
        content: Text(message, style: DialogStyles.bodyStyle),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: DialogStyles.primaryButtonStyle(context),
            child: Text(okText),
          ),
        ],
      ),
    );
  }

  /// Shows an error dialog
  static Future<void> showErrorDialog(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (context) => HTDialog(
        title: title,
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 32),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: DialogStyles.bodyStyle)),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: DialogStyles.primaryButtonStyle(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
