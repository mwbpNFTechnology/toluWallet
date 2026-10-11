// ============================================================
// cold_target.h - the PN532 as a card, so the phone can hand over
//                 the wallet's slots and password
// ============================================================
// An iPhone cannot act as a card towards another reader, but it is
// already an ISO 7816 reader for the tolu card. So the PN532 goes into
// target mode and plays an ISO-DEP smart card, and the phone writes
// to it:
//
//   phone → SELECT F0746F6C75434F4C44          → 9000
//   phone → 80 20 00 00 <Lc> <setup>           → 9000     start a wallet
//   phone → 80 21 00 00                        → 9000     cancel
//
//   setup = 01                      format version
//           <key object id, 4>      where the secp256k1 key will live
//           <password object id, 4> where the password that guards it lives
//           <n> <password, n>       4..16 bytes
//
// The phone can do this at any point up to the finished wallet: a
// setup starts the ceremony (over again, if one was running) and a
// cancel ends it.
//
// Nothing secret about the wallet's KEY crosses here — the key does not
// exist yet, and when it does it never leaves this device and the card.
// ============================================================
#ifndef COLD_TARGET_H
#define COLD_TARGET_H

#include "cold_pn532.h"

// F0 = a proprietary AID, then "toluCOLD" in ASCII.
static const uint8_t COLD_AID[] = { 0xF0, 0x74, 0x6F, 0x6C, 0x75, 0x43, 0x4F, 0x4C, 0x44 };

// The two things the phone can ask for (CLA 80).
#define COLD_INS_SETUP          0x20
#define COLD_INS_CANCEL         0x21

#define COLD_SETUP_VERSION      0x01
#define COLD_SETUP_HEADER_LEN   10     // version + two object ids + password length
#define COLD_PASSWORD_MIN       4
#define COLD_PASSWORD_MAX       16
// Object ids 0x7FFFxxxx are the card's own (NXP reserved).
#define SE_RESERVED_ID_PREFIX   0x7FFF

// ISO 7816 status words this "card" answers with.
#define SW_OK                   0x9000
#define SW_WRONG_LENGTH         0x6700
#define SW_WRONG_DATA           0x6A80
#define SW_FILE_NOT_FOUND       0x6A82
#define SW_INS_NOT_SUPPORTED    0x6D00

#define TARGET_REPLY_TIMEOUT_MS    800
#define TARGET_COMMAND_TIMEOUT_MS  1200
// The app needs two commands. A reader that is still talking after
// this many is something else.
#define TARGET_MAX_COMMANDS        12

/// The slots and password of a new wallet.
struct ColdSetup {
  uint32_t keyId = 0;
  uint32_t passwordId = 0;
  uint8_t  password[COLD_PASSWORD_MAX];
  uint8_t  passwordLen = 0;
  bool     complete = false;

  void reset() {
    coldWipe(password, sizeof(password));
    keyId = 0;
    passwordId = 0;
    passwordLen = 0;
    complete = false;
  }
};

/// What one tap of the phone asked for.
struct ColdTap {
  bool      cancel = false;   // stop whatever is going on
  ColdSetup setup;            // complete when a setup arrived: start with it

  bool askedForSomething() const { return cancel || setup.complete; }
};

/// TgSetData — the status word that answers the phone's last command.
static inline bool targetReply(uint16_t statusWord) {
  const uint8_t header = PN532_COMMAND_TGSETDATA;
  const uint8_t body[2] = { (uint8_t)(statusWord >> 8), (uint8_t)statusWord };
  return nfcCommand(&header, 1, body, sizeof(body), TARGET_REPLY_TIMEOUT_MS);
}

/// TgGetData — whatever the phone just sent. Returns the length, or <0
/// when the phone is gone or the exchange broke down.
static inline int16_t targetReceive(uint8_t* out, uint8_t outSize) {
  const uint8_t header = PN532_COMMAND_TGGETDATA;
  return nfcExchange(&header, 1, nullptr, 0, out, outSize, TARGET_COMMAND_TIMEOUT_MS);
}

/// Reads the setup record out of an APDU body. Rejects anything that
/// could not be a valid wallet, so a bad tap never reaches the card.
static inline bool targetParseSetup(const uint8_t* body, uint8_t len, ColdSetup& setup) {
  if (len < COLD_SETUP_HEADER_LEN || body[0] != COLD_SETUP_VERSION) return false;
  const uint8_t passwordLen = body[9];
  if (passwordLen < COLD_PASSWORD_MIN || passwordLen > COLD_PASSWORD_MAX) return false;
  if (len != COLD_SETUP_HEADER_LEN + passwordLen) return false;

  const uint32_t keyId = coldLoadBe32(body + 1);
  const uint32_t passwordId = coldLoadBe32(body + 5);
  // Zero is not a usable id, the two must differ, and neither may be
  // one of the card's own objects.
  if (keyId == 0 || passwordId == 0 || keyId == passwordId) return false;
  if ((keyId >> 16) == SE_RESERVED_ID_PREFIX || (passwordId >> 16) == SE_RESERVED_ID_PREFIX) return false;

  setup.reset();
  setup.keyId = keyId;
  setup.passwordId = passwordId;
  setup.passwordLen = passwordLen;
  memcpy(setup.password, body + COLD_SETUP_HEADER_LEN, passwordLen);
  return true;
}

