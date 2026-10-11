// ============================================================
// cold_se05x.h - the SE05x commands a cold wallet needs
// ============================================================
// GetRandom for the card's share of the entropy, then: the secp256k1
// curve, a password object with an attempt limit, the key pair
// IMPORTED (the private key comes from this device, derived from the
// seed phrase), and a password session to read the public key back and
// prove it took.
//
// Byte layouts follow NXP's APDU specification for the SE05x IoT
// applet and match what the toluWallet app sends for the same commands.
//
// The transport is a function pointer so this file can be exercised on
// a computer with a pretend card (test/test_card.cpp).
// ============================================================
#ifndef COLD_SE05X_H
#define COLD_SE05X_H

#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include "cold_util.h"
#include "cold_secp256k1.h"

/// Sends an APDU, returns the response length (data + SW1 SW2) or <0.
typedef int16_t (*ColdExchangeFn)(const uint8_t* apdu, uint8_t apduLen, uint8_t* rsp, uint8_t rspSize);

static ColdExchangeFn se05xExchange = nullptr;
/// Status word of the last command that reached the card (0 if none did).
static uint16_t se05xLastSW = 0;

static const uint8_t SE05X_AID[16] = {
  0xA0, 0x00, 0x00, 0x03, 0x96, 0x54, 0x53, 0x00,
  0x00, 0x00, 0x01, 0x03, 0x00, 0x00, 0x00, 0x00
};

// ISO 7816-4 SELECT by name
#define ISO_CLA              0x00
#define ISO_INS_SELECT       0xA4
#define ISO_P1_SELECT_NAME   0x04
#define ISO_SW_SUCCESS       0x9000

// Instructions
#define SE_CLA               0x80
#define SE_INS_WRITE         0x01
#define SE_INS_READ          0x02
#define SE_INS_MGMT          0x04
#define SE_INS_PROCESS       0x05   // run a command inside a session
#define SE_INS_AUTH_OBJECT   0x40   // OR-ed into WRITE for authentication objects
// P1
#define SE_P1_DEFAULT        0x00
#define SE_P1_EC             0x01
#define SE_P1_USERID         0x07
#define SE_P1_CURVE          0x0B
#define SE_P1_KEY_PAIR       0x60
// P2
#define SE_P2_DEFAULT        0x00
#define SE_P2_CREATE         0x04
#define SE_P2_SESSION_CREATE 0x1B
#define SE_P2_EXIST          0x27
#define SE_P2_SESSION_USERID 0x2C
#define SE_P2_PARAM          0x40
#define SE_P2_RANDOM         0x49
// TLV tags
#define SE_TAG_SESSION_ID    0x10
#define SE_TAG_POLICY        0x11
#define SE_TAG_MAX_ATTEMPTS  0x12
#define SE_TAG_1             0x41
#define SE_TAG_2             0x42
#define SE_TAG_3             0x43
#define SE_TAG_4             0x44

#define SE_CURVE_SECP256K1   0x10
// Which parameter of a curve a SetECCurveParam carries
#define SE_CURVE_PARAM_A     0x01
#define SE_CURVE_PARAM_B     0x02
#define SE_CURVE_PARAM_G     0x04
#define SE_CURVE_PARAM_N     0x08
#define SE_CURVE_PARAM_PRIME 0x10

#define SE_RESULT_SUCCESS    0x01
#define SE_SESSION_ID_LEN    8

// Key policy: what may be done with the key, and only after the
// password session is open. No WRITE and no DELETE — once it is on the
// card it can be used, never replaced or removed.
#define SE_POLICY_SIGN       0x10000000UL
#define SE_POLICY_VERIFY     0x08000000UL
#define SE_POLICY_READ       0x00200000UL

// ── Building and parsing ─────────────────────────────────────
/// A command being put together: header, Lc, then data.
struct SeApdu {
  uint8_t bytes[200];
  uint8_t len;
  bool    overflow;      // something did not fit; the command is never sent
};

