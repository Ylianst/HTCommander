// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
// Build-only compatibility for the unmodified BlueZ generic C implementation.
#include <stdint.h>
#include <intrin.h>
typedef intptr_t ssize_t;
#define __attribute__(x)
#define __LITTLE_ENDIAN 1234
#define __BIG_ENDIAN 4321
#define __BYTE_ORDER __LITTLE_ENDIAN

static unsigned sbc_reference_clz(unsigned value)
{
    unsigned long index;
    return _BitScanReverse(&index, value) ? 31 - index : 32;
}
#define __builtin_clz(value) sbc_reference_clz(value)
