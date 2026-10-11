// ============================================================
// cold_secp256k1.h - just enough secp256k1 for key derivation
// ============================================================
// Field arithmetic mod p, scalar addition mod n, and k*G — what BIP-32
// needs to walk a derivation path and what turns the final private key
// into the public key the card stores. No signing happens here: the
// card signs.
//
// Self-contained like cold_sha2.h, so it is checked on a computer
// against reference vectors. It is not constant-time; it runs once,
// on a device that is not connected to anything.
// ============================================================
#ifndef COLD_SECP256K1_H
#define COLD_SECP256K1_H

#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include "cold_util.h"

/// A 256-bit number, least significant 32-bit limb first.
struct ColdU256 {
  uint32_t v[8];
};

static const ColdU256 COLD_ONE = {{ 1, 0, 0, 0, 0, 0, 0, 0 }};

// p = 2^256 - 2^32 - 977
static const ColdU256 COLD_P = {{ 0xFFFFFC2FUL, 0xFFFFFFFEUL, 0xFFFFFFFFUL, 0xFFFFFFFFUL,
                                  0xFFFFFFFFUL, 0xFFFFFFFFUL, 0xFFFFFFFFUL, 0xFFFFFFFFUL }};
// n, the group order
static const ColdU256 COLD_N = {{ 0xD0364141UL, 0xBFD25E8CUL, 0xAF48A03BUL, 0xBAAEDCE6UL,
                                  0xFFFFFFFEUL, 0xFFFFFFFFUL, 0xFFFFFFFFUL, 0xFFFFFFFFUL }};
static const ColdU256 COLD_GX = {{ 0x16F81798UL, 0x59F2815BUL, 0x2DCE28D9UL, 0x029BFCDBUL,
                                   0xCE870B07UL, 0x55A06295UL, 0xF9DCBBACUL, 0x79BE667EUL }};
static const ColdU256 COLD_GY = {{ 0xFB10D4B8UL, 0x9C47D08FUL, 0xA6855419UL, 0xFD17B448UL,
                                   0x0E1108A8UL, 0x5DA4FBFCUL, 0x26A3C465UL, 0x483ADA77UL }};

// ── 256-bit helpers ──────────────────────────────────────────
/// From 32 big-endian bytes, as keys and coordinates are written.
static inline void coldU256FromBytes(ColdU256& out, const uint8_t in[32]) {
  for (int i = 0; i < 8; i++) out.v[i] = coldLoadBe32(in + (7 - i) * 4);
}

static inline void coldU256ToBytes(const ColdU256& in, uint8_t out[32]) {
  for (int i = 0; i < 8; i++) coldStoreBe32(out + (7 - i) * 4, in.v[i]);
}

static inline bool coldU256Bit(const ColdU256& a, int bit) {
  return (a.v[bit >> 5] >> (bit & 31)) & 1;
}

static inline bool coldU256IsZero(const ColdU256& a) {
  uint32_t acc = 0;
  for (int i = 0; i < 8; i++) acc |= a.v[i];
  return acc == 0;
}

/// -1, 0 or 1.
static inline int coldU256Cmp(const ColdU256& a, const ColdU256& b) {
  for (int i = 7; i >= 0; i--) {
    if (a.v[i] < b.v[i]) return -1;
    if (a.v[i] > b.v[i]) return 1;
  }
  return 0;
}

/// out = a + b, returns the carry out of bit 255. `out` may be an operand.
static inline uint32_t coldU256Add(ColdU256& out, const ColdU256& a, const ColdU256& b) {
  uint64_t carry = 0;
  for (int i = 0; i < 8; i++) {
    carry += (uint64_t)a.v[i] + b.v[i];
    out.v[i] = (uint32_t)carry;
    carry >>= 32;
  }
  return (uint32_t)carry;
}

/// out = a - b, returns 1 if it borrowed (a < b). `out` may be an operand.
static inline uint32_t coldU256Sub(ColdU256& out, const ColdU256& a, const ColdU256& b) {
  uint64_t borrow = 0;
  for (int i = 0; i < 8; i++) {
    const uint64_t d = (uint64_t)a.v[i] - b.v[i] - borrow;
    out.v[i] = (uint32_t)d;
    borrow = (d >> 32) & 1;
  }
  return (uint32_t)borrow;
}

// ── Arithmetic modulo p (the field) and n (the scalars) ──────
/// Brings a value below 2m back under m: subtracts m once if a + carry·2^256
/// is not already below it.
static inline void coldReduceOnce(ColdU256& a, uint32_t carry, const ColdU256& m) {
  if (carry || coldU256Cmp(a, m) >= 0) coldU256Sub(a, a, m);
}

/// out = (a + b) mod m, for a, b < m.
static inline void coldAddMod(ColdU256& out, const ColdU256& a, const ColdU256& b, const ColdU256& m) {
  const uint32_t carry = coldU256Add(out, a, b);
  coldReduceOnce(out, carry, m);
}

/// A valid private key or tweak: 0 < a < n.
static inline bool coldScalarValid(const ColdU256& a) {
  return !coldU256IsZero(a) && coldU256Cmp(a, COLD_N) < 0;
}

