// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Ordered, asynchronous file I/O for PCM16 mono clips. Admission is synchronous
/// so the first audio frame can be captured without waiting for the file open.
///
/// The shared budget includes allocated batches until their writes complete.
/// Overflow fails the entire affected clip, never publishing audio with a gap.
class WavRecordingWriter {
  WavRecordingWriter({
    required this.onError,
    this.maxPendingBytes = 1024 * 1024,
    this.batchBytes = 64 * 1024,
    this.maxPendingClips = 32,
    Future<RandomAccessFile> Function(String path)? openFile,
  }) : _openFile = openFile ?? _openRecordingFile {
    if (batchBytes <= 0 ||
        maxPendingBytes < batchBytes ||
        maxPendingClips <= 0) {
      throw ArgumentError('Invalid recording queue limits');
    }
  }

  final void Function(String message) onError;
  final int maxPendingBytes;
  final int batchBytes;
  final int maxPendingClips;
  final Future<RandomAccessFile> Function(String path) _openFile;
  final Queue<_Command> _queue = Queue<_Command>();
  final Set<WavClipRecorder> _clips = {};
  int _pendingBytes = 0;
  bool _running = false;

  WavClipRecorder open(String path, int sampleRate) {
    if (sampleRate <= 0) throw ArgumentError.value(sampleRate, 'sampleRate');
    final clip = WavClipRecorder._(this, path, sampleRate);
    if (_clips.length >= maxPendingClips) {
      clip._fail('pending clip limit ($maxPendingClips) exceeded');
    } else {
      _clips.add(clip);
      _queue.add(_Command(_Kind.open, clip));
      _schedule();
    }
    return clip;
  }

  void _schedule() {
    if (_running) return;
    _running = true;
    // Briefly coalesce adjacent audio events; close waits for this drain too.
    unawaited(Future<void>.delayed(const Duration(milliseconds: 20), _drain));
  }

  Future<void> _drain() async {
    while (_queue.isNotEmpty) {
      final command = _queue.removeFirst();
      final clip = command.clip;
      try {
        switch (command.kind) {
          case _Kind.open:
            if (!clip._failed) {
              clip._file = await _openFile(clip.path);
              await clip._file!.writeFrom(_header(0, clip.sampleRate));
            }
          case _Kind.write:
            if (!clip._failed) {
              await clip._file!.writeFrom(command.bytes!, 0, command.used);
            }
          case _Kind.close:
            await _finish(clip);
        }
      } catch (error) {
        clip._fail('${command.kind.name}: $error');
        if (command.kind == _Kind.close) {
          await _release(clip);
        }
      } finally {
        _pendingBytes -= command.bytes?.length ?? 0;
      }
    }
    _running = false;
  }

  Future<void> _finish(WavClipRecorder clip) async {
    if (!clip._failed && !clip._discard) {
      await clip._file!.setPosition(0);
      await clip._file!.writeFrom(_header(clip.dataBytes, clip.sampleRate));
      await clip._file!.flush();
    }
    await _release(clip);
  }

  Future<void> _release(WavClipRecorder clip) async {
    final file = clip._file;
    clip._file = null;
    if (file != null) {
      try {
        await file.close();
      } catch (error) {
        clip._fail('close: $error');
      }
    }
    String? result;
    if (clip._failed || clip._discard) {
      // Only remove files we successfully opened; an open failure must not
      // delete an unrelated existing path.
      if (file != null) {
        try {
          await File(clip.path).delete();
        } catch (error) {
          onError('[Recording] Failed to discard ${clip.path}: $error');
        }
      }
    } else {
      result = clip.path;
      final destination = clip._renameTo;
      if (destination != null && destination != result) {
        try {
          await File(result).rename(destination);
          result = destination;
        } catch (error) {
          onError('[Recording] Failed to rename $result: $error');
        }
      }
    }
    _clips.remove(clip);
    clip._closed.complete(result);
  }
}

Future<RandomAccessFile> _openRecordingFile(String path) =>
    File(path).open(mode: FileMode.write);

class WavClipRecorder {
  WavClipRecorder._(this._writer, this.path, this.sampleRate);

  final WavRecordingWriter _writer;
  final String path;
  final int sampleRate;
  final Completer<String?> _closed = Completer<String?>();
  RandomAccessFile? _file;
  bool _failed = false;
  bool _closing = false;
  bool _discard = false;
  String? _renameTo;
  int _dataBytes = 0;

  /// Bytes accepted for this clip, available immediately for duration tracking.
  int get dataBytes => _dataBytes;

  void _fail(String reason) {
    if (_failed) return;
    _failed = true;
    _writer.onError('[Recording] Failed recording $path: $reason');
  }

  void write(Uint8List bytes, int offset, int length) {
    RangeError.checkValidRange(offset, offset + length, bytes.length);
    if (_closing) throw StateError('Recording is already closing');
    if (_failed || length == 0) return;
    if (_dataBytes + length > 0xffffffff - 36) {
      _fail('WAV size limit exceeded');
      return;
    }
    final tail = _writer._queue.isEmpty ? null : _writer._queue.last;
    final reusable =
        tail != null && tail.kind == _Kind.write && identical(tail.clip, this);
    final available = reusable ? tail.bytes!.length - tail.used : 0;
    final newBytes = math.max(0, length - available);
    final allocation =
        ((newBytes + _writer.batchBytes - 1) ~/ _writer.batchBytes) *
        _writer.batchBytes;
    if (_writer._pendingBytes + allocation > _writer.maxPendingBytes) {
      _fail('pending audio queue overflow (${_writer.maxPendingBytes} bytes)');
      return;
    }
    var remaining = length;
    var position = offset;
    var batch = reusable ? tail : null;
    while (remaining > 0) {
      if (batch == null || batch.used == batch.bytes!.length) {
        batch = _Command(_Kind.write, this, Uint8List(_writer.batchBytes));
        _writer._pendingBytes += _writer.batchBytes;
        _writer._queue.add(batch);
      }
      final count = math.min(remaining, batch.bytes!.length - batch.used);
      batch.bytes!.setRange(batch.used, batch.used + count, bytes, position);
      batch.used += count;
      position += count;
      remaining -= count;
    }
    _dataBytes += length;
    _writer._schedule();
  }

  /// Drains all accepted PCM before patching sizes, flushing and closing.
  /// Returns the final path, or null for a discarded/failed clip. Idempotent.
  Future<String?> close({String? renameTo, bool discard = false}) {
    if (_closing) return _closed.future;
    _closing = true;
    _renameTo = renameTo;
    _discard = discard;
    if (!_writer._clips.contains(this)) {
      _closed.complete(null);
    } else {
      _writer._queue.add(_Command(_Kind.close, this));
      _writer._schedule();
    }
    return _closed.future;
  }
}

enum _Kind { open, write, close }

class _Command {
  _Command(this.kind, this.clip, [this.bytes]);
  final _Kind kind;
  final WavClipRecorder clip;
  final Uint8List? bytes;
  int used = 0;
}

Uint8List _header(int dataBytes, int sampleRate) {
  final bytes = Uint8List(44);
  final data = ByteData.sublistView(bytes);
  bytes.setAll(0, 'RIFF'.codeUnits);
  data.setUint32(4, 36 + dataBytes, Endian.little);
  bytes.setAll(8, 'WAVEfmt '.codeUnits);
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  bytes.setAll(36, 'data'.codeUnits);
  data.setUint32(40, dataBytes, Endian.little);
  return bytes;
}
