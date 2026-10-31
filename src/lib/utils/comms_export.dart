import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../dialogs/message_details_dialog.dart';
import '../l10n/app_localizations.dart';
import '../widgets/chat_widget.dart';

enum CommsExportFormat { csv, txt }

/// Prompts for a destination and saves [messages] as UTF-8 CSV or TXT.
Future<void> saveMessagesToFile(
  BuildContext context,
  List<ChatMessage> messages,
  CommsExportFormat format,
  String filePrefix,
) async {
  if (messages.isEmpty) return;
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final content = exportCommsMessages(messages, format);
  final extension = format.name;
  final timestamp = DateTime.now()
      .toUtc()
      .toIso8601String()
      .replaceAll(':', '-')
      .replaceAll('.', '-');
  final needsBytes = kIsWeb || Platform.isAndroid || Platform.isIOS;
  String? outputPath;
  try {
    outputPath = await FilePicker.saveFile(
      dialogTitle: l10n.commsSaveAsTitle,
      fileName: '$filePrefix-$timestamp.$extension',
      type: FileType.custom,
      allowedExtensions: [extension],
      bytes: needsBytes ? Uint8List.fromList(utf8.encode(content)) : null,
    );
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.errorOpeningFileDialog(error.toString()))),
    );
    return;
  }
  if (outputPath == null) return;
  if (!needsBytes) {
    if (!outputPath.toLowerCase().endsWith('.$extension')) {
      outputPath = '$outputPath.$extension';
    }
    try {
      await File(
        outputPath,
      ).writeAsString(content, encoding: utf8, flush: true);
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.errorSavingFile(error.toString()))),
      );
      return;
    }
  }
  messenger.showSnackBar(
    SnackBar(content: Text(l10n.commonSavedTo(outputPath))),
  );
}

String exportCommsMessages(
  Iterable<ChatMessage> messages,
  CommsExportFormat format,
) {
  final ordered = messages.indexed.toList()
    ..sort((first, second) {
      final comparison = first.$2.time.compareTo(second.$2.time);
      return comparison != 0 ? comparison : first.$1.compareTo(second.$1);
    });
  const headers = [
    'timestamp_utc',
    'direction',
    'type',
    'channel',
    'source',
    'destination',
    'text',
    'latitude',
    'longitude',
    'duration_seconds',
    'filename',
    'image_path',
    'wpm',
    'key_type',
    'authentication',
    'id',
    'route',
  ];
  final rows = ordered.map((entry) {
    final message = entry.$2;
    final details = message.tag is CommsMessageDetails
        ? message.tag as CommsMessageDetails
        : null;
    return <String>[
      message.time.toUtc().toIso8601String(),
      message.isSender ? 'sent' : 'received',
      details?.encoding ?? '',
      details?.channel ?? '',
      details?.source ?? message.senderCallsign,
      details?.destination ?? '',
      details != null && details.text.isNotEmpty
          ? details.text
          : message.message,
      (details?.latitude ?? message.latitude)?.toString() ?? '',
      (details?.longitude ?? message.longitude)?.toString() ?? '',
      details?.duration.toString() ?? '',
      details?.filename ?? message.filename ?? '',
      details?.imagePath ?? message.imagePath ?? '',
      details?.wpm?.toString() ?? '',
      details?.keyType ?? '',
      message.authState.name,
      message.id,
      message.route,
    ];
  });
  if (format == CommsExportFormat.csv) {
    String encodeRow(List<String> row) =>
        row.map((field) => '"${field.replaceAll('"', '""')}"').join(',');
    return '${[encodeRow(headers), ...rows.map(encodeRow)].join('\r\n')}\r\n';
  }
  final output = StringBuffer();
  for (final row in rows) {
    output.writeln('[${row[0]}] ${row[1].toUpperCase()}');
    for (var index = 2; index < headers.length; index++) {
      if (index == 6 || row[index].isEmpty) continue;
      output.writeln('${headers[index]}: ${row[index]}');
    }
    output.writeln(row[6]);
    output.writeln();
  }
  return output.toString();
}
