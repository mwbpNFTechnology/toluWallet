// The device's NFC code, compiled for this computer:
//   - its SE05x commands, against a pretend card that checks every byte;
//   - its phone-facing side, against sample taps;
//   - the PN532 transport both of those share, against a pretend PN532.
#include <initializer_list>
#include <map>
#include <utility>
#include "test_support.h"
#include "cold_target.h"
#include "cold_reader.h"
#include "cold_se05x.h"

// ── A pretend SE05x ──────────────────────────────────────────
// Enough of the applet to accept what the firmware sends, and to refuse
// what a real card would refuse: a slot written twice, a read outside
// a password session, a password tried too often.
class FakeCard {
 public:
  /// Every APDU received, as hex.
  std::vector<std::string> log;
  /// Answer reads as 41 82 00 41 …, the long length form the real card uses.
  bool longFormReads = true;

  std::vector<uint8_t> receive(const uint8_t* apdu, size_t len) {
    log.push_back(hex(apdu, len));
    return run(apdu, len, false);
  }

  uint16_t attemptLimit(uint32_t passwordId) { return passwords[passwordId].maxAttempts; }
  std::vector<uint8_t> privateKey(uint32_t keyId) { return keys[keyId].privateKey; }

 private:
  struct Password {
    std::vector<uint8_t> value;
    uint16_t maxAttempts = 0, failed = 0;
  };
  struct KeyPair {
    std::vector<uint8_t> privateKey, publicKey;
    uint32_t authId = 0;
  };

  std::map<uint32_t, Password> passwords;
  std::map<uint32_t, KeyPair> keys;
  uint32_t sessionAuth = 0;
  bool sessionOpen = false;

  static std::vector<uint8_t> answer(uint16_t statusWord, std::vector<uint8_t> data = {}) {
    data.push_back((uint8_t)(statusWord >> 8));
    data.push_back((uint8_t)statusWord);
    return data;
  }

  /// The value of a short-form TLV. Written separately from the
  /// firmware's parser, so one cannot cover for the other.
  static std::vector<uint8_t> tlv(const uint8_t* body, size_t len, uint8_t tag) {
    for (size_t i = 0; i + 2 <= len; i += 2 + body[i + 1]) {
      if (body[i] == tag && i + 2 + body[i + 1] <= len) {
        return std::vector<uint8_t>(body + i + 2, body + i + 2 + body[i + 1]);
      }
    }
    return {};
  }

  static uint32_t objectId(const std::vector<uint8_t>& value) {
    return value.size() == 4 ? coldLoadBe32(value.data()) : 0;
  }

  std::vector<uint8_t> run(const uint8_t* apdu, size_t len, bool inSession) {
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
      const bool exists = passwords.count(id) || keys.count(id);
      return answer(0x9000, { SE_TAG_1, 0x01, (uint8_t)(exists ? 0x01 : 0x02) });
    }

    if (ins == SE_INS_WRITE && p1 == SE_P1_CURVE) return answer(0x9000);

    if (ins == (SE_INS_WRITE | SE_INS_AUTH_OBJECT) && p1 == SE_P1_USERID) {
      if (passwords.count(id)) return answer(0x6985);
      const std::vector<uint8_t> attempts = tlv(body, lc, SE_TAG_MAX_ATTEMPTS);
      Password password;
      password.value = tlv(body, lc, SE_TAG_2);
      password.maxAttempts = attempts.size() == 2 ? (uint16_t)((attempts[0] << 8) | attempts[1]) : 0;
      passwords[id] = password;
      return answer(0x9000);
    }

    if (ins == SE_INS_WRITE && p1 == (SE_P1_KEY_PAIR | SE_P1_EC)) {
      if (keys.count(id)) return answer(0x6985);
      const std::vector<uint8_t> policy = tlv(body, lc, SE_TAG_POLICY);
      KeyPair pair;
      pair.privateKey = tlv(body, lc, SE_TAG_3);
      pair.publicKey = tlv(body, lc, SE_TAG_4);
      if (policy.size() != 9 || pair.privateKey.size() != 32 || pair.publicKey.size() != 65) return answer(0x6A80);
      pair.authId = coldLoadBe32(policy.data() + 1);
      keys[id] = pair;
      return answer(0x9000);
    }

    if (ins == SE_INS_MGMT && p2 == SE_P2_SESSION_CREATE) {
      sessionAuth = id;
      sessionOpen = false;
      if (!passwords.count(id)) return answer(0x6A82);
      return answer(0x9000, { SE_TAG_1, 0x08, 1, 2, 3, 4, 5, 6, 7, 8 });
    }

