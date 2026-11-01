/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
HF data frame layout (payload, terminator/marker, control byte, CRC) and the
connect header frame.
*/

import 'dart:typed_data';

import 'call.dart';
import 'crc.dart';

const int hfTerminator = 0x14;

class HfControl {
  final int reply;
  final bool compressed;
  final int hint;

  const HfControl({this.reply = 0, this.compressed = false, this.hint = 0});

  int byte(bool last, bool full) =>
      ((reply << 6) | ((compressed ? 1 : 0) << 5) | ((hint & 7) << 2) | ((last ? 1 : 0) << 1) | (full ? 1 : 0)) &
      0xFF;

  static (HfControl, bool, bool) fromByte(int b) => (
        HfControl(reply: b >> 6, compressed: (b & 0x20) != 0, hint: (b >> 2) & 7),
        (b & 2) != 0,
        (b & 1) != 0,
      );

  @override
  bool operator ==(Object other) =>
      other is HfControl && other.reply == reply && other.compressed == compressed && other.hint == hint;

  @override
  int get hashCode => Object.hash(reply, compressed, hint);
}

int termMarker(List<int> caller) {
  final int m = crc16Genibus(caller) >> 8;
  return m == 0x00 || m == hfTerminator ? 0x01 : m;
}

int payloadCapacity(int frameLen, bool last) {
  final int v = frameLen - (3 + (last ? 1 : 0));
  return v > 0 ? v : 0;
}

Uint8List buildFrame(int frameLen, List<int> data, HfControl ctrl, int? last, int marker) {
  final int room = payloadCapacity(frameLen, last != null);
  final bool full = data.length >= room;
  final List<int> out = <int>[...data.take(room)];
  if (!full) {
    out.add(hfTerminator);
    if (out.length < room) out.add(marker);
    while (out.length < room) {
      out.add(0);
    }
  }
  if (last != null) out.add(last & 0xFF);
  out.add(ctrl.byte(last != null, full));
  final int crc = crc16Genibus(out);
  return Uint8List.fromList(<int>[...out, crc >> 8, crc & 0xFF]);
}

Uint8List headerPayload(List<int> call, int flags) {
  final Uint8List p = packCall(call);
  return Uint8List.fromList(<int>[...p, 0, flags & 0xFF]);
}

class HfHeader {
  final String call;
  final bool valid;
  final bool registered;
  final int comp;
  final int reply;
  final int offer;

  const HfHeader({
    this.call = '',
    this.valid = false,
    this.registered = false,
    this.comp = 0,
    this.reply = 0,
    this.offer = 0,
  });

  int get _flags => (valid ? 1 : 0) << 7 | (comp & 3) << 1 | (registered ? 1 : 0);

  Uint8List toFrame(int frameLen, int hint, int marker) => buildFrame(
      frameLen, headerPayload(call.codeUnits, _flags), HfControl(reply: reply, hint: hint), offer, marker);

  static HfHeader? parse(List<int> b) {
    if (b.length < 11) return null;
    final (HfControl ctrl, bool last, bool _) = HfControl.fromByte(b[b.length - 3]);
    if (!last || ctrl.compressed || b[6] != 0) return null;
    final int flags = b[7];
    return HfHeader(
      call: unpackCall(b.sublist(0, 6)) ?? '',
      valid: (flags & 0x80) != 0,
      registered: (flags & 1) != 0,
      comp: flags >> 1 & 3,
      reply: ctrl.reply,
      offer: b[b.length - 4],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HfHeader &&
      other.call == call &&
      other.valid == valid &&
      other.registered == registered &&
      other.comp == comp &&
      other.reply == reply &&
      other.offer == offer;

  @override
  int get hashCode => Object.hash(call, valid, registered, comp, reply, offer);
}