static inline void seStart(SeApdu& a, uint8_t ins, uint8_t p1, uint8_t p2, uint8_t cla = SE_CLA) {
  a.bytes[0] = cla; a.bytes[1] = ins; a.bytes[2] = p1; a.bytes[3] = p2;
  a.bytes[4] = 0;        // Lc, filled in by seFinish
  a.len = 5;
  a.overflow = false;
}

static inline void seAppend(SeApdu& a, const uint8_t* data, uint8_t dataLen) {
  // One byte is kept back for Le.
  if (a.overflow || a.len + dataLen > sizeof(a.bytes) - 1) { a.overflow = true; return; }
  memcpy(a.bytes + a.len, data, dataLen);
  a.len += dataLen;
}

static inline void seTlv(SeApdu& a, uint8_t tag, const uint8_t* value, uint8_t valueLen) {
  const uint8_t header[2] = { tag, valueLen };
  seAppend(a, header, sizeof(header));
  seAppend(a, value, valueLen);
}

static inline void seTlvByte(SeApdu& a, uint8_t tag, uint8_t value) { seTlv(a, tag, &value, 1); }

static inline void seTlvId(SeApdu& a, uint8_t tag, uint32_t objectId) {
  uint8_t id[4];
  coldStoreBe32(id, objectId);
  seTlv(a, tag, id, sizeof(id));
}

/// Fills in Lc and appends Le = 0.
static inline void seFinish(SeApdu& a) {
  a.bytes[4] = (uint8_t)(a.len - 5);
  a.bytes[a.len++] = 0x00;
}

static inline void seWipe(SeApdu& a) {
  coldWipe(a.bytes, sizeof(a.bytes));
  a.len = 0;
}

/// Sends the APDU. Returns the length of the response DATA (status word
/// stripped) when the card answers 9000, otherwise -1.
static inline int16_t seSend(const SeApdu& a, uint8_t* rsp, uint8_t rspSize) {
  se05xLastSW = 0;
  if (!se05xExchange || a.overflow) return -1;
  const int16_t n = se05xExchange(a.bytes, a.len, rsp, rspSize);
  if (n < 2) return -1;
  se05xLastSW = (uint16_t)((rsp[n - 2] << 8) | rsp[n - 1]);
  return se05xLastSW == ISO_SW_SUCCESS ? (int16_t)(n - 2) : -1;
}

/// The value of the first TLV with `tag`. Understands the short length
/// form and the 0x81 / 0x82 long forms the card uses for read data.
static inline const uint8_t* seFind(const uint8_t* data, int16_t len, uint8_t tag, uint16_t* valueLen) {
  int16_t i = 0;
  while (i + 2 <= len) {
    const uint8_t current = data[i++];
    uint16_t l = data[i++];
    if (l == 0x81) {
      if (i >= len) return nullptr;
      l = data[i++];
    } else if (l == 0x82) {
      if (i + 1 >= len) return nullptr;
      l = (uint16_t)((data[i] << 8) | data[i + 1]);
      i += 2;
    }
    if (i + (int16_t)l > len) return nullptr;
    if (current == tag) { *valueLen = l; return &data[i]; }
    i += l;
  }
  return nullptr;
}

// ── Commands ─────────────────────────────────────────────────
/// SELECT the SE05x applet. Must come first after the card is activated.
static inline bool se05xSelect() {
  SeApdu a;
  seStart(a, ISO_INS_SELECT, ISO_P1_SELECT_NAME, 0x00, ISO_CLA);
  seAppend(a, SE05X_AID, sizeof(SE05X_AID));
  seFinish(a);

  uint8_t rsp[64];
  return seSend(a, rsp, sizeof(rsp)) >= 0;
}

/// Random bytes from the generator inside the secure element: a
/// standards-compliant DRBG seeded by a true random source in the chip.
static inline bool se05xGetRandom(uint8_t* out, uint8_t count) {
  SeApdu a;
  seStart(a, SE_INS_MGMT, SE_P1_DEFAULT, SE_P2_RANDOM);
  const uint8_t size[2] = { 0x00, count };
  seTlv(a, SE_TAG_1, size, sizeof(size));
  seFinish(a);

  uint8_t rsp[80];
  const int16_t n = seSend(a, rsp, sizeof(rsp));
  uint16_t len = 0;
  const uint8_t* value = n < 0 ? nullptr : seFind(rsp, n, SE_TAG_1, &len);
  const bool ok = value && len == count;
  if (ok) memcpy(out, value, count);
  coldWipe(rsp, sizeof(rsp));
  return ok;
}

