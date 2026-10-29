// ============================================================
// cold_p256.h - just enough NIST P-256 for one encrypted session
// ============================================================
// The card's encrypted session runs on P-256 (cold_session.h). This
// device makes two keys for a single write, signs one with the other
// (ECDSA over SHA-256, the nonce from RFC 6979), and agrees on a secret
// with the card (ECDH). That is all that is here.
//
// The arithmetic is in Montgomery form, with one routine for both
// moduli: the field (p) and the group order (n). Self-contained like
// cold_sha2.h, so it is checked on a computer against reference
// vectors. It is not constant-time: each key is used once, by a device
// connected to nothing but the card, which leaves no second
// measurement to compare.
// ============================================================
#ifndef COLD_P256_H
#define COLD_P256_H

#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include "cold_util.h"
#include "cold_u256.h"
#include "cold_sha2.h"

// The curve as the standard writes it — and as SetECCurveParam takes it.
static const uint8_t COLD_P256_PRIME[32] = {
  0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF
};
static const uint8_t COLD_P256_A[32] = {        // p - 3
  0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFC
};
static const uint8_t COLD_P256_B[32] = {
  0x5A, 0xC6, 0x35, 0xD8, 0xAA, 0x3A, 0x93, 0xE7, 0xB3, 0xEB, 0xBD, 0x55, 0x76, 0x98, 0x86, 0xBC,
  0x65, 0x1D, 0x06, 0xB0, 0xCC, 0x53, 0xB0, 0xF6, 0x3B, 0xCE, 0x3C, 0x3E, 0x27, 0xD2, 0x60, 0x4B
};
static const uint8_t COLD_P256_G[65] = {
  0x04,
  0x6B, 0x17, 0xD1, 0xF2, 0xE1, 0x2C, 0x42, 0x47, 0xF8, 0xBC, 0xE6, 0xE5, 0x63, 0xA4, 0x40, 0xF2,
  0x77, 0x03, 0x7D, 0x81, 0x2D, 0xEB, 0x33, 0xA0, 0xF4, 0xA1, 0x39, 0x45, 0xD8, 0x98, 0xC2, 0x96,
  0x4F, 0xE3, 0x42, 0xE2, 0xFE, 0x1A, 0x7F, 0x9B, 0x8E, 0xE7, 0xEB, 0x4A, 0x7C, 0x0F, 0x9E, 0x16,
  0x2B, 0xCE, 0x33, 0x57, 0x6B, 0x31, 0x5E, 0xCE, 0xCB, 0xB6, 0x40, 0x68, 0x37, 0xBF, 0x51, 0xF5
};
static const uint8_t COLD_P256_N[32] = {
  0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
  0xBC, 0xE6, 0xFA, 0xAD, 0xA7, 0x17, 0x9E, 0x84, 0xF3, 0xB9, 0xCA, 0xC2, 0xFC, 0x63, 0x25, 0x51
};

#define COLD_P256_POINT_LEN  65    // 04 || X || Y
#define COLD_P256_SIG_MAX    72    // a DER-encoded ECDSA signature, at its longest

// ── Montgomery arithmetic modulo an odd m ────────────────────
// A number a is held as a·2^256 mod m. Products then reduce with
// shifts and one multiply per limb, whatever m is.
struct ColdMont {
  ColdU256 m;
  ColdU256 one;       // 2^256 mod m: 1 in Montgomery form
  ColdU256 rr;        // 2^512 mod m: multiplying by it enters Montgomery form
  uint32_t m0inv;     // -m^-1 mod 2^32
};

/// out = a·b·2^-256 mod m, for a, b < m. `out` may be an operand.
static inline void coldMontMul(ColdU256& out, const ColdU256& a, const ColdU256& b, const ColdMont& M) {
  uint32_t t[10] = { 0 };
  for (int i = 0; i < 8; i++) {
    // t += a · b[i]
    uint64_t carry = 0;
    for (int j = 0; j < 8; j++) {
      const uint64_t s = (uint64_t)t[j] + (uint64_t)a.v[j] * b.v[i] + carry;
      t[j] = (uint32_t)s;
      carry = s >> 32;
    }
    uint64_t s = (uint64_t)t[8] + carry;
    t[8] = (uint32_t)s;
    t[9] = (uint32_t)(s >> 32);

    // t = (t + q·m) / 2^32, q chosen so the low limb becomes zero
    const uint32_t q = t[0] * M.m0inv;
    s = (uint64_t)t[0] + (uint64_t)q * M.m.v[0];
    carry = s >> 32;
    for (int j = 1; j < 8; j++) {
      s = (uint64_t)t[j] + (uint64_t)q * M.m.v[j] + carry;
      t[j - 1] = (uint32_t)s;
      carry = s >> 32;
    }
    s = (uint64_t)t[8] + carry;
    t[7] = (uint32_t)s;
    t[8] = t[9] + (uint32_t)(s >> 32);
  }
  ColdU256 r;
  for (int j = 0; j < 8; j++) r.v[j] = t[j];
  coldReduceOnce(r, t[8], M.m);      // the result is below 2m
  out = r;
  coldWipe(t, sizeof(t));
}

