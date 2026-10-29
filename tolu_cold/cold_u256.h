// ============================================================
// cold_u256.h - 256-bit numbers, for both curves
// ============================================================
// The plain integer arithmetic under secp256k1 (the wallet key) and
// NIST P-256 (the card's encrypted session): conversion from and to
// big-endian bytes, comparison, addition and subtraction with carry,
// and one-step reduction modulo a 256-bit number.
// ============================================================
#ifndef COLD_U256_H
#define COLD_U256_H

#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include "cold_util.h"

/// A 256-bit number, least significant 32-bit limb first.
struct ColdU256 {
  uint32_t v[8];
};

static const ColdU256 COLD_ONE = {{ 1, 0, 0, 0, 0, 0, 0, 0 }};

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

// ── Modular reduction ────────────────────────────────────────
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

#endif // COLD_U256_H
