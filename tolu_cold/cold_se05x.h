// ============================================================
// cold_se05x.h - the SE05x commands a cold wallet needs
// ============================================================
// GetRandom for the card's share of the entropy, then: the curves, the
// phone's public key as an ECKey authentication object, and what the
// key pair is written with — a policy that lets only a session opened
// with the phone's key use it. That session needs the phone's Secure
// Enclave and Face ID, so this device can write the key but never use
// it — and nobody holding the card can either. The write itself runs in
// an encrypted session of this device's own (cold_session.h).
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
#include "cold_p256.h"

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
#define SE_INS_PROCESS       0x05   // a command carried into a session
#define SE_INS_AUTH_OBJECT   0x40   // OR-ed into WRITE for authentication objects
// P1
#define SE_P1_DEFAULT        0x00
#define SE_P1_EC             0x01
#define SE_P1_CURVE          0x0B
#define SE_P1_PUBLIC         0x20
#define SE_P1_KEY_PAIR       0x60
// P2
#define SE_P2_DEFAULT        0x00
#define SE_P2_CREATE         0x04
#define SE_P2_SESSION_CREATE 0x1B
#define SE_P2_EXIST          0x27
#define SE_P2_DELETE_OBJECT  0x28
#define SE_P2_PARAM          0x40
#define SE_P2_RANDOM         0x49
// TLV tags
#define SE_TAG_SESSION_ID    0x10
#define SE_TAG_POLICY        0x11
#define SE_TAG_1             0x41
#define SE_TAG_2             0x42
#define SE_TAG_3             0x43
#define SE_TAG_4             0x44

#define SE_CURVE_NIST_P256   0x03
#define SE_CURVE_SECP256K1   0x10
// Which parameter of a curve a SetECCurveParam carries
#define SE_CURVE_PARAM_A     0x01
#define SE_CURVE_PARAM_B     0x02
#define SE_CURVE_PARAM_G     0x04
#define SE_CURVE_PARAM_N     0x08
#define SE_CURVE_PARAM_PRIME 0x10

// CheckObjectExists answers
#define SE_RESULT_SUCCESS    0x01
#define SE_RESULT_FAILURE    0x02

// The card's factory unique identifier (a reserved binary object).
#define SE_RESERVED_UNIQUE_ID 0x7FFF0206UL
#define SE_UNIQUE_ID_LEN      18
// The card's own P-256 key pair for ECKey sessions; anyone may read its public half.
#define SE_RESERVED_ECKEY_SESSION 0x7FFF0201UL

// Key policy: what may be done with the key, and only inside a session
// opened with the phone's key. No WRITE and no DELETE — once it is on
// the card it can be used, never replaced or removed.
#define SE_POLICY_SIGN       0x10000000UL
#define SE_POLICY_VERIFY     0x08000000UL
#define SE_POLICY_READ       0x00200000UL
#define SE_POLICY_DELETE     0x00040000UL
// The session a policy rule is for: 0 is the default session — anyone.
#define SE_DEFAULT_SESSION   0x00000000UL

#define SE_EC_POINT_LEN      65     // 04 || X || Y

