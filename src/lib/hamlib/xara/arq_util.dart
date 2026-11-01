/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
Small ARQ helpers: B2F protocol snooping, queue hints and in-order delivery.
*/

import 'dart:collection';

import 'hf_level.dart';
import 'textcomp.dart';

class B2fSnoop {
  bool _fs = false;
  bool _quit = false;

  void observe(List<int> block) {
    _quit |= block.length == 3 && block[0] == 0x46 && block[1] == 0x51 && block[2] == 0x0D;
    _fs |= block.length >= 5 &&
        block[0] == 0x46 &&
        block[1] == 0x53 &&
        block[2] == 0x20 &&
        block[block.length - 1] == 0x0D;
  }

  bool get fs => _fs;

  void clearFs() => _fs = false;

  bool takeQuit() {
    final bool q = _quit;
    _quit = false;
    return q;
  }
}

typedef HintRow = (int down, int same, List<(int, int)> up);

int queueHintBy(int l, int n, List<HintRow> rows, int max, bool Function(int l, int k) fits) {
  int k = 1;
  for (final (int down, int same, List<(int, int)> up) in rows) {
    if (l > 1 && fits(l - 1, k)) return down;
    if (fits(l, k)) return same;
    for (final (int d, int h) in up) {
      if (l + d <= n && fits(l + d, k)) return h;
    }
    k++;
  }
  return max;
}

const int hfHintMax = 6;
const List<(int, int)> _up = <(int, int)>[(1, 3), (2, 4), (3, 5), (4, 6)];

int hfPayloadLen(HfBandwidth bw, HfRecord level) => bw.level(level).payload;

int _hfQueueHintBy(HfBandwidth bw, HfRecord level, bool Function(HfRecord l, int k) fits) {
  final HfRecord top = bw.topLevel;
  return queueHintBy(level.value, top.value, <HintRow>[(0, 2, _up), (0, 1, _up)], hfHintMax, (l, k) {
    final HfRecord? r = HfRecord.of(l);
    return r != null && r.value <= top.value && fits(r, k);
  });
}

int hfQueueHint(HfBandwidth bw, HfRecord level, int queued) =>
    _hfQueueHintBy(bw, level, (l, k) => queued < k * hfPayloadLen(bw, l));

int hfQueueHintText(HfBandwidth bw, HfRecord level, List<int> queued, int state) =>
    _hfQueueHintBy(bw, level, (l, k) {
      final int p = hfPayloadLen(bw, l);
      return fitsFrames(queued, k, p, p - 1, state);
    });

/// Places received bytes into the first free slots after skipping [skip]
/// free slots, releasing the contiguous prefix.
class Reorder {
  final ListQueue<int?> _slots = ListQueue<int?>();
  final List<int?> _list = <int?>[];

  List<int> put(List<int> data, int skip) {
    _list
      ..clear()
      ..addAll(_slots);
    int i = 0, free = 0, it = 0;
    while (it < data.length) {
      if (i == _list.length) _list.add(null);
      if (_list[i] == null) {
        if (free >= skip) _list[i] = data[it++];
        free++;
      }
      i++;
    }
    int n = 0;
    while (n < _list.length && _list[n] != null) {
      n++;
    }
    final List<int> out = <int>[for (int j = 0; j < n; j++) _list[j]!];
    _slots
      ..clear()
      ..addAll(_list.skip(n));
    return out;
  }

  void clear() => _slots.clear();
}
