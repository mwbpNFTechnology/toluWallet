// ============================================================
// cold_keccak.h - Keccak-256 and Ethereum addresses
// ============================================================
// Ethereum uses the original Keccak padding (0x01), not NIST SHA3 (0x06).
// Self-contained like cold_sha2.h and checked the same way.
// ============================================================
#ifndef COLD_KECCAK_H
#define COLD_KECCAK_H

#include <stdint.h>
#include <stddef.h>
#include <string.h>

static const uint64_t COLD_KECCAK_RC[24] = {
  0x0000000000000001ULL, 0x0000000000008082ULL, 0x800000000000808aULL,
  0x8000000080008000ULL, 0x000000000000808bULL, 0x0000000080000001ULL,
  0x8000000080008081ULL, 0x8000000000008009ULL, 0x000000000000008aULL,
  0x0000000000000088ULL, 0x0000000080008009ULL, 0x000000008000000aULL,
  0x000000008000808bULL, 0x800000000000008bULL, 0x8000000000008089ULL,
  0x8000000000008003ULL, 0x8000000000008002ULL, 0x8000000000000080ULL,
  0x000000000000800aULL, 0x800000008000000aULL, 0x8000000080008081ULL,
  0x8000000000008080ULL, 0x0000000080000001ULL, 0x8000000080008008ULL
};
static const int COLD_KECCAK_ROT[24] = {
  1,  3,  6,  10, 15, 21, 28, 36, 45, 55, 2,  14,
  27, 41, 56, 8,  25, 43, 62, 18, 39, 61, 20, 44
};
static const int COLD_KECCAK_PI[24] = {
  10, 7,  11, 17, 18, 3,  5,  16, 8,  21, 24, 4,
  15, 23, 19, 13, 12, 2,  20, 14, 22, 9,  6,  1
};

static inline uint64_t coldRotl64(uint64_t x, int n) { return (x << n) | (x >> (64 - n)); }

static inline void coldKeccakF(uint64_t st[25]) {
  uint64_t t, bc[5];
  for (int round = 0; round < 24; round++) {
    for (int i = 0; i < 5; i++)
      bc[i] = st[i] ^ st[i + 5] ^ st[i + 10] ^ st[i + 15] ^ st[i + 20];
    for (int i = 0; i < 5; i++) {
      t = bc[(i + 4) % 5] ^ coldRotl64(bc[(i + 1) % 5], 1);
      for (int j = 0; j < 25; j += 5) st[j + i] ^= t;
    }
    t = st[1];
    for (int i = 0; i < 24; i++) {
      const int j = COLD_KECCAK_PI[i];
      bc[0] = st[j];
      st[j] = coldRotl64(t, COLD_KECCAK_ROT[i]);
      t = bc[0];
    }
    for (int j = 0; j < 25; j += 5) {
      for (int i = 0; i < 5; i++) bc[i] = st[j + i];
      for (int i = 0; i < 5; i++) st[j + i] ^= (~bc[(i + 1) % 5]) & bc[(i + 2) % 5];
    }
    st[0] ^= COLD_KECCAK_RC[round];
  }
}

static inline uint64_t coldLoadLe64(const uint8_t* p) {
  uint64_t v = 0;
  for (int i = 7; i >= 0; i--) v = (v << 8) | p[i];
  return v;
}

static inline void coldKeccak256(const uint8_t* data, size_t len, uint8_t hash[32]) {
  uint64_t st[25];
  memset(st, 0, sizeof(st));
  const size_t rate = 136;

  while (len >= rate) {
    for (size_t i = 0; i < rate / 8; i++) st[i] ^= coldLoadLe64(data + i * 8);
    coldKeccakF(st);
    data += rate;
    len -= rate;
  }

  uint8_t last[136];
  memset(last, 0, rate);
  memcpy(last, data, len);
  last[len] = 0x01;
  last[rate - 1] |= 0x80;
  for (size_t i = 0; i < rate / 8; i++) st[i] ^= coldLoadLe64(last + i * 8);
  coldKeccakF(st);

  for (int i = 0; i < 32; i++) hash[i] = (uint8_t)(st[i / 8] >> (8 * (i % 8)));
}

/// The address of an uncompressed public key: the last 20 bytes of
/// Keccak-256 over X || Y.
static inline void coldAddressFromPublicKey(const uint8_t publicKey[65], uint8_t address[20]) {
  uint8_t hash[32];
  coldKeccak256(publicKey + 1, 64, hash);
  memcpy(address, hash + 12, 20);
}

/// "0x" + 40 hex digits in EIP-55 mixed case, null-terminated (43 bytes).
static inline void coldChecksumAddress(const uint8_t address[20], char out[43]) {
  static const char* digits = "0123456789abcdef";
  char lower[40];
  for (int i = 0; i < 20; i++) {
    lower[i * 2]     = digits[address[i] >> 4];
    lower[i * 2 + 1] = digits[address[i] & 0x0F];
  }
  uint8_t hash[32];
  coldKeccak256((const uint8_t*)lower, 40, hash);

  out[0] = '0';
  out[1] = 'x';
  for (int i = 0; i < 40; i++) {
    const uint8_t nibble = (i & 1) ? (hash[i / 2] & 0x0F) : (hash[i / 2] >> 4);
    char c = lower[i];
    if (c >= 'a' && c <= 'f' && nibble >= 8) c = (char)(c - 'a' + 'A');
    out[2 + i] = c;
  }
  out[42] = '\0';
}

#endif // COLD_KECCAK_H
