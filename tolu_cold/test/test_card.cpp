// The device's NFC code, compiled for this computer:
//   - its SE05x commands, against a pretend card that checks every byte;
//   - the encrypted write, against the same card running ECKey sessions;
//   - its phone-facing side, against sample taps;
//   - the PN532 transport both of those share, against a pretend PN532.
#include <algorithm>
#include <initializer_list>
#include <map>
#include <utility>
#include "test_support.h"
#include "test_p256.h"
#include "cold_target.h"
#include "cold_reader.h"
#include "cold_se05x.h"
#include "cold_session.h"

// ── A pretend SE05x ──────────────────────────────────────────
// Enough of the applet to accept what the firmware sends, and to refuse
// what a real card would refuse: a slot written twice, a key on a curve
// the card was never told, any read of the wallet key — which only the
// phone's own session may do — and a delete its policy does not allow.
// It opens ECKey sessions as the card does: it checks the signature with
// the stored key, agrees on keys with its own, checks every command's
// MAC, decrypts it, and MACs its answers.
class FakeCard {
 public:
  /// Every APDU received, as hex.
  std::vector<std::string> log;
  /// Every command run inside a session, as hex, as the card decrypted it.
  std::vector<std::string> sessionLog;
  /// Answer reads as 41 82 00 41 …, the long length form the real card uses.
  bool longFormReads = true;
  /// What CheckObjectExists answers, if not the truth (0 = the truth).
  uint8_t existsAnswer = 0;
  /// Answers the session's opening with a wrong receipt.
  bool spoilReceipt = false;
  /// Answers inside the session with a wrong MAC.
  bool spoilAnswers = false;
  /// Refuses every session signature, as for a key it does not hold.
  bool refuseSignatures = false;
  std::vector<uint8_t> uniqueId = unhex("04005001568873bd96295204561beac82190");

  std::vector<uint8_t> receive(const uint8_t* apdu, size_t len) {
    log.push_back(hex(apdu, len));
    return run(apdu, len);
  }

  std::vector<uint8_t> privateKey(uint32_t keyId) { return keys[keyId].privateKey; }
  uint32_t keyOwner(uint32_t keyId) { return keys[keyId].authId; }
  bool keyCameEncrypted(uint32_t keyId) { return keys[keyId].encrypted; }
  bool holds(uint32_t id) const { return authKeys.count(id) || keys.count(id); }
  void forgetCurves() { curves.clear(); }

  /// An authentication object with no policy of its own — the default
  /// lets nobody delete it.
  void plantAuthKey(uint32_t id, const std::vector<uint8_t>& point) { authKeys[id].point = point; }

 private:
  struct AuthKey {
    std::vector<uint8_t> point;
    std::map<uint32_t, uint32_t> rules;   // session → what it may do; empty = the default policy
  };
  struct KeyPair {
    std::vector<uint8_t> privateKey, publicKey;
    uint32_t authId = 0;
    bool encrypted = false;               // written inside a session
  };
  std::map<uint32_t, AuthKey> authKeys;   // ECKey authentication objects
  std::map<uint32_t, KeyPair> keys;
  std::vector<uint8_t> curves;

  // The card's own key for ECKey sessions, and its one session.
  std::vector<uint8_t> cardKey = unhex("51a7c0de51a7c0de51a7c0de51a7c0de51a7c0de51a7c0de51a7c0de51a7c0de");
  std::vector<uint8_t> sessionId = unhex("5e55105e55105e55");
  std::vector<uint8_t> challenge = unhex("c0c1c2c3c4c5c6c7c8c9cacbcccdcecf");
  uint32_t sessionAuth = 0;               // CreateSession was asked for this object
  bool sessionOpen = false;               // and its opening proven
  SeScpKeys sessionKeys;
  uint8_t counter[16], chain[16];
  uint32_t context = SE_DEFAULT_SESSION;  // the session the command at hand runs in

  static std::vector<uint8_t> answer(uint16_t statusWord, std::vector<uint8_t> data = {}) {
    data.push_back((uint8_t)(statusWord >> 8));
    data.push_back((uint8_t)statusWord);
    return data;
  }

  /// The value of a TLV, short form or 0x81. Written separately from the
  /// firmware's parser, so one cannot cover for the other.
  static std::vector<uint8_t> tlv(const uint8_t* body, size_t len, uint8_t tag) {
    for (size_t i = 0; i + 2 <= len;) {
      size_t length = body[i + 1], at = i + 2;
      if (length == 0x81) {
        if (at >= len) break;
        length = body[at++];
      }
      if (at + length > len) break;
      if (body[i] == tag) return std::vector<uint8_t>(body + at, body + at + length);
      i = at + length;
    }
    return {};
  }

  static uint32_t objectId(const std::vector<uint8_t>& value) {
    return value.size() == 4 ? coldLoadBe32(value.data()) : 0;
  }

  bool knowsCurve(const std::vector<uint8_t>& curve) const {
    return curve.size() == 1 && std::find(curves.begin(), curves.end(), curve[0]) != curves.end();
  }

