/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
Link compression modes and the FILES-mode deflate chunking.
*/

import 'dart:typed_data';

import 'package:archive/archive.dart' show Deflate;

import 'arq_time.dart';
import 'inflate.dart';

enum Compression {
  off,
  text,
  files;

  int get bits => index;

  static Compression fromBits(int b) => b == 1 ? text : (b == 2 ? files : off);
}

const int filesPause = second * 3 ~/ 20;
const int filesChunkLen = 32500;
const int maxInflated = 50000;

/// One FILES chunk: 2-byte header (deflated flag + length) then the body.
Uint8List filesChunk(List<int> data) {
  final Uint8List z = Deflate(data).getBytes();
  final bool deflated = z.length < data.length;
  final List<int> body = deflated ? z : data;
  return Uint8List.fromList(<int>[(deflated ? 0x80 : 0) | (body.length >> 8), body.length & 0xFF, ...body]);
}

void chunkQueue(List<int> buf) {
  if (buf.isEmpty) return;
  final List<int> raw = List<int>.of(buf);
  buf.clear();
  for (int i = 0; i < raw.length; i += filesChunkLen) {
    buf.addAll(filesChunk(raw.sublist(i, i + filesChunkLen < raw.length ? i + filesChunkLen : raw.length)));
  }
}

class FilesStager {
  List<int> _stage = <int>[];
  int? _flushAt;

  int get length => _stage.length;
  bool get isEmpty => _stage.isEmpty;
  int? get deadline => _flushAt;

  bool due(int now) => _flushAt != null && now >= _flushAt!;

  void clear() {
    _stage = <int>[];
    _flushAt = null;
  }

  void push(int now, List<int> data, List<int> out) {
    _stage.addAll(data);
    _flushAt = now + filesPause;
    while (_stage.length >= filesChunkLen) {
      out.addAll(filesChunk(_stage.sublist(0, filesChunkLen)));
      _stage = _stage.sublist(filesChunkLen);
    }
  }

  void flush(List<int> out) {
    _flushAt = null;
    if (_stage.isNotEmpty) {
      out.addAll(filesChunk(_stage));
      _stage = <int>[];
    }
  }
}

class FilesReader {
  final List<int> _buf = <int>[];

  List<Uint8List> push(List<int> data) {
    _buf.addAll(data);
    final List<Uint8List> blocks = <Uint8List>[];
    while (true) {
      if (_buf.length < 2) return blocks;
      final int len = (_buf[0] & 0x7F) << 8 | _buf[1];
      if (_buf.length < 2 + len) return blocks;
      final bool deflated = (_buf[0] & 0x80) != 0;
      final Uint8List body = Uint8List.fromList(_buf.sublist(2, 2 + len));
      _buf.removeRange(0, 2 + len);
      final Uint8List out = deflated ? (inflateRaw(body, maxInflated) ?? Uint8List(0)) : body;
      if (out.isNotEmpty) blocks.add(out);
    }
  }
}
