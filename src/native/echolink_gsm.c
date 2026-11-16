// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
#include "echolink_gsm.h"
#include "gsm_simd.h"
#include "gsm.h"
#include "private.h"

#include <stdlib.h>
#include <string.h>

struct ht_gsm_codec {
  struct gsm_state state;
  int32_t encoder;
  int16_t pcm[640];
  uint8_t frames[132];
};

int32_t ht_gsm_simd_width(void) { return HT_GSM_SIMD_WIDTH; }
int32_t ht_gsm_storage_bytes(void) { return (int32_t)sizeof(ht_gsm_codec); }

const char* ht_gsm_license(void) {
  return
    "Copyright 1992, 1993, 1994 by Jutta Degener and Carsten Bormann,\n"
    "Technische Universitaet Berlin\n\n"
    "Any use of this software is permitted provided that this notice is not\n"
    "removed and that neither the authors nor the Technische Universitaet Berlin\n"
    "are deemed to have made any representations as to the suitability of this\n"
    "software for any purpose nor are held responsible for any defects of\n"
    "this software.  THERE IS ABSOLUTELY NO WARRANTY FOR THIS SOFTWARE.\n\n"
    "As a matter of courtesy, the authors request to be informed about uses\n"
    "this software has found, about bugs in this software, and about any\n"
    "improvements that may be of general interest.\n\n"
    "Berlin, 28.11.1994\nJutta Degener\nCarsten Bormann\n\n"
    "                                 oOo\n\n"
    "Since the original terms of 15 years ago maybe do not make our\n"
    "intentions completely clear given today's refined usage of the legal\n"
    "terms, we append this additional permission:\n\n"
    "      Permission to use, copy, modify, and distribute this software\n"
    "      for any purpose with or without fee is hereby granted,\n"
    "      provided that this notice is not removed and that neither\n"
    "      the authors nor the Technische Universitaet Berlin are\n"
    "      deemed to have made any representations as to the suitability\n"
    "      of this software for any purpose nor are held responsible\n"
    "      for any defects of this software.  THERE IS ABSOLUTELY NO\n"
    "      WARRANTY FOR THIS SOFTWARE.\n\n"
    "Berkeley/Bremen, 05.04.2009\nJutta Degener\nCarsten Bormann\n";
}

ht_gsm_codec* ht_gsm_create(int32_t encoder, int32_t simd) {
  ht_gsm_codec* codec;
  if ((encoder != 0 && encoder != 1) || (simd != 0 && simd != 1)) return NULL;
  codec = (ht_gsm_codec*)calloc(1, sizeof(*codec));
  if (!codec) return NULL;
  codec->encoder = encoder;
  codec->state.nrp = 40;
  codec->state.ht_simd = simd;
  return codec;
}

void ht_gsm_destroy(ht_gsm_codec* codec) { free(codec); }

void ht_gsm_reset(ht_gsm_codec* codec) {
  if (codec) {
    const int simd = codec->state.ht_simd;
    memset(&codec->state, 0, sizeof(codec->state));
    codec->state.nrp = 40;
    codec->state.ht_simd = simd;
  }
}

int16_t* ht_gsm_pcm(ht_gsm_codec* codec) {
  return codec ? codec->pcm : NULL;
}

uint8_t* ht_gsm_frames(ht_gsm_codec* codec) {
  return codec ? codec->frames : NULL;
}

int32_t ht_gsm_encode(ht_gsm_codec* codec) {
  int i;
  if (!codec || !codec->encoder) return -1;
  for (i = 0; i < 4; ++i) {
    gsm_encode(&codec->state, codec->pcm + 160 * i, codec->frames + 33 * i);
  }
  return 0;
}

int32_t ht_gsm_decode(ht_gsm_codec* codec) {
  int i;
  if (!codec || codec->encoder) return -1;
  for (i = 0; i < 4; ++i) {
    if (gsm_decode(&codec->state, codec->frames + 33 * i,
                   codec->pcm + 160 * i) != 0) return i + 1;
  }
  return 0;
}