/// One command from the phone, answered. Returns false when the
/// conversation is over because the phone has said what it came to say.
static inline bool targetHandle(const uint8_t* apdu, int16_t len, ColdTap& tap) {
  if (len < 4) { targetReply(SW_WRONG_LENGTH); return true; }

  // CLA INS P1 P2 [Lc data…]
  const uint8_t cla = apdu[0], ins = apdu[1], p1 = apdu[2];
  const uint8_t lc = len > 4 ? apdu[4] : 0;
  const uint8_t* data = apdu + 5;
  const bool dataArrived = len >= 5 + lc;

  // SELECT by name. iOS sends one for each AID in the app's list until
  // one answers, so an unknown AID has to be refused politely.
  if (cla == 0x00 && ins == 0xA4 && p1 == 0x04) {
    const bool ours = dataArrived && lc == sizeof(COLD_AID) && memcmp(data, COLD_AID, sizeof(COLD_AID)) == 0;
    targetReply(ours ? SW_OK : SW_FILE_NOT_FOUND);
    if (ours) Serial.println("[nfc] phone selected toluCold");
    return true;
  }

  // 80 20 — the wallet setup, in one APDU.
  if (cla == 0x80 && ins == COLD_INS_SETUP) {
    if (!dataArrived) { targetReply(SW_WRONG_LENGTH); return true; }
    if (!targetParseSetup(data, lc, tap.setup)) { targetReply(SW_WRONG_DATA); return true; }

    targetReply(SW_OK);
    tap.setup.complete = true;
    Serial.println("[nfc] setup received");      // never print the setup itself
    return false;
  }

  // 80 21 — cancel. Always accepted: with nothing to cancel it changes
  // nothing, and the phone need not know which it was.
  if (cla == 0x80 && ins == COLD_INS_CANCEL) {
    targetReply(SW_OK);
    tap.cancel = true;
    Serial.println("[nfc] cancel received");
    return false;
  }

  targetReply(SW_INS_NOT_SUPPORTED);
  return true;
}

/// Arms the PN532 as a card and returns at once (TgInitAsTarget).
/// Mode 0x05 = passive only + PICC only; SEL_RES 0x20 marks the card as
/// ISO-DEP, which is what makes an iPhone treat it as an ISO 7816 tag.
static inline bool targetArm() {
  const uint8_t command[] = {
    PN532_COMMAND_TGINITASTARGET, 0x05,
    0x04, 0x00, 0x54, 0x4F, 0x4C,  0x20,                        // MifareParams: SENS_RES, NFCID1t, SEL_RES
    0x01, 0xFE, 0x0F, 0xBB, 0xBA, 0xA6, 0xC9, 0x89,             // FeliCaParams (unused, but required)
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0xFF, 0xFF,
    0x01, 0xFE, 0x0F, 0xBB, 0xBA, 0xA6, 0xC9, 0x89, 0x00, 0x00, // NFCID3t
    0x00,                                                       // LEN Gt
    0x00                                                        // LEN Tk
  };
  return pn532spi.writeCommand(command, sizeof(command)) == 0;
}

/// Has a phone arrived? Waits `waitMs` for the armed target to be
/// activated. A timeout is not a failure: the chip is still armed and
/// still silent — just ask again.
///
/// Returns 1 = the phone asked for something (see `tap`), 0 = still
/// waiting, <0 = the link broke and the caller should re-arm.
static inline int targetCheck(ColdTap& tap, uint16_t waitMs) {
  uint8_t activation[64];
  const int16_t n = pn532spi.readResponse(activation, sizeof(activation), waitMs);
  if (n == -2) return 0;        // nobody yet — still armed, still quiet
  if (n < 0) return -1;

  uint8_t apdu[64];
  for (int command = 0; command < TARGET_MAX_COMMANDS; command++) {
    const int16_t len = targetReceive(apdu, sizeof(apdu));
    if (len < 0 || !targetHandle(apdu, len, tap)) break;
  }
  coldWipe(apdu, sizeof(apdu));  // it held the password
  return tap.askedForSomething() ? 1 : -1;
}

#endif // COLD_TARGET_H
