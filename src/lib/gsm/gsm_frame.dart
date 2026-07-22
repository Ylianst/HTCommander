// gsm_frame.dart - Standard (non-WAV49) 33-byte frame packing.
//
// Port of the non-WAV49 paths of libgsm 1.0.22 gsm_encode.c / gsm_decode.c.
// This is the classic "toast" bit layout used by EchoLink. Source of truth:
// reference/libgsm/src/gsm_encode.c, reference/libgsm/src/gsm_decode.c.

import 'dart:typed_data';

/// 13 kbit/s RPE-LTP magic nibble.
const int gsmMagic = 0xD;

/// Encoded frame size in bytes.
const int gsmFrameSize = 33;

/// Decoded samples per frame.
const int gsmFrameSamples = 160;

/// Packs the coder parameters into 33 bytes at `c[off..off+32]`.
void packFrame(Int16List larc, Int16List nc, Int16List bc, Int16List mc,
    Int16List xmaxc, Int16List xmc, Uint8List c, [int off = 0]) {
  c[off + 0] = ((gsmMagic & 0xF) << 4) | ((larc[0] >> 2) & 0xF);
  c[off + 1] = ((larc[0] & 0x3) << 6) | (larc[1] & 0x3F);
  c[off + 2] = ((larc[2] & 0x1F) << 3) | ((larc[3] >> 2) & 0x7);
  c[off + 3] = ((larc[3] & 0x3) << 6) | ((larc[4] & 0xF) << 2) | ((larc[5] >> 2) & 0x3);
  c[off + 4] = ((larc[5] & 0x3) << 6) | ((larc[6] & 0x7) << 3) | (larc[7] & 0x7);
  c[off + 5] = ((nc[0] & 0x7F) << 1) | ((bc[0] >> 1) & 0x1);
  c[off + 6] = ((bc[0] & 0x1) << 7) | ((mc[0] & 0x3) << 5) | ((xmaxc[0] >> 1) & 0x1F);
  c[off + 7] = ((xmaxc[0] & 0x1) << 7) | ((xmc[0] & 0x7) << 4) | ((xmc[1] & 0x7) << 1) | ((xmc[2] >> 2) & 0x1);
  c[off + 8] = ((xmc[2] & 0x3) << 6) | ((xmc[3] & 0x7) << 3) | (xmc[4] & 0x7);
  c[off + 9] = ((xmc[5] & 0x7) << 5) | ((xmc[6] & 0x7) << 2) | ((xmc[7] >> 1) & 0x3);
  c[off + 10] = ((xmc[7] & 0x1) << 7) | ((xmc[8] & 0x7) << 4) | ((xmc[9] & 0x7) << 1) | ((xmc[10] >> 2) & 0x1);
  c[off + 11] = ((xmc[10] & 0x3) << 6) | ((xmc[11] & 0x7) << 3) | (xmc[12] & 0x7);
  c[off + 12] = ((nc[1] & 0x7F) << 1) | ((bc[1] >> 1) & 0x1);
  c[off + 13] = ((bc[1] & 0x1) << 7) | ((mc[1] & 0x3) << 5) | ((xmaxc[1] >> 1) & 0x1F);
  c[off + 14] = ((xmaxc[1] & 0x1) << 7) | ((xmc[13] & 0x7) << 4) | ((xmc[14] & 0x7) << 1) | ((xmc[15] >> 2) & 0x1);
  c[off + 15] = ((xmc[15] & 0x3) << 6) | ((xmc[16] & 0x7) << 3) | (xmc[17] & 0x7);
  c[off + 16] = ((xmc[18] & 0x7) << 5) | ((xmc[19] & 0x7) << 2) | ((xmc[20] >> 1) & 0x3);
  c[off + 17] = ((xmc[20] & 0x1) << 7) | ((xmc[21] & 0x7) << 4) | ((xmc[22] & 0x7) << 1) | ((xmc[23] >> 2) & 0x1);
  c[off + 18] = ((xmc[23] & 0x3) << 6) | ((xmc[24] & 0x7) << 3) | (xmc[25] & 0x7);
  c[off + 19] = ((nc[2] & 0x7F) << 1) | ((bc[2] >> 1) & 0x1);
  c[off + 20] = ((bc[2] & 0x1) << 7) | ((mc[2] & 0x3) << 5) | ((xmaxc[2] >> 1) & 0x1F);
  c[off + 21] = ((xmaxc[2] & 0x1) << 7) | ((xmc[26] & 0x7) << 4) | ((xmc[27] & 0x7) << 1) | ((xmc[28] >> 2) & 0x1);
  c[off + 22] = ((xmc[28] & 0x3) << 6) | ((xmc[29] & 0x7) << 3) | (xmc[30] & 0x7);
  c[off + 23] = ((xmc[31] & 0x7) << 5) | ((xmc[32] & 0x7) << 2) | ((xmc[33] >> 1) & 0x3);
  c[off + 24] = ((xmc[33] & 0x1) << 7) | ((xmc[34] & 0x7) << 4) | ((xmc[35] & 0x7) << 1) | ((xmc[36] >> 2) & 0x1);
  c[off + 25] = ((xmc[36] & 0x3) << 6) | ((xmc[37] & 0x7) << 3) | (xmc[38] & 0x7);
  c[off + 26] = ((nc[3] & 0x7F) << 1) | ((bc[3] >> 1) & 0x1);
  c[off + 27] = ((bc[3] & 0x1) << 7) | ((mc[3] & 0x3) << 5) | ((xmaxc[3] >> 1) & 0x1F);
  c[off + 28] = ((xmaxc[3] & 0x1) << 7) | ((xmc[39] & 0x7) << 4) | ((xmc[40] & 0x7) << 1) | ((xmc[41] >> 2) & 0x1);
  c[off + 29] = ((xmc[41] & 0x3) << 6) | ((xmc[42] & 0x7) << 3) | (xmc[43] & 0x7);
  c[off + 30] = ((xmc[44] & 0x7) << 5) | ((xmc[45] & 0x7) << 2) | ((xmc[46] >> 1) & 0x3);
  c[off + 31] = ((xmc[46] & 0x1) << 7) | ((xmc[47] & 0x7) << 4) | ((xmc[48] & 0x7) << 1) | ((xmc[49] >> 2) & 0x1);
  c[off + 32] = ((xmc[49] & 0x3) << 6) | ((xmc[50] & 0x7) << 3) | (xmc[51] & 0x7);
}

