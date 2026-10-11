// The device's key-derivation code, compiled for this computer and
// checked against values from the ethers library and Node's crypto
// module (vectors.txt, written by make_vectors.js).
//
// Each line of vectors.txt is one case, tab-separated:
//   W  entropy  phrase  seed  private key  public key  address
//   H  message  hmac key  sha256  sha512  hmac-sha512  keccak256
//   F  a  b  a*b mod p  a+b mod p  a-b mod p
#include <algorithm>
#include <fstream>
#include <sstream>
#include "test_support.h"
#include "cold_sha2.h"
#include "cold_keccak.h"
#include "cold_secp256k1.h"
#include "cold_bip39.h"
#include "cold_bip32.h"
#include "cold_entropy.h"

static std::vector<std::string> split(const std::string& line) {
  std::vector<std::string> fields;
  std::stringstream stream(line);
  std::string field;
  while (std::getline(stream, field, '\t')) fields.push_back(field);
  return fields;
}

/// Entropy → phrase → seed → private key → public key → address.
static void checkWallet(const std::vector<std::string>& f) {
  const std::vector<uint8_t> entropy = unhex(f[1]);
  const std::string name = "wallet " + f[1];

  uint16_t words[COLD_MAX_WORDS];
  const int count = coldMnemonicFromEntropy(entropy.data(), entropy.size(), words);
  check(count == (entropy.size() == 16 ? 12 : 24), name + ": word count");
  char phrase[COLD_MAX_WORDS * 9 + 1];
  coldMnemonicSentence(words, count, phrase, sizeof(phrase));
  check(f[2] == phrase, name + ": phrase");

  uint8_t seed[64], privateKey[32], publicKey[65], address[20];
  char addressText[43];
  check(coldSeedFromMnemonic(words, count, seed), name + ": seed made");
  check(hex(seed, sizeof(seed)) == f[3], name + ": seed");
  check(coldDeriveEthereumKey(seed, privateKey), name + ": key derived");
  check(hex(privateKey, sizeof(privateKey)) == f[4], name + ": private key");
  check(coldPublicKey(privateKey, publicKey), name + ": public key made");
  check(hex(publicKey, sizeof(publicKey)) == f[5], name + ": public key");
  coldAddressFromPublicKey(publicKey, address);
  coldChecksumAddress(address, addressText);
  check(f[6] == addressText, name + ": address");
}

/// SHA-256, SHA-512, HMAC-SHA512 and Keccak-256 of one message.
static void checkHashes(const std::vector<std::string>& f) {
  const std::vector<uint8_t> message = unhex(f[1]), key = unhex(f[2]);
  const std::string name = "message of " + std::to_string(message.size()) + " bytes";

  uint8_t sha256[32], sha512[64], mac[64], keccak[32];
  coldSha256(message.data(), message.size(), sha256);
  check(hex(sha256, sizeof(sha256)) == f[3], name + ": sha256");

  // Fed in uneven pieces, to exercise the block buffering.
  ColdSha512 state;
  coldSha2Init(state);
  for (size_t offset = 0, step = 1; offset < message.size(); step = step * 3 + 1) {
    const size_t take = std::min(step, message.size() - offset);
    coldSha2Update(state, message.data() + offset, take);
    offset += take;
  }
  coldSha2Final(state, sha512);
  check(hex(sha512, sizeof(sha512)) == f[4], name + ": sha512");

  coldHmac512(key.data(), key.size(), message.data(), message.size(), mac);
  check(hex(mac, sizeof(mac)) == f[5], name + ": hmac-sha512, key of " + std::to_string(key.size()));

  coldKeccak256(message.data(), message.size(), keccak);
  check(hex(keccak, sizeof(keccak)) == f[6], name + ": keccak256");
}

static std::string hex(const ColdU256& value) {
  uint8_t bytes[32];
  coldU256ToBytes(value, bytes);
  return hex(bytes, sizeof(bytes));
}

/// Multiplication, addition and subtraction modulo p, and the inverse.
static void checkField(const std::vector<std::string>& f) {
  ColdU256 a, b, result;
  coldU256FromBytes(a, unhex(f[1]).data());
  coldU256FromBytes(b, unhex(f[2]).data());
  const std::string name = f[1] + " and " + f[2];

  coldFieldMul(result, a, b);
  check(hex(result) == f[3], "mul " + name);
  coldFieldAdd(result, a, b);
  check(hex(result) == f[4], "add " + name);
  coldFieldSub(result, a, b);
  check(hex(result) == f[5], "sub " + name);

  // The result may be written over an operand.
  ColdU256 inPlace = a;
  coldFieldMul(inPlace, inPlace, b);
  check(hex(inPlace) == f[3], "mul in place " + name);
  inPlace = a;
  coldFieldAdd(inPlace, inPlace, b);
  check(hex(inPlace) == f[4], "add in place " + name);
  inPlace = a;
  coldFieldSub(inPlace, inPlace, b);
  check(hex(inPlace) == f[5], "sub in place " + name);

  if (!coldU256IsZero(a)) {
    ColdU256 inverse, product;
    coldFieldInv(inverse, a);
    coldFieldMul(product, inverse, a);
    check(coldU256Cmp(product, COLD_ONE) == 0, "inverse of " + f[1]);
  }
}