  bool mayDelete(uint32_t id) const {
    const auto found = authKeys.find(id);
    if (found == authKeys.end()) return false;           // wallet keys carry no DELETE
    const auto rule = found->second.rules.find(context);
    return rule != found->second.rules.end() && (rule->second & SE_POLICY_DELETE);
  }

  std::vector<uint8_t> readAnswer(const std::vector<uint8_t>& value) const {
    std::vector<uint8_t> data = longFormReads
        ? std::vector<uint8_t>{ SE_TAG_1, 0x82, 0x00, (uint8_t)value.size() }
        : std::vector<uint8_t>{ SE_TAG_1, (uint8_t)value.size() };
    data.insert(data.end(), value.begin(), value.end());
    return answer(0x9000, data);
  }

  std::vector<uint8_t> run(const uint8_t* apdu, size_t len) {
    const uint8_t cla = apdu[0], ins = apdu[1], p1 = apdu[2], p2 = apdu[3];
    const uint8_t* body = apdu + 5;
    const size_t lc = len > 5 ? apdu[4] : 0;
    const uint32_t id = objectId(tlv(body, lc, SE_TAG_1));

    if (cla == ISO_CLA && ins == ISO_INS_SELECT) return answer(0x9000);

    if (ins == SE_INS_MGMT && p2 == SE_P2_RANDOM) {
      const uint8_t count = tlv(body, lc, SE_TAG_1)[1];
      std::vector<uint8_t> data = { SE_TAG_1, count };
      for (uint8_t i = 0; i < count; i++) data.push_back((uint8_t)(0xA0 + i));
      return answer(0x9000, data);
    }

    if (ins == SE_INS_MGMT && p2 == SE_P2_EXIST) {
      const uint8_t result = existsAnswer ? existsAnswer : (holds(id) ? SE_RESULT_SUCCESS : SE_RESULT_FAILURE);
      return answer(0x9000, { SE_TAG_1, 0x01, result });
    }

    if (ins == SE_INS_MGMT && p2 == SE_P2_DELETE_OBJECT) {
      if (!holds(id)) return answer(0x6A82);
      if (!mayDelete(id)) return answer(0x6986);
      authKeys.erase(id);
      return answer(0x9000);
    }

    if (ins == SE_INS_MGMT && p2 == SE_P2_SESSION_CREATE) {
      if (!authKeys.count(id)) return answer(0x6A82);
      sessionAuth = id;
      sessionOpen = false;
      std::vector<uint8_t> data = { SE_TAG_1, (uint8_t)sessionId.size() };
      data.insert(data.end(), sessionId.begin(), sessionId.end());
      return answer(0x9000, data);
    }

    if (ins == SE_INS_PROCESS) return processSession(body, lc);

    if (ins == SE_INS_WRITE && p1 == SE_P1_CURVE) {
      if (p2 == SE_P2_CREATE) curves.push_back(tlv(body, lc, SE_TAG_1)[0]);
      return answer(0x9000);
    }

    // An ECKey authentication object: the phone's key, or the device's
    // temporary one. Rules come in 9 bytes: 08, the session, the rights.
    if (ins == (SE_INS_WRITE | SE_INS_AUTH_OBJECT) && p1 == (SE_P1_PUBLIC | SE_P1_EC)) {
      if (holds(id)) return answer(0x6985);
      const std::vector<uint8_t> curve = tlv(body, lc, SE_TAG_2), point = tlv(body, lc, SE_TAG_4);
      if (curve != std::vector<uint8_t>{ SE_CURVE_NIST_P256 } || !knowsCurve(curve)) return answer(0x6985);
      if (point.size() != 65 || point[0] != 0x04) return answer(0x6A80);
      const std::vector<uint8_t> policy = tlv(body, lc, SE_TAG_POLICY);
      if (policy.size() % 9 != 0) return answer(0x6A80);
      AuthKey key;
      key.point = point;
      for (size_t at = 0; at < policy.size(); at += 9) {
        if (policy[at] != 8) return answer(0x6A80);
        key.rules[coldLoadBe32(policy.data() + at + 1)] = coldLoadBe32(policy.data() + at + 5);
      }
      authKeys[id] = key;
      return answer(0x9000);
    }

    if (ins == SE_INS_WRITE && p1 == (SE_P1_KEY_PAIR | SE_P1_EC)) {
      if (holds(id)) return answer(0x6985);
      if (!knowsCurve(tlv(body, lc, SE_TAG_2))) return answer(0x6985);
      const std::vector<uint8_t> policy = tlv(body, lc, SE_TAG_POLICY);
      KeyPair pair;
      pair.privateKey = tlv(body, lc, SE_TAG_3);
      pair.publicKey = tlv(body, lc, SE_TAG_4);
      if (policy.size() != 9 || pair.privateKey.size() != 32 || pair.publicKey.size() != 65) return answer(0x6A80);
      pair.authId = coldLoadBe32(policy.data() + 1);
      pair.encrypted = context != SE_DEFAULT_SESSION;
      keys[id] = pair;
      return answer(0x9000);
    }

    if (ins == SE_INS_READ) {
      if (id == SE_RESERVED_UNIQUE_ID) return readAnswer(uniqueId);
      if (id == SE_RESERVED_ECKEY_SESSION) {
        uint8_t point[65];
        coldP256PublicKey(cardKey.data(), point);
        return readAnswer(std::vector<uint8_t>(point, point + 65));
      }
      if (authKeys.count(id)) return readAnswer(authKeys[id].point);
      if (keys.count(id)) return answer(0x6985);     // only in the phone's session
      return answer(0x6A82);
    }

    return answer(0x6D00);
  }

