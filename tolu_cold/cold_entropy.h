// ============================================================
// cold_entropy.h - two random sources into one
// ============================================================
// The seed phrase is not made from the card's random bytes alone. They
// are hashed together with random bytes from this device, so:
//
//   - both generators would have to be bad for the phrase to be weak;
//   - the card's bytes cross the air unencrypted, and someone who
//     caught them still has nothing — the other half never left here.
//
// Hashing can only add: the result is at least as hard to guess as the
// better of the two inputs.
//
// The toluWallet app uses the same recipe and the same label when it
// makes a seed phrase on the phone.
// ============================================================
#ifndef COLD_ENTROPY_H
#define COLD_ENTROPY_H

#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include "cold_util.h"
#include "cold_sha2.h"

// How many bytes each source gives, whatever the phrase length.
#define COLD_ENTROPY_SOURCE_BYTES 32

/// SHA-256("tolu entropy v1" || card || local), cut to `outLen` bytes
/// (16 for 12 words, 32 for 24).
static inline void coldMixEntropy(const uint8_t card[COLD_ENTROPY_SOURCE_BYTES],
                           const uint8_t local[COLD_ENTROPY_SOURCE_BYTES],
                           uint8_t* out, size_t outLen) {
  static const char label[] = "tolu entropy v1";
  uint8_t digest[32];
  ColdSha256 s;
  coldSha2Init(s);
  coldSha2Update(s, (const uint8_t*)label, sizeof(label) - 1);
  coldSha2Update(s, card, COLD_ENTROPY_SOURCE_BYTES);
  coldSha2Update(s, local, COLD_ENTROPY_SOURCE_BYTES);
  coldSha2Final(s, digest);          // also wipes the hash state
  memcpy(out, digest, outLen < sizeof(digest) ? outLen : sizeof(digest));
  coldWipe(digest, sizeof(digest));
}

#endif // COLD_ENTROPY_H
