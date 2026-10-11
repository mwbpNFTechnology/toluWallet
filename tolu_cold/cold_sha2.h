// ============================================================
// cold_sha2.h - SHA-256, SHA-512, HMAC-SHA512, PBKDF2-HMAC-SHA512
// ============================================================
// Self-contained on purpose: this file has no Arduino or mbedTLS
// dependency, so exactly the same code that runs on the device is
// compiled and checked on a computer against reference vectors
// (test/test_crypto.cpp).
// ============================================================
#ifndef COLD_SHA2_H
#define COLD_SHA2_H

#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include "cold_util.h"

// ── SHA-2 ────────────────────────────────────────────────────
// SHA-256 and SHA-512 are one algorithm at two word sizes. What differs
// — the word, the number of rounds, the constants and the rotation
// amounts (FIPS 180-4) — is written down once per variant; everything
// else is shared.

struct ColdSha256Variant {
  typedef uint32_t Word;
  static constexpr int rounds = 64;
  static constexpr uint8_t bigSigma0[3]   = { 2, 13, 22 };    // rotr, rotr, rotr
  static constexpr uint8_t bigSigma1[3]   = { 6, 11, 25 };
  static constexpr uint8_t smallSigma0[3] = { 7, 18, 3 };     // rotr, rotr, shift
  static constexpr uint8_t smallSigma1[3] = { 17, 19, 10 };
  static constexpr Word initial[8] = {
    0x6a09e667UL, 0xbb67ae85UL, 0x3c6ef372UL, 0xa54ff53aUL,
    0x510e527fUL, 0x9b05688cUL, 0x1f83d9abUL, 0x5be0cd19UL
  };
  static constexpr Word k[64] = {
    0x428a2f98UL, 0x71374491UL, 0xb5c0fbcfUL, 0xe9b5dba5UL,
    0x3956c25bUL, 0x59f111f1UL, 0x923f82a4UL, 0xab1c5ed5UL,
    0xd807aa98UL, 0x12835b01UL, 0x243185beUL, 0x550c7dc3UL,
    0x72be5d74UL, 0x80deb1feUL, 0x9bdc06a7UL, 0xc19bf174UL,
    0xe49b69c1UL, 0xefbe4786UL, 0x0fc19dc6UL, 0x240ca1ccUL,
    0x2de92c6fUL, 0x4a7484aaUL, 0x5cb0a9dcUL, 0x76f988daUL,
    0x983e5152UL, 0xa831c66dUL, 0xb00327c8UL, 0xbf597fc7UL,
    0xc6e00bf3UL, 0xd5a79147UL, 0x06ca6351UL, 0x14292967UL,
    0x27b70a85UL, 0x2e1b2138UL, 0x4d2c6dfcUL, 0x53380d13UL,
    0x650a7354UL, 0x766a0abbUL, 0x81c2c92eUL, 0x92722c85UL,
    0xa2bfe8a1UL, 0xa81a664bUL, 0xc24b8b70UL, 0xc76c51a3UL,
    0xd192e819UL, 0xd6990624UL, 0xf40e3585UL, 0x106aa070UL,
    0x19a4c116UL, 0x1e376c08UL, 0x2748774cUL, 0x34b0bcb5UL,
    0x391c0cb3UL, 0x4ed8aa4aUL, 0x5b9cca4fUL, 0x682e6ff3UL,
    0x748f82eeUL, 0x78a5636fUL, 0x84c87814UL, 0x8cc70208UL,
    0x90befffaUL, 0xa4506cebUL, 0xbef9a3f7UL, 0xc67178f2UL
  };
};