/// The word list is the published one, byte for byte.
static void checkWordList() {
  std::string text;
  for (const char* word : COLD_BIP39_WORDS) text += std::string(word) + "\n";
  uint8_t digest[32];
  coldSha256((const uint8_t*)text.data(), text.size(), digest);
  check(hex(digest, sizeof(digest)) == "2f5eed53a4727b4bf8880d8f3f199efc90e58503646d9ff8eff3a2ed3b24dbda",
        "word list is bip-0039/english.txt");
}

/// SHA-256("tolu entropy v1" || 00..1f || 20..3f), worked out separately
/// with Python's hashlib. The toluWallet app is held to the same value.
static void checkEntropyMix() {
  uint8_t card[COLD_ENTROPY_SOURCE_BYTES], local[COLD_ENTROPY_SOURCE_BYTES], mixed[32];
  for (int i = 0; i < COLD_ENTROPY_SOURCE_BYTES; i++) {
    card[i] = (uint8_t)i;
    local[i] = (uint8_t)(0x20 + i);
  }
  coldMixEntropy(card, local, mixed, sizeof(mixed));
  check(hex(mixed, sizeof(mixed)) == "838b30c94b4d5f89e3278e60db6afe4d32e9d2d9c4f9601bd0a4a53416219abb", "entropy mix");

  // Twelve words come from the first 16 bytes of the same digest.
  uint8_t entropy[16];
  uint16_t words[COLD_MAX_WORDS];
  char phrase[COLD_MAX_WORDS * 9 + 1];
  coldMixEntropy(card, local, entropy, sizeof(entropy));
  check(memcmp(entropy, mixed, sizeof(entropy)) == 0, "12-word entropy is the digest's first half");
  coldMnemonicSentence(words, coldMnemonicFromEntropy(entropy, sizeof(entropy), words), phrase, sizeof(phrase));
  check(std::string(phrase) == "logic flower crane notable sting shaft milk vault general swap sauce orange",
        "entropy mix as words");

  // Neither source alone decides the result.
  uint8_t changed[32];
  card[31] ^= 1;
  coldMixEntropy(card, local, changed, sizeof(changed));
  check(memcmp(changed, mixed, sizeof(mixed)) != 0, "the card's bytes matter");
  card[31] ^= 1;
  local[0] ^= 1;
  coldMixEntropy(card, local, changed, sizeof(changed));
  check(memcmp(changed, mixed, sizeof(mixed)) != 0, "the device's bytes matter");
}

static void checkRejections() {
  uint16_t words[COLD_MAX_WORDS];
  uint8_t entropy[33] = { 0 };
  for (size_t length : { 0, 15, 18, 33 }) {
    check(coldMnemonicFromEntropy(entropy, length, words) == 0, "entropy of " + std::to_string(length) + " bytes refused");
  }

  uint8_t publicKey[65], key[32] = { 0 };
  check(!coldPublicKey(key, publicKey), "private key 0 refused");
  coldU256ToBytes(COLD_N, key);
  check(!coldPublicKey(key, publicKey), "private key n refused");

  uint8_t one[32] = { 0 }, generator[65];
  one[31] = 1;
  generator[0] = 0x04;
  coldU256ToBytes(COLD_GX, generator + 1);
  coldU256ToBytes(COLD_GY, generator + 33);
  check(coldPublicKey(one, publicKey) && memcmp(publicKey, generator, sizeof(generator)) == 0, "1 * G is G");
}

int main(int argc, char** argv) {
  if (argc < 2) {
    printf("usage: %s vectors.txt\n", argv[0]);
    return 2;
  }
  std::ifstream vectors(argv[1]);
  if (!vectors) {
    printf("cannot read %s\n", argv[1]);
    return 2;
  }

  int wallets = 0, hashes = 0, fields = 0;
  for (std::string line; std::getline(vectors, line);) {
    const std::vector<std::string> f = split(line);
    if (f.empty()) continue;
    if (f[0] == "W" && f.size() == 7)      { checkWallet(f); wallets++; }
    else if (f[0] == "H" && f.size() == 7) { checkHashes(f); hashes++; }
    else if (f[0] == "F" && f.size() == 6) { checkField(f); fields++; }
    else check(false, "unreadable line: " + line.substr(0, 40));
  }
  check(wallets > 0 && hashes > 0 && fields > 0, "vectors.txt holds all three kinds of case");

  checkWordList();
  checkEntropyMix();
  checkRejections();

  return finish(std::to_string(wallets) + " wallets, " + std::to_string(hashes) + " hash cases, " +
                std::to_string(fields) + " field cases");
}
