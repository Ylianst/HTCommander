/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Manages the BBS file area from the BBS tab: lists the files BBS users can
download, adds and deletes files, opens the folder and toggles uploads. Talks to
the host's BbsFileStore over the DataBroker, so it also works from a detached
window.
*/

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../handlers/bbs_files.dart';
import '../l10n/app_localizations.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import 'dialog_utils.dart';

class BbsFilesDialog extends StatefulWidget {
  const BbsFilesDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => const BbsFilesDialog(),
  );

  @override
  State<BbsFilesDialog> createState() => _BbsFilesDialogState();
}

class _BbsFilesDialogState extends State<BbsFilesDialog> {
  final DataBrokerClient _broker = DataBrokerClient();
  List<BbsFile> _files = const [];
  int? _selectedId;
  bool _uploadsEnabled = true;

  /// Too narrow for the date column (phones).
  bool _compact = false;

  static bool get _canOpenFolder =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  @override
  void initState() {
    super.initState();
    _applyFiles(DataBroker.getValueDynamic(1, 'BbsFiles'));
    _uploadsEnabled =
        (_broker.getValue<int>(0, BbsFileStore.uploadsSetting, 1) ?? 1) == 1;
    _broker.subscribe(
      deviceId: 1,
      name: 'BbsFiles',
      callback: (_, _, data) => setState(() => _applyFiles(data)),
    );
    _broker.subscribe(
      deviceId: 0,
      name: BbsFileStore.uploadsSetting,
      callback: (_, _, data) =>
          setState(() => _uploadsEnabled = (data is int ? data : 1) == 1),
    );
    // Pick up files the sysop copied into the folder.
    _command('BbsFilesRefresh');
  }

  @override
  void dispose() {
    _broker.dispose();
    super.dispose();
  }

  void _applyFiles(Object? data) {
    if (data is! List) return;
    _files = [for (final f in data) ?BbsFile.fromJson(f)].reversed.toList();
    if (!_files.any((f) => f.id == _selectedId)) _selectedId = null;
  }

  void _command(String name, [Object? data]) =>
      _broker.dispatch(deviceId: 1, name: name, data: data, store: false);

  Future<void> _addFiles() async {
    final l10n = AppLocalizations.of(context);
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (result == null) return;
    for (final file in result.files) {
      var bytes = file.bytes;
      if (bytes == null && !kIsWeb && file.path != null) {
        try {
          bytes = await File(file.path!).readAsBytes();
        } catch (_) {}
      }
      if (bytes == null) {
        if (mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(content: Text(l10n.bbsFilesAddFailed(file.name))),
          );
        }
        continue;
      }
      _command('BbsFileAdd', <String, Object?>{
        'Name': file.name,
        'Data': bytes,
      });
    }
  }

  Future<void> _deleteSelected() async {
    final l10n = AppLocalizations.of(context);
    final file = _files.where((f) => f.id == _selectedId).firstOrNull;
    if (file == null) return;
    final ok = await DialogHelper.showConfirmDialog(
      context,
      title: l10n.commonDelete,
      message: l10n.bbsFilesDeleteConfirm(file.name),
      okText: l10n.commonDelete,
      cancelText: l10n.commonCancel,
    );
    if (ok) _command('BbsFileDelete', file.id);
  }

  void _setUploads(bool value) {
    setState(() => _uploadsEnabled = value);
    _broker.dispatch(
      deviceId: 0,
      name: BbsFileStore.uploadsSetting,
      data: value ? 1 : 0,
    );
  }

  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String _date(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final header = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: scheme.onSurfaceVariant,
    );
    return HTDialog(
      title: l10n.bbsFilesTitle,
      maxWidth: 640,
      maxHeight: 520,
      content: LayoutBuilder(
        builder: (context, constraints) {
          _compact = constraints.maxWidth < 480;
          return _buildContent(header);
        },
      ),
    );
  }

  Widget _buildContent(TextStyle header) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Checkbox(
              value: _uploadsEnabled,
              onChanged: (v) => _setUploads(v ?? false),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () => _setUploads(!_uploadsEnabled),
                child: Text(
                  l10n.bbsFilesAllowUploads,
                  style: DialogStyles.bodyStyle,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          color: scheme.surfaceContainerHigh,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              SizedBox(width: 40, child: Text('#', style: header)),
              Expanded(child: Text(l10n.bbsFilesColName, style: header)),
              SizedBox(
                width: 72,
                child: Text(
                  l10n.bbsFilesColSize,
                  style: header,
                  textAlign: TextAlign.right,
                ),
              ),
              const SizedBox(width: 12),
              if (!_compact) ...[
                SizedBox(
                  width: 100,
                  child: Text(l10n.bbsFilesColUploader, style: header),
                ),
                SizedBox(
                  width: 120,
                  child: Text(l10n.bbsFilesColDate, style: header),
                ),
              ],
            ],
          ),
        ),
        Flexible(
          child: Container(
            constraints: const BoxConstraints(minHeight: 160),
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: _files.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        l10n.bbsFilesEmpty,
                        textAlign: TextAlign.center,
                        style: DialogStyles.bodyStyle.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemExtent: 30,
                    itemCount: _files.length,
                    itemBuilder: (context, i) => _buildRow(_files[i]),
                  ),
          ),
        ),
        const SizedBox(height: 16),
        // Wraps on narrow screens, unlike HTDialog's action row.
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: _buildActions(),
        ),
      ],
    );
  }

  List<Widget> _buildActions() {
    final l10n = AppLocalizations.of(context);
    return [
      if (_canOpenFolder)
        TextButton(
          onPressed: () => _command('BbsFileOpenFolder'),
          style: DialogStyles.secondaryButtonStyle(context),
          child: Text(l10n.bbsFilesOpenFolder),
        ),
      TextButton(
        onPressed: _selectedId == null ? null : _deleteSelected,
        style: DialogStyles.secondaryButtonStyle(context),
        child: Text(l10n.commonDelete),
      ),
      TextButton(
        onPressed: _addFiles,
        style: DialogStyles.secondaryButtonStyle(context),
        child: Text(l10n.bbsFilesAdd),
      ),
      ElevatedButton(
        onPressed: () => Navigator.of(context).pop(),
        style: DialogStyles.primaryButtonStyle(context),
        child: Text(l10n.commonClose),
      ),
    ];
  }

  Widget _buildRow(BbsFile f) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final selected = f.id == _selectedId;
    const style = TextStyle(fontSize: 13);
    return InkWell(
      onTap: () => setState(() => _selectedId = selected ? null : f.id),
      child: Container(
        color: selected ? scheme.primaryContainer : null,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            SizedBox(width: 40, child: Text('${f.id}', style: style)),
            Expanded(
              child: Text(
                f.name,
                style: style,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: 72,
              child: Text(
                _size(f.size),
                style: style,
                textAlign: TextAlign.right,
              ),
            ),
            const SizedBox(width: 12),
            if (!_compact) ...[
              SizedBox(
                width: 100,
                child: Text(
                  f.uploader.isEmpty ? l10n.bbsFilesSysop : f.uploader,
                  style: style.copyWith(
                    color: f.uploader.isEmpty ? scheme.onSurfaceVariant : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(width: 120, child: Text(_date(f.time), style: style)),
            ],
          ],
        ),
      ),
    );
  }
}