struct ColdSha512Variant {
  typedef uint64_t Word;
  static constexpr int rounds = 80;
  static constexpr uint8_t bigSigma0[3]   = { 28, 34, 39 };
  static constexpr uint8_t bigSigma1[3]   = { 14, 18, 41 };
  static constexpr uint8_t smallSigma0[3] = { 1, 8, 7 };
  static constexpr uint8_t smallSigma1[3] = { 19, 61, 6 };
  static constexpr Word initial[8] = {
    0x6a09e667f3bcc908ULL, 0xbb67ae8584caa73bULL,
    0x3c6ef372fe94f82bULL, 0xa54ff53a5f1d36f1ULL,
    0x510e527fade682d1ULL, 0x9b05688c2b3e6c1fULL,
    0x1f83d9abfb41bd6bULL, 0x5be0cd19137e2179ULL
  };
  static constexpr Word k[80] = {
    0x428a2f98d728ae22ULL, 0x7137449123ef65cdULL,
    0xb5c0fbcfec4d3b2fULL, 0xe9b5dba58189dbbcULL,
    0x3956c25bf348b538ULL, 0x59f111f1b605d019ULL,
    0x923f82a4af194f9bULL, 0xab1c5ed5da6d8118ULL,
    0xd807aa98a3030242ULL, 0x12835b0145706fbeULL,
    0x243185be4ee4b28cULL, 0x550c7dc3d5ffb4e2ULL,
    0x72be5d74f27b896fULL, 0x80deb1fe3b1696b1ULL,
    0x9bdc06a725c71235ULL, 0xc19bf174cf692694ULL,
    0xe49b69c19ef14ad2ULL, 0xefbe4786384f25e3ULL,
    0x0fc19dc68b8cd5b5ULL, 0x240ca1cc77ac9c65ULL,
    0x2de92c6f592b0275ULL, 0x4a7484aa6ea6e483ULL,
    0x5cb0a9dcbd41fbd4ULL, 0x76f988da831153b5ULL,
    0x983e5152ee66dfabULL, 0xa831c66d2db43210ULL,
    0xb00327c898fb213fULL, 0xbf597fc7beef0ee4ULL,
    0xc6e00bf33da88fc2ULL, 0xd5a79147930aa725ULL,
    0x06ca6351e003826fULL, 0x142929670a0e6e70ULL,
    0x27b70a8546d22ffcULL, 0x2e1b21385c26c926ULL,
    0x4d2c6dfc5ac42aedULL, 0x53380d139d95b3dfULL,
    0x650a73548baf63deULL, 0x766a0abb3c77b2a8ULL,
    0x81c2c92e47edaee6ULL, 0x92722c851482353bULL,
    0xa2bfe8a14cf10364ULL, 0xa81a664bbc423001ULL,
    0xc24b8b70d0f89791ULL, 0xc76c51a30654be30ULL,
    0xd192e819d6ef5218ULL, 0xd69906245565a910ULL,
    0xf40e35855771202aULL, 0x106aa07032bbd1b8ULL,
    0x19a4c116b8d2d0c8ULL, 0x1e376c085141ab53ULL,
    0x2748774cdf8eeb99ULL, 0x34b0bcb5e19b48a8ULL,
    0x391c0cb3c5c95a63ULL, 0x4ed8aa4ae3418acbULL,
    0x5b9cca4f7763e373ULL, 0x682e6ff3d6b2b8a3ULL,
    0x748f82ee5defb2fcULL, 0x78a5636f43172f60ULL,
    0x84c87814a1f0ab72ULL, 0x8cc702081a6439ecULL,
    0x90befffa23631e28ULL, 0xa4506cebde82bde9ULL,
    0xbef9a3f7b2c67915ULL, 0xc67178f2e372532bULL,
    0xca273eceea26619cULL, 0xd186b8c721c0c207ULL,
    0xeada7dd6cde0eb1eULL, 0xf57d4f7fee6ed178ULL,
    0x06f067aa72176fbaULL, 0x0a637dc5a2c898a6ULL,
    0x113f9804bef90daeULL, 0x1b710b35131c471bULL,
    0x28db77f523047d84ULL, 0x32caab7b40c72493ULL,
    0x3c9ebe0a15c9bebcULL, 0x431d67c49c100d4cULL,
    0x4cc5d4becb3e42b6ULL, 0x597f299cfc657e2aULL,
    0x5fcb6fab3ad6faecULL, 0x6c44198c4a475817ULL
  };
};