  // ── Sessions ───────────────────────────────────────────────
  std::vector<uint8_t> processSession(const uint8_t* body, size_t lc) {
    const std::vector<uint8_t> id = tlv(body, lc, SE_TAG_SESSION_ID);
    const std::vector<uint8_t> inner = tlv(body, lc, SE_TAG_1);
    if (!sessionAuth || id != sessionId || inner.size() < 4) return answer(0x6985);
    return sessionOpen ? secureMessage(inner) : authenticate(inner);
  }

  /// ECKeySessionInternalAuthenticate: 84 88 00 00, a 1-byte Lc, no Le.
  std::vector<uint8_t> authenticate(const std::vector<uint8_t>& inner) {
    if (hex(inner.data(), 4) != "84880000") return answer(0x6D00);
    if (inner.size() < 5 || inner[4] == 0 || inner.size() != 5u + inner[4]) return answer(0x6A80);
    const std::vector<uint8_t> data(inner.begin() + 5, inner.end());

    // The request, laid out as AN12543 §3.6.3.3 has it.
    const std::string request = hex(data);
    const std::string head = "a61d4f10a00000039654530000000103000000009003ab0133800188810110" "7f4946" "b041";
    if (data.size() < 107 || request.compare(0, head.size(), head) != 0 || request.substr(202, 6) != "f00103" ||
        data[104] != 0x5F || data[105] != 0x37 || data.size() != 107u + data[106]) {
      return answer(0x6A80);
    }
    const std::vector<uint8_t> signedPart(data.begin(), data.begin() + 104);
    const std::vector<uint8_t> oneTimeKey(data.begin() + 36, data.begin() + 101);
    const std::vector<uint8_t> signature(data.begin() + 107, data.end());

    if (refuseSignatures || !p256Verify(authKeys[sessionAuth].point.data(), signedPart.data(), 104, signature)) {
      return answer(0x6982);
    }
    uint8_t secret[32], receipt[16];
    if (!coldP256Ecdh(cardKey.data(), oneTimeKey.data(), secret)) return answer(0x6A80);
    seScpKeys(sessionKeys, secret, challenge.data());
    coldAesCmac(sessionKeys.rmac, signedPart.data(), signedPart.size(), receipt);
    if (spoilReceipt) receipt[0] ^= 1;
    memset(counter, 0, sizeof(counter));
    counter[15] = 1;
    memcpy(chain, sessionKeys.chain, sizeof(chain));
    sessionOpen = true;

    std::vector<uint8_t> out = { SE_TAG_CHALLENGE, 16 };
    out.insert(out.end(), challenge.begin(), challenge.end());
    out.push_back(SE_TAG_RECEIPT);
    out.push_back(16);
    out.insert(out.end(), receipt, receipt + 16);
    return answer(0x9000, out);
  }

  void stepCounter() {
    for (int i = 15; i >= 0 && ++counter[i] == 0; i--) {}
  }