static inline void coldMontSetup(ColdMont& M, const uint8_t modulus[32]) {
  coldU256FromBytes(M.m, modulus);
  // m^-1 mod 2^32 by Newton's iteration: each step doubles the correct bits.
  uint32_t inverse = 1;
  for (int i = 0; i < 5; i++) inverse *= 2 - M.m.v[0] * inverse;
  M.m0inv = 0 - inverse;
  // 2^256 and 2^512 modulo m, by doubling.
  ColdU256 r = COLD_ONE;
  for (int i = 1; i <= 512; i++) {
    coldAddMod(r, r, r, M.m);
    if (i == 256) M.one = r;
  }
  M.rr = r;
}

static inline void coldMontTo(ColdU256& out, const ColdU256& a, const ColdMont& M) { coldMontMul(out, a, M.rr, M); }
static inline void coldMontFrom(ColdU256& out, const ColdU256& a, const ColdMont& M) { coldMontMul(out, a, COLD_ONE, M); }

static inline void coldMontSub(ColdU256& out, const ColdU256& a, const ColdU256& b, const ColdMont& M) {
  if (coldU256Sub(out, a, b)) coldU256Add(out, out, M.m);
}

/// The inverse, a^(m-2) for a prime m (Fermat). In and out in Montgomery form.
static inline void coldMontInv(ColdU256& out, const ColdU256& a, const ColdMont& M) {
  static const ColdU256 two = {{ 2, 0, 0, 0, 0, 0, 0, 0 }};
  ColdU256 exponent;
  coldU256Sub(exponent, M.m, two);
  ColdU256 result = M.one, base = a;
  for (int bit = 0; bit < 256; bit++) {
    if (coldU256Bit(exponent, bit)) coldMontMul(result, result, base, M);
    coldMontMul(base, base, base, M);
  }
  out = result;
  coldWipe(&base, sizeof(base));
}

// ── The curve ────────────────────────────────────────────────
struct ColdP256 {
  ColdMont field;      // modulo p
  ColdMont order;      // modulo n
  ColdU256 b, gx, gy;  // Montgomery form, modulo p
};

static inline ColdP256 coldP256Make() {
  ColdP256 c;
  coldMontSetup(c.field, COLD_P256_PRIME);
  coldMontSetup(c.order, COLD_P256_N);
  ColdU256 plain;
  coldU256FromBytes(plain, COLD_P256_B);
  coldMontTo(c.b, plain, c.field);
  coldU256FromBytes(plain, COLD_P256_G + 1);
  coldMontTo(c.gx, plain, c.field);
  coldU256FromBytes(plain, COLD_P256_G + 33);
  coldMontTo(c.gy, plain, c.field);
  return c;
}

static inline const ColdP256& coldP256() {
  static const ColdP256 curve = coldP256Make();
  return curve;
}

/// A point in Jacobian coordinates (x/z², y/z³), in Montgomery form.
/// z == 0 is the point at infinity.
struct ColdP256Point {
  ColdU256 x, y, z;
};

