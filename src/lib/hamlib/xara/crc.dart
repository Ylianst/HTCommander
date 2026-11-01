/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
*/

/// CRC-16/GENIBUS over [data].
int crc16Genibus(List<int> data, [int start = 0, int? end]) {
  final int stop = end ?? data.length;
  int c = 0xFFFF;
  for (int i = start; i < stop; i++) {
    c ^= (data[i] & 0xFF) << 8;
    for (int b = 0; b < 8; b++) {
      c = (c & 0x8000) != 0 ? ((c << 1) ^ 0x1021) & 0xFFFF : (c << 1) & 0xFFFF;
    }
  }
  return c ^ 0xFFFF;
}

/// True when the last two bytes of [frame] are the big-endian CRC of the rest.
bool crcOk(List<int> frame) {
  final int n = frame.length;
  if (n < 3) return false;
  final int crc = crc16Genibus(frame, 0, n - 2);
  return frame[n - 2] == crc >> 8 && frame[n - 1] == (crc & 0xFF);
}