  /// A protected command: MAC checked, data decrypted, the command run in
  /// this session, the answer MAC'd (and its data encrypted).
  std::vector<uint8_t> secureMessage(const std::vector<uint8_t>& inner) {
    if (inner[0] != 0x84 || inner.size() < 5) return answer(0x6985);
    size_t headerLen = 5, lc = inner[4];
    if (lc == 0) {
      if (inner.size() < 7) return answer(0x6A80);
      headerLen = 7;
      lc = (size_t)((inner[5] << 8) | inner[6]);
    }
    if (inner.size() != headerLen + lc || lc < 8 || (lc - 8) % 16 != 0) return answer(0x6A80);
    const size_t encryptedLen = lc - 8;

    uint8_t mac[16];
    ColdCmac cmac;
    coldCmacBegin(cmac, sessionKeys.mac);
    coldCmacUpdate(cmac, chain, sizeof(chain));
    coldCmacUpdate(cmac, inner.data(), headerLen + encryptedLen);
    coldCmacEnd(cmac, mac);
    if (memcmp(mac, inner.data() + headerLen + encryptedLen, 8) != 0) {
      stepCounter();
      return answer(0x6982);
    }
    memcpy(chain, mac, sizeof(chain));

    ColdAes128 aes;
    coldAesKey(aes, sessionKeys.enc);
    std::vector<uint8_t> plain(inner.begin() + (long)headerLen, inner.begin() + (long)(headerLen + encryptedLen));
    if (!plain.empty()) {
      uint8_t iv[16];
      coldAesEncrypt(aes, counter, iv);
      coldAesCbcDecrypt(aes, iv, plain.data(), plain.size());
      while (!plain.empty() && plain.back() == 0x00) plain.pop_back();
      if (plain.empty() || plain.back() != 0x80) return answer(0x6A80);
      plain.pop_back();
    }

    std::vector<uint8_t> command = { 0x80, inner[1], inner[2], inner[3] };
    if (!plain.empty()) {
      command.push_back((uint8_t)plain.size());
      command.insert(command.end(), plain.begin(), plain.end());
    }
    sessionLog.push_back(hex(command));
    context = sessionAuth;
    std::vector<uint8_t> result = run(command.data(), command.size());
    context = SE_DEFAULT_SESSION;

    const uint16_t sw = (uint16_t)((result[result.size() - 2] << 8) | result.back());
    std::vector<uint8_t> data(result.begin(), result.end() - 2), out;
    if (sw == 0x9000) {
      if (!data.empty()) {
        data.push_back(0x80);
        while (data.size() % 16) data.push_back(0x00);
        uint8_t iv[16];
        memcpy(iv, counter, sizeof(iv));
        iv[0] = 0x80;
        coldAesEncrypt(aes, iv, iv);
        coldAesCbcEncrypt(aes, iv, data.data(), data.size());
        out = data;
      }
      const uint8_t status[2] = { 0x90, 0x00 };
      coldCmacBegin(cmac, sessionKeys.rmac);
      coldCmacUpdate(cmac, chain, sizeof(chain));
      coldCmacUpdate(cmac, out.data(), out.size());
      coldCmacUpdate(cmac, status, sizeof(status));
      coldCmacEnd(cmac, mac);
      if (spoilAnswers) mac[0] ^= 1;
      out.insert(out.end(), mac, mac + 8);
    }
    stepCounter();
    return answer(sw, out);
  }
};

static FakeCard card;

static int16_t exchangeWithFakeCard(const uint8_t* apdu, uint8_t apduLen, uint8_t* rsp, uint8_t rspSize) {
  const std::vector<uint8_t> response = card.receive(apdu, apduLen);
  if (response.size() > rspSize) return -4;
  memcpy(rsp, response.data(), response.size());
  return (int16_t)response.size();
}

// ── The SE05x commands ───────────────────────────────────────
static const uint32_t KEY_ID = 0x12222221, PHONE_KEY_ID = 0x12222222;
// The NIST P-256 generator, standing in for an iPhone's key — the same
// one toluWalletTests/PhoneKeyObjectTests.swift pins.
static const std::string PHONE_KEY =
  "046b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296"
  "4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5";

/// Stands in for the ESP32's generator: a different pattern every call.
static uint8_t randomCalls = 0;
static void patternRandom(void* out, size_t len) {
  uint8_t* bytes = (uint8_t*)out;
  for (size_t i = 0; i < len; i++) bytes[i] = (uint8_t)(0x31 * (i + 1) + randomCalls * 7);
  randomCalls++;
}