// ── Building and parsing ─────────────────────────────────────
/// A command being put together: header, Lc, then data. The longest is
/// the one that opens a session, about 200 bytes; the PN532 carries 252.
struct SeApdu {
  uint8_t bytes[240];
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

/// A TLV. Lengths over 127 take the 0x81 form: a command carried into a
/// session can be that long.
static inline void seTlv(SeApdu& a, uint8_t tag, const uint8_t* value, uint8_t valueLen) {
  const bool longForm = valueLen > 0x7F;
  const uint8_t header[3] = { tag, (uint8_t)(longForm ? 0x81 : valueLen), valueLen };
  seAppend(a, header, longForm ? 3 : 2);
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
/// stripped, and kept in se05xLastSW) whatever the card answered, or -1
/// when no answer came back.
static inline int16_t seSendRaw(const SeApdu& a, uint8_t* rsp, uint8_t rspSize) {
  se05xLastSW = 0;
  if (!se05xExchange || a.overflow) return -1;
  const int16_t n = se05xExchange(a.bytes, a.len, rsp, rspSize);
  if (n < 2) return -1;
  se05xLastSW = (uint16_t)((rsp[n - 2] << 8) | rsp[n - 1]);
  return (int16_t)(n - 2);
}

/// Sends the APDU. Returns the length of the response DATA when the card
/// answers 9000, otherwise -1.
static inline int16_t seSend(const SeApdu& a, uint8_t* rsp, uint8_t rspSize) {
  const int16_t n = seSendRaw(a, rsp, rspSize);
  return n >= 0 && se05xLastSW == ISO_SW_SUCCESS ? n : -1;
}

/// The value of the first TLV with `tag`. Understands the short length
/// form and the 0x81 / 0x82 long forms the card uses for read data.
static inline const uint8_t* seFind(const uint8_t* data, int16_t len, uint8_t tag, uint16_t* valueLen) {
  int32_t i = 0;
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
    if ((int32_t)l > len - i) return nullptr;
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
  if (value[0] == SE_RESULT_SUCCESS) return 1;
  if (value[0] == SE_RESULT_FAILURE) return 0;
  return -1;
}

/// One curve parameter for SetECCurveParam.
struct SeCurveParam {
  uint8_t        selector;
  const uint8_t* value;
  uint8_t        len;
};

/// CreateECCurve and its five parameters. A card that already has the
/// curve refuses these, which is fine — the answers are not checked.
static inline void seInitCurve(uint8_t curveId, const SeCurveParam (&params)[5]) {
  uint8_t rsp[32];
  SeApdu apdu;
  seStart(apdu, SE_INS_WRITE, SE_P1_CURVE, SE_P2_CREATE);
  seTlvByte(apdu, SE_TAG_1, curveId);
  seFinish(apdu);
  seSend(apdu, rsp, sizeof(rsp));

  for (const SeCurveParam& param : params) {
    seStart(apdu, SE_INS_WRITE, SE_P1_CURVE, SE_P2_PARAM);
    seTlvByte(apdu, SE_TAG_1, curveId);
    seTlvByte(apdu, SE_TAG_2, param.selector);
    seTlv(apdu, SE_TAG_3, param.value, param.len);
    seFinish(apdu);
    seSend(apdu, rsp, sizeof(rsp));
  }
}

/// Makes sure the card knows both curves: secp256k1 (y² = x³ + 7) for
/// the wallet key, NIST P-256 for the phone's key.
static inline void se05xInitCurves() {
  uint8_t prime[32], a[32] = { 0 }, b[32] = { 0 }, generator[SE_EC_POINT_LEN], order[32];
  coldU256ToBytes(COLD_P, prime);
  b[31] = 7;
  generator[0] = 0x04;
  coldU256ToBytes(COLD_GX, generator + 1);
  coldU256ToBytes(COLD_GY, generator + 33);
  coldU256ToBytes(COLD_N, order);

  const SeCurveParam secp256k1[5] = {
    { SE_CURVE_PARAM_PRIME, prime, sizeof(prime) },
    { SE_CURVE_PARAM_A, a, sizeof(a) },
    { SE_CURVE_PARAM_B, b, sizeof(b) },
    { SE_CURVE_PARAM_G, generator, sizeof(generator) },
    { SE_CURVE_PARAM_N, order, sizeof(order) }
  };
  const SeCurveParam p256[5] = {
    { SE_CURVE_PARAM_PRIME, COLD_P256_PRIME, sizeof(COLD_P256_PRIME) },
    { SE_CURVE_PARAM_A, COLD_P256_A, sizeof(COLD_P256_A) },
    { SE_CURVE_PARAM_B, COLD_P256_B, sizeof(COLD_P256_B) },
    { SE_CURVE_PARAM_G, COLD_P256_G, sizeof(COLD_P256_G) },
    { SE_CURVE_PARAM_N, COLD_P256_N, sizeof(COLD_P256_N) }
  };
  seInitCurve(SE_CURVE_SECP256K1, secp256k1);
  seInitCurve(SE_CURVE_NIST_P256, p256);
}

/// ReadObject without a session. Works for what anyone may read: the
/// card's unique id, and authentication objects (their default policy).
/// Returns the value's length, or -1.
static inline int16_t seReadObject(uint32_t objectId, uint8_t* out, uint8_t outSize) {
  SeApdu a;
  seStart(a, SE_INS_READ, SE_P1_DEFAULT, SE_P2_DEFAULT);
  seTlvId(a, SE_TAG_1, objectId);
  seFinish(a);

  uint8_t rsp[96];
  const int16_t n = seSend(a, rsp, sizeof(rsp));
  uint16_t len = 0;
  const uint8_t* value = n < 0 ? nullptr : seFind(rsp, n, SE_TAG_1, &len);
  if (!value || len > outSize) return -1;
  memcpy(out, value, len);
  return (int16_t)len;
}

/// The card's factory unique id, to tell one card from another.
static inline bool se05xReadUniqueId(uint8_t out[SE_UNIQUE_ID_LEN]) {
  return seReadObject(SE_RESERVED_UNIQUE_ID, out, SE_UNIQUE_ID_LEN) == SE_UNIQUE_ID_LEN;
}

/// What the phone key slot holds: 0 = free, 1 = exactly this phone's
/// key (left by an earlier wallet or an earlier try, and usable as it
/// is), 2 = something else, -1 = the card didn't say.
static inline int se05xPhoneKeySlot(uint32_t objectId, const uint8_t phoneKey[SE_EC_POINT_LEN]) {
  const int exists = se05xExists(objectId);
  if (exists <= 0) return exists;
  uint8_t stored[SE_EC_POINT_LEN];
  const int16_t len = seReadObject(objectId, stored, sizeof(stored));
  return len == SE_EC_POINT_LEN && memcmp(stored, phoneKey, SE_EC_POINT_LEN) == 0 ? 1 : 2;
}

/// Writes the phone's public key as an ECKey authentication object. No
/// policy and no attempt limit: by default anyone may read it and nobody
/// may change or delete it, and a signature can't be guessed.
static inline bool se05xWritePhoneKey(uint32_t objectId, const uint8_t phoneKey[SE_EC_POINT_LEN]) {
  SeApdu a;
  seStart(a, SE_INS_WRITE | SE_INS_AUTH_OBJECT, SE_P1_PUBLIC | SE_P1_EC, SE_P2_DEFAULT);
  seTlvId(a, SE_TAG_1, objectId);
  seTlvByte(a, SE_TAG_2, SE_CURVE_NIST_P256);
  seTlv(a, SE_TAG_4, phoneKey, SE_EC_POINT_LEN);
  seFinish(a);

  uint8_t rsp[32];
  return seSend(a, rsp, sizeof(rsp)) >= 0;
}

/// Deletes an object, for a session its policy allows to.
static inline bool se05xDeleteObject(uint32_t objectId) {
  SeApdu a;
  seStart(a, SE_INS_MGMT, SE_P1_DEFAULT, SE_P2_DELETE_OBJECT);
  seTlvId(a, SE_TAG_1, objectId);
  seFinish(a);

  uint8_t rsp[32];
  return seSend(a, rsp, sizeof(rsp)) >= 0;
}

/// Writes a public key of this device's as an ECKey authentication
/// object, for one encrypted session (cold_session.h). Its policy gives
/// the default session — anybody — the right to delete it, and nothing
/// else: a key that opens a session with no rights over any other key.
static inline bool se05xWriteSessionKey(uint32_t objectId, const uint8_t publicKey[SE_EC_POINT_LEN]) {
  uint8_t policy[9];
  policy[0] = sizeof(policy) - 1;
  coldStoreBe32(policy + 1, SE_DEFAULT_SESSION);
  coldStoreBe32(policy + 5, SE_POLICY_DELETE);

  SeApdu a;
  seStart(a, SE_INS_WRITE | SE_INS_AUTH_OBJECT, SE_P1_PUBLIC | SE_P1_EC, SE_P2_DEFAULT);
  seTlv(a, SE_TAG_POLICY, policy, sizeof(policy));
  seTlvId(a, SE_TAG_1, objectId);
  seTlvByte(a, SE_TAG_2, SE_CURVE_NIST_P256);
  seTlv(a, SE_TAG_4, publicKey, SE_EC_POINT_LEN);
  seFinish(a);

  uint8_t rsp[32];
  return seSend(a, rsp, sizeof(rsp)) >= 0;
}

/// The data of the WriteECKey that puts a secp256k1 key pair made
/// outside the card onto it (P1 = KEY_PAIR | EC). The policy binds it to
/// the phone's key: sign, verify and read the public key — only inside
/// a session that phone opens. No WRITE and no DELETE.
static inline void seKeyPairPayload(SeApdu& a, uint32_t keyId, uint32_t phoneKeyId,
                                    const uint8_t privateKey[32], const uint8_t publicKey[SE_EC_POINT_LEN]) {
  // One policy rule: its length, who it is for, what they may do.
  uint8_t policy[9];
  policy[0] = sizeof(policy) - 1;
  coldStoreBe32(policy + 1, phoneKeyId);
  coldStoreBe32(policy + 5, SE_POLICY_SIGN | SE_POLICY_VERIFY | SE_POLICY_READ);

  seTlv(a, SE_TAG_POLICY, policy, sizeof(policy));
  seTlvId(a, SE_TAG_1, keyId);
  seTlvByte(a, SE_TAG_2, SE_CURVE_SECP256K1);
  seTlv(a, SE_TAG_3, privateKey, 32);
  seTlv(a, SE_TAG_4, publicKey, SE_EC_POINT_LEN);
}

#endif // COLD_SE05X_H
