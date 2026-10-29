// ============================================================
// cold_aes.h - AES-128 and AES-CMAC, for the card's secure channel
// ============================================================
// What an encrypted session with the card needs (cold_session.h): one
// AES-128 block in both directions, CBC over whole blocks, and the
// CMAC of RFC 4493. The toluWallet app runs the same session with the
// same three (SecureChannel.swift, AesCmac.swift).
//
// Self-contained like cold_sha2.h, so it is checked on a computer
// against reference vectors. The table look-ups make it not
// constant-time; every key it runs with lives for a single write.
// ============================================================
#ifndef COLD_AES_H
#define COLD_AES_H

#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include "cold_util.h"

#define COLD_AES_BLOCK 16

static const uint8_t COLD_AES_SBOX[256] = {
  0x63, 0x7C, 0x77, 0x7B, 0xF2, 0x6B, 0x6F, 0xC5, 0x30, 0x01, 0x67, 0x2B, 0xFE, 0xD7, 0xAB, 0x76,
  0xCA, 0x82, 0xC9, 0x7D, 0xFA, 0x59, 0x47, 0xF0, 0xAD, 0xD4, 0xA2, 0xAF, 0x9C, 0xA4, 0x72, 0xC0,
  0xB7, 0xFD, 0x93, 0x26, 0x36, 0x3F, 0xF7, 0xCC, 0x34, 0xA5, 0xE5, 0xF1, 0x71, 0xD8, 0x31, 0x15,
  0x04, 0xC7, 0x23, 0xC3, 0x18, 0x96, 0x05, 0x9A, 0x07, 0x12, 0x80, 0xE2, 0xEB, 0x27, 0xB2, 0x75,
  0x09, 0x83, 0x2C, 0x1A, 0x1B, 0x6E, 0x5A, 0xA0, 0x52, 0x3B, 0xD6, 0xB3, 0x29, 0xE3, 0x2F, 0x84,
  0x53, 0xD1, 0x00, 0xED, 0x20, 0xFC, 0xB1, 0x5B, 0x6A, 0xCB, 0xBE, 0x39, 0x4A, 0x4C, 0x58, 0xCF,
  0xD0, 0xEF, 0xAA, 0xFB, 0x43, 0x4D, 0x33, 0x85, 0x45, 0xF9, 0x02, 0x7F, 0x50, 0x3C, 0x9F, 0xA8,
  0x51, 0xA3, 0x40, 0x8F, 0x92, 0x9D, 0x38, 0xF5, 0xBC, 0xB6, 0xDA, 0x21, 0x10, 0xFF, 0xF3, 0xD2,
  0xCD, 0x0C, 0x13, 0xEC, 0x5F, 0x97, 0x44, 0x17, 0xC4, 0xA7, 0x7E, 0x3D, 0x64, 0x5D, 0x19, 0x73,
  0x60, 0x81, 0x4F, 0xDC, 0x22, 0x2A, 0x90, 0x88, 0x46, 0xEE, 0xB8, 0x14, 0xDE, 0x5E, 0x0B, 0xDB,
  0xE0, 0x32, 0x3A, 0x0A, 0x49, 0x06, 0x24, 0x5C, 0xC2, 0xD3, 0xAC, 0x62, 0x91, 0x95, 0xE4, 0x79,
  0xE7, 0xC8, 0x37, 0x6D, 0x8D, 0xD5, 0x4E, 0xA9, 0x6C, 0x56, 0xF4, 0xEA, 0x65, 0x7A, 0xAE, 0x08,
  0xBA, 0x78, 0x25, 0x2E, 0x1C, 0xA6, 0xB4, 0xC6, 0xE8, 0xDD, 0x74, 0x1F, 0x4B, 0xBD, 0x8B, 0x8A,
  0x70, 0x3E, 0xB5, 0x66, 0x48, 0x03, 0xF6, 0x0E, 0x61, 0x35, 0x57, 0xB9, 0x86, 0xC1, 0x1D, 0x9E,
  0xE1, 0xF8, 0x98, 0x11, 0x69, 0xD9, 0x8E, 0x94, 0x9B, 0x1E, 0x87, 0xE9, 0xCE, 0x55, 0x28, 0xDF,
  0x8C, 0xA1, 0x89, 0x0D, 0xBF, 0xE6, 0x42, 0x68, 0x41, 0x99, 0x2D, 0x0F, 0xB0, 0x54, 0xBB, 0x16
};
static const uint8_t COLD_AES_INV_SBOX[256] = {
  0x52, 0x09, 0x6A, 0xD5, 0x30, 0x36, 0xA5, 0x38, 0xBF, 0x40, 0xA3, 0x9E, 0x81, 0xF3, 0xD7, 0xFB,
  0x7C, 0xE3, 0x39, 0x82, 0x9B, 0x2F, 0xFF, 0x87, 0x34, 0x8E, 0x43, 0x44, 0xC4, 0xDE, 0xE9, 0xCB,
  0x54, 0x7B, 0x94, 0x32, 0xA6, 0xC2, 0x23, 0x3D, 0xEE, 0x4C, 0x95, 0x0B, 0x42, 0xFA, 0xC3, 0x4E,
  0x08, 0x2E, 0xA1, 0x66, 0x28, 0xD9, 0x24, 0xB2, 0x76, 0x5B, 0xA2, 0x49, 0x6D, 0x8B, 0xD1, 0x25,
  0x72, 0xF8, 0xF6, 0x64, 0x86, 0x68, 0x98, 0x16, 0xD4, 0xA4, 0x5C, 0xCC, 0x5D, 0x65, 0xB6, 0x92,
  0x6C, 0x70, 0x48, 0x50, 0xFD, 0xED, 0xB9, 0xDA, 0x5E, 0x15, 0x46, 0x57, 0xA7, 0x8D, 0x9D, 0x84,
  0x90, 0xD8, 0xAB, 0x00, 0x8C, 0xBC, 0xD3, 0x0A, 0xF7, 0xE4, 0x58, 0x05, 0xB8, 0xB3, 0x45, 0x06,
  0xD0, 0x2C, 0x1E, 0x8F, 0xCA, 0x3F, 0x0F, 0x02, 0xC1, 0xAF, 0xBD, 0x03, 0x01, 0x13, 0x8A, 0x6B,
  0x3A, 0x91, 0x11, 0x41, 0x4F, 0x67, 0xDC, 0xEA, 0x97, 0xF2, 0xCF, 0xCE, 0xF0, 0xB4, 0xE6, 0x73,
  0x96, 0xAC, 0x74, 0x22, 0xE7, 0xAD, 0x35, 0x85, 0xE2, 0xF9, 0x37, 0xE8, 0x1C, 0x75, 0xDF, 0x6E,
  0x47, 0xF1, 0x1A, 0x71, 0x1D, 0x29, 0xC5, 0x89, 0x6F, 0xB7, 0x62, 0x0E, 0xAA, 0x18, 0xBE, 0x1B,
  0xFC, 0x56, 0x3E, 0x4B, 0xC6, 0xD2, 0x79, 0x20, 0x9A, 0xDB, 0xC0, 0xFE, 0x78, 0xCD, 0x5A, 0xF4,
  0x1F, 0xDD, 0xA8, 0x33, 0x88, 0x07, 0xC7, 0x31, 0xB1, 0x12, 0x10, 0x59, 0x27, 0x80, 0xEC, 0x5F,
  0x60, 0x51, 0x7F, 0xA9, 0x19, 0xB5, 0x4A, 0x0D, 0x2D, 0xE5, 0x7A, 0x9F, 0x93, 0xC9, 0x9C, 0xEF,
  0xA0, 0xE0, 0x3B, 0x4D, 0xAE, 0x2A, 0xF5, 0xB0, 0xC8, 0xEB, 0xBB, 0x3C, 0x83, 0x53, 0x99, 0x61,
  0x17, 0x2B, 0x04, 0x7E, 0xBA, 0x77, 0xD6, 0x26, 0xE1, 0x69, 0x14, 0x63, 0x55, 0x21, 0x0C, 0x7D
};

