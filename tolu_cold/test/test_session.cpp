// The encrypted session's code, compiled for this computer:
//   - AES-128, CBC, AES-CMAC, HMAC-SHA256 and P-256 against Node's crypto
//     module (session_vectors.txt, written by make_session_vectors.js);
//   - ECDSA against RFC 6979's own published signatures;
//   - the session keys, protected commands and opened answers against
//     the values toluWalletTests/SecureChannelTests.swift pins for the
//     app — so the device and the phone speak the same bytes.
//
// Each line of session_vectors.txt is one case, tab-separated:
//   A  key  block  AES(key, block)
//   B  key  iv  plaintext  AES-CBC ciphertext
//   C  key  message  AES-CMAC
//   M  key  message  HMAC-SHA256
//   P  private key  public key  peer's public key  ECDH secret
//   S  public key  message  ECDSA-SHA256 signature (DER, made by Node)
#include <fstream>
#include <sstream>
#include "test_support.h"
#include "test_p256.h"
#include "cold_aes.h"
#include "cold_p256.h"
#include "cold_session.h"

static std::vector<std::string> split(const std::string& line) {
  std::vector<std::string> fields;
  std::stringstream stream(line);
  std::string field;
  while (std::getline(stream, field, '\t')) fields.push_back(field);
  return fields;
}

static std::string aesBlock(const std::vector<uint8_t>& key, const std::vector<uint8_t>& block, bool decrypt) {
  ColdAes128 aes;
  coldAesKey(aes, key.data());
  uint8_t out[16];
  if (decrypt) coldAesDecrypt(aes, block.data(), out);
  else         coldAesEncrypt(aes, block.data(), out);
  return hex(out, sizeof(out));
}

static void checkAes(const std::vector<std::string>& f) {
  const std::vector<uint8_t> key = unhex(f[1]), plain = unhex(f[2]), cipher = unhex(f[3]);
  check(aesBlock(key, plain, false) == f[3], "AES encrypt " + f[2]);
  check(aesBlock(key, cipher, true) == f[2], "AES decrypt " + f[3]);
}

static void checkCbc(const std::vector<std::string>& f) {
  const std::vector<uint8_t> key = unhex(f[1]), iv = unhex(f[2]);
  ColdAes128 aes;
  coldAesKey(aes, key.data());
  std::vector<uint8_t> data = unhex(f[3]);
  coldAesCbcEncrypt(aes, iv.data(), data.data(), data.size());
  check(hex(data) == f[4], "CBC encrypt, " + std::to_string(data.size()) + " bytes");
  coldAesCbcDecrypt(aes, iv.data(), data.data(), data.size());
  check(hex(data) == f[3], "CBC decrypt, " + std::to_string(data.size()) + " bytes");
}

static void checkCmac(const std::vector<std::string>& f) {
  const std::vector<uint8_t> key = unhex(f[1]), message = unhex(f[2]);
  const std::string name = "CMAC of " + std::to_string(message.size()) + " bytes";
  uint8_t mac[16];
  coldAesCmac(key.data(), message.data(), message.size(), mac);
  check(hex(mac, sizeof(mac)) == f[3], name);

  // The same, fed in uneven pieces, as the secure channel feeds it.
  ColdCmac ctx;
  coldCmacBegin(ctx, key.data());
  for (size_t at = 0; at < message.size();) {
    const size_t piece = std::min<size_t>(1 + at % 7, message.size() - at);
    coldCmacUpdate(ctx, message.data() + at, piece);
    at += piece;
  }
  coldCmacEnd(ctx, mac);
  check(hex(mac, sizeof(mac)) == f[3], name + ", in pieces");
}

static void checkHmac(const std::vector<std::string>& f) {
  const std::vector<uint8_t> key = unhex(f[1]), message = unhex(f[2]);
  ColdHmac256 ctx;
  uint8_t mac[32];
  coldHmac256Begin(ctx, key.data(), key.size());
  coldHmac256Update(ctx, message.data(), message.size());
  coldHmac256End(ctx, mac);
  check(hex(mac, sizeof(mac)) == f[3],
        "HMAC-SHA256, key " + std::to_string(key.size()) + ", message " + std::to_string(message.size()));
}

