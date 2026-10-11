// ============================================================
// cold_bip39.h - entropy → seed phrase → seed (BIP-39)
// ============================================================
// 16 bytes of entropy make 12 words, 32 bytes make 24. The last word
// carries a checksum, so a phrase written down wrong is caught when it
// is typed into any other wallet.
// ============================================================
#ifndef COLD_BIP39_H
#define COLD_BIP39_H

#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include "cold_util.h"
#include "cold_sha2.h"
#include "cold_bip39_words.h"

#define COLD_MAX_WORDS 24

/// Turns entropy into word indexes (0..2047). `entropyLen` must be 16,
/// 20, 24, 28 or 32. Returns the number of words, or 0 if it isn't.
static inline int coldMnemonicFromEntropy(const uint8_t* entropy, size_t entropyLen,
                                   uint16_t words[COLD_MAX_WORDS]) {
  if (entropyLen < 16 || entropyLen > 32 || entropyLen % 4 != 0) return 0;

  // entropy || checksum, where the checksum is the first ENT/32 bits
  // of SHA-256(entropy).
  uint8_t bits[33];
  uint8_t hash[32];
  coldSha256(entropy, entropyLen, hash);
  memcpy(bits, entropy, entropyLen);
  bits[entropyLen] = hash[0];

  const int count = (int)(entropyLen * 8 + entropyLen / 4) / 11;
  for (int w = 0; w < count; w++) {
    uint16_t index = 0;
    for (int b = 0; b < 11; b++) {
      const int pos = w * 11 + b;
      index = (uint16_t)((index << 1) | ((bits[pos / 8] >> (7 - pos % 8)) & 1));
    }
    words[w] = index;
  }
  coldWipe(bits, sizeof(bits));
  coldWipe(hash, sizeof(hash));
  return count;
}

/// The phrase as text: words separated by single spaces. `out` needs
/// room for 24 words of up to 8 letters plus spaces (216 bytes).
static inline size_t coldMnemonicSentence(const uint16_t* words, int count, char* out, size_t outSize) {
  size_t n = 0;
  for (int i = 0; i < count; i++) {
    const char* word = COLD_BIP39_WORDS[words[i] & 0x7FF];
    const size_t len = strlen(word);
    if (n + len + 2 > outSize) return 0;
    if (i > 0) out[n++] = ' ';
    memcpy(out + n, word, len);
    n += len;
  }
  out[n] = '\0';
  return n;
}

/// The 64-byte seed BIP-32 starts from: PBKDF2-HMAC-SHA512 over the
/// phrase, salted with "mnemonic" (no passphrase), 2048 rounds.
static inline bool coldSeedFromMnemonic(const uint16_t* words, int count, uint8_t seed[64]) {
  char sentence[COLD_MAX_WORDS * 9 + 1];
  const size_t len = coldMnemonicSentence(words, count, sentence, sizeof(sentence));
  if (len == 0) return false;
  static const char salt[] = "mnemonic";
  coldPbkdf2Sha512((const uint8_t*)sentence, len, (const uint8_t*)salt, 8, 2048, seed);
  coldWipe(sentence, sizeof(sentence));
  return true;
}

#endif // COLD_BIP39_H
