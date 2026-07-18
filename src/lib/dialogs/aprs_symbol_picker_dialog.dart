/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart';

import '../aprs/aprs_symbols.dart';
import 'dialog_utils.dart';

/// Shows a picker that lets the user choose an APRS symbol. Returns the chosen
/// [AprsSymbol], or `null` if the dialog was dismissed without a selection.
///
/// [selectedTable] and [selectedCode] highlight the currently chosen symbol.
Future<AprsSymbol?> showAprsSymbolPicker(
  BuildContext context, {
  String? selectedTable,
  String? selectedCode,
}) {
  return showDialog<AprsSymbol>(
    context: context,
    builder: (context) => _AprsSymbolPickerDialog(
      selectedTable: selectedTable,
      selectedCode: selectedCode,
    ),
  );
}

class _AprsSymbolPickerDialog extends StatefulWidget {
  final String? selectedTable;
  final String? selectedCode;

  const _AprsSymbolPickerDialog({this.selectedTable, this.selectedCode});

  @override
  State<_AprsSymbolPickerDialog> createState() =>
      _AprsSymbolPickerDialogState();
}

class _AprsSymbolPickerDialogState extends State<_AprsSymbolPickerDialog> {
  String _filter = '';

  // When true, the dialog is in "combo" (overlay) selection mode.
  bool _comboMode = false;

  // Selected overlay character for combo mode (a digit or capital letter).
  String _overlayChar = 'A';

  @override
  void initState() {
    super.initState();
    // Start in combo mode when the current selection is already an overlay.
    final table = widget.selectedTable ?? '';
    if (aprsIsOverlay(table)) {
      _comboMode = true;
      _overlayChar = table;
    }
  }

  bool _matches(AprsSymbol s) {
    if (_filter.isEmpty) return true;
    final q = _filter.toLowerCase();
    return s.name.toLowerCase().contains(q) ||
        s.id.toLowerCase().contains(q) ||
        s.code.toLowerCase() == q;
  }

  bool _isSelected(AprsSymbol s) =>
      s.table == widget.selectedTable && s.code == widget.selectedCode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return HTDialog(
      title:
          _comboMode ? 'Select Overlay (Combo) Symbol' : 'Select APRS Symbol',
      maxWidth: 560,
      maxHeight: 640,
      content: _comboMode ? _buildComboMode(scheme) : _buildListMode(scheme),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: DialogStyles.secondaryButtonStyle(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // List (plain symbol) mode
  // ---------------------------------------------------------------------------

  Widget _buildListMode(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
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
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => setState(() => _comboMode = true),
              icon: const Icon(Icons.layers, size: 18),
              label: const Text('Combo'),
            ),
          ],
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
    final selected = _isSelected(s);
    return InkWell(
      onTap: () => Navigator.of(context).pop(s),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : null,
          border: Border(
            bottom: BorderSide(color: scheme.outlineVariant, width: 0.5),
          ),
        ),
        child: Row(
          children: [
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
            _idChip(scheme, s.id),
            const SizedBox(width: 12),
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
            if (selected) Icon(Icons.check, size: 18, color: scheme.primary),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Combo (overlay) mode
  // ---------------------------------------------------------------------------

  Widget _buildComboMode(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Back',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.arrow_back, size: 20),
              onPressed: () => setState(() => _comboMode = false),
            ),
            const SizedBox(width: 4),
            const Expanded(
              child: Text(
                'Pick an overlay character, then a base symbol.',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Overlay character',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: scheme.primary,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final ch in kAprsOverlayChars) _overlayCharChip(scheme, ch),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Base symbol',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: scheme.primary,
          ),
        ),
        const SizedBox(height: 6),
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
                for (final base in aprsOverlayableSymbols)
                  _buildComboRow(scheme, base),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _overlayCharChip(ColorScheme scheme, String ch) {
    final selected = ch == _overlayChar;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => setState(() => _overlayChar = ch),
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 1.5 : 0.5,
          ),
        ),
        child: Text(
          ch,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _buildComboRow(ColorScheme scheme, AprsSymbol base) {
    final id = '$_overlayChar${base.code}';
    return InkWell(
      onTap: () => Navigator.of(context)
          .pop(AprsSymbol(_overlayChar, base.code, base.name)),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: scheme.outlineVariant, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Align(
                alignment: Alignment.centerLeft,
                // Live preview of the base with the current overlay char.
                child: aprsSymbolWidgetFor(
                  _overlayChar,
                  base.code,
                  color: scheme.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _idChip(scheme, id),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                base.name,
                style: TextStyle(fontSize: 13, color: scheme.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _idChip(ColorScheme scheme, String id) {
    return Container(
      width: 44,
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        id,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

