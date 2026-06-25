/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Downloads and caches the speech-to-text models used by the sherpa-onnx
recognizer.

sherpa-onnx loads models from file paths, so the chosen model's release archive
is fetched once, the required files are extracted, and their on-disk paths are
returned. Several model families of different sizes are offered (see [models]).
Only the model files live on disk; the radio audio is always processed in
memory.
*/

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'data_broker.dart';


/// Recognizer family a model belongs to; selects the sherpa-onnx config the
/// recognition isolate builds.
enum SttModelFamily { senseVoice, whisper }

/// A speech-to-text model the user can download and use.
class SttModel {
  final String id;
  final String name;
  final String description;
  final String downloadLabel;
  final SttModelFamily family;
  final String archiveUrl;
  final String dirName;

  /// Local file name to write -> exact base name inside the archive.
  final Map<String, String> files;

  /// Local file name whose presence (and size) marks a complete install.
  final String primaryFile;

  /// Recognition language codes the user may pick, or null for single-language
  /// (English-only) models.
  final List<String>? languages;

  const SttModel({
    required this.id,
    required this.name,
    required this.description,
    required this.downloadLabel,
    required this.family,
    required this.archiveUrl,
    required this.dirName,
    required this.files,
    required this.primaryFile,
    this.languages,
  });

  bool get multilingual => (languages?.length ?? 0) > 1;
}

/// Resolved on-disk paths for a downloaded model, ready for the engine.
class SttModelPaths {
  final SttModelFamily family;

  /// Local file name -> absolute path on disk.
  final Map<String, String> files;

  const SttModelPaths(this.family, this.files);
}

/// Lifecycle state of an on-disk speech-to-text model.
enum SttModelState { notInstalled, downloading, installing, ready, error }

/// Snapshot of a model's install/download status for the settings UI.
class SttModelStatus {
  final SttModelState state;
  final int receivedBytes;
  final int totalBytes;
  final String? message;

  const SttModelStatus(
    this.state, {
    this.receivedBytes = 0,
    this.totalBytes = -1,
    this.message,
  });

  /// Download/install progress in `[0, 1]`, or null when the total is unknown.
  double? get progress =>
      totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0.0, 1.0) : null;
}

/// Downloads, caches, and reports status for the selectable speech-to-text
/// models, downloading and extracting each on first use.
class SherpaModelManager {
  SherpaModelManager._();

  static const String _releaseBase =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/';

  /// Default model when none is selected or an unknown id is stored.
  static const String defaultModelId = 'sense-voice';

  /// Catalog of selectable models.
  static const List<SttModel> models = [
    SttModel(
      id: 'sense-voice',
      name: 'SenseVoice — multilingual',
      description:
          'Recognizes English, Chinese, Japanese, Korean and Cantonese with '
          'automatic language detection. Highest quality, largest download.',
      downloadLabel: '~1 GB download',
      family: SttModelFamily.senseVoice,
      archiveUrl:
          '${_releaseBase}sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17.tar.bz2',
      dirName: 'sense-voice',
      files: {'model.int8.onnx': 'model.int8.onnx', 'tokens.txt': 'tokens.txt'},
      primaryFile: 'model.int8.onnx',
      languages: ['auto', 'en', 'zh', 'ja', 'ko', 'yue'],
    ),
    SttModel(
      id: 'whisper-tiny.en',
      name: 'Whisper Tiny — English',
      description:
          'English only. Smallest and fastest download; lower accuracy than '
          'the larger models.',
      downloadLabel: '~110 MB download',
      family: SttModelFamily.whisper,
      archiveUrl: '${_releaseBase}sherpa-onnx-whisper-tiny.en.tar.bz2',
      dirName: 'whisper-tiny.en',
      files: {
        'encoder.int8.onnx': 'tiny.en-encoder.int8.onnx',
        'decoder.int8.onnx': 'tiny.en-decoder.int8.onnx',
        'tokens.txt': 'tiny.en-tokens.txt',
      },
      primaryFile: 'decoder.int8.onnx',
    ),
    SttModel(
      id: 'whisper-base.en',
      name: 'Whisper Base — English',
      description: 'English only. A good balance of accuracy and size.',
      downloadLabel: '~210 MB download',
      family: SttModelFamily.whisper,
      archiveUrl: '${_releaseBase}sherpa-onnx-whisper-base.en.tar.bz2',
      dirName: 'whisper-base.en',
      files: {
        'encoder.int8.onnx': 'base.en-encoder.int8.onnx',
        'decoder.int8.onnx': 'base.en-decoder.int8.onnx',
        'tokens.txt': 'base.en-tokens.txt',
      },
      primaryFile: 'decoder.int8.onnx',
    ),
  ];

  /// Looks up a model by id, falling back to the default for unknown/empty ids.
  static SttModel modelById(String? id) {
    for (final m in models) {
      if (m.id == id) return m;
    }
    return models.firstWhere((m) => m.id == defaultModelId);
  }

