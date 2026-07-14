/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Port of the C# `AddTorrentFileForm`.
*/

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/torrent_file.dart';
import '../utils/compression.dart';
import '../l10n/app_localizations.dart';
import 'dialog_utils.dart';

/// Shows the "Add Torrent File" dialog and returns the built [TorrentFile] when
/// the user confirms, or `null` if cancelled.
///
/// [initialPath] pre-selects a file (used by drag-and-drop in the torrent tab).
Future<TorrentFile?> showAddTorrentFileDialog(
  BuildContext context, {
  String? initialPath,
}) {
  return showDialog<TorrentFile>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AddTorrentFileDialog(initialPath: initialPath),
  );
}

/// Dialog that selects a file, compresses it, and produces a shareable
/// [TorrentFile] (port of the C# `AddTorrentFileForm`).
class AddTorrentFileDialog extends StatefulWidget {
  const AddTorrentFileDialog({super.key, this.initialPath});

  /// Optional file path to import immediately when the dialog opens.
  final String? initialPath;

  @override
  State<AddTorrentFileDialog> createState() => _AddTorrentFileDialogState();
}

class _AddTorrentFileDialogState extends State<AddTorrentFileDialog> {
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _fileController = TextEditingController();

  TorrentFile? _torrentFile;
  String _compressionLabel = '';
  String? _errorMessage;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialPath;
    if (initial != null && initial.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _import(initial));
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _fileController.dispose();
    super.dispose();
  }

  Future<void> _selectFile() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: AppLocalizations.of(context).attSelectFile,
    );
    final path = result?.files.single.path;
    if (path == null) return;
    await _import(path);
  }

  /// Reads the file at [path], builds a [TorrentFile], and updates the UI
  /// (mirrors the C# `Import`).
  Future<void> _import(String path) async {
    setState(() {
      _busy = true;
      _errorMessage = null;
      _compressionLabel = AppLocalizations.of(context).attCompressing;
    });
    try {
      final file = File(path);
      final bytes = await file.readAsBytes();
      final name = _basename(path);
      final torrent = TorrentFile.fromFileBytes(
        fileName: name,
        fileBytes: bytes,
      );
      if (!mounted) return;
      setState(() {
        _torrentFile = torrent;
        _fileController.text = name;
        _compressionLabel = _buildCompressionLabel(torrent);
        _busy = false;
      });
    } on TorrentImportException catch (e) {
      if (!mounted) return;
      setState(() {
        _torrentFile = null;
        _fileController.text = '';
        _compressionLabel = '';
        _errorMessage = e.message;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _torrentFile = null;
        _fileController.text = '';
        _compressionLabel = '';
        _errorMessage = 'Failed to read file: $e';
        _busy = false;
      });
    }
  }

  String _buildCompressionLabel(TorrentFile file) {
    final compressedBytes = file.compressedSize - 1; // strip the tag byte
    switch (file.compression) {
      case TorrentCompression.deflate:
        return 'Deflate, ${file.size} -> $compressedBytes bytes';
      case TorrentCompression.brotli:
        return 'Brotli, ${file.size} -> $compressedBytes bytes';
      case TorrentCompression.none:
      case TorrentCompression.unknown:
        return 'None, $compressedBytes bytes';
    }
  }

  void _onAdd() {
    final file = _torrentFile;
    if (file == null) return;
    final description = _descriptionController.text;
    file.description = description.length > 200
        ? description.substring(0, 200)
        : description;
    Navigator.of(context).pop(file);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFFF5F5F5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(AppLocalizations.of(context).attTitle, style: DialogStyles.titleStyle),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: _sectionDecoration(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            readOnly: true,
                            controller: _fileController,
                            decoration: _inputDecoration(labelText: AppLocalizations.of(context).torrentColFile),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _busy ? null : _selectFile,
                          style: DialogStyles.primaryButtonStyle(context),
                          child: Text(AppLocalizations.of(context).attSelect),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Colors.red,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (_compressionLabel.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            if (_busy)
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            else
                              const Icon(
                                Icons.check_circle_outline,
                                color: Colors.green,
                                size: 18,
                              ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _compressionLabel,
                                style: DialogStyles.bodyStyle,
                              ),
                            ),
                          ],
                        ),
                      ),
                    TextField(
                      controller: _descriptionController,
                      maxLength: 200,
                      maxLines: 3,
                      minLines: 3,
                      inputFormatters: [LengthLimitingTextInputFormatter(200)],
                      decoration: _inputDecoration(
                        labelText: AppLocalizations.of(context).attDescriptionOptional,
                        alignLabelWithHint: true,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: DialogStyles.secondaryButtonStyle(context),
                    child: Text(AppLocalizations.of(context).commonCancel),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: (_torrentFile != null && !_busy) ? _onAdd : null,
                    style: DialogStyles.primaryButtonStyle(context),
                    child: Text(AppLocalizations.of(context).commonAdd),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final idx = normalized.lastIndexOf('/');
    return idx >= 0 ? normalized.substring(idx + 1) : normalized;
  }

  BoxDecoration _sectionDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration({
    String? labelText,
    bool alignLabelWithHint = false,
  }) {
    return InputDecoration(
      filled: true,
      fillColor: Colors.grey.shade100,
      labelText: labelText,
      isDense: true,
      alignLabelWithHint: alignLabelWithHint,
      contentPadding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
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
