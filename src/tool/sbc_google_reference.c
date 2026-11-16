// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
// Thin ownership/interleaving adapter; codec arithmetic stays upstream.
#include <sbc.h>
#include <stdlib.h>

struct reference {
    sbc_t codec;
    struct sbc_frame frame;
};

__declspec(dllexport) void *reference_create(int header, int bitpool, int msbc)
{
    struct reference *ref = calloc(1, sizeof(*ref));
    if (!ref) return NULL;
    ref->frame = (struct sbc_frame) {
        .msbc = msbc != 0,
        .freq = (header >> 6) & 3,
        .mode = (header >> 2) & 3,
        .bam = (header >> 1) & 1,
        .nblocks = msbc ? 15 : 4 * (1 + ((header >> 4) & 3)),
        .nsubbands = (header & 1) ? 8 : 4,
        .bitpool = bitpool
    };
    sbc_reset(&ref->codec);
    return ref;
}

__declspec(dllexport) void reference_destroy(struct reference *ref)
{
    free(ref);
}

__declspec(dllexport) int reference_process(
    struct reference *ref, int encode, const unsigned char *input, int input_size,
    unsigned char *output, int output_size)
{
    const int channels = ref->frame.mode == SBC_MODE_MONO ? 1 : 2;
    const int pcm_size = ref->frame.nblocks * ref->frame.nsubbands * channels * 2;
    const int frame_size = (int)sbc_get_frame_size(&ref->frame);
    if (frame_size <= 0 ||
        input_size != (encode ? pcm_size : frame_size) ||
        output_size < (encode ? frame_size : pcm_size)) return -1;
    int status;
    if (encode) {
        const int16_t *pcm = (const int16_t *)input;
        status = sbc_encode(&ref->codec, pcm, channels,
            channels == 1 ? NULL : pcm + 1, channels,
            &ref->frame, output, output_size);
    } else {
        int16_t *pcm = (int16_t *)output;
        status = sbc_decode(&ref->codec, input, input_size, &ref->frame,
            pcm, channels, channels == 1 ? NULL : pcm + 1, channels);
    }
    return status == 0 ? (encode ? frame_size : pcm_size) : -1;
}