/// Unpacks 33 bytes at `b[off..off+32]` into the parameter arrays. Returns
/// false if the GSM magic nibble is wrong (matches gsm_decode returning -1).
bool unpackFrame(Uint8List b, int off, Int16List larc, Int16List nc,
    Int16List bc, Int16List mc, Int16List xmaxc, Int16List xmc) {
  int i = off;
  if (((b[i] >> 4) & 0x0F) != gsmMagic) return false;

  larc[0] = (b[i++] & 0xF) << 2;
  larc[0] |= (b[i] >> 6) & 0x3;
  larc[1] = b[i++] & 0x3F;
  larc[2] = (b[i] >> 3) & 0x1F;
  larc[3] = (b[i++] & 0x7) << 2;
  larc[3] |= (b[i] >> 6) & 0x3;
  larc[4] = (b[i] >> 2) & 0xF;
  larc[5] = (b[i++] & 0x3) << 2;
  larc[5] |= (b[i] >> 6) & 0x3;
  larc[6] = (b[i] >> 3) & 0x7;
  larc[7] = b[i++] & 0x7;
  nc[0] = (b[i] >> 1) & 0x7F;
  bc[0] = (b[i++] & 0x1) << 1;
  bc[0] |= (b[i] >> 7) & 0x1;
  mc[0] = (b[i] >> 5) & 0x3;
  xmaxc[0] = (b[i++] & 0x1F) << 1;
  xmaxc[0] |= (b[i] >> 7) & 0x1;
  xmc[0] = (b[i] >> 4) & 0x7;
  xmc[1] = (b[i] >> 1) & 0x7;
  xmc[2] = (b[i++] & 0x1) << 2;
  xmc[2] |= (b[i] >> 6) & 0x3;
  xmc[3] = (b[i] >> 3) & 0x7;
  xmc[4] = b[i++] & 0x7;
  xmc[5] = (b[i] >> 5) & 0x7;
  xmc[6] = (b[i] >> 2) & 0x7;
  xmc[7] = (b[i++] & 0x3) << 1;
  xmc[7] |= (b[i] >> 7) & 0x1;
  xmc[8] = (b[i] >> 4) & 0x7;
  xmc[9] = (b[i] >> 1) & 0x7;
  xmc[10] = (b[i++] & 0x1) << 2;
  xmc[10] |= (b[i] >> 6) & 0x3;
  xmc[11] = (b[i] >> 3) & 0x7;
  xmc[12] = b[i++] & 0x7;
  nc[1] = (b[i] >> 1) & 0x7F;
  bc[1] = (b[i++] & 0x1) << 1;
  bc[1] |= (b[i] >> 7) & 0x1;
  mc[1] = (b[i] >> 5) & 0x3;
  xmaxc[1] = (b[i++] & 0x1F) << 1;
  xmaxc[1] |= (b[i] >> 7) & 0x1;
  xmc[13] = (b[i] >> 4) & 0x7;
  xmc[14] = (b[i] >> 1) & 0x7;
  xmc[15] = (b[i++] & 0x1) << 2;
  xmc[15] |= (b[i] >> 6) & 0x3;
  xmc[16] = (b[i] >> 3) & 0x7;
  xmc[17] = b[i++] & 0x7;
  xmc[18] = (b[i] >> 5) & 0x7;
  xmc[19] = (b[i] >> 2) & 0x7;
  xmc[20] = (b[i++] & 0x3) << 1;
  xmc[20] |= (b[i] >> 7) & 0x1;
  xmc[21] = (b[i] >> 4) & 0x7;
  xmc[22] = (b[i] >> 1) & 0x7;
  xmc[23] = (b[i++] & 0x1) << 2;
  xmc[23] |= (b[i] >> 6) & 0x3;
  xmc[24] = (b[i] >> 3) & 0x7;
  xmc[25] = b[i++] & 0x7;
  nc[2] = (b[i] >> 1) & 0x7F;
  bc[2] = (b[i++] & 0x1) << 1;
  bc[2] |= (b[i] >> 7) & 0x1;
  mc[2] = (b[i] >> 5) & 0x3;
  xmaxc[2] = (b[i++] & 0x1F) << 1;
  xmaxc[2] |= (b[i] >> 7) & 0x1;
  xmc[26] = (b[i] >> 4) & 0x7;
  xmc[27] = (b[i] >> 1) & 0x7;
  xmc[28] = (b[i++] & 0x1) << 2;
  xmc[28] |= (b[i] >> 6) & 0x3;
  xmc[29] = (b[i] >> 3) & 0x7;
  xmc[30] = b[i++] & 0x7;
  xmc[31] = (b[i] >> 5) & 0x7;
  xmc[32] = (b[i] >> 2) & 0x7;
  xmc[33] = (b[i++] & 0x3) << 1;
  xmc[33] |= (b[i] >> 7) & 0x1;
  xmc[34] = (b[i] >> 4) & 0x7;
  xmc[35] = (b[i] >> 1) & 0x7;
  xmc[36] = (b[i++] & 0x1) << 2;
  xmc[36] |= (b[i] >> 6) & 0x3;
  xmc[37] = (b[i] >> 3) & 0x7;
  xmc[38] = b[i++] & 0x7;
  nc[3] = (b[i] >> 1) & 0x7F;
  bc[3] = (b[i++] & 0x1) << 1;
  bc[3] |= (b[i] >> 7) & 0x1;
  mc[3] = (b[i] >> 5) & 0x3;
  xmaxc[3] = (b[i++] & 0x1F) << 1;
  xmaxc[3] |= (b[i] >> 7) & 0x1;
  xmc[39] = (b[i] >> 4) & 0x7;
  xmc[40] = (b[i] >> 1) & 0x7;
  xmc[41] = (b[i++] & 0x1) << 2;
  xmc[41] |= (b[i] >> 6) & 0x3;
  xmc[42] = (b[i] >> 3) & 0x7;
  xmc[43] = b[i++] & 0x7;
  xmc[44] = (b[i] >> 5) & 0x7;
  xmc[45] = (b[i] >> 2) & 0x7;
  xmc[46] = (b[i++] & 0x3) << 1;
  xmc[46] |= (b[i] >> 7) & 0x1;
  xmc[47] = (b[i] >> 4) & 0x7;
  xmc[48] = (b[i] >> 1) & 0x7;
  xmc[49] = (b[i++] & 0x1) << 2;
  xmc[49] |= (b[i] >> 6) & 0x3;
  xmc[50] = (b[i] >> 3) & 0x7;
  xmc[51] = b[i] & 0x7;

  return true;
}
