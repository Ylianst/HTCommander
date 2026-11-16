// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
#include "reed_solomon.h"
#include <algorithm>
#include <cstring>
#include <memory>
#include <new>

namespace {
struct Plan {
  int mode, nr, fcr, prim, ip;
  uint8_t exp[256], log[256], gen[256], data[510]{};
  int scratch[9][512]{};
  std::unique_ptr<uint8_t[]> products;
  const uint8_t* syndromeRows[254]{};
  int mod(int x) const { x %= 255; return x < 0 ? x + 255 : x; }
  int power(int x) const { return exp[mod(x)]; }
  int mul(int a, int b) const {
    return products[(a << 8) | b];
  }
  int inv(int x) const { return power(255 - log[x]); }
  int eval(const int* p, int len, int x) const {
    const uint8_t* row = products.get() + (x << 8);
    int y = p[len - 1];
    for (int i = len - 2; i >= 0; --i) y = row[y] ^ p[i];
    return y;
  }
  bool sondeSyndromes(int* s) const {
    for (int i = 0; i < nr; ++i) s[i] = data[254];
    // Independent Horner chains hide lookup latency. Each fixed-root row is
    // just 256 bytes; there are no logs, zero branches or modulo in this loop.
    for (int j = 253; j >= 0; --j) {
      const int coefficient = data[j];
      for (int i = 0; i < nr; ++i)
        s[i] = syndromeRows[i][s[i]] ^ coefficient;
    }
    int any = 0;
    for (int i = 0; i < nr; ++i) any |= s[i];
    return any != 0;
  }
  void encode() {
    auto& rem = scratch[0];
    std::fill_n(rem, 512, 0);
    if (mode == 0) {
      for (int i = 254; i >= nr; --i) {
        int feedback = data[i] ^ rem[nr - 1];
        for (int j = nr - 1; j > 0; --j)
          rem[j] = rem[j - 1] ^ mul(feedback, gen[j]);
        rem[0] = mul(feedback, gen[0]);
      }
      for (int i = 0; i < nr; ++i) data[i] = uint8_t(rem[i]);
    } else {
      for (int i = 0; i < 255 - nr; ++i) {
        int feedback = log[data[i] ^ rem[0]];
        if (feedback != 255)
          for (int j = 1; j < nr; ++j)
            rem[j] ^= power(feedback + gen[nr - j]);
        for (int j = 0; j < nr - 1; ++j) rem[j] = rem[j + 1];
        rem[nr - 1] = feedback == 255 ? 0 : power(feedback + gen[0]);
      }
      for (int i = 0; i < nr; ++i) data[255 - nr + i] = uint8_t(rem[i]);
    }
  }
  int sonde() {
    auto& s = scratch[0];
    auto& lambda = scratch[1];
    auto& b = scratch[2];
    auto& t = scratch[3];
    auto& omega = scratch[4];
    auto& derivative = scratch[5];
    auto& roots = scratch[6];
    auto& positions = scratch[7];
    if (!sondeSyndromes(s)) return 0;
    // No scratch clearing is needed on the common clean-block path.
    std::fill_n(lambda, 512, 0);
    std::fill_n(b, 512, 0);
    std::fill_n(omega, 512, 0);
    std::fill_n(derivative, 512, 0);
    lambda[0] = b[0] = 1;
    int ll = 1, bl = 1, l = 0, m = 1, bb = 1;
    for (int nn = 0; nn < nr; ++nn) {
      int delta = s[nn];
      for (int i = 1; i <= l; ++i)
        if (i < ll) delta ^= mul(lambda[i], s[nn - i]);
      if (delta == 0) { ++m; continue; }
      int oldLen = ll;
      std::copy_n(lambda, ll, t);
      int scale = mul(delta, inv(bb));
      ll = std::max(ll, m + bl);
      for (int i = oldLen; i < ll; ++i) lambda[i] = 0;
      for (int i = 0; i < bl; ++i) lambda[i + m] ^= mul(scale, b[i]);
      if (2 * l <= nn) {
        l = nn + 1 - l;
        bl = oldLen;
        std::copy_n(t, bl, b);
        bb = delta;
        m = 1;
      } else {
        ++m;
      }
    }
    int degree = ll - 1;
    while (degree > 0 && lambda[degree] == 0) --degree;
    if (degree > nr / 2) return -1;
    int count = 0;
    for (int xe = 1; xe < 256; ++xe) {
      if (eval(lambda, ll, xe) == 0) {
        roots[count] = xe;
        positions[count++] = mod(log[inv(xe)] * ip);
      }
    }
    if (count != degree) return -1;
    for (int i = 0; i < nr; ++i)
      for (int j = 0; j < ll && i + j < nr; ++j)
        omega[i + j] ^= mul(s[i], lambda[j]);
    int dl = std::max(1, ll - 1);
    for (int i = 1; i < ll; ++i) derivative[i - 1] = (i & 1) ? lambda[i] : 0;
    for (int k = 0; k < count; ++k) {
      int xe = roots[k];
      int den = eval(derivative, dl, xe);
      if (den == 0) return -1;
      int y = mul(eval(omega, nr, xe), inv(den));
      if (fcr == 0) y = mul(y, inv(xe));
      else if (fcr > 1) y = mul(y, power((fcr - 1) * log[xe]));
      data[positions[k]] ^= uint8_t(y);
    }
    return sondeSyndromes(s) ? -1 : count;
  }
  int fx25(int noEras) {
    auto& lambda = scratch[0];
    auto& s = scratch[1];
    auto& b = scratch[2];
    auto& t = scratch[3];
    auto& omega = scratch[4];
    auto& root = scratch[5];
    auto& reg = scratch[6];
    auto& loc = scratch[7];
    for (int i = 0; i < nr; ++i) s[i] = data[0];
    for (int j = 1; j < 255; ++j)
      for (int i = 0; i < nr; ++i)
        s[i] = s[i] == 0 ? data[j]
            : data[j] ^ power(log[s[i]] + (fcr + i) * prim);
    int synError = 0;
    for (int i = 0; i < nr; ++i) {
      synError |= s[i];
      s[i] = log[s[i]];
    }
    if (synError == 0) return 0;
    lambda[0] = 1;
    if (noEras > 0) {
      lambda[1] = power(prim * (254 - data[255]));
      for (int i = 1; i < noEras; ++i) {
        // Preserve the reference implementation's polynomial-form u here.
        int u = power(prim * (254 - data[255 + i]));
        for (int j = i + 1; j > 0; --j) {
          int tmp = log[lambda[j - 1]];
          if (tmp != 255) lambda[j] ^= power(u + tmp);
        }
      }
    }
    for (int i = 0; i <= nr; ++i) b[i] = log[lambda[i]];
    int r = noEras, el = noEras;
    while (++r <= nr) {
      int discr = 0;
      for (int i = 0; i < r; ++i)
        if (lambda[i] != 0 && s[r - i - 1] != 255)
          discr ^= power(log[lambda[i]] + s[r - i - 1]);
      discr = log[discr];
      if (discr == 255) {
        for (int i = nr; i > 0; --i) b[i] = b[i - 1];
        b[0] = 255;
      } else {
        t[0] = lambda[0];
        for (int i = 0; i < nr; ++i)
          t[i + 1] = lambda[i + 1] ^ (b[i] == 255 ? 0 : power(discr + b[i]));
        if (2 * el <= r + noEras - 1) {
          el = r + noEras - el;
          for (int i = 0; i <= nr; ++i)
            b[i] = lambda[i] == 0 ? 255 : mod(log[lambda[i]] - discr + 255);
        } else {
          for (int i = nr; i > 0; --i) b[i] = b[i - 1];
          b[0] = 255;
        }
        std::copy_n(t, nr + 1, lambda);
      }
    }
    int degree = 0;
    for (int i = 0; i <= nr; ++i) {
      lambda[i] = log[lambda[i]];
      if (lambda[i] != 255) degree = i;
    }
    int degOmega = 0;
    for (int i = 0; i < nr; ++i) {
      int tmp = 0;
      for (int j = std::min(degree, i); j >= 0; --j)
        if (s[i - j] != 255 && lambda[j] != 255)
          tmp ^= power(s[i - j] + lambda[j]);
      if (tmp != 0) degOmega = i;
      omega[i] = log[tmp];
    }
    omega[nr] = 255;
    for (int i = 1; i <= nr; ++i) reg[i] = lambda[i];
    int count = 0, k = ip - 1;
    for (int i = 1; i <= 255; ++i, k = mod(k + ip)) {
      int q = 1;
      for (int j = degree; j > 0; --j) {
        if (reg[j] != 255) {
          reg[j] = mod(reg[j] + j);
          q ^= exp[reg[j]];
        }
      }
      if (q != 0) continue;
      root[count] = i;
      loc[count] = k;
      if (++count == degree) break;
    }
    if (degree != count) return -1;
    for (int j = count - 1; j >= 0; --j) {
      int num1 = 0;
      for (int i = degOmega; i >= 0; --i)
        if (omega[i] != 255) num1 ^= power(omega[i] + i * root[j]);
      int num2 = power(root[j] * (fcr - 1) + 255), den = 0;
      for (int i = std::min(degree, nr - 1) & ~1; i >= 0; i -= 2)
        if (lambda[i + 1] != 255)
          den ^= power(lambda[i + 1] + i * root[j]);
      if (den == 0) return -1;
      if (num1 != 0 && loc[j] < 255)
        data[loc[j]] ^= uint8_t(power(log[num1] + log[num2] + 255 - log[den]));
    }
    return count;
  }
};
}

