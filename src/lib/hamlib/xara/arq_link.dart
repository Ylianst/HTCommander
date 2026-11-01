/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
Per-link state shared by the HF and FM sessions: timers, compression mode,
FILES staging, B2F snooping and in-order delivery.
*/

import 'dart:typed_data';

import 'arq_util.dart';
import 'compression.dart';
import 'textcomp.dart';

class RxAsm {
  final Reorder slots = Reorder();
  bool? turnCompressed;
}

class ArqLink {
  final RxAsm rx = RxAsm();
  Compression comp = Compression.off;
  final FilesStager files = FilesStager();
  final B2fSnoop b2f = B2fSnoop();
  int? deadline;
  int? watchdog;
  int? idleTimer;
  int idleTicks = 0;
  bool discNow = false;
  bool discAfterTx = false;
  int discTimeouts = 0;
  final FilesReader _reader = FilesReader();

  int? nextDeadline() {
    int? best;
    for (final int? t in <int?>[deadline, watchdog, idleTimer, files.deadline]) {
      if (t != null && (best == null || t < best)) best = t;
    }
    return best;
  }

  bool watchdogFired(int now) {
    final bool due = watchdog != null && now >= watchdog!;
    if (due) watchdog = null;
    return due;
  }

  bool deadlineFired(int now) {
    final bool due = deadline != null && now >= deadline!;
    if (due) deadline = null;
    return due;
  }

  int? idleFired(int now) {
    if (idleTimer == null || now < idleTimer!) return null;
    idleTimer = null;
    return ++idleTicks;
  }

  bool get text => comp == Compression.text;

  void queue(int now, bool connected, List<int> data, List<int> buf) {
    b2f.observe(data);
    if (connected && comp == Compression.files) {
      files.push(now, data, buf);
    } else {
      buf.addAll(data);
    }
  }

  void startFiles(List<int> buf) {
    if (comp == Compression.files) chunkQueue(buf);
  }

  Uint8List? inflate(bool second, bool compressed, Uint8List data) =>
      text && !second && compressed ? decompress(data)?.$1 : data;

  void turnQuit(List<int> buf) {
    b2f.clearFs();
    if (b2f.takeQuit()) {
      discAfterTx = true;
      buf.clear();
    }
  }

  bool wantsQrt(int queued) => discNow || discAfterTx && queued + files.length == 0;

  void deliver(List<int> data, int skip, void Function(Uint8List) host) {
    final List<int> out = rx.slots.put(data, skip);
    if (out.isEmpty) return;
    if (comp != Compression.files) {
      host(Uint8List.fromList(out));
      return;
    }
    for (final Uint8List b in _reader.push(out)) {
      host(b);
    }
  }
}