    if (ins == SE_INS_PROCESS) {
      if (tlv(body, lc, SE_TAG_SESSION_ID) != std::vector<uint8_t>{ 1, 2, 3, 4, 5, 6, 7, 8 }) return answer(0x6985);
      const std::vector<uint8_t> inner = tlv(body, lc, SE_TAG_1);
      return run(inner.data(), inner.size(), true);
    }

    if (inSession && ins == SE_INS_MGMT && p2 == SE_P2_SESSION_USERID) {
      Password& password = passwords[sessionAuth];
      if (password.maxAttempts && password.failed >= password.maxAttempts) return answer(0x6985);
      if (tlv(body, lc, SE_TAG_1) != password.value) {
        password.failed++;
        return answer(0x6985);
      }
      password.failed = 0;
      sessionOpen = true;
      return answer(0x9000);
    }

    if (ins == SE_INS_READ) {
      if (!keys.count(id)) return answer(0x6A82);
      if (!(inSession && sessionOpen && sessionAuth == keys[id].authId)) return answer(0x6985);
      std::vector<uint8_t> data = longFormReads ? std::vector<uint8_t>{ SE_TAG_1, 0x82, 0x00, 0x41 }
                                                : std::vector<uint8_t>{ SE_TAG_1, 0x41 };
      data.insert(data.end(), keys[id].publicKey.begin(), keys[id].publicKey.end());
      return answer(0x9000, data);
    }