static void checkCardCommands() {
  se05xExchange = exchangeWithFakeCard;
  uint8_t privateKey[32], publicKey[65];
  for (int i = 0; i < 32; i++) privateKey[i] = (uint8_t)(i + 1);
  check(coldPublicKey(privateKey, publicKey), "public key");
  const std::vector<uint8_t> phoneKey = unhex(PHONE_KEY);

  check(se05xSelect(), "select");
  check(card.log.back() == "00a4040010a000000396545300000001030000000000", "SELECT bytes: " + card.log.back());

  uint8_t random[32];
  check(se05xGetRandom(random, sizeof(random)) && random[0] == 0xA0 && random[31] == 0xBF, "get random");
  check(card.log.back() == "80040049044102002000", "GetRandom bytes: " + card.log.back());

  uint8_t cardId[SE_UNIQUE_ID_LEN];
  check(se05xReadUniqueId(cardId) && hex(cardId, sizeof(cardId)) == hex(card.uniqueId), "unique id (long-form TLV)");
  check(card.log.back() == "800200000641047fff020600", "ReadObject (unique id) bytes: " + card.log.back());

  check(se05xExists(KEY_ID) == 0 && se05xPhoneKeySlot(PHONE_KEY_ID, phoneKey.data()) == 0, "both slots free");
  check(card.log.back() == "800400270641041222222200", "CheckObjectExists bytes: " + card.log.back());

  // A key on a curve the card was never told is refused — curves first.
  check(!se05xWritePhoneKey(PHONE_KEY_ID, phoneKey.data()) && se05xLastSW == 0x6985, "no P-256 yet: phone key refused");

  const size_t before = card.log.size();
  se05xInitCurves();
  check(card.log.size() == before + 12, "curves: two creates and ten parameters");
  check(card.log[before] == "80010b040341011000", "CreateECCurve (secp256k1) bytes: " + card.log[before]);
  check(card.log[before + 1] == "80010b402841011042011043" "20"
        "fffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f" "00",
        "secp256k1 prime bytes: " + card.log[before + 1]);
  check(card.log[before + 4] == "80010b404941011042010443" "41" "04"
        "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
        "483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8" "00",
        "secp256k1 generator bytes: " + card.log[before + 4]);
  check(card.log[before + 6] == "80010b040341010300", "CreateECCurve (P-256) bytes: " + card.log[before + 6]);
  check(card.log[before + 7] == "80010b402841010342011043" "20"
        "ffffffff00000001000000000000000000000000ffffffffffffffffffffffff" "00",
        "P-256 prime bytes: " + card.log[before + 7]);
  check(card.log[before + 9] == "80010b402841010342010243" "20"
        "5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b" "00",
        "P-256 b bytes: " + card.log[before + 9]);
  check(card.log[before + 10] == "80010b404941010342010443" "41" + PHONE_KEY + "00",
        "P-256 generator bytes: " + card.log[before + 10]);
  check(card.log[before + 11] == "80010b402841010342010843" "20"
        "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551" "00",
        "P-256 order bytes: " + card.log[before + 11]);

  check(se05xWritePhoneKey(PHONE_KEY_ID, phoneKey.data()), "write phone key");
  check(card.log.back() == "80412100" "4c" "410412222222" "420103" "4441" + PHONE_KEY + "00",
        "WriteECKey (phone key) bytes: " + card.log.back());
  check(se05xPhoneKeySlot(PHONE_KEY_ID, phoneKey.data()) == 1, "the slot holds this phone's key");
  std::vector<uint8_t> otherPhone = phoneKey;
  otherPhone[40] ^= 1;
  check(se05xPhoneKeySlot(PHONE_KEY_ID, otherPhone.data()) == 2, "another phone's key is told apart");
  card.longFormReads = false;
  check(se05xPhoneKeySlot(PHONE_KEY_ID, phoneKey.data()) == 1, "phone key read back (short-form TLV)");
  card.longFormReads = true;

  coldSessionRandom = patternRandom;
  const size_t sealedFrom = card.log.size();
  check(se05xImportKeyPairSealed(KEY_ID, PHONE_KEY_ID, COLD_TEMP_KEY_ID, privateKey, publicKey) == SE_SEALED_OK,
        "key written in an encrypted session");
  check(card.privateKey(KEY_ID) == std::vector<uint8_t>(privateKey, privateKey + 32), "card holds the private key");
  check(card.keyOwner(KEY_ID) == PHONE_KEY_ID, "the key is bound to the phone's key");
  check(card.keyCameEncrypted(KEY_ID), "the key arrived inside the session");
  check(!card.holds(COLD_TEMP_KEY_ID), "the temporary key is gone again");
  check(card.sessionLog.back() == "80016100" "79" "1109" "08" "12222222" "18200000" "410412222221" "420110"
        "4320" + hex(privateKey, 32) + "4441" + hex(publicKey, 65),
        "WriteECKey, as the card decrypted it: " + card.sessionLog.back());

  // What crossed the air, in order — and not one byte of the private key in the clear.
  const std::vector<std::string> air(card.log.begin() + (long)sealedFrom, card.log.end());
  bool clear = false;
  for (const std::string& apdu : air) clear = clear || apdu.find(hex(privateKey, 32)) != std::string::npos;
  check(!clear, "the private key never crossed the air in the clear");
  check(air.size() == 8, "eight commands: " + std::to_string(air.size()));
  if (air.size() == 8) {
    check(air[0] == "80040027064104" "7ffec01d" "00", "is the temporary slot free: " + air[0]);
    check(air[1].compare(0, 56, "80412100" "57" "1109" "08" "00000000" "00040000" "41047ffec01d" "420103" "4441" "04") == 0 &&
          air[1].size() == 2 * (5 + 0x57 + 1), "temporary key: deletable by the default session, nothing else: " + air[1]);
    check(air[2] == "800200000641047fff020100", "ReadObject (the card's session key): " + air[2]);
    check(air[3] == "8004001b064104" "7ffec01d" "00", "CreateSession for the temporary key: " + air[3]);
    check(air[4].compare(0, 8, "80050000") == 0 && air[4].compare(10, 20, "1008" "5e55105e55105e55") == 0 &&
          air[4].compare(30, 4, "4181") == 0 && air[4].compare(36, 8, "84880000") == 0 &&
          air[4].compare(46, 62, "a61d4f10a00000039654530000000103000000009003ab0133800188810110") == 0,
          "ECKeySessionInternalAuthenticate in ProcessSessionCmd: " + air[4].substr(0, 120));
    check(air[5].compare(0, 8, "80050000") == 0 && air[5].compare(30, 16, "41818d" "8401610088") == 0,
          "the key, encrypted, in ProcessSessionCmd: " + air[5].substr(0, 60));
    check(air[6] == "80040027064104" "7ffec01d" "00", "is the temporary key still there: " + air[6]);
    check(air[7] == "80040028064104" "7ffec01d" "00", "DeleteSecureObject (temporary key): " + air[7]);
  }

  // This device can't read the key back: only the phone's session may.
  uint8_t readBack[65];
  check(seReadObject(KEY_ID, readBack, sizeof(readBack)) < 0 && se05xLastSW == 0x6985, "the key can't be read here");

  // The slots are taken now: second writes are refused, the status word kept.
  check(se05xExists(KEY_ID) == 1, "key slot used");
  check(!se05xWritePhoneKey(PHONE_KEY_ID, phoneKey.data()) && se05xLastSW == 0x6985, "phone key can't be replaced");
  check(se05xImportKeyPairSealed(KEY_ID, PHONE_KEY_ID, COLD_TEMP_KEY_ID, privateKey, publicKey) ==
        SE_SEALED_KEY_REFUSED && se05xLastSW == 0x6985, "second key write refused");
  check(!card.holds(COLD_TEMP_KEY_ID), "the temporary key is removed after a refusal too");

  // An answer CheckObjectExists does not define is "didn't say", never "free".
  card.existsAnswer = 0x07;
  check(se05xExists(0x12345678) == -1, "an unknown CheckObjectExists answer is not a free slot");
  card.existsAnswer = 0;

  // A TLV length of 0x8000 or more must not wrap negative and read before the buffer.
  const uint8_t hostile[] = { 0x99, 0x82, 0xFF, 0xF0, 0x41, 0x01, 0x00 };
  uint16_t found = 0;
  check(seFind(hostile, sizeof(hostile), SE_TAG_1, &found) == nullptr, "a huge TLV length is refused");

  // A command too long for the buffer is never sent.
  const size_t sent = card.log.size();
  const uint8_t big[250] = { 0 };
  uint8_t rsp[8];
  SeApdu apdu;
  seStart(apdu, SE_INS_WRITE, SE_P1_DEFAULT, SE_P2_DEFAULT);
  seTlv(apdu, SE_TAG_1, big, sizeof(big));
  seFinish(apdu);
  check(seSend(apdu, rsp, sizeof(rsp)) == -1 && card.log.size() == sent, "oversized command not sent");
}

