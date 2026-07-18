/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart';

import '../aprs/aprs_symbols.dart';
import 'dialog_utils.dart';

/// Debug dialog that lists every APRS symbol alongside its two-character
/// identifier, name, and the Flutter icon we map it to. Used to visually
/// verify the symbol -> icon mappings in [kAprsPrimarySymbols] and
/// [kAprsAlternateSymbols].
Future<void> showAprsSymbolsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const _AprsSymbolsDialog(),
  );
}

class _AprsSymbolsDialog extends StatefulWidget {
  const _AprsSymbolsDialog();

  @override
  State<_AprsSymbolsDialog> createState() => _AprsSymbolsDialogState();
}

class _AprsSymbolsDialogState extends State<_AprsSymbolsDialog> {
  String _filter = '';

  bool _matches(AprsSymbol s) {
    if (_filter.isEmpty) return true;
    final q = _filter.toLowerCase();
    return s.name.toLowerCase().contains(q) ||
        s.id.toLowerCase().contains(q) ||
        s.code.toLowerCase() == q;
  }

  int get _mappedCount =>
      kAprsPrimarySymbols.where((s) => s.hasVisual).length +
      kAprsAlternateSymbols.where((s) => s.hasVisual).length;

  int get _totalCount =>
      kAprsPrimarySymbols.length + kAprsAlternateSymbols.length;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return HTDialog(
      title: 'APRS Symbols ($_mappedCount/$_totalCount mapped)',
      maxWidth: 560,
      maxHeight: 640,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            decoration: InputDecoration(
              filled: true,
              fillColor: scheme.surfaceContainerHighest,
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 18),
              hintText: 'Filter by name or symbol',
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
            ),
            onChanged: (v) => setState(() => _filter = v),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  _buildSection(scheme, 'Primary table  (/)', kAprsPrimarySymbols),
                  const SizedBox(height: 8),
                  _buildSection(
                      scheme, 'Alternate table  (\\)', kAprsAlternateSymbols),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: DialogStyles.primaryButtonStyle(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildSection(
    ColorScheme scheme,
    String title,
    List<AprsSymbol> symbols,
  ) {
    final rows = symbols.where(_matches).toList();
    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: scheme.primary,
            ),
          ),
        ),
        ...rows.map((s) => _buildRow(scheme, s)),
      ],
    );
  }

  Widget _buildRow(ColorScheme scheme, AprsSymbol s) {
    final hasVisual = s.hasVisual;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Icon preview, or an empty cell for un-mapped symbols (no icon yet).
          SizedBox(
            width: 32,
            child: hasVisual
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: aprsSymbolWidget(s, color: scheme.onSurface),
                  )
                : null,
          ),
          const SizedBox(width: 8),
          // Two-character identifier in a monospace box.
          Container(
            width: 44,
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              s.id,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Name.
          Expanded(
            child: Text(
              s.name,
              style: TextStyle(
                fontSize: 13,
                color: hasVisual ? scheme.onSurface : scheme.onSurfaceVariant,
                fontStyle: hasVisual ? FontStyle.normal : FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