/// An AES-128 key, expanded into its eleven round keys.
struct ColdAes128 {
  uint8_t roundKeys[176];
};

/// Multiplies by x in GF(2^8).
static inline uint8_t coldAesXtime(uint8_t a) {
  return (uint8_t)((a << 1) ^ ((a & 0x80) ? 0x1B : 0x00));
}

/// a · b in GF(2^8), for the inverse MixColumns.
static inline uint8_t coldAesMul(uint8_t a, uint8_t b) {
  uint8_t product = 0;
  while (b) {
    if (b & 1) product ^= a;
    a = coldAesXtime(a);
    b >>= 1;
  }
  return product;
}

static inline void coldAesKey(ColdAes128& ctx, const uint8_t key[16]) {
  static const uint8_t rcon[10] = { 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1B, 0x36 };
  memcpy(ctx.roundKeys, key, 16);
  int round = 0;
  for (int i = 16; i < 176; i += 4) {
    uint8_t word[4];
    memcpy(word, ctx.roundKeys + i - 4, 4);
    if (i % 16 == 0) {
      // RotWord, SubWord, Rcon
      const uint8_t first = word[0];
      word[0] = (uint8_t)(COLD_AES_SBOX[word[1]] ^ rcon[round++]);
      word[1] = COLD_AES_SBOX[word[2]];
      word[2] = COLD_AES_SBOX[word[3]];
      word[3] = COLD_AES_SBOX[first];
    }
    for (int j = 0; j < 4; j++) ctx.roundKeys[i + j] = ctx.roundKeys[i - 16 + j] ^ word[j];
  }
}