/// A hash in progress.
template <typename Variant>
struct ColdSha2 {
  typedef typename Variant::Word Word;

  Word     h[8];
  uint64_t total;                     // bytes so far; messages here are far below 2^61
  uint8_t  block[sizeof(Word) * 16];
  size_t   used;
};

typedef ColdSha2<ColdSha256Variant> ColdSha256;
typedef ColdSha2<ColdSha512Variant> ColdSha512;

template <typename Word>
static inline Word coldRotr(Word x, unsigned n) {
  return (Word)((x >> n) | (x << (sizeof(Word) * 8 - n)));
}

template <typename Word>
static inline Word coldBigSigma(Word x, const uint8_t r[3]) {
  return coldRotr(x, r[0]) ^ coldRotr(x, r[1]) ^ coldRotr(x, r[2]);
}

template <typename Word>
static inline Word coldSmallSigma(Word x, const uint8_t r[3]) {
  return coldRotr(x, r[0]) ^ coldRotr(x, r[1]) ^ (x >> r[2]);
}

/// Folds the full block in `s.block` into the state.
template <typename V>
static inline void coldSha2Compress(ColdSha2<V>& s) {
  typedef typename V::Word Word;

  Word w[V::rounds];
  for (int i = 0; i < 16; i++) coldLoadBe(s.block + i * sizeof(Word), w[i]);
  for (int i = 16; i < V::rounds; i++) {
    w[i] = w[i - 16] + coldSmallSigma(w[i - 15], V::smallSigma0) + w[i - 7] + coldSmallSigma(w[i - 2], V::smallSigma1);
  }

  Word a = s.h[0], b = s.h[1], c = s.h[2], d = s.h[3], e = s.h[4], f = s.h[5], g = s.h[6], h = s.h[7];
  for (int i = 0; i < V::rounds; i++) {
    const Word t1 = h + coldBigSigma(e, V::bigSigma1) + ((e & f) ^ (~e & g)) + V::k[i] + w[i];
    const Word t2 = coldBigSigma(a, V::bigSigma0) + ((a & b) ^ (a & c) ^ (b & c));
    h = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2;
  }
  s.h[0] += a; s.h[1] += b; s.h[2] += c; s.h[3] += d; s.h[4] += e; s.h[5] += f; s.h[6] += g; s.h[7] += h;
  coldWipe(w, sizeof(w));
}

template <typename V>
static inline void coldSha2Init(ColdSha2<V>& s) {
  memcpy(s.h, V::initial, sizeof(s.h));
  s.total = 0;
  s.used = 0;
}

template <typename V>
static inline void coldSha2Update(ColdSha2<V>& s, const uint8_t* data, size_t len) {
  s.total += len;
  while (len > 0) {
    const size_t room = sizeof(s.block) - s.used;
    const size_t take = room < len ? room : len;
    memcpy(s.block + s.used, data, take);
    s.used += take; data += take; len -= take;
    if (s.used == sizeof(s.block)) { coldSha2Compress(s); s.used = 0; }
  }
}

/// Writes the digest — 32 bytes for SHA-256, 64 for SHA-512 — and wipes
/// the state.
template <typename V>
static inline void coldSha2Final(ColdSha2<V>& s, uint8_t* out) {
  typedef typename V::Word Word;
  // The padding ends with the message length in bits. It is given two
  // words; the count here fits the last 8 bytes, the rest stays zero.
  const size_t lengthRoom = 2 * sizeof(Word);
  const size_t lengthAt = sizeof(s.block) - 8;
  const uint64_t bits = s.total * 8;

  s.block[s.used++] = 0x80;
  if (s.used > sizeof(s.block) - lengthRoom) {
    memset(s.block + s.used, 0, sizeof(s.block) - s.used);
    coldSha2Compress(s);
    s.used = 0;
  }
  memset(s.block + s.used, 0, lengthAt - s.used);
  coldStoreBe(s.block + lengthAt, bits);
  coldSha2Compress(s);

  for (int i = 0; i < 8; i++) coldStoreBe(out + i * sizeof(Word), s.h[i]);
  coldWipe(&s, sizeof(s));
}