  /// The model currently chosen in settings (DataBroker dev 0 'VoiceModel').
  static String selectedModelId() {
    final id = DataBroker.getValue<String>(0, 'VoiceModel', defaultModelId);
    return modelById(id).id;
  }

  /// Per-model reactive status notifiers for the settings UI to observe.
  static final Map<String, ValueNotifier<SttModelStatus>> _statusByModel = {};

  /// Per-model guards against concurrent ensure calls.
  static final Map<String, Future<SttModelPaths?>> _inFlight = {};

  /// Optional progress sink: (receivedBytes, totalBytes | -1 if unknown).
  static void Function(int received, int total)? onDownloadProgress;

  static ValueNotifier<SttModelStatus> _notifier(String modelId) =>
      _statusByModel.putIfAbsent(
        modelId,
        () => ValueNotifier(const SttModelStatus(SttModelState.notInstalled)),
      );

  /// Reactive status for [modelId], created lazily.
  static ValueListenable<SttModelStatus> statusOf(String modelId) =>
      _notifier(modelId);

  /// Ensures [modelId] is available on disk, downloading/extracting if needed.
  /// Returns null if the model could not be made available.
  static Future<SttModelPaths?> ensureModel(String modelId) {
    final model = modelById(modelId);
    // NOTE: the callback MUST use a block body. An arrow body
    // `() => _inFlight.remove(model.id)` returns the removed value — which is
    // this very future — and Future.whenComplete then waits for that returned
    // future to complete, i.e. the future waits on itself and deadlocks (the
    // awaiting initialize() never resumes). A block body returns void instead.
    return _inFlight[model.id] ??= _ensure(model).whenComplete(() {
      _inFlight.remove(model.id);
    });
  }

  /// Directory holding [model]'s cached files.
  static Future<Directory> _modelDir(SttModel model) async {
    final supportDir = await getApplicationSupportDirectory();
    return Directory('${supportDir.path}/models/${model.dirName}');
  }

  /// Public helper returning the on-disk directory for [model].
  static Future<Directory> modelDirectory(SttModel model) => _modelDir(model);

  static Future<bool> _isInstalledIn(SttModel model, Directory dir) async {
    for (final local in model.files.keys) {
      if (!await File('${dir.path}/$local').exists()) return false;
    }
    final primary = File('${dir.path}/${model.primaryFile}');
    return await primary.length() > 1024 * 1024;
  }

  /// Whether [modelId] is fully downloaded and ready to load.
  static Future<bool> isInstalled(String modelId) async {
    final model = modelById(modelId);
    return _isInstalledIn(model, await _modelDir(model));
  }

  /// Total size on disk of [modelId]'s files, in bytes.
  static Future<int> installedSizeBytes(String modelId) async {
    final model = modelById(modelId);
    final dir = await _modelDir(model);
    var total = 0;
    for (final local in model.files.keys) {
      final f = File('${dir.path}/$local');
      if (await f.exists()) total += await f.length();
    }
    return total;
  }

  /// Recomputes [modelId]'s status from disk. No-op while it is busy.
  static Future<void> refreshStatus(String modelId) async {
    final n = _notifier(modelId);
    final s = n.value.state;
    if (s == SttModelState.downloading || s == SttModelState.installing) return;
    final installed = await isInstalled(modelId);
    n.value = SttModelStatus(
      installed ? SttModelState.ready : SttModelState.notInstalled,
    );
  }

  /// Deletes [modelId]'s cached files to reclaim disk space.
  static Future<void> deleteModel(String modelId) async {
    final n = _notifier(modelId);
    final s = n.value.state;
    if (s == SttModelState.downloading || s == SttModelState.installing) return;
    try {
      final dir = await _modelDir(modelById(modelId));
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('[SherpaModelManager] delete failed: $e');
    }
    n.value = const SttModelStatus(SttModelState.notInstalled);
  }

  static Future<SttModelPaths?> _ensure(SttModel model) async {
    final n = _notifier(model.id);
    try {
      final dir = await _modelDir(model);
      final installed = await _isInstalledIn(model, dir);

      // Already extracted? Use a size floor on the primary file to reject a
      // truncated/partial previous download.
      if (installed) {
        n.value = const SttModelStatus(SttModelState.ready);
        return _resolve(model, dir);
      }

      await dir.create(recursive: true);

      n.value = const SttModelStatus(SttModelState.downloading);
      final archiveFile = File('${dir.path}/${model.id}.tar.bz2.part');
      await _download(model.archiveUrl, archiveFile, (received, total) {
        onDownloadProgress?.call(received, total);
        n.value = SttModelStatus(
          SttModelState.downloading,
          receivedBytes: received,
          totalBytes: total,
        );
      });

      n.value = const SttModelStatus(SttModelState.installing);
      final ok = await _extractWithProgress(model, archiveFile.path, dir.path, n);

      // Best-effort cleanup of the downloaded archive.
      try {
        if (await archiveFile.exists()) await archiveFile.delete();
      } catch (_) {}

      if (!ok || !await _isInstalledIn(model, dir)) {
        n.value = const SttModelStatus(
          SttModelState.error,
          message: 'Model installation failed',
        );
        return null;
      }

      n.value = const SttModelStatus(SttModelState.ready);
      return _resolve(model, dir);
    } catch (e) {
      debugPrint('[SherpaModelManager] Failed to prepare ${model.id}: $e');
      n.value = SttModelStatus(SttModelState.error, message: '$e');
      return null;
    }
  }