/// out = 2p. The formulas for a = -3 (dbl-2001-b). `out` may be `p`.
static inline void coldP256Double(ColdP256Point& out, const ColdP256Point& p, const ColdP256& c) {
  const ColdMont& F = c.field;
  if (coldU256IsZero(p.z)) { out = p; return; }
  ColdU256 delta, gamma, beta, alpha, t, u;
  coldMontMul(delta, p.z, p.z, F);
  coldMontMul(gamma, p.y, p.y, F);
  coldMontMul(beta, p.x, gamma, F);
  // alpha = 3 (x - delta)(x + delta)
  coldMontSub(t, p.x, delta, F);
  coldAddMod(u, p.x, delta, F.m);
  coldMontMul(alpha, t, u, F);
  coldAddMod(t, alpha, alpha, F.m);
  coldAddMod(alpha, t, alpha, F.m);

  ColdP256Point r;
  // z3 = (y + z)^2 - gamma - delta
  coldAddMod(t, p.y, p.z, F.m);
  coldMontMul(r.z, t, t, F);
  coldMontSub(r.z, r.z, gamma, F);
  coldMontSub(r.z, r.z, delta, F);
  // x3 = alpha^2 - 8 beta
  ColdU256 beta4, beta8;
  coldAddMod(beta4, beta, beta, F.m);
  coldAddMod(beta4, beta4, beta4, F.m);
  coldAddMod(beta8, beta4, beta4, F.m);
  coldMontMul(r.x, alpha, alpha, F);
  coldMontSub(r.x, r.x, beta8, F);
  // y3 = alpha (4 beta - x3) - 8 gamma^2
  coldMontSub(t, beta4, r.x, F);
  coldMontMul(r.y, alpha, t, F);
  coldMontMul(u, gamma, gamma, F);
  coldAddMod(u, u, u, F.m);
  coldAddMod(u, u, u, F.m);
  coldAddMod(u, u, u, F.m);
  coldMontSub(r.y, r.y, u, F);
  out = r;
}

/// out = p + q, for q in affine coordinates (madd-2007-bl). `out` may be `p`.
static inline void coldP256AddAffine(ColdP256Point& out, const ColdP256Point& p,
                                     const ColdU256& qx, const ColdU256& qy, const ColdP256& c) {
  const ColdMont& F = c.field;
  if (coldU256IsZero(p.z)) {
    out.x = qx;
    out.y = qy;
    out.z = F.one;
    return;
  }
  ColdU256 z1z1, u2, s2, h, r, t;
  coldMontMul(z1z1, p.z, p.z, F);
  coldMontMul(u2, qx, z1z1, F);
  coldMontMul(t, p.z, z1z1, F);
  coldMontMul(s2, qy, t, F);
  coldMontSub(h, u2, p.x, F);
  coldMontSub(r, s2, p.y, F);
  if (coldU256IsZero(h)) {
    if (coldU256IsZero(r)) coldP256Double(out, p, c);    // p == q
    else memset(&out, 0, sizeof(out));                   // p == -q
    return;
  }
  ColdU256 hh, i, j, v;
  coldAddMod(r, r, r, F.m);
  coldMontMul(hh, h, h, F);
  coldAddMod(i, hh, hh, F.m);
  coldAddMod(i, i, i, F.m);
  coldMontMul(j, h, i, F);
  coldMontMul(v, p.x, i, F);

  ColdP256Point sum;
  // x3 = r^2 - j - 2v
  coldMontMul(sum.x, r, r, F);
  coldMontSub(sum.x, sum.x, j, F);
  coldMontSub(sum.x, sum.x, v, F);
  coldMontSub(sum.x, sum.x, v, F);
  // y3 = r (v - x3) - 2 y1 j
  coldMontSub(t, v, sum.x, F);
  coldMontMul(sum.y, r, t, F);
  coldMontMul(t, p.y, j, F);
  coldAddMod(t, t, t, F.m);
  coldMontSub(sum.y, sum.y, t, F);
  // z3 = (z1 + h)^2 - z1z1 - hh
  coldAddMod(t, p.z, h, F.m);
  coldMontMul(sum.z, t, t, F);
  coldMontSub(sum.z, sum.z, z1z1, F);
  coldMontSub(sum.z, sum.z, hh, F);
  out = sum;
}

/// out = k·q for an affine q, double-and-add from the top bit.
static inline void coldP256Multiply(ColdP256Point& out, const ColdU256& k,
                                    const ColdU256& qx, const ColdU256& qy, const ColdP256& c) {
  ColdP256Point r;
  memset(&r, 0, sizeof(r));
  for (int bit = 255; bit >= 0; bit--) {
    coldP256Double(r, r, c);
    if (coldU256Bit(k, bit)) coldP256AddAffine(r, r, qx, qy, c);
  }
  out = r;
  coldWipe(&r, sizeof(r));
}