static inline void coldScalarAdd(ColdU256& out, const ColdU256& a, const ColdU256& b) {
  coldAddMod(out, a, b, COLD_N);
}

static inline void coldFieldAdd(ColdU256& out, const ColdU256& a, const ColdU256& b) {
  coldAddMod(out, a, b, COLD_P);
}

static inline void coldFieldSub(ColdU256& out, const ColdU256& a, const ColdU256& b) {
  if (coldU256Sub(out, a, b)) coldU256Add(out, out, COLD_P);
}

/// out = a * b mod p.
///
/// 2^256 ≡ 2^32 + 977 (mod p), so the high half of the 512-bit product
/// folds back into the low half by multiplying it with that constant.
static inline void coldFieldMul(ColdU256& out, const ColdU256& a, const ColdU256& b) {
  uint32_t t[16];
  memset(t, 0, sizeof(t));
  for (int i = 0; i < 8; i++) {
    uint64_t carry = 0;
    for (int j = 0; j < 8; j++) {
      carry += (uint64_t)a.v[i] * b.v[j] + t[i + j];
      t[i + j] = (uint32_t)carry;
      carry >>= 32;
    }
    t[i + 8] = (uint32_t)carry;
  }

  // First fold: low + high * (2^32 + 977) — up to 2^290, so 10 limbs.
  uint32_t r[10];
  uint64_t carry = 0;
  for (int i = 0; i < 10; i++) {
    uint64_t acc = carry;
    if (i < 8) acc += t[i];
    if (i < 8) acc += (uint64_t)t[i + 8] * 977U;
    carry = acc >> 32;
    acc &= 0xFFFFFFFFULL;
    if (i >= 1 && i <= 8) acc += t[i + 7];          // the 2^32 term, one limb up
    carry += acc >> 32;
    r[i] = (uint32_t)acc;
  }

  // Second fold: what is left above 2^256 is under 2^34.
  const uint64_t high = ((uint64_t)r[9] << 32) | r[8];
  ColdU256 res;
  uint64_t acc = (uint64_t)r[0] + (high & 0xFFFFFFFFULL) * 977U;
  res.v[0] = (uint32_t)acc;
  acc = (acc >> 32) + r[1] + (high >> 32) * 977U + (high & 0xFFFFFFFFULL);
  res.v[1] = (uint32_t)acc;
  acc = (acc >> 32) + r[2] + (high >> 32);
  res.v[2] = (uint32_t)acc;
  for (int i = 3; i < 8; i++) {
    acc = (acc >> 32) + r[i];
    res.v[i] = (uint32_t)acc;
  }

  // A last carry is one more 2^256, i.e. one more 2^32 + 977.
  if (acc >> 32) {
    uint64_t c = (uint64_t)res.v[0] + 977U;
    res.v[0] = (uint32_t)c;
    c = (c >> 32) + res.v[1] + 1U;
    res.v[1] = (uint32_t)c;
    for (int i = 2; i < 8 && (c >> 32); i++) {
      c = (c >> 32) + res.v[i];
      res.v[i] = (uint32_t)c;
    }
  }
  coldReduceOnce(res, 0, COLD_P);
  out = res;
}

static inline void coldFieldSqr(ColdU256& out, const ColdU256& a) { coldFieldMul(out, a, a); }

/// out = a^(p-2) mod p, the inverse of a (Fermat).
static inline void coldFieldInv(ColdU256& out, const ColdU256& a) {
  static const ColdU256 two = {{ 2, 0, 0, 0, 0, 0, 0, 0 }};
  ColdU256 exponent;
  coldU256Sub(exponent, COLD_P, two);

  ColdU256 result = COLD_ONE;
  ColdU256 base = a;
  for (int bit = 0; bit < 256; bit++) {
    if (coldU256Bit(exponent, bit)) coldFieldMul(result, result, base);
    coldFieldSqr(base, base);
  }
  out = result;
}

// ── Points (Jacobian coordinates, a = 0) ─────────────────────
struct ColdPoint {
  ColdU256 x, y, z;   // z == 0 is the point at infinity
};

static inline bool coldPointIsInfinity(const ColdPoint& p) { return coldU256IsZero(p.z); }
static inline void coldPointSetInfinity(ColdPoint& p) { memset(&p, 0, sizeof(p)); }