static inline void coldSha256(const uint8_t* data, size_t len, uint8_t out[32]) {
  ColdSha256 s;
  coldSha2Init(s);
  coldSha2Update(s, data, len);
  coldSha2Final(s, out);
}

// ── HMAC-SHA512 ──────────────────────────────────────────────
/// A keyed HMAC whose padded-key blocks are hashed once and reused —
/// PBKDF2 runs it thousands of times with the same key.
struct ColdHmac512 {
  ColdSha512 inner;   // state after the ipad block
  ColdSha512 outer;   // state after the opad block
};

static inline void coldHmac512Key(ColdHmac512& ctx, const uint8_t* key, size_t keyLen) {
  uint8_t k[128];
  memset(k, 0, sizeof(k));
  if (keyLen > 128) {
    ColdSha512 s;
    coldSha2Init(s);
    coldSha2Update(s, key, keyLen);
    coldSha2Final(s, k);          // 64 bytes, the rest stays zero
  } else {
    memcpy(k, key, keyLen);
  }
  uint8_t pad[128];
  for (int i = 0; i < 128; i++) pad[i] = k[i] ^ 0x36;
  coldSha2Init(ctx.inner);
  coldSha2Update(ctx.inner, pad, 128);
  for (int i = 0; i < 128; i++) pad[i] = k[i] ^ 0x5c;
  coldSha2Init(ctx.outer);
  coldSha2Update(ctx.outer, pad, 128);
  coldWipe(k, sizeof(k));
  coldWipe(pad, sizeof(pad));
}

/// HMAC of one message under the prepared key. The context stays usable.
static inline void coldHmac512Compute(const ColdHmac512& ctx, const uint8_t* a, size_t aLen,
                               const uint8_t* b, size_t bLen, uint8_t out[64]) {
  uint8_t digest[64];
  ColdSha512 s = ctx.inner;
  if (aLen) coldSha2Update(s, a, aLen);
  if (bLen) coldSha2Update(s, b, bLen);
  coldSha2Final(s, digest);
  s = ctx.outer;
  coldSha2Update(s, digest, 64);
  coldSha2Final(s, out);
  coldWipe(digest, sizeof(digest));
}

static inline void coldHmac512(const uint8_t* key, size_t keyLen,
                               const uint8_t* data, size_t dataLen, uint8_t out[64]) {
  ColdHmac512 ctx;
  coldHmac512Key(ctx, key, keyLen);
  coldHmac512Compute(ctx, data, dataLen, nullptr, 0, out);
  coldWipe(&ctx, sizeof(ctx));
}

// ── PBKDF2-HMAC-SHA512, one 64-byte block ────────────────────
/// BIP-39 asks for exactly 64 bytes, which is a single PBKDF2 block.
static inline void coldPbkdf2Sha512(const uint8_t* password, size_t passwordLen,
                             const uint8_t* salt, size_t saltLen,
                             uint32_t iterations, uint8_t out[64]) {
  ColdHmac512 ctx;
  coldHmac512Key(ctx, password, passwordLen);

  static const uint8_t blockIndex[4] = { 0, 0, 0, 1 };
  uint8_t u[64];
  coldHmac512Compute(ctx, salt, saltLen, blockIndex, 4, u);
  memcpy(out, u, 64);
  for (uint32_t i = 1; i < iterations; i++) {
    coldHmac512Compute(ctx, u, 64, nullptr, 0, u);
    for (int j = 0; j < 64; j++) out[j] ^= u[j];
  }
  coldWipe(u, sizeof(u));
  coldWipe(&ctx, sizeof(ctx));
}

#endif // COLD_SHA2_H
