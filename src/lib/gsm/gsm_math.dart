// gsm_math.dart - Fixed-point arithmetic primitives for the GSM 06.10 codec.
//
// Faithful pure-Dart port of the integer math in libgsm 1.0.22
// (add.c and the macros in private.h) by Jutta Degener and Carsten Bormann,
// Technische Universitaet Berlin. Source of truth: reference/libgsm.
//
// Terminology mirrors the C source:
//   word     -> signed 16-bit value ([-32768, 32767])
//   longword -> signed 32-bit value ([-2147483648, 2147483647])
//
// The reference is built with -DSASR (arithmetic shift right), which matches
// Dart's `>>` operator on ints, and with the pure integer path (no FAST /
// USE_FLOAT_MUL). longword accumulations that are not explicitly saturated fit
// within 64-bit ints exactly as they do in the reference build on a 64-bit
// host (where C `long` is 64-bit), so Dart ints reproduce them bit-for-bit.

const int kMinWord = -32768; // MIN_WORD = -(32767) - 1
const int kMaxWord = 32767; // MAX_WORD
const int kMinLongword = -2147483648; // MIN_LONGWORD
const int kMaxLongword = 2147483647; // MAX_LONGWORD

/// Reinterprets the low 16 bits of [x] as a signed word.
///
/// This models assignment to a C `word` (short) variable, which silently
/// truncates. Storing into an [Int16List] performs the same truncation, so
/// this helper is only needed for scalar `word` locals that can overflow.
int wordOf(int x) {
  x &= 0xFFFF;
  return x >= 0x8000 ? x - 0x10000 : x;
}

/// saturate(x) from add.c: clamp to word range.
int saturate(int x) => x < kMinWord ? kMinWord : (x > kMaxWord ? kMaxWord : x);

/// gsm_add: word = saturate(a + b).
int gsmAdd(int a, int b) => saturate(a + b);

/// gsm_sub: word = saturate(a - b).
int gsmSub(int a, int b) => saturate(a - b);

/// gsm_mult (function form, with the a==b==MIN_WORD special case).
int gsmMult(int a, int b) {
  if (a == kMinWord && b == kMinWord) return kMaxWord;
  return (a * b) >> 15;
}

/// gsm_mult_r (function form): rounds, masks to 16 bits, handles MIN*MIN.
int gsmMultR(int a, int b) {
  if (a == kMinWord && b == kMinWord) return kMaxWord;
  final int prod = (a * b + 16384) >> 15;
  return wordOf(prod & 0xFFFF);
}

/// gsm_abs.
int gsmAbs(int a) => a < 0 ? (a == kMinWord ? kMaxWord : -a) : a;

/// GSM_MULT macro form: SASR(a*b, 15), no special case, no truncation.
int multMacro(int a, int b) => (a * b) >> 15;

/// GSM_MULT_R macro form: SASR(a*b + 16384, 15), no mask, no special case.
int multRMacro(int a, int b) => (a * b + 16384) >> 15;

/// GSM_L_MULT macro: (a * b) << 1. Assumes not (a == b == MIN_WORD).
int lMult(int a, int b) => (a * b) << 1;

/// gsm_L_add / GSM_L_ADD: saturating 32-bit add.
int gsmLAdd(int a, int b) {
  if (a < 0) {
    if (b >= 0) return a + b;
    final int aA = -(a + 1) + -(b + 1);
    return aA >= kMaxLongword ? kMinLongword : -aA - 2;
  } else if (b <= 0) {
    return a + b;
  } else {
    final int aA = a + b;
    return aA > kMaxLongword ? kMaxLongword : aA;
  }
}

/// gsm_L_sub: saturating 32-bit subtract.
int gsmLSub(int a, int b) {
  if (a >= 0) {
    if (b >= 0) {
      return a - b;
    } else {
      final int aA = a + -(b + 1);
      return aA >= kMaxLongword ? kMaxLongword : (aA + 1);
    }
  } else if (b <= 0) {
    return a - b;
  } else {
    final int aA = -(a + 1) + b;
    return aA >= kMaxLongword ? kMinLongword : -aA - 1;
  }
}

const List<int> _bitoff = <int>[
  8, 7, 6, 6, 5, 5, 5, 5, 4, 4, 4, 4, 4, 4, 4, 4, //
  3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
  2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
  2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
];

/// gsm_norm: number of left shifts needed to normalize a 32-bit value.
int gsmNorm(int a) {
  assert(a != 0);
  if (a < 0) {
    if (a <= -1073741824) return 0;
    a = ~a;
  }
  return (a & 0xffff0000) != 0
      ? ((a & 0xff000000) != 0
          ? -1 + _bitoff[0xFF & (a >> 24)]
          : 7 + _bitoff[0xFF & (a >> 16)])
      : ((a & 0xff00) != 0
          ? 15 + _bitoff[0xFF & (a >> 8)]
          : 23 + _bitoff[0xFF & a]);
}

/// gsm_asr: arithmetic shift right on a word, with the libgsm edge cases.
int gsmAsr(int a, int n) {
  if (n >= 16) return -(a < 0 ? 1 : 0);
  if (n <= -16) return 0;
  if (n < 0) return wordOf(a << -n);
  return a >> n;
}

/// gsm_asl: arithmetic shift left on a word, with the libgsm edge cases.
int gsmAsl(int a, int n) {
  if (n >= 16) return 0;
  if (n <= -16) return -(a < 0 ? 1 : 0);
  if (n < 0) return gsmAsr(a, -n);
  return wordOf(a << n);
}

/// gsm_div: integer division as specified in section 4.2.5 (denum >= num > 0).
int gsmDiv(int num, int denum) {
  int lNum = num;
  final int lDenum = denum;
  int div = 0;
  int k = 15;
  if (num == 0) return 0;
  while (k-- > 0) {
    div <<= 1;
    lNum <<= 1;
    if (lNum >= lDenum) {
      lNum -= lDenum;
      div++;
    }
  }
  return div;
}
