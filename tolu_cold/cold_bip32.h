// ============================================================
// cold_bip32.h - seed → the wallet's private key (BIP-32 / BIP-44)
// ============================================================
// Walks m/44'/60'/0'/0/0, the path every Ethereum wallet uses for its
// first account — so the phrase written on paper restores this exact
// address in MetaMask, Ledger, or anything else.
// ============================================================
#ifndef COLD_BIP32_H
#define COLD_BIP32_H

#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include "cold_util.h"
#include "cold_sha2.h"
#include "cold_secp256k1.h"

#define COLD_HARDENED 0x80000000UL

/// One step down the tree. `key` and `chain` (32 bytes each) are
/// replaced by the child's. Returns false for the vanishingly rare
/// index BIP-32 says to skip.
static inline bool coldDeriveChild(uint8_t key[32], uint8_t chain[32], uint32_t index) {
  uint8_t data[37];
  if (index & COLD_HARDENED) {
    data[0] = 0x00;
    memcpy(data + 1, key, 32);
  } else {
    uint8_t publicKey[65];
    if (!coldPublicKey(key, publicKey)) return false;
    coldCompressPublicKey(publicKey, data);
  }
  coldStoreBe32(data + 33, index);

  uint8_t digest[64];
  coldHmac512(chain, 32, data, sizeof(data), digest);
  coldWipe(data, sizeof(data));

  ColdU256 tweak, parent, child;
  coldU256FromBytes(tweak, digest);
  coldU256FromBytes(parent, key);
  bool ok = coldU256Cmp(tweak, COLD_N) < 0;
  if (ok) {
    coldScalarAdd(child, parent, tweak);
    ok = !coldU256IsZero(child);
  }
  if (ok) {
    coldU256ToBytes(child, key);
    memcpy(chain, digest + 32, 32);
  }
  coldWipe(digest, sizeof(digest));
  coldWipe(&tweak, sizeof(tweak));
  coldWipe(&parent, sizeof(parent));
  coldWipe(&child, sizeof(child));
  return ok;
}

/// The private key at m/44'/60'/0'/0/0 for a 64-byte BIP-39 seed.
static inline bool coldDeriveEthereumKey(const uint8_t seed[64], uint8_t privateKey[32]) {
  static const char masterKey[] = "Bitcoin seed";
  uint8_t digest[64];
  coldHmac512((const uint8_t*)masterKey, 12, seed, 64, digest);

  uint8_t key[32], chain[32];
  memcpy(key, digest, 32);
  memcpy(chain, digest + 32, 32);
  coldWipe(digest, sizeof(digest));

  ColdU256 master;
  coldU256FromBytes(master, key);
  bool ok = coldScalarValid(master);
  coldWipe(&master, sizeof(master));

  static const uint32_t path[5] = {
    44 | COLD_HARDENED, 60 | COLD_HARDENED, 0 | COLD_HARDENED, 0, 0
  };
  for (int i = 0; ok && i < 5; i++) ok = coldDeriveChild(key, chain, path[i]);

  if (ok) memcpy(privateKey, key, 32);
  coldWipe(key, sizeof(key));
  coldWipe(chain, sizeof(chain));
  return ok;
}

#endif // COLD_BIP32_H