static inline void coldPointDouble(ColdPoint& out, const ColdPoint& p) {
  if (coldPointIsInfinity(p) || coldU256IsZero(p.y)) {
    coldPointSetInfinity(out);
    return;
  }
  ColdU256 a, b, c, d, e, f, t;
  coldFieldSqr(a, p.x);                       // A = X1^2
  coldFieldSqr(b, p.y);                       // B = Y1^2
  coldFieldSqr(c, b);                         // C = B^2
  coldFieldAdd(t, p.x, b);
  coldFieldSqr(t, t);
  coldFieldSub(t, t, a);
  coldFieldSub(t, t, c);
  coldFieldAdd(d, t, t);                      // D = 2((X1+B)^2 - A - C)
  coldFieldAdd(e, a, a);
  coldFieldAdd(e, e, a);                      // E = 3A
  coldFieldSqr(f, e);                         // F = E^2

  ColdPoint r;
  coldFieldSub(r.x, f, d);
  coldFieldSub(r.x, r.x, d);                  // X3 = F - 2D
  coldFieldSub(t, d, r.x);
  coldFieldMul(t, e, t);
  ColdU256 c8;
  coldFieldAdd(c8, c, c);
  coldFieldAdd(c8, c8, c8);
  coldFieldAdd(c8, c8, c8);
  coldFieldSub(r.y, t, c8);                   // Y3 = E(D - X3) - 8C
  coldFieldMul(t, p.y, p.z);
  coldFieldAdd(r.z, t, t);                    // Z3 = 2 Y1 Z1
  out = r;
}

static inline void coldPointAdd(ColdPoint& out, const ColdPoint& p, const ColdPoint& q) {
  if (coldPointIsInfinity(p)) { out = q; return; }
  if (coldPointIsInfinity(q)) { out = p; return; }

  ColdU256 z1z1, z2z2, u1, u2, s1, s2, t;
  coldFieldSqr(z1z1, p.z);
  coldFieldSqr(z2z2, q.z);
  coldFieldMul(u1, p.x, z2z2);
  coldFieldMul(u2, q.x, z1z1);
  coldFieldMul(t, p.y, q.z);
  coldFieldMul(s1, t, z2z2);
  coldFieldMul(t, q.y, p.z);
  coldFieldMul(s2, t, z1z1);

  if (coldU256Cmp(u1, u2) == 0) {
    if (coldU256Cmp(s1, s2) == 0) coldPointDouble(out, p);
    else                          coldPointSetInfinity(out);    // P + (-P)
    return;
  }

  ColdU256 h, i, j, rr, v;
  coldFieldSub(h, u2, u1);
  coldFieldAdd(t, h, h);
  coldFieldSqr(i, t);                         // I = (2H)^2
  coldFieldMul(j, h, i);                      // J = H I
  coldFieldSub(t, s2, s1);
  coldFieldAdd(rr, t, t);                     // r = 2(S2 - S1)
  coldFieldMul(v, u1, i);                     // V = U1 I

  ColdPoint r;
  coldFieldSqr(r.x, rr);
  coldFieldSub(r.x, r.x, j);
  coldFieldSub(r.x, r.x, v);
  coldFieldSub(r.x, r.x, v);                  // X3 = r^2 - J - 2V
  coldFieldSub(t, v, r.x);
  coldFieldMul(t, rr, t);
  ColdU256 s1j;
  coldFieldMul(s1j, s1, j);
  coldFieldAdd(s1j, s1j, s1j);
  coldFieldSub(r.y, t, s1j);                  // Y3 = r(V - X3) - 2 S1 J
  coldFieldAdd(t, p.z, q.z);
  coldFieldSqr(t, t);
  coldFieldSub(t, t, z1z1);
  coldFieldSub(t, t, z2z2);
  coldFieldMul(r.z, t, h);                    // Z3 = ((Z1+Z2)^2 - Z1Z1 - Z2Z2) H
  out = r;
}

/// The public key for a private key: k*G as 65 bytes, 0x04 || X || Y.
/// Returns false if k is not a valid private key.
static inline bool coldPublicKey(const uint8_t privateKey[32], uint8_t out[65]) {
  ColdU256 k;
  coldU256FromBytes(k, privateKey);
  const bool valid = coldScalarValid(k);

  // Double-and-add from the top bit down.
  const ColdPoint g = { COLD_GX, COLD_GY, COLD_ONE };
  ColdPoint result;
  coldPointSetInfinity(result);
  for (int bit = 255; valid && bit >= 0; bit--) {
    coldPointDouble(result, result);
    if (coldU256Bit(k, bit)) coldPointAdd(result, result, g);
  }
  coldWipe(&k, sizeof(k));
  if (coldPointIsInfinity(result)) return false;     // also the answer for an invalid key

  // Back to affine: x = X / Z^2, y = Y / Z^3.
  ColdU256 zInv, zInv2, zInv3, x, y;
  coldFieldInv(zInv, result.z);
  coldFieldSqr(zInv2, zInv);
  coldFieldMul(zInv3, zInv2, zInv);
  coldFieldMul(x, result.x, zInv2);
  coldFieldMul(y, result.y, zInv3);

  out[0] = 0x04;
  coldU256ToBytes(x, out + 1);
  coldU256ToBytes(y, out + 33);
  coldWipe(&result, sizeof(result));
  return true;
}

/// The 33-byte compressed form BIP-32 hashes: 0x02/0x03 || X.
static inline void coldCompressPublicKey(const uint8_t uncompressed[65], uint8_t out[33]) {
  out[0] = (uncompressed[64] & 1) ? 0x03 : 0x02;
  memcpy(out + 1, uncompressed + 1, 32);
}

#endif // COLD_SECP256K1_H