// ── The encrypted write, when things go wrong ────────────────
/// A new card with both curves and the phone's key: what the write finds.
static void freshCard() {
  card = FakeCard();
  se05xInitCurves();
  se05xWritePhoneKey(PHONE_KEY_ID, unhex(PHONE_KEY).data());
}

static SeSealedResult writeSealed(const uint8_t privateKey[32], const uint8_t publicKey[65]) {
  return se05xImportKeyPairSealed(KEY_ID, PHONE_KEY_ID, COLD_TEMP_KEY_ID, privateKey, publicKey);
}

static void checkSealedWrite() {
  coldSessionRandom = patternRandom;
  uint8_t privateKey[32], publicKey[65];
  for (int i = 0; i < 32; i++) privateKey[i] = (uint8_t)(0x80 + i);
  coldPublicKey(privateKey, publicKey);
  std::vector<uint8_t> someKey(COLD_P256_G, COLD_P256_G + 65);

  // An earlier try that stopped half-way left its temporary key: it goes first.
  freshCard();
  check(se05xWriteSessionKey(COLD_TEMP_KEY_ID, someKey.data()), "a leftover temporary key");
  check(writeSealed(privateKey, publicKey) == SE_SEALED_OK && card.keyCameEncrypted(KEY_ID) &&
        !card.holds(COLD_TEMP_KEY_ID), "a leftover is removed and the write goes ahead");

  // Something in the slot this device may not delete: stop, and write nothing.
  freshCard();
  card.plantAuthKey(COLD_TEMP_KEY_ID, someKey);
  check(writeSealed(privateKey, publicKey) == SE_SEALED_SLOT_TAKEN && !card.holds(KEY_ID),
        "a slot that can't be freed stops the write");

  // A receipt that does not match: the keys differ, or someone changed the
  // request. Nothing goes through the session, and the temporary key goes.
  freshCard();
  card.spoilReceipt = true;
  check(writeSealed(privateKey, publicKey) == SE_SEALED_TAMPERED && !card.holds(KEY_ID) &&
        !card.holds(COLD_TEMP_KEY_ID), "a bad receipt: no key sent, temporary key removed");

  // An answer inside the session that does not authenticate.
  freshCard();
  card.spoilAnswers = true;
  check(writeSealed(privateKey, publicKey) == SE_SEALED_TAMPERED && !card.holds(COLD_TEMP_KEY_ID),
        "an answer with a bad MAC is not taken for a success");

  // The card turns the session down.
  freshCard();
  card.refuseSignatures = true;
  check(writeSealed(privateKey, publicKey) == SE_SEALED_NO_SESSION && se05xLastSW == 0x6982 &&
        !card.holds(KEY_ID) && !card.holds(COLD_TEMP_KEY_ID), "a refused session: its status word kept, nothing left");

  // No random source: no keys, no write.
  freshCard();
  coldSessionRandom = nullptr;
  check(writeSealed(privateKey, publicKey) == SE_SEALED_NO_SESSION && !card.holds(KEY_ID) &&
        !card.holds(COLD_TEMP_KEY_ID), "no random source, nothing written");
  coldSessionRandom = patternRandom;

  // Two writes, two different temporary keys.
  freshCard();
  writeSealed(privateKey, publicKey);
  const std::string first = card.log[card.log.size() - 7];
  freshCard();
  writeSealed(privateKey, publicKey);
  const std::string second = card.log[card.log.size() - 7];
  check(first.compare(0, 8, "80412100") == 0 && second.compare(0, 8, "80412100") == 0 && first != second,
        "every write brings a new temporary key");
}