/// The affine x and y, out of Montgomery form. False for the point at infinity.
static inline bool coldP256Affine(ColdU256& x, ColdU256& y, const ColdP256Point& p, const ColdP256& c) {
  const ColdMont& F = c.field;
  if (coldU256IsZero(p.z)) return false;
  ColdU256 zInv, zPower, t;
  coldMontInv(zInv, p.z, F);
  coldMontMul(zPower, zInv, zInv, F);
  coldMontMul(t, p.x, zPower, F);
  coldMontFrom(x, t, F);
  coldMontMul(zPower, zPower, zInv, F);
  coldMontMul(t, p.y, zPower, F);
  coldMontFrom(y, t, F);
  return true;
}

/// An uncompressed point, into Montgomery form. False unless it is a
/// point on P-256 — what is done with someone else's key starts here.
static inline bool coldP256LoadPoint(ColdU256& x, ColdU256& y, const uint8_t point[COLD_P256_POINT_LEN],
                                     const ColdP256& c) {
  const ColdMont& F = c.field;
  if (point[0] != 0x04) return false;
  ColdU256 px, py;
  coldU256FromBytes(px, point + 1);
  coldU256FromBytes(py, point + 33);
  if (coldU256Cmp(px, F.m) >= 0 || coldU256Cmp(py, F.m) >= 0) return false;
  coldMontTo(x, px, F);
  coldMontTo(y, py, F);
  // y^2 = x^3 - 3x + b
  ColdU256 left, right, t;
  coldMontMul(left, y, y, F);
  coldMontMul(t, x, x, F);
  coldMontMul(right, t, x, F);
  coldAddMod(t, x, x, F.m);
  coldAddMod(t, t, x, F.m);
  coldMontSub(right, right, t, F);
  coldAddMod(right, right, c.b, F.m);
  return coldU256Cmp(left, right) == 0;
}

// ── Keys, ECDH and ECDSA ─────────────────────────────────────
/// A valid private key: 0 < k < n.
static inline bool coldP256ScalarValid(const ColdU256& k) {
  return !coldU256IsZero(k) && coldU256Cmp(k, coldP256().order.m) < 0;
}

/// k·G as 04 || X || Y. False if k is not a valid private key.
static inline bool coldP256PublicKey(const uint8_t privateKey[32], uint8_t out[COLD_P256_POINT_LEN]) {
  const ColdP256& c = coldP256();
  ColdU256 k, x, y;
  coldU256FromBytes(k, privateKey);
  bool ok = coldP256ScalarValid(k);
  ColdP256Point p;
  if (ok) {
    coldP256Multiply(p, k, c.gx, c.gy, c);
    ok = coldP256Affine(x, y, p, c);
  }
  if (ok) {
    out[0] = 0x04;
    coldU256ToBytes(x, out + 1);
    coldU256ToBytes(y, out + 33);
  }
  coldWipe(&k, sizeof(k));
  coldWipe(&p, sizeof(p));
  return ok;
}

/// ECDH: the x coordinate of k·Q, the secret both sides arrive at.
/// False if k is not a valid private key or Q is not on the curve.
static inline bool coldP256Ecdh(const uint8_t privateKey[32], const uint8_t peer[COLD_P256_POINT_LEN],
                                uint8_t secret[32]) {
  const ColdP256& c = coldP256();
  ColdU256 k, qx, qy, x, y;
  coldU256FromBytes(k, privateKey);
  bool ok = coldP256ScalarValid(k) && coldP256LoadPoint(qx, qy, peer, c);
  ColdP256Point p;
  if (ok) {
    coldP256Multiply(p, k, qx, qy, c);
    ok = coldP256Affine(x, y, p, c);
  }
  if (ok) coldU256ToBytes(x, secret);
  coldWipe(&k, sizeof(k));
  coldWipe(&p, sizeof(p));
  coldWipe(&x, sizeof(x));
  return ok;
}

/// One DER INTEGER: no leading zero bytes, and one 0x00 in front when
/// the top bit is set, so it does not read as negative.
static inline uint8_t coldDerInteger(uint8_t* out, const uint8_t value[32]) {
  int start = 0;
  while (start < 31 && value[start] == 0) start++;
  const uint8_t pad = (value[start] & 0x80) ? 1 : 0;
  const uint8_t length = (uint8_t)(32 - start + pad);
  out[0] = 0x02;
  out[1] = length;
  if (pad) out[2] = 0x00;
  memcpy(out + 2 + pad, value + start, 32 - start);
  return (uint8_t)(2 + length);
}