/// 1 = the object exists, 0 = the slot is free, -1 = the card didn't say.
static inline int se05xExists(uint32_t objectId) {
  SeApdu a;
  seStart(a, SE_INS_MGMT, SE_P1_DEFAULT, SE_P2_EXIST);
  seTlvId(a, SE_TAG_1, objectId);
  seFinish(a);

  uint8_t rsp[32];
  const int16_t n = seSend(a, rsp, sizeof(rsp));
  if (n < 0) return -1;
  uint16_t len = 0;
  const uint8_t* value = seFind(rsp, n, SE_TAG_1, &len);
  if (!value || len < 1) return -1;
  return value[0] == SE_RESULT_SUCCESS ? 1 : 0;
}

/// Makes sure the card knows secp256k1 (y² = x³ + 7): creates the curve
/// and sets its five parameters. A card that already has the curve
/// refuses these, which is fine — the answers are not checked.
static inline void se05xInitCurve() {
  uint8_t prime[32], a[32] = { 0 }, b[32] = { 0 }, generator[65], order[32];
  coldU256ToBytes(COLD_P, prime);
  b[31] = 7;
  generator[0] = 0x04;
  coldU256ToBytes(COLD_GX, generator + 1);
  coldU256ToBytes(COLD_GY, generator + 33);
  coldU256ToBytes(COLD_N, order);

  const struct { uint8_t selector; const uint8_t* value; uint8_t len; } params[] = {
    { SE_CURVE_PARAM_PRIME, prime, sizeof(prime) },
    { SE_CURVE_PARAM_A, a, sizeof(a) },
    { SE_CURVE_PARAM_B, b, sizeof(b) },
    { SE_CURVE_PARAM_G, generator, sizeof(generator) },
    { SE_CURVE_PARAM_N, order, sizeof(order) }
  };

  uint8_t rsp[32];
  SeApdu apdu;
  seStart(apdu, SE_INS_WRITE, SE_P1_CURVE, SE_P2_CREATE);
  seTlvByte(apdu, SE_TAG_1, SE_CURVE_SECP256K1);
  seFinish(apdu);
  seSend(apdu, rsp, sizeof(rsp));

  for (const auto& param : params) {
    seStart(apdu, SE_INS_WRITE, SE_P1_CURVE, SE_P2_PARAM);
    seTlvByte(apdu, SE_TAG_1, SE_CURVE_SECP256K1);
    seTlvByte(apdu, SE_TAG_2, param.selector);
    seTlv(apdu, SE_TAG_3, param.value, param.len);
    seFinish(apdu);
    seSend(apdu, rsp, sizeof(rsp));
  }
}

/// Creates the password object (a UserID). `maxAttempts` wrong
/// passwords lock it — and with it the key — for good; 0 = unlimited.
static inline bool se05xCreatePassword(uint32_t objectId, const uint8_t* password, uint8_t passwordLen,
                                       uint16_t maxAttempts) {
  SeApdu a;
  seStart(a, SE_INS_WRITE | SE_INS_AUTH_OBJECT, SE_P1_USERID, SE_P2_DEFAULT);
  if (maxAttempts > 0) {
    const uint8_t attempts[2] = { (uint8_t)(maxAttempts >> 8), (uint8_t)maxAttempts };
    seTlv(a, SE_TAG_MAX_ATTEMPTS, attempts, sizeof(attempts));
  }
  seTlvId(a, SE_TAG_1, objectId);
  seTlv(a, SE_TAG_2, password, passwordLen);
  seFinish(a);

  uint8_t rsp[32];
  const bool ok = seSend(a, rsp, sizeof(rsp)) >= 0;
  seWipe(a);
  return ok;
}