// The state is the block as it comes: column c is bytes 4c … 4c+3.
static inline void coldAesEncrypt(const ColdAes128& ctx, const uint8_t in[16], uint8_t out[16]) {
  uint8_t s[16], t[16];
  for (int i = 0; i < 16; i++) s[i] = in[i] ^ ctx.roundKeys[i];
  for (int round = 1; round <= 10; round++) {
    // SubBytes and ShiftRows: row r moves r columns to the left.
    for (int c = 0; c < 4; c++) {
      for (int r = 0; r < 4; r++) t[c * 4 + r] = COLD_AES_SBOX[s[((c + r) & 3) * 4 + r]];
    }
    if (round < 10) {
      // MixColumns
      for (int c = 0; c < 4; c++) {
        uint8_t* col = t + c * 4;
        const uint8_t a0 = col[0], a1 = col[1], a2 = col[2], a3 = col[3];
        const uint8_t all = a0 ^ a1 ^ a2 ^ a3;
        col[0] ^= all ^ coldAesXtime(a0 ^ a1);
        col[1] ^= all ^ coldAesXtime(a1 ^ a2);
        col[2] ^= all ^ coldAesXtime(a2 ^ a3);
        col[3] ^= all ^ coldAesXtime(a3 ^ a0);
      }
    }
    for (int i = 0; i < 16; i++) s[i] = t[i] ^ ctx.roundKeys[round * 16 + i];
  }
  memcpy(out, s, 16);
  coldWipe(s, sizeof(s));
  coldWipe(t, sizeof(t));
}

static inline void coldAesDecrypt(const ColdAes128& ctx, const uint8_t in[16], uint8_t out[16]) {
  uint8_t s[16], t[16];
  for (int i = 0; i < 16; i++) s[i] = in[i] ^ ctx.roundKeys[160 + i];
  for (int round = 9; round >= 0; round--) {
    // InvShiftRows and InvSubBytes: row r moves r columns to the right.
    for (int c = 0; c < 4; c++) {
      for (int r = 0; r < 4; r++) t[c * 4 + r] = COLD_AES_INV_SBOX[s[((c - r) & 3) * 4 + r]];
    }
    for (int i = 0; i < 16; i++) t[i] ^= ctx.roundKeys[round * 16 + i];
    if (round > 0) {
      // InvMixColumns
      for (int c = 0; c < 4; c++) {
        uint8_t* col = t + c * 4;
        const uint8_t a0 = col[0], a1 = col[1], a2 = col[2], a3 = col[3];
        col[0] = coldAesMul(a0, 14) ^ coldAesMul(a1, 11) ^ coldAesMul(a2, 13) ^ coldAesMul(a3, 9);
        col[1] = coldAesMul(a0, 9) ^ coldAesMul(a1, 14) ^ coldAesMul(a2, 11) ^ coldAesMul(a3, 13);
        col[2] = coldAesMul(a0, 13) ^ coldAesMul(a1, 9) ^ coldAesMul(a2, 14) ^ coldAesMul(a3, 11);
        col[3] = coldAesMul(a0, 11) ^ coldAesMul(a1, 13) ^ coldAesMul(a2, 9) ^ coldAesMul(a3, 14);
      }
    }
    memcpy(s, t, 16);
  }
  memcpy(out, s, 16);
  coldWipe(s, sizeof(s));
  coldWipe(t, sizeof(t));
}

