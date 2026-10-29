// ECDSA verification on P-256, for the tests alone: the pretend card
// checks the device's signatures with it the way a real card would, and
// test_session.cpp holds it to signatures made by Node. Built from
// cold_p256.h's arithmetic — the firmware itself never verifies.
#pragma once

#include <vector>
#include "cold_p256.h"

/// r and s out of a DER signature, each as 32 bytes.
static inline bool derSignatureParts(const std::vector<uint8_t>& der, uint8_t r[32], uint8_t s[32]) {
  if (der.size() < 8 || der[0] != 0x30 || der[1] != der.size() - 2) return false;
  size_t at = 2;
  for (uint8_t* out : { r, s }) {
    if (at + 2 > der.size() || der[at] != 0x02) return false;
    size_t length = der[at + 1];
    at += 2;
    if (length == 0 || at + length > der.size()) return false;
    const uint8_t* value = der.data() + at;
    at += length;
    if (length == 33 && value[0] == 0x00) { value++; length--; }
    if (length > 32) return false;
    memset(out, 0, 32);
    memcpy(out + 32 - length, value, length);
  }
  return at == der.size();
}

/// Whether `der` is a valid ECDSA signature over SHA-256(message) by `publicKey`.
static inline bool p256Verify(const uint8_t publicKey[COLD_P256_POINT_LEN], const uint8_t* message, size_t len,
                              const std::vector<uint8_t>& der) {
  const ColdP256& c = coldP256();
  const ColdMont& n = c.order;
  uint8_t rBytes[32], sBytes[32], digest[32];
  if (!derSignatureParts(der, rBytes, sBytes)) return false;
  ColdU256 r, s, e, qx, qy;
  coldU256FromBytes(r, rBytes);
  coldU256FromBytes(s, sBytes);
  if (!coldP256ScalarValid(r) || !coldP256ScalarValid(s)) return false;
  if (!coldP256LoadPoint(qx, qy, publicKey, c)) return false;
  coldSha256(message, len, digest);
  coldU256FromBytes(e, digest);
  coldReduceOnce(e, 0, n.m);

  // u1 = e/s, u2 = r/s; the signature holds if (u1·G + u2·Q).x = r (mod n)
  ColdU256 w, t, u1, u2;
  coldMontTo(t, s, n);
  coldMontInv(w, t, n);
  coldMontTo(t, e, n);
  coldMontMul(t, t, w, n);
  coldMontFrom(u1, t, n);
  coldMontTo(t, r, n);
  coldMontMul(t, t, w, n);
  coldMontFrom(u2, t, n);

  ColdP256Point a, b, sum;
  ColdU256 ax, ay, x, y;
  coldP256Multiply(a, u1, c.gx, c.gy, c);
  coldP256Multiply(b, u2, qx, qy, c);
  if (!coldP256Affine(ax, ay, a, c)) return false;
  coldMontTo(ax, ax, c.field);
  coldMontTo(ay, ay, c.field);
  coldP256AddAffine(sum, b, ax, ay, c);
  if (!coldP256Affine(x, y, sum, c)) return false;
  coldReduceOnce(x, 0, n.m);
  return coldU256Cmp(x, r) == 0;
}