/// RFC 6979 §3.2 step d to f, and step h's first update: K and V from
/// the key and the hash, with the 0x00 then the 0x01 marker.
static inline void coldRfc6979Start(uint8_t k[32], uint8_t v[32], const uint8_t key[32], const uint8_t h1[32]) {
  memset(v, 0x01, 32);
  memset(k, 0x00, 32);
  for (uint8_t marker = 0; marker < 2; marker++) {
    ColdHmac256 h;
    coldHmac256Begin(h, k, 32);
    coldHmac256Update(h, v, 32);
    coldHmac256Update(h, &marker, 1);
    coldHmac256Update(h, key, 32);
    coldHmac256Update(h, h1, 32);
    coldHmac256End(h, k);
    coldHmac256Begin(h, k, 32);
    coldHmac256Update(h, v, 32);
    coldHmac256End(h, v);
  }
}

/// An ECDSA signature over SHA-256(message), DER-encoded the way the
/// card reads it. The nonce follows RFC 6979: it comes from the key and
/// the message, so no weak or repeated random number can ever give the
/// key away. Returns the signature's length, or 0 for an invalid key.
static inline uint8_t coldP256Sign(const uint8_t privateKey[32], const uint8_t* message, size_t len,
                                   uint8_t out[COLD_P256_SIG_MAX]) {
  const ColdP256& c = coldP256();
  const ColdMont& N = c.order;
  ColdU256 d, e;
  coldU256FromBytes(d, privateKey);
  if (!coldP256ScalarValid(d)) return 0;

  uint8_t h1[32];
  coldSha256(message, len, h1);
  coldU256FromBytes(e, h1);
  coldReduceOnce(e, 0, N.m);         // the hash is below 2^256 < 2n
  coldU256ToBytes(e, h1);

  uint8_t kBytes[32], vBytes[32];
  coldRfc6979Start(kBytes, vBytes, privateKey, h1);

  ColdU256 dm, em, k, km, rm, sm, t, x, y;
  coldMontTo(dm, d, N);
  coldMontTo(em, e, N);
  uint8_t signatureLength = 0;
  for (int attempt = 0; attempt < 64 && !signatureLength; attempt++) {
    ColdHmac256 h;
    coldHmac256Begin(h, kBytes, 32);
    coldHmac256Update(h, vBytes, 32);
    coldHmac256End(h, vBytes);
    coldU256FromBytes(k, vBytes);

    if (coldP256ScalarValid(k)) {
      // r = (k·G).x mod n
      ColdP256Point point;
      coldP256Multiply(point, k, c.gx, c.gy, c);
      ColdU256 r;
      if (coldP256Affine(x, y, point, c)) {
        r = x;
        coldReduceOnce(r, 0, N.m);    // x is below p < 2n
      } else {
        memset(&r, 0, sizeof(r));
      }
      // s = k^-1 (e + r·d) mod n
      coldMontTo(rm, r, N);
      coldMontMul(t, rm, dm, N);
      coldAddMod(t, t, em, N.m);
      coldMontTo(km, k, N);
      coldMontInv(km, km, N);
      coldMontMul(sm, km, t, N);
      ColdU256 s;
      coldMontFrom(s, sm, N);

      if (!coldU256IsZero(r) && !coldU256IsZero(s)) {
        uint8_t rBytes[32], sBytes[32];
        coldU256ToBytes(r, rBytes);
        coldU256ToBytes(s, sBytes);
        uint8_t length = coldDerInteger(out + 2, rBytes);
        length = (uint8_t)(length + coldDerInteger(out + 2 + length, sBytes));
        out[0] = 0x30;
        out[1] = length;
        signatureLength = (uint8_t)(2 + length);
      }
      coldWipe(&point, sizeof(point));
    }
    if (!signatureLength) {
      // RFC 6979 step h.3: K = HMAC_K(V || 0x00), V = HMAC_K(V)
      const uint8_t zero = 0x00;
      coldHmac256Begin(h, kBytes, 32);
      coldHmac256Update(h, vBytes, 32);
      coldHmac256Update(h, &zero, 1);
      coldHmac256End(h, kBytes);
      coldHmac256Begin(h, kBytes, 32);
      coldHmac256Update(h, vBytes, 32);
      coldHmac256End(h, vBytes);
    }
  }
  coldWipe(&d, sizeof(d));
  coldWipe(&dm, sizeof(dm));
  coldWipe(&k, sizeof(k));
  coldWipe(&km, sizeof(km));
  coldWipe(kBytes, sizeof(kBytes));
  coldWipe(vBytes, sizeof(vBytes));
  return signatureLength;
}

#endif // COLD_P256_H