// ── The phone's tap ──────────────────────────────────────────
static const std::vector<uint8_t> GOOD_SETUP = unhex("02" "12222221" "12222222" + PHONE_KEY);

/// GOOD_SETUP with some of its bytes replaced.
static std::vector<uint8_t> setupWith(std::initializer_list<std::pair<size_t, uint8_t>> changes) {
  std::vector<uint8_t> record = GOOD_SETUP;
  for (const auto& change : changes) record[change.first] = change.second;
  return record;
}

static bool parses(const std::vector<uint8_t>& record, size_t length) {
  ColdSetup setup;
  return targetParseSetup(record.data(), (uint8_t)length, setup);
}

static void checkSetupParser() {
  ColdSetup setup;
  check(targetParseSetup(GOOD_SETUP.data(), (uint8_t)GOOD_SETUP.size(), setup) && setup.keyId == KEY_ID &&
        setup.phoneKeyId == PHONE_KEY_ID && hex(setup.phoneKey, sizeof(setup.phoneKey)) == PHONE_KEY,
        "setup parsed");

  const size_t whole = GOOD_SETUP.size();
  check(!parses(setupWith({ { 0, 0x01 } }), whole), "the first firmware's password setup refused");
  check(!parses(setupWith({ { 0, 0x03 } }), whole), "unknown version refused");
  check(!parses(setupWith({ { 8, 0x21 } }), whole), "the same slot twice refused");
  check(!parses(setupWith({ { 1, 0x7F }, { 2, 0xFF } }), whole), "a slot in the card's reserved range refused");
  check(!parses(setupWith({ { 1, 0 }, { 2, 0 }, { 3, 0 }, { 4, 0 } }), whole), "slot zero refused");
  check(!parses(setupWith({ { 5, 0x7F }, { 6, 0xFE }, { 7, 0xC0 }, { 8, 0x1D } }), whole),
        "the slot this device borrows refused");
  check(!parses(setupWith({ { 9, 0x02 } }), whole), "a compressed phone key refused");
  check(!parses(setupWith({}), whole - 1), "a truncated record refused");
  std::vector<uint8_t> longer = GOOD_SETUP;
  longer.push_back(0x00);
  check(!parses(longer, longer.size()), "a record with extra bytes refused");
}

static std::vector<uint8_t> setupApdu() {
  std::vector<uint8_t> apdu = { 0x80, 0x20, 0x00, 0x00, (uint8_t)GOOD_SETUP.size() };
  apdu.insert(apdu.end(), GOOD_SETUP.begin(), GOOD_SETUP.end());
  return apdu;
}

static const std::vector<uint8_t> SELECT_COLD = {
  0x00, 0xA4, 0x04, 0x00, 0x09, 0xF0, 0x74, 0x6F, 0x6C, 0x75, 0x43, 0x4F, 0x4C, 0x44, 0x00
};

static const std::vector<uint8_t> CANCEL = { 0x80, COLD_INS_CANCEL, 0x00, 0x00 };

/// The status word the device last answered with, as it went to the PN532.
static std::string lastReply() { return hex(pn532spi.sent.back()); }

static void checkCommandHandler() {
  ColdTap tap;
  pn532spi.sent.clear();

  check(targetHandle(SELECT_COLD.data(), (int16_t)SELECT_COLD.size(), tap) && lastReply() == "8e9000",
        "our AID selected");

  const uint8_t otherAid[] = { 0x00, 0xA4, 0x04, 0x00, 0x08, 0xF0, 0x74, 0x6F, 0x6C, 0x75, 0x50, 0x4F, 0x53, 0x00 };
  check(targetHandle(otherAid, sizeof(otherAid), tap) && lastReply() == "8e6a82", "another AID refused with 6A82");

  const uint8_t unknown[] = { 0x80, 0x99, 0x00, 0x00 };
  check(targetHandle(unknown, sizeof(unknown), tap) && lastReply() == "8e6d00",
        "unknown instruction refused with 6D00");

  const uint8_t tooShort[] = { 0x80, 0x20, 0x00 };
  check(targetHandle(tooShort, sizeof(tooShort), tap) && lastReply() == "8e6700", "three bytes refused with 6700");

  std::vector<uint8_t> apdu = setupApdu();
  check(targetHandle(apdu.data(), (int16_t)(apdu.size() - 1), tap) && lastReply() == "8e6700",
        "setup cut short refused with 6700");

  apdu[5] = 0x09;                                   // unknown version
  check(targetHandle(apdu.data(), (int16_t)apdu.size(), tap) && lastReply() == "8e6a80",
        "bad setup refused with 6A80");
  check(!tap.askedForSomething(), "nothing refused counts as a request");

  apdu = setupApdu();
  check(!targetHandle(apdu.data(), (int16_t)apdu.size(), tap) && tap.setup.complete && !tap.cancel &&
        lastReply() == "8e9000", "setup accepted, conversation over");

  ColdTap cancelTap;
  check(!targetHandle(CANCEL.data(), (int16_t)CANCEL.size(), cancelTap) && cancelTap.cancel &&
        !cancelTap.setup.complete && lastReply() == "8e9000", "cancel accepted, conversation over");

  // iOS may add a zero Le or Lc to a command with no data.
  const uint8_t cancelWithLe[] = { 0x80, COLD_INS_CANCEL, 0x00, 0x00, 0x00 };
  ColdTap leTap;
  check(!targetHandle(cancelWithLe, sizeof(cancelWithLe), leTap) && leTap.cancel, "cancel with a trailing zero accepted");
}