// ── CBC over whole blocks, in place ──────────────────────────
static inline void coldAesCbcEncrypt(const ColdAes128& ctx, const uint8_t iv[16], uint8_t* data, size_t len) {
  const uint8_t* previous = iv;
  for (size_t at = 0; at + COLD_AES_BLOCK <= len; at += COLD_AES_BLOCK) {
    for (int i = 0; i < COLD_AES_BLOCK; i++) data[at + i] ^= previous[i];
    coldAesEncrypt(ctx, data + at, data + at);
    previous = data + at;
  }
}

static inline void coldAesCbcDecrypt(const ColdAes128& ctx, const uint8_t iv[16], uint8_t* data, size_t len) {
  uint8_t previous[16], cipher[16];
  memcpy(previous, iv, 16);
  for (size_t at = 0; at + COLD_AES_BLOCK <= len; at += COLD_AES_BLOCK) {
    memcpy(cipher, data + at, 16);
    coldAesDecrypt(ctx, data + at, data + at);
    for (int i = 0; i < COLD_AES_BLOCK; i++) data[at + i] ^= previous[i];
    memcpy(previous, cipher, 16);
  }
  coldWipe(previous, sizeof(previous));
  coldWipe(cipher, sizeof(cipher));
}

// ── AES-CMAC (RFC 4493), fed in pieces ───────────────────────
// The secure channel MACs a chaining value followed by a command, or
// by an answer and its status word, so the input arrives in parts.
struct ColdCmac {
  ColdAes128 aes;
  uint8_t    k1[16], k2[16];   // the subkeys for a whole and a padded last block
  uint8_t    x[16];            // the CBC-MAC so far
  uint8_t    block[16];        // the latest block, held back until it is known not to be the last
  uint8_t    blockLen;
};

/// One subkey from the one before: a left shift, and 0x87 folded in
/// when a bit falls off the top.
static inline void coldCmacDouble(const uint8_t in[16], uint8_t out[16]) {
  const uint8_t carry = in[0] >> 7;
  for (int i = 0; i < 15; i++) out[i] = (uint8_t)((in[i] << 1) | (in[i + 1] >> 7));
  out[15] = (uint8_t)((in[15] << 1) ^ (carry ? 0x87 : 0x00));
}

static inline void coldCmacBegin(ColdCmac& ctx, const uint8_t key[16]) {
  coldAesKey(ctx.aes, key);
  uint8_t l[16] = { 0 };
  coldAesEncrypt(ctx.aes, l, l);
  coldCmacDouble(l, ctx.k1);
  coldCmacDouble(ctx.k1, ctx.k2);
  coldWipe(l, sizeof(l));
  memset(ctx.x, 0, sizeof(ctx.x));
  ctx.blockLen = 0;
}

static inline void coldCmacUpdate(ColdCmac& ctx, const uint8_t* data, size_t len) {
  while (len) {
    if (ctx.blockLen == COLD_AES_BLOCK) {        // more is coming, so this one is not the last
      for (int i = 0; i < COLD_AES_BLOCK; i++) ctx.x[i] ^= ctx.block[i];
      coldAesEncrypt(ctx.aes, ctx.x, ctx.x);
      ctx.blockLen = 0;
    }
    const size_t room = (size_t)(COLD_AES_BLOCK - ctx.blockLen);
    const size_t take = len < room ? len : room;
    memcpy(ctx.block + ctx.blockLen, data, take);
    ctx.blockLen = (uint8_t)(ctx.blockLen + take);
    data += take;
    len -= take;
  }
}

/// The 16-byte MAC. Wipes the context.
static inline void coldCmacEnd(ColdCmac& ctx, uint8_t out[16]) {
  const uint8_t* subkey = ctx.k1;
  if (ctx.blockLen < COLD_AES_BLOCK) {           // a padded last block (also the empty message)
    ctx.block[ctx.blockLen] = 0x80;
    memset(ctx.block + ctx.blockLen + 1, 0, COLD_AES_BLOCK - ctx.blockLen - 1);
    subkey = ctx.k2;
  }
  for (int i = 0; i < COLD_AES_BLOCK; i++) ctx.x[i] ^= ctx.block[i] ^ subkey[i];
  coldAesEncrypt(ctx.aes, ctx.x, out);
  coldWipe(&ctx, sizeof(ctx));
}

static inline void coldAesCmac(const uint8_t key[16], const uint8_t* data, size_t len, uint8_t out[16]) {
  ColdCmac ctx;
  coldCmacBegin(ctx, key);
  coldCmacUpdate(ctx, data, len);
  coldCmacEnd(ctx, out);
}

#endif // COLD_AES_H