static void checkP256(const std::vector<std::string>& f) {
  const std::vector<uint8_t> privateKey = unhex(f[1]), peer = unhex(f[3]);
  const std::string name = "P-256 key " + f[1].substr(0, 12);
  uint8_t publicKey[65], secret[32];
  check(coldP256PublicKey(privateKey.data(), publicKey) && hex(publicKey, sizeof(publicKey)) == f[2],
        name + ": public key");
  check(coldP256Ecdh(privateKey.data(), peer.data(), secret) && hex(secret, sizeof(secret)) == f[4],
        name + ": ECDH secret");

  // What it signs, the verifier accepts — and refuses once changed.
  const uint8_t message[] = { 't', 'o', 'l', 'u' };
  uint8_t signature[COLD_P256_SIG_MAX];
  const uint8_t length = coldP256Sign(privateKey.data(), message, sizeof(message), signature);
  std::vector<uint8_t> der(signature, signature + length);
  check(length >= 8 && p256Verify(publicKey, message, sizeof(message), der), name + ": signature verifies");
  der[der.size() - 1] ^= 1;
  check(!p256Verify(publicKey, message, sizeof(message), der), name + ": changed signature refused");
}

/// Node's signatures, which keep the verifier the pretend card uses honest.
static void checkNodeSignature(const std::vector<std::string>& f) {
  const std::vector<uint8_t> publicKey = unhex(f[1]), message = unhex(f[2]), signature = unhex(f[3]);
  const std::string name = "Node signature over " + std::to_string(message.size()) + " bytes";
  check(p256Verify(publicKey.data(), message.data(), message.size(), signature), name + " verifies");
  std::vector<uint8_t> other = message;
  other.push_back(0x00);
  check(!p256Verify(publicKey.data(), other.data(), other.size(), signature), name + ": other message refused");
}

/// RFC 6979 A.2.5: P-256, SHA-256 — the deterministic nonce exactly.
static void checkRfc6979() {
  const std::vector<uint8_t> key = unhex("c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721");
  uint8_t publicKey[65], signature[COLD_P256_SIG_MAX];
  check(coldP256PublicKey(key.data(), publicKey) &&
        hex(publicKey, sizeof(publicKey)) == "04"
        "60fed4ba255a9d31c961eb74c6356d68c049b8923b61fa6ce669622e60f29fb6"
        "7903fe1008b8bc99a41ae9e95628bc64f2f1b20c2d7e9f5177a3c294d4462299", "RFC 6979 public key");

  uint8_t length = coldP256Sign(key.data(), (const uint8_t*)"sample", 6, signature);
  check(hex(signature, length) == "3046"
        "022100efd48b2aacb6a8fd1140dd9cd45e81d69d2c877b56aaf991c34d0ea84eaf3716"
        "022100f7cb1c942d657c41d436c7a1b6e29f65f3e900dbb9aff4064dc4ab2f843acda8", "RFC 6979 \"sample\"");
  length = coldP256Sign(key.data(), (const uint8_t*)"test", 4, signature);
  check(hex(signature, length) == "3045"
        "022100f1abb023518351cd71d881567b1ea663ed3efcf6c5132b354f28d3b0b7d38367"
        "0220019f4113742a2b14bd25926b49c649155f267e60d3814b4c0cc84250e46f0083", "RFC 6979 \"test\" (short s)");
}

static void checkRejections() {
  uint8_t publicKey[65], secret[32], signature[COLD_P256_SIG_MAX];
  uint8_t zero[32] = { 0 };
  check(!coldP256PublicKey(zero, publicKey), "private key 0 refused");
  check(!coldP256PublicKey(COLD_P256_N, publicKey), "private key n refused");
  check(coldP256Sign(COLD_P256_N, zero, sizeof(zero), signature) == 0, "no signature with key n");

  uint8_t one[32] = { 0 };
  one[31] = 1;
  check(coldP256PublicKey(one, publicKey) && memcmp(publicKey, COLD_P256_G, 65) == 0, "1 * G is G");

  // A key agreement with a point off the curve would leak the key: refused.
  uint8_t offCurve[65];
  memcpy(offCurve, COLD_P256_G, 65);
  offCurve[64] ^= 1;
  check(!coldP256Ecdh(one, offCurve, secret), "a point off the curve refused");
  uint8_t compressed[65];
  memcpy(compressed, COLD_P256_G, 65);
  compressed[0] = 0x02;
  check(!coldP256Ecdh(one, compressed, secret), "a point not in the 04 form refused");
  uint8_t tooBig[65];
  tooBig[0] = 0x04;
  memcpy(tooBig + 1, COLD_P256_PRIME, 32);
  memcpy(tooBig + 33, COLD_P256_G + 33, 32);
  check(!coldP256Ecdh(one, tooBig, secret), "a coordinate of p or more refused");

  // DER integers: no leading zeros, and a 00 in front of a high bit.
  uint8_t value[32] = { 0 }, der[35];
  value[31] = 0x7F;
  check(coldDerInteger(der, value) == 3 && hex(der, 3) == "02017f", "DER small integer");
  value[31] = 0x80;
  check(coldDerInteger(der, value) == 4 && hex(der, 4) == "02020080", "DER integer with its top bit set");
}