/// Writes a secp256k1 key pair made outside the card. The policy binds
/// it to the password object: sign, verify and read the public key —
/// only inside a session opened with the password.
static inline bool se05xImportKeyPair(uint32_t keyId, uint32_t passwordId,
                                      const uint8_t privateKey[32], const uint8_t publicKey[65]) {
  // One policy rule: its length, who it is for, what they may do.
  uint8_t policy[9];
  policy[0] = sizeof(policy) - 1;
  coldStoreBe32(policy + 1, passwordId);
  coldStoreBe32(policy + 5, SE_POLICY_SIGN | SE_POLICY_VERIFY | SE_POLICY_READ);

  SeApdu a;
  seStart(a, SE_INS_WRITE, SE_P1_KEY_PAIR | SE_P1_EC, SE_P2_DEFAULT);
  seTlv(a, SE_TAG_POLICY, policy, sizeof(policy));
  seTlvId(a, SE_TAG_1, keyId);
  seTlvByte(a, SE_TAG_2, SE_CURVE_SECP256K1);
  seTlv(a, SE_TAG_3, privateKey, 32);
  seTlv(a, SE_TAG_4, publicKey, 65);
  seFinish(a);

  uint8_t rsp[32];
  const bool ok = seSend(a, rsp, sizeof(rsp)) >= 0;
  seWipe(a);
  return ok;
}

/// Wraps a command so it runs inside an open session.
static inline int16_t seSendInSession(const uint8_t sessionId[SE_SESSION_ID_LEN], const SeApdu& inner,
                                      uint8_t* rsp, uint8_t rspSize) {
  SeApdu outer;
  seStart(outer, SE_INS_PROCESS, SE_P1_DEFAULT, SE_P2_DEFAULT);
  seTlv(outer, SE_TAG_SESSION_ID, sessionId, SE_SESSION_ID_LEN);
  seTlv(outer, SE_TAG_1, inner.bytes, inner.len);
  seFinish(outer);
  const int16_t n = seSend(outer, rsp, rspSize);
  seWipe(outer);
  return n;
}

/// Opens a session against the password object and proves the password.
/// A wrong password uses up one of the object's attempts.
static inline bool se05xOpenSession(uint32_t passwordId, const uint8_t* password, uint8_t passwordLen,
                                    uint8_t sessionId[SE_SESSION_ID_LEN]) {
  SeApdu create;
  seStart(create, SE_INS_MGMT, SE_P1_DEFAULT, SE_P2_SESSION_CREATE);
  seTlvId(create, SE_TAG_1, passwordId);
  seFinish(create);

  uint8_t rsp[48];
  int16_t n = seSend(create, rsp, sizeof(rsp));
  if (n < 0) return false;
  uint16_t len = 0;
  const uint8_t* value = seFind(rsp, n, SE_TAG_1, &len);
  if (!value || len != SE_SESSION_ID_LEN) return false;
  memcpy(sessionId, value, SE_SESSION_ID_LEN);

  SeApdu verify;
  seStart(verify, SE_INS_MGMT, SE_P1_DEFAULT, SE_P2_SESSION_USERID);
  seTlv(verify, SE_TAG_1, password, passwordLen);
  seFinish(verify);
  n = seSendInSession(sessionId, verify, rsp, sizeof(rsp));
  seWipe(verify);
  return n >= 0;
}

/// Reads the key pair's public key inside a session and says whether it
/// is the one expected (0x04 || X || Y).
///
/// The point comes back inside nested TLVs whose wrapping is not worth
/// depending on, so the response is searched for the expected bytes —
/// which is also exactly the question being asked.
static inline bool se05xKeyMatches(const uint8_t sessionId[SE_SESSION_ID_LEN], uint32_t keyId,
                                   const uint8_t expected[65]) {
  SeApdu a;
  seStart(a, SE_INS_READ, SE_P1_DEFAULT, SE_P2_DEFAULT);
  seTlvId(a, SE_TAG_1, keyId);
  seFinish(a);

  uint8_t rsp[160];
  const int16_t n = seSendInSession(sessionId, a, rsp, sizeof(rsp));
  for (int16_t i = 0; i + 65 <= n; i++) {
    if (memcmp(&rsp[i], expected, 65) == 0) return true;
  }
  return false;
}

#endif // COLD_SE05X_H