  static SttModelPaths _resolve(SttModel model, Directory dir) {
    return SttModelPaths(model.family, <String, String>{
      for (final local in model.files.keys) local: '${dir.path}/$local',
    });
  }

  /// Resolves model file paths from an already known install directory without
  /// downloading or extracting any files.
  static SttModelPaths resolveInstalledModelPaths(SttModel model, Directory dir) {
    return _resolve(model, dir);
  }

  /// Decompresses and extracts [model] in a background isolate, reporting
  /// progress (compressed bytes consumed) through [n] while it runs.
  static Future<bool> _extractWithProgress(
    SttModel model,
    String archivePath,
    String outDir,
    ValueNotifier<SttModelStatus> n,
  ) async {
    final receivePort = ReceivePort();
    final completer = Completer<bool>();
    receivePort.listen((msg) {
      if (msg is List && msg.length == 2) {
        n.value = SttModelStatus(
          SttModelState.installing,
          receivedBytes: msg[0] as int,
          totalBytes: msg[1] as int,
        );
      } else if (msg is bool) {
        if (!completer.isCompleted) completer.complete(msg);
        receivePort.close();
      }
    });
    try {
      await Isolate.spawn(_extractIsolate, <Object>[
        receivePort.sendPort,
        archivePath,
        outDir,
        model.files,
      ]);
    } catch (_) {
      receivePort.close();
      return false;
    }
    return completer.future;
  }

  /// Streams [url] to [dest] without buffering the whole archive in memory.
  static Future<void> _download(
    String url,
    File dest,
    void Function(int received, int total) onProgress,
  ) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Download failed (HTTP ${response.statusCode})',
          uri: Uri.parse(url),
        );
      }

      final total = response.contentLength;
      var received = 0;
      final sink = dest.openWrite();
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          onProgress(received, total);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
    } finally {
      client.close();
    }
  }
}

/// Isolate entry point: streams the bzip2/tar archive from disk, reports the
/// number of compressed bytes consumed back to `args[0]` (a [SendPort]) as
/// `[consumed, total]` lists, and writes the requested files (`args[3]`, a
/// local-name -> archive-base-name map) to `args[2]`. Sends a final `bool`
/// indicating whether every requested file was written.
void _extractIsolate(List<Object> args) {
  final send = args[0] as SendPort;
  final archivePath = args[1] as String;
  final outDir = args[2] as String;
  final spec = (args[3] as Map).cast<String, String>();
  // Archive base name -> local file name to write.
  final wanted = <String, String>{
    for (final e in spec.entries) e.value: e.key,
  };
  try {
    final total = File(archivePath).lengthSync();
    final input = InputFileStream(archivePath);
    var lastReported = 0;
    final output = _ProgressOutputStream(() {
      final pos = input.position;
      if (pos - lastReported >= 4 * 1024 * 1024) {
        lastReported = pos;
        send.send(<int>[pos, total]);
      }
    });
    BZip2Decoder().decodeStream(input, output);
    input.closeSync();
    final tarBytes = output.getBytes();
    final archive = TarDecoder().decodeBytes(tarBytes);

    final written = <String>{};
    for (final entry in archive) {
      if (!entry.isFile) continue;
      final base = entry.name.split('/').last;
      final local = wanted[base];
      if (local != null) {
        File('$outDir/$local').writeAsBytesSync(entry.content as List<int>);
        written.add(local);
      }
      if (written.length == spec.length) break;
    }

    send.send(written.length == spec.length);
  } catch (_) {
    send.send(false);
  }
}

/// In-memory output buffer that notifies on each write so the extraction
/// isolate can report progress based on how much input has been consumed.
class _ProgressOutputStream extends OutputMemoryStream {
  final void Function() _onWrite;
  int _writeCount = 0;

  _ProgressOutputStream(this._onWrite);

  @override
  void writeByte(int value) {
    super.writeByte(value);
    // Sample only occasionally to keep the per-byte overhead negligible.
    if ((++_writeCount & 0xFFFFF) == 0) _onWrite();
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    super.writeBytes(bytes, length: length);
    _onWrite();
  }
}