// ── The session, against the app's own values ────────────────
// SecureChannelTests.swift: a fixed ECDH secret and card challenge, and
// card answers made by a reference written from NXP's middleware.
static SeScpKeys appSessionKeys() {
  const std::vector<uint8_t> secret(32, 0x5C);
  const std::vector<uint8_t> challenge = unhex("0102030405060708090a0b0c0d0e0f10");
  SeScpKeys keys;
  seScpKeys(keys, secret.data(), challenge.data());
  return keys;
}

static std::string repeated(const std::string& part, int times) {
  std::string out;
  for (int i = 0; i < times; i++) out += part;
  return out;
}

static const std::string READ_ANSWER =
  "d3ddb1485444d50b4872ebd395e25b86524c2c4d51df391ea8d7a69e2fe6ec9f04f56a47f0553e7bc68d814f0889eedc"
  "f0d031fff2be9bbae2b668867f6dd472d8b941c43cdc8943e1e1f8351c981e2e4709d34a689914a8";

static int16_t openAnswer(SeChannel& channel, const std::string& answer, uint16_t sw, uint8_t* out, uint8_t outSize) {
  const std::vector<uint8_t> bytes = unhex(answer);
  return seChannelOpen(channel, bytes.data(), (int16_t)bytes.size(), sw, out, outSize);
}

static std::string protect(SeChannel& channel, uint8_t ins, uint8_t p1, uint8_t p2,
                           const std::string& data, bool extendedLength) {
  const std::vector<uint8_t> bytes = unhex(data);
  uint8_t out[200];
  const uint16_t length = seChannelProtect(channel, 0x80, ins, p1, p2, bytes.data(), (uint8_t)bytes.size(),
                                           extendedLength, out, sizeof(out));
  return hex(out, length);
}

static void checkSessionKeys() {
  const SeScpKeys keys = appSessionKeys();
  check(hex(keys.enc, 16) == "925a8a2ac0ce40a0e9d73c7d911ca334", "S-ENC");
  check(hex(keys.mac, 16) == "eec4750d680964192bf8cb5426948d22", "S-MAC");
  check(hex(keys.rmac, 16) == "50d62f453b2bbfb20931601378bdf77d", "S-RMAC");
  check(hex(keys.chain, 16) == "e7a3a1b1307eef744a282dbeaf8d5406", "first chaining value");
}

/// Three commands in a row: the counter steps and the MAC chains.
static void checkSecureMessaging() {
  SeChannel channel;
  seChannelBegin(channel, appSessionKeys());
  uint8_t out[96];

  check(protect(channel, 0x02, 0x00, 0x00, "410400000003", true) ==
        "8402000000001830e658c720910eb7decc14f31b915d19413685974ef9375e", "protected ReadObject");
  const int16_t read = openAnswer(channel, READ_ANSWER, 0x9000, out, sizeof(out));
  check(read == 67 && hex(out, 67) == "414104" + repeated("ab", 64), "ReadObject answer opened");

  const std::string pair = "1109" "08000000021820000041040000000142011043" "20" + repeated("11", 32)
                         + "4441" "04" + repeated("22", 64);
  check(protect(channel, 0x01, 0x61, 0x00, pair, false) ==
        "84016100886d4b1ec6f2e20eeae33461cbe67bdcc634824e9348be8faabd240eec3a12313f"
        "b0ea0a353de689475cbbb3860485b72b64078b55f48267088ce2965546da57448185e72287e44c10acbe1352ce57d563dd"
        "d238772dc5383a7dc08212d05fb747f5ea8552e344813c8c9261dcd582b509278b47c00ca0da86691e134abf93e0b8a75a"
        "486c1c26bb7a", "protected WriteECKey");
  check(openAnswer(channel, "8ea90aced232d8d7", 0x9000, out, sizeof(out)) == 0, "WriteECKey answer: its MAC alone");

  check(protect(channel, 0x04, 0x00, 0x1C, "-", false) == "8404001c085681e46604a16208", "protected empty command");
}