/// A PN532 answer: the status byte, then data.
static std::vector<uint8_t> framed(const std::vector<uint8_t>& data, uint8_t status = 0x00) {
  std::vector<uint8_t> frame = { status };
  frame.insert(frame.end(), data.begin(), data.end());
  return frame;
}

/// Whole taps, the way the main loop sees them.
static void checkWholeTap() {
  const std::vector<uint8_t> ack = { 0x00 };

  pn532spi.sent.clear();
  check(targetArm() && pn532spi.sent.back().size() == 38 && pn532spi.sent.back()[0] == PN532_COMMAND_TGINITASTARGET,
        "armed as a card");

  ColdTap nobody;
  pn532spi.answers = { {} };                                      // nothing in the field
  check(targetCheck(nobody, 60) == 0 && !nobody.askedForSomething(), "no phone yet: keep waiting");

  ColdTap setupTap;
  pn532spi.sent.clear();
  pn532spi.answers = { ack, framed(SELECT_COLD), ack, framed(setupApdu()), ack };
  check(targetCheck(setupTap, 60) == 1 && setupTap.setup.complete && setupTap.setup.keyId == KEY_ID,
        "a tap delivers the setup");
  check(pn532spi.sent.size() == 4 && hex(pn532spi.sent[0]) == "86" && hex(pn532spi.sent[1]) == "8e9000" &&
        hex(pn532spi.sent[2]) == "86" && hex(pn532spi.sent[3]) == "8e9000", "two commands, two answers");

  ColdTap cancelTap;
  pn532spi.answers = { ack, framed(SELECT_COLD), ack, framed(CANCEL), ack };
  check(targetCheck(cancelTap, 60) == 1 && cancelTap.cancel && !cancelTap.setup.complete, "a tap delivers a cancel");

  ColdTap dropped;
  pn532spi.answers = { ack, framed({}, 0x29) };                   // the phone left mid-way
  check(targetCheck(dropped, 60) == -1 && !dropped.askedForSomething(), "a tap that drops asks for a re-arm");

  ColdTap onlySelected;
  pn532spi.answers = { ack, framed(SELECT_COLD), ack, framed({}, 0x29) };
  check(targetCheck(onlySelected, 60) == -1, "selecting us and leaving asks for nothing");
  pn532spi.answers.clear();
}

// ── The transport under both ─────────────────────────────────
static void checkTransport() {
  const uint8_t apdu[] = { 0x80, 0x04, 0x00, 0x27 };
  uint8_t rsp[8];

  pn532spi.sent.clear();
  pn532spi.answers = { framed({ 0x41, 0x01, 0x02, 0x90, 0x00 }) };
  check(readerExchange(apdu, sizeof(apdu), rsp, sizeof(rsp)) == 5 && rsp[0] == 0x41 && rsp[4] == 0x00,
        "card answer returned without the status byte");
  check(hex(pn532spi.sent.back()) == "400180040027", "InDataExchange to target 1");

  pn532spi.answers = { {} };
  check(readerExchange(apdu, sizeof(apdu), rsp, sizeof(rsp)) == -2, "no answer reported");
  pn532spi.answers = { framed({}, 0x01) };
  check(readerExchange(apdu, sizeof(apdu), rsp, sizeof(rsp)) == -3, "RF error reported");
  pn532spi.answers = { framed(std::vector<uint8_t>(sizeof(rsp) + 1, 0xEE)) };
  check(readerExchange(apdu, sizeof(apdu), rsp, sizeof(rsp)) == -4, "an answer too long for the buffer refused");

  check(nfcFieldOff() && hex(pn532spi.sent.back()) == "320100", "RF field switched off");
}

int main() {
  checkCardCommands();
  const size_t cardApdus = card.log.size();
  checkSealedWrite();
  checkSetupParser();
  checkCommandHandler();
  checkWholeTap();
  checkTransport();
  return finish(std::to_string(cardApdus) + " APDUs exchanged with the pretend card, then the failure cases");
}