    return answer(0x6D00);
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
static const uint32_t KEY_ID = 0x12222221, PASSWORD_ID = 0x12222222;
static const uint8_t PASSWORD[6] = { 'a', 'b', 'c', 'd', 'e', 'f' };

static void checkCardCommands() {
  se05xExchange = exchangeWithFakeCard;

  uint8_t privateKey[32], publicKey[65];
  for (int i = 0; i < 32; i++) privateKey[i] = (uint8_t)(i + 1);
  check(coldPublicKey(privateKey, publicKey), "public key");

  check(se05xSelect(), "select");
  check(card.log.back() == "00a4040010a000000396545300000001030000000000", "SELECT bytes: " + card.log.back());

  uint8_t random[32];
  check(se05xGetRandom(random, sizeof(random)) && random[0] == 0xA0 && random[31] == 0xBF, "get random");
  check(card.log.back() == "80040049044102002000", "GetRandom bytes: " + card.log.back());

  check(se05xExists(KEY_ID) == 0 && se05xExists(PASSWORD_ID) == 0, "both slots free");
  check(card.log.back() == "800400270641041222222200", "CheckObjectExists bytes: " + card.log.back());

  const size_t before = card.log.size();
  se05xInitCurve();
  check(card.log.size() == before + 6, "curve: one create and five parameters");
  check(card.log[before] == "80010b040341011000", "CreateECCurve bytes: " + card.log[before]);
  check(card.log[before + 1] == "80010b402841011042011043" "20"
        "fffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f" "00",
        "curve prime bytes: " + card.log[before + 1]);
  check(card.log[before + 3] == "80010b402841011042010243" "20"
        "0000000000000000000000000000000000000000000000000000000000000007" "00",
        "curve b bytes: " + card.log[before + 3]);
  check(card.log[before + 4] == "80010b404941011042010443" "41" "04"
        "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
        "483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8" "00",
        "curve generator bytes: " + card.log[before + 4]);
  check(card.log[before + 5] == "80010b402841011042010843" "20"
        "fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141" "00",
        "curve order bytes: " + card.log[before + 5]);

  check(se05xCreatePassword(PASSWORD_ID, PASSWORD, sizeof(PASSWORD), 5), "create password");
  check(card.log.back() == "80410700" "12" "12020005" "410412222222" "4206616263646566" "00",
        "WriteUserID bytes: " + card.log.back());
  check(card.attemptLimit(PASSWORD_ID) == 5, "attempt limit stored as 5");

  check(se05xImportKeyPair(KEY_ID, PASSWORD_ID, privateKey, publicKey), "import key pair");
  check(card.log.back() == "80016100" "79" "1109" "08" "12222222" "18200000" "410412222221" "420110"
        "4320" + hex(privateKey, 32) + "4441" + hex(publicKey, 65) + "00",
        "WriteECKey bytes: " + card.log.back());
  check(card.privateKey(KEY_ID) == std::vector<uint8_t>(privateKey, privateKey + 32), "card holds the private key");

  uint8_t session[SE_SESSION_ID_LEN];
  check(se05xOpenSession(PASSWORD_ID, PASSWORD, sizeof(PASSWORD), session), "open session");
  check(card.log[card.log.size() - 2] == "8004001b0641041222222200",
        "CreateSession bytes: " + card.log[card.log.size() - 2]);
  check(card.log.back() == "80050000" "1a" "10080102030405060708" "410e" "8004002c084106616263646566" "00" "00",
        "VerifySessionUserID bytes: " + card.log.back());

  check(se05xKeyMatches(session, KEY_ID, publicKey), "key read back (long-form TLV)");
  check(card.log.back() == "80050000" "18" "10080102030405060708" "410c" "800200000641041222222100" "00",
        "ReadObject bytes: " + card.log.back());
  card.longFormReads = false;
  check(se05xKeyMatches(session, KEY_ID, publicKey), "key read back (short-form TLV)");
  uint8_t otherKey[65];
  memcpy(otherKey, publicKey, sizeof(otherKey));
  otherKey[20] ^= 1;
  check(!se05xKeyMatches(session, KEY_ID, otherKey), "a different key is not a match");

  // The slots are taken now: a second write is refused, and the status word kept.
  check(se05xExists(KEY_ID) == 1 && se05xExists(PASSWORD_ID) == 1, "both slots used");
  check(!se05xCreatePassword(PASSWORD_ID, PASSWORD, sizeof(PASSWORD), 5) && se05xLastSW == 0x6985,
        "second password write refused, status word kept");
  check(!se05xImportKeyPair(KEY_ID, PASSWORD_ID, privateKey, publicKey) && se05xLastSW == 0x6985,
        "second key write refused");

  // Five wrong passwords lock the object — after that even the right one fails.
  const uint8_t wrong[6] = { 'x', 'x', 'x', 'x', 'x', 'x' };
  for (int attempt = 0; attempt < 5; attempt++) {
    check(!se05xOpenSession(PASSWORD_ID, wrong, sizeof(wrong), session), "wrong password refused");
  }
  check(!se05xOpenSession(PASSWORD_ID, PASSWORD, sizeof(PASSWORD), session), "locked after five wrong tries");

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

// ── The phone's tap ──────────────────────────────────────────
static const uint8_t GOOD_SETUP[] = {
  0x01, 0x12, 0x22, 0x22, 0x21, 0x12, 0x22, 0x22, 0x22, 6, 'a', 'b', 'c', 'd', 'e', 'f'
};

/// GOOD_SETUP with some of its bytes replaced.
static std::vector<uint8_t> setupWith(std::initializer_list<std::pair<size_t, uint8_t>> changes) {
  std::vector<uint8_t> record(GOOD_SETUP, GOOD_SETUP + sizeof(GOOD_SETUP));
  for (const auto& change : changes) record[change.first] = change.second;
  return record;
}

static bool parses(const std::vector<uint8_t>& record, size_t length) {
  ColdSetup setup;
  return targetParseSetup(record.data(), (uint8_t)length, setup);
}

static void checkSetupParser() {
  ColdSetup setup;
  check(targetParseSetup(GOOD_SETUP, sizeof(GOOD_SETUP), setup) && setup.keyId == KEY_ID &&
        setup.passwordId == PASSWORD_ID && setup.passwordLen == 6 && memcmp(setup.password, "abcdef", 6) == 0,
        "setup parsed");

  const size_t whole = sizeof(GOOD_SETUP);
  check(!parses(setupWith({ { 0, 0x02 } }), whole), "unknown version refused");
  check(!parses(setupWith({ { 8, 0x21 } }), whole), "the same slot twice refused");
  check(!parses(setupWith({ { 1, 0x7F }, { 2, 0xFF } }), whole), "a slot in the card's reserved range refused");
  check(!parses(setupWith({ { 1, 0 }, { 2, 0 }, { 3, 0 }, { 4, 0 } }), whole), "slot zero refused");
  check(!parses(setupWith({ { 9, 3 } }), COLD_SETUP_HEADER_LEN + 3), "a 3-character password refused");
  check(!parses(setupWith({ { 9, 17 } }), whole), "a password longer than the record refused");
  check(!parses(setupWith({}), whole - 1), "a truncated record refused");
}

static std::vector<uint8_t> setupApdu() {
  std::vector<uint8_t> apdu = { 0x80, 0x20, 0x00, 0x00, (uint8_t)sizeof(GOOD_SETUP) };
  apdu.insert(apdu.end(), GOOD_SETUP, GOOD_SETUP + sizeof(GOOD_SETUP));
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
  checkSetupParser();
  checkCommandHandler();
  checkWholeTap();
  checkTransport();
  return finish(std::to_string(card.log.size()) + " APDUs exchanged with the pretend card");
}