void* ht_rs_create(int32_t mode, int32_t roots, int32_t fcr,
    int32_t prim, int32_t inverse_prim, const uint8_t* exp,
    const uint8_t* log, const uint8_t* generator) {
  if ((mode != 0 && mode != 1) || roots < 1 || roots > 254 ||
      fcr < 0 || fcr > 254 || prim < 1 || prim > 254 ||
      inverse_prim < 1 || inverse_prim > 254 ||
      !exp || !log || !generator) return nullptr;
  auto* p = new (std::nothrow) Plan{};
  if (!p) return nullptr;
  p->mode = mode; p->nr = roots; p->fcr = fcr;
  p->prim = prim; p->ip = inverse_prim;
  std::memcpy(p->exp, exp, 256);
  std::memcpy(p->log, log, 256);
  std::memcpy(p->gen, generator, roots + 1);
  if (mode == 0) {
    p->products.reset(new (std::nothrow) uint8_t[65536]);
    if (!p->products) { delete p; return nullptr; }
    for (int a = 0; a < 256; ++a)
      for (int b = 0; b < 256; ++b)
        p->products[(a << 8) | b] = uint8_t(
            a == 0 || b == 0 ? 0 : p->power(log[a] + log[b]));
    for (int i = 0; i < roots; ++i)
      p->syndromeRows[i] = p->products.get() +
          (p->power(prim * (fcr + i)) << 8);
  }
  return p;
}
void ht_rs_destroy(void* plan) { delete static_cast<Plan*>(plan); }
uint8_t* ht_rs_buffer(void* plan) {
  return plan ? static_cast<Plan*>(plan)->data : nullptr;
}
int32_t ht_rs_process(void* plan, int32_t encode, int32_t erasures) {
  auto* p = static_cast<Plan*>(plan);
  if (!p || (encode != 0 && encode != 1) || erasures < 0 ||
      erasures > p->nr || (p->mode == 0 && erasures != 0)) return -2;
  for (int i = 0; i < erasures; ++i)
    if (p->data[255 + i] == 255) return -2;
  if (p->mode == 0) {
    if (encode) { p->encode(); return 0; }
    return p->sonde();
  }
  std::memset(p->scratch, 0, sizeof(p->scratch));
  if (encode) { p->encode(); return 0; }
  return p->fx25(erasures);
}