static void checkRefusedAnswers() {
  uint8_t out[96];
  SeChannel channel;
  seChannelBegin(channel, appSessionKeys());
  protect(channel, 0x02, 0x00, 0x00, "410400000003", true);
  std::vector<uint8_t> tampered = unhex(READ_ANSWER);
  tampered[3] ^= 0x01;
  check(seChannelOpen(channel, tampered.data(), (int16_t)tampered.size(), 0x9000, out, sizeof(out)) == -2,
        "an answer that does not authenticate is refused");

  seChannelBegin(channel, appSessionKeys());
  protect(channel, 0x02, 0x00, 0x00, "410400000003", true);
  check(openAnswer(channel, "-", 0x6985, out, sizeof(out)) == -1, "an error status is a refusal");
  check(openAnswer(channel, "0102030405", 0x9000, out, sizeof(out)) == -2, "an answer shorter than a MAC is refused");
}

/// ECKeySessionInternalAuthenticate's signed part, as AN12543 §3.6.3.3
/// and the app lay it out.
static void checkSignedPart() {
  uint8_t oneTime[65], signedPart[SE_ECKEY_SIGNED_LEN];
  oneTime[0] = 0x04;
  memset(oneTime + 1, 0xEE, 64);
  seECKeySignedPart(oneTime, signedPart);
  check(hex(signedPart, sizeof(signedPart)) == "a61d" "4f10a0000003965453000000010300000000" "9003ab0133" "800188"
        "810110" "7f4946" "b041" + hex(oneTime, sizeof(oneTime)) + "f00103", "signed part of the session request");
}

/// The temporary keys: new with every write, different for each purpose,
/// and never made without a random source.
static uint8_t randomRun = 0;
static void countingRandom(void* out, size_t len) {
  uint8_t* bytes = (uint8_t*)out;
  for (size_t i = 0; i < len; i++) bytes[i] = (uint8_t)(i * 7 + randomRun);
  randomRun++;
}

static void checkSessionKeyDerivation() {
  uint8_t wallet[32], a[32], b[32], c[32];
  for (int i = 0; i < 32; i++) wallet[i] = (uint8_t)(0x40 + i);

  coldSessionRandom = nullptr;
  check(!coldSessionKey(a, 'T', wallet), "no random source, no key");

  coldSessionRandom = countingRandom;
  check(coldSessionKey(a, 'T', wallet) && coldSessionKey(b, 'T', wallet), "temporary keys made");
  check(memcmp(a, b, 32) != 0, "a new key every time");
  randomRun = 0;
  check(coldSessionKey(c, 'E', wallet), "one-time key made");
  randomRun = 0;
  check(coldSessionKey(b, 'T', wallet) && memcmp(b, a, 32) == 0, "the same random bytes give the same key");
  check(memcmp(c, a, 32) != 0, "a different key for each purpose");
  wallet[0] ^= 1;
  randomRun = 0;
  check(coldSessionKey(b, 'T', wallet) && memcmp(b, a, 32) != 0, "the wallet key goes into it");
}

int main(int argc, char** argv) {
  if (argc < 2) {
    printf("usage: %s session_vectors.txt\n", argv[0]);
    return 2;
  }
  std::ifstream vectors(argv[1]);
  if (!vectors) {
    printf("cannot read %s\n", argv[1]);
    return 2;
  }

  int cases = 0;
  std::string kinds;
  for (std::string line; std::getline(vectors, line);) {
    const std::vector<std::string> f = split(line);
    if (f.empty()) continue;
    if (f[0] == "A" && f.size() == 4)      checkAes(f);
    else if (f[0] == "B" && f.size() == 5) checkCbc(f);
    else if (f[0] == "C" && f.size() == 4) checkCmac(f);
    else if (f[0] == "M" && f.size() == 4) checkHmac(f);
    else if (f[0] == "P" && f.size() == 5) checkP256(f);
    else if (f[0] == "S" && f.size() == 4) checkNodeSignature(f);
    else { check(false, "unreadable line: " + line.substr(0, 40)); continue; }
    if (kinds.find(f[0]) == std::string::npos) kinds += f[0];
    cases++;
  }
  check(kinds.size() == 6, "session_vectors.txt holds all six kinds of case");

  checkRfc6979();
  checkRejections();
  checkSessionKeys();
  checkSecureMessaging();
  checkRefusedAnswers();
  checkSignedPart();
  checkSessionKeyDerivation();

  return finish(std::to_string(cases) + " session cases");
}
