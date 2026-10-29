// ============================================================
// cold_session.h - writing the key to the card, encrypted
// ============================================================
// The wallet key must not cross the air in the clear. The card only
// encrypts inside a session, and a session opens only for someone who
// proves they hold the private half of an authentication key stored on
// the card (NXP's ECKey session, AN12543 §3.6.3.3). The phone's key
// cannot do that here — it never leaves the iPhone — so this device
// brings a key of its own, made for this one write:
//
//   1. a fresh P-256 key, its public half written to the card as an
//      authentication object that anybody may delete, and nothing else
//   2. an ECKey session opened with it: a one-time key, signed with it,
//      and ECDH with the card's session key — AES keys on both sides,
//      never sent
//   3. the wallet key written inside that session, so it crosses the
//      air encrypted — with the same policy as ever: only the phone's
//      session may use it
//   4. the temporary object deleted again
//
// No key on the card names the temporary one in its policy, so its
// session can't read, use, change or delete any of them. All it could
// do is create objects, which anyone can, and it is gone at the end.
//
// The session is the one the toluWallet app opens with the phone's key
// (Se05xTag+ECKeySession.swift, SecureChannel.swift), byte for byte;
// test/test_session.cpp holds the two to the same values.
// ============================================================
#ifndef COLD_SESSION_H
#define COLD_SESSION_H

#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include "cold_util.h"
#include "cold_sha2.h"
#include "cold_aes.h"
#include "cold_p256.h"
#include "cold_se05x.h"

#define SE_CLA_SECURE_MESSAGING  0x04   // OR-ed into CLA
#define SE_INS_INTERNAL_AUTH     0x88   // ECKeySessionInternalAuthenticate
#define SE_TAG_CHALLENGE         0x85
#define SE_TAG_RECEIPT           0x86
#define SE_SESSION_ID_LEN        8
#define SE_CHALLENGE_LEN         16
#define SE_MAC_LEN               8      // the part of each MAC that is sent

// The session's settings, the same in what is signed and what is hashed
// into the keys: security level 0x33 (every command and every answer
// encrypted and MAC'd), keys of type AES (0x88), 16 bytes long.
#define SE_SCP_SECURITY_LEVEL    0x33
#define SE_SCP_KEY_TYPE          0x88
#define SE_SCP_KEY_LEN           0x10

/// Where random bytes come from: the ESP32's generator on the device, a
/// fixed pattern in the tests.
typedef void (*ColdRandomFn)(void* out, size_t len);
static ColdRandomFn coldSessionRandom = nullptr;

// ── Session keys ─────────────────────────────────────────────
/// The AES keys of one session (SCP03, as the SE05x applet derives them).
struct SeScpKeys {
  uint8_t enc[16];     // encrypts commands and answers
  uint8_t mac[16];     // authenticates commands
  uint8_t rmac[16];    // authenticates answers
  uint8_t chain[16];   // the first MAC chaining value
};

/// SCP03 key derivation data: an 11-byte zero label, the constant, a
/// separator, the output length in bits (128) and the KDF counter (1).
static inline void seScpDerivationData(uint8_t constant, uint8_t out[16]) {
  memset(out, 0, 16);
  out[11] = constant;
  out[14] = 0x80;
  out[15] = 0x01;
}

///   master key = SHA-256(00000001 ‖ ECDH secret ‖ challenge ‖ 01 33 ‖ 88 10), first 16 bytes
///   S-ENC, S-MAC, S-RMAC, first chaining value = CMAC(master key, derivation data 04, 06, 07, 08)
static inline void seScpKeys(SeScpKeys& keys, const uint8_t secret[32], const uint8_t challenge[SE_CHALLENGE_LEN]) {
  static const uint8_t counter[4] = { 0x00, 0x00, 0x00, 0x01 };
  static const uint8_t settings[4] = { 0x01, SE_SCP_SECURITY_LEVEL, SE_SCP_KEY_TYPE, SE_SCP_KEY_LEN };
  uint8_t digest[32];
  ColdSha256 s;
  coldSha2Init(s);
  coldSha2Update(s, counter, sizeof(counter));
  coldSha2Update(s, secret, 32);
  coldSha2Update(s, challenge, SE_CHALLENGE_LEN);
  coldSha2Update(s, settings, sizeof(settings));
  coldSha2Final(s, digest);

  uint8_t data[16];
  seScpDerivationData(0x04, data);
  coldAesCmac(digest, data, sizeof(data), keys.enc);
  seScpDerivationData(0x06, data);
  coldAesCmac(digest, data, sizeof(data), keys.mac);
  seScpDerivationData(0x07, data);
  coldAesCmac(digest, data, sizeof(data), keys.rmac);
  seScpDerivationData(0x08, data);
  coldAesCmac(digest, data, sizeof(data), keys.chain);
  coldWipe(digest, sizeof(digest));
}

// ── Secure messaging ─────────────────────────────────────────
// command: data padded (80 00…) and AES-CBC encrypted under S-ENC, the
//          IV being the counter encrypted under S-ENC; CLA | 0x04; then
//          CMAC(S-MAC, chaining value ‖ header ‖ Lc ‖ data), whose first
//          8 bytes are appended and whose 16 become the next chaining value.
// answer:  data ‖ R-MAC ‖ SW, where R-MAC = CMAC(S-RMAC, chaining value ‖
//          data ‖ SW); data decrypted with the IV 80 ‖ counter under S-ENC.
// The counter steps after every answer, refusals included.
struct SeChannel {
  SeScpKeys keys;
  uint8_t   counter[16];
  uint8_t   chain[16];
};

static inline void seChannelBegin(SeChannel& ch, const SeScpKeys& keys) {
  ch.keys = keys;
  memset(ch.counter, 0, sizeof(ch.counter));
  ch.counter[15] = 0x01;
  memcpy(ch.chain, keys.chain, sizeof(ch.chain));
}

static inline void seChannelStep(SeChannel& ch) {
  for (int i = 15; i >= 0; i--) {
    if (++ch.counter[i] != 0) break;
  }
}

/// The protected form of one command, carried into the session by
/// ProcessSessionCmd. `extendedLength` picks the 3-byte Lc, which NXP's
/// middleware uses for its extended-length commands (ReadObject,
/// GetRandom) alone. Returns its length, or 0 if it does not fit `out`.
static inline uint16_t seChannelProtect(SeChannel& ch, uint8_t cla, uint8_t ins, uint8_t p1, uint8_t p2,
                                        const uint8_t* data, uint8_t dataLen, bool extendedLength,
                                        uint8_t* out, uint16_t outSize) {
  // ISO 9797-1 method 2: 0x80, then zeros to the end of a block.
  const uint16_t bodyLen = dataLen ? (uint16_t)((dataLen / COLD_AES_BLOCK + 1) * COLD_AES_BLOCK) : 0;
  const uint16_t lc = (uint16_t)(bodyLen + SE_MAC_LEN);
  const uint16_t headerLen = (lc < 0xFF && !extendedLength) ? 5 : 7;
  if (headerLen + lc > outSize) return 0;

  out[0] = cla | SE_CLA_SECURE_MESSAGING;
  out[1] = ins;
  out[2] = p1;
  out[3] = p2;
  if (headerLen == 5) {
    out[4] = (uint8_t)lc;
  } else {
    out[4] = 0x00;
    out[5] = (uint8_t)(lc >> 8);
    out[6] = (uint8_t)lc;
  }
  if (dataLen) {
    uint8_t* body = out + headerLen;
    memcpy(body, data, dataLen);
    body[dataLen] = 0x80;
    memset(body + dataLen + 1, 0, bodyLen - dataLen - 1);
    ColdAes128 aes;
    uint8_t iv[16];
    coldAesKey(aes, ch.keys.enc);
    coldAesEncrypt(aes, ch.counter, iv);
    coldAesCbcEncrypt(aes, iv, body, bodyLen);
    coldWipe(&aes, sizeof(aes));
  }

  ColdCmac mac;
  coldCmacBegin(mac, ch.keys.mac);
  coldCmacUpdate(mac, ch.chain, sizeof(ch.chain));
  coldCmacUpdate(mac, out, headerLen + bodyLen);
  coldCmacEnd(mac, ch.chain);
  memcpy(out + headerLen + bodyLen, ch.chain, SE_MAC_LEN);
  return (uint16_t)(headerLen + lc);
}

/// The plain answer to the command `seChannelProtect` built last.
/// Returns its length; -1 if the card refused the command (se05xLastSW
/// says how); -2 if the answer does not authenticate.
///
/// An empty 9000 is taken as it is, as the app takes it: the card
/// confirms an empty answer with a MAC, but nothing secret rides on it —
/// the phone checks the key in its own session before it keeps a wallet.
static inline int16_t seChannelOpen(SeChannel& ch, const uint8_t* rsp, int16_t len, uint16_t sw,
                                    uint8_t* out, uint8_t outSize) {
  int16_t result;
  if (sw != ISO_SW_SUCCESS) {
    result = -1;                         // a refusal carries neither data nor MAC
  } else if (len == 0) {
    result = 0;
  } else if (len < SE_MAC_LEN || (len - SE_MAC_LEN) % COLD_AES_BLOCK != 0 || len - SE_MAC_LEN > outSize) {
    result = -2;
  } else {
    const int16_t dataLen = (int16_t)(len - SE_MAC_LEN);
    const uint8_t status[2] = { (uint8_t)(sw >> 8), (uint8_t)sw };
    uint8_t expected[16];
    ColdCmac mac;
    coldCmacBegin(mac, ch.keys.rmac);
    coldCmacUpdate(mac, ch.chain, sizeof(ch.chain));
    coldCmacUpdate(mac, rsp, (size_t)dataLen);
    coldCmacUpdate(mac, status, sizeof(status));
    coldCmacEnd(mac, expected);

    if (!coldEqual(expected, rsp + dataLen, SE_MAC_LEN)) {
      result = -2;
    } else if (dataLen == 0) {
      result = 0;
    } else {
      uint8_t iv[16];
      memcpy(iv, ch.counter, sizeof(iv));
      iv[0] = 0x80;
      ColdAes128 aes;
      coldAesKey(aes, ch.keys.enc);
      coldAesEncrypt(aes, iv, iv);
      memcpy(out, rsp, (size_t)dataLen);
      coldAesCbcDecrypt(aes, iv, out, (size_t)dataLen);
      coldWipe(&aes, sizeof(aes));
      // Strip the padding: zeros back to a 0x80, within the last block.
      result = -2;
      for (int16_t i = (int16_t)(dataLen - 1); i >= dataLen - COLD_AES_BLOCK; i--) {
        if (out[i] == 0x80) { result = i; break; }
        if (out[i] != 0x00) break;
      }
    }
  }
  seChannelStep(ch);
  return result;
}

// ── Opening a session ────────────────────────────────────────
#define SE_ECKEY_SIGNED_LEN  104

/// What the session opener signs, and what the card's receipt covers:
///   A6 1D  4F 10 <applet AID>  90 03 AB 01 33  80 01 88  81 01 10
///   7F49 46  B0 41 <one-time P-256 public key>  F0 01 03
static inline void seECKeySignedPart(const uint8_t oneTimePublic[SE_EC_POINT_LEN], uint8_t out[SE_ECKEY_SIGNED_LEN]) {
  uint8_t* p = out;
  *p++ = 0xA6; *p++ = 0x1D;
  *p++ = 0x4F; *p++ = sizeof(SE05X_AID);
  memcpy(p, SE05X_AID, sizeof(SE05X_AID)); p += sizeof(SE05X_AID);
  *p++ = 0x90; *p++ = 0x03; *p++ = 0xAB; *p++ = 0x01; *p++ = SE_SCP_SECURITY_LEVEL;
  *p++ = 0x80; *p++ = 0x01; *p++ = SE_SCP_KEY_TYPE;
  *p++ = 0x81; *p++ = 0x01; *p++ = SE_SCP_KEY_LEN;
  *p++ = 0x7F; *p++ = 0x49; *p++ = 0x46;
  *p++ = 0xB0; *p++ = SE_EC_POINT_LEN;
  memcpy(p, oneTimePublic, SE_EC_POINT_LEN); p += SE_EC_POINT_LEN;
  *p++ = 0xF0; *p++ = 0x01; *p = SE_CURVE_NIST_P256;
}

/// An open session: its id, and the channel every command goes through.
struct SeSession {
  uint8_t   id[SE_SESSION_ID_LEN];
  SeChannel channel;
  bool      open;
};

/// ProcessSessionCmd around `inner`: the session id, then the command.
static inline void seProcessSession(SeApdu& a, const SeSession& s, const uint8_t* inner, uint8_t innerLen) {
  seStart(a, SE_INS_PROCESS, SE_P1_DEFAULT, SE_P2_DEFAULT);
  seTlv(a, SE_TAG_SESSION_ID, s.id, SE_SESSION_ID_LEN);
  seTlv(a, SE_TAG_1, inner, innerLen);
  seFinish(a);
}

/// Opens an ECKey session for the authentication object `authId`, whose
/// private half is `authKey`, with `oneTimeKey` for the key agreement.
/// The way NXP's middleware does it:
///   1. read the card's key-agreement public key (0x7FFF0201)
///   2. CreateSession for the authentication object
///   3. ECKeySessionInternalAuthenticate: the one-time public key, signed;
///      the card answers its random challenge and a receipt
///   4. both sides derive the session keys from ECDH; the receipt proves
///      the card did — only then is the session trusted
static inline bool se05xOpenECKeySession(SeSession& s, uint32_t authId, const uint8_t authKey[32],
                                         const uint8_t oneTimeKey[32]) {
  coldWipe(&s, sizeof(s));
  uint8_t cardKey[SE_EC_POINT_LEN];
  if (seReadObject(SE_RESERVED_ECKEY_SESSION, cardKey, sizeof(cardKey)) != SE_EC_POINT_LEN) return false;

  SeApdu a;
  seStart(a, SE_INS_MGMT, SE_P1_DEFAULT, SE_P2_SESSION_CREATE);
  seTlvId(a, SE_TAG_1, authId);
  seFinish(a);
  uint8_t rsp[64];
  int16_t n = seSend(a, rsp, sizeof(rsp));
  uint16_t len = 0;
  const uint8_t* sessionId = n < 0 ? nullptr : seFind(rsp, n, SE_TAG_1, &len);
  if (!sessionId || len != SE_SESSION_ID_LEN) return false;
  memcpy(s.id, sessionId, SE_SESSION_ID_LEN);

  // The request: the one-time public key and the session's settings,
  // signed with the authentication key. Header, a 1-byte Lc and no Le,
  // as the middleware sends it — the card answers 6A80 to any other form.
  uint8_t oneTimePublic[SE_EC_POINT_LEN], signedPart[SE_ECKEY_SIGNED_LEN], signature[COLD_P256_SIG_MAX];
  if (!coldP256PublicKey(oneTimeKey, oneTimePublic)) return false;
  seECKeySignedPart(oneTimePublic, signedPart);
  const uint8_t signatureLen = coldP256Sign(authKey, signedPart, sizeof(signedPart), signature);
  if (!signatureLen) return false;

  uint8_t inner[5 + SE_ECKEY_SIGNED_LEN + 3 + COLD_P256_SIG_MAX];
  uint8_t innerLen = 0;
  inner[innerLen++] = SE_CLA | SE_CLA_SECURE_MESSAGING;
  inner[innerLen++] = SE_INS_INTERNAL_AUTH;
  inner[innerLen++] = SE_P1_DEFAULT;
  inner[innerLen++] = SE_P2_DEFAULT;
  inner[innerLen++] = (uint8_t)(SE_ECKEY_SIGNED_LEN + 3 + signatureLen);
  memcpy(inner + innerLen, signedPart, sizeof(signedPart));
  innerLen = (uint8_t)(innerLen + sizeof(signedPart));
  inner[innerLen++] = 0x5F;
  inner[innerLen++] = 0x37;
  inner[innerLen++] = signatureLen;
  memcpy(inner + innerLen, signature, signatureLen);
  innerLen = (uint8_t)(innerLen + signatureLen);

  seProcessSession(a, s, inner, innerLen);
  n = seSend(a, rsp, sizeof(rsp));
  uint16_t challengeLen = 0, receiptLen = 0;
  const uint8_t* challenge = n < 0 ? nullptr : seFind(rsp, n, SE_TAG_CHALLENGE, &challengeLen);
  const uint8_t* receipt = n < 0 ? nullptr : seFind(rsp, n, SE_TAG_RECEIPT, &receiptLen);
  if (!challenge || challengeLen != SE_CHALLENGE_LEN || !receipt || receiptLen != 16) return false;

  // The same keys as the card, from a secret neither side sent.
  uint8_t secret[32], expected[16];
  SeScpKeys keys;
  bool ok = coldP256Ecdh(oneTimeKey, cardKey, secret);
  if (ok) {
    seScpKeys(keys, secret, challenge);
    coldAesCmac(keys.rmac, signedPart, sizeof(signedPart), expected);
    ok = coldEqual(expected, receipt, sizeof(expected));
  }
  if (ok) {
    seChannelBegin(s.channel, keys);
    s.open = true;
  }
  coldWipe(secret, sizeof(secret));
  coldWipe(&keys, sizeof(keys));
  return ok;
}

/// Runs one command inside the session, encrypted and authenticated.
/// Returns the plain answer's length; -1 if the card refused it or did
/// not answer; -2 if the answer did not authenticate, which ends the
/// session here.
static inline int16_t se05xSessionRun(SeSession& s, uint8_t ins, uint8_t p1, uint8_t p2,
                                      const uint8_t* data, uint8_t dataLen, uint8_t* out, uint8_t outSize) {
  if (!s.open) return -1;
  uint8_t inner[160];
  const uint16_t innerLen = seChannelProtect(s.channel, SE_CLA, ins, p1, p2, data, dataLen, false,
                                             inner, sizeof(inner));
  if (!innerLen) return -1;

  SeApdu a;
  seProcessSession(a, s, inner, (uint8_t)innerLen);
  uint8_t rsp[96];
  const int16_t n = seSendRaw(a, rsp, sizeof(rsp));
  int16_t result;
  if (n < 0) {
    s.open = false;                      // whether the card took it is unknown
    result = -1;
  } else {
    result = seChannelOpen(s.channel, rsp, n, se05xLastSW, out, outSize);
    if (result == -2) s.open = false;
  }
  coldWipe(inner, sizeof(inner));
  seWipe(a);
  coldWipe(rsp, sizeof(rsp));
  return result;
}

// ── The whole write ──────────────────────────────────────────
enum SeSealedResult {
  SE_SEALED_OK,              // the key is on the card, and the temporary key gone again
  SE_SEALED_NO_ANSWER,       // the card stopped answering
  SE_SEALED_SLOT_TAKEN,      // the temporary slot holds something this device may not remove
  SE_SEALED_NO_SESSION,      // the card refused the temporary key or its session (se05xLastSW)
  SE_SEALED_KEY_REFUSED,     // the card refused the key inside the session (se05xLastSW)
  SE_SEALED_TAMPERED         // an answer did not authenticate: something between changed it
};

/// A P-256 private key for this write alone: SHA-256 of a label, what it
/// is for, a counter, the wallet key and 32 fresh random bytes. The
/// random bytes make it new every time. The wallet key keeps it secret
/// even if the generator could ever be predicted — whoever wanted to
/// work it out from what crosses the air would need the very key it
/// protects.
static inline bool coldSessionKey(uint8_t out[32], uint8_t purpose, const uint8_t walletKey[32]) {
  static const char label[] = "tolu session key v1";
  if (!coldSessionRandom) return false;
  for (uint8_t counter = 0; counter < 8; counter++) {
    uint8_t random[32];
    coldSessionRandom(random, sizeof(random));
    ColdSha256 s;
    coldSha2Init(s);
    coldSha2Update(s, (const uint8_t*)label, sizeof(label) - 1);
    coldSha2Update(s, &purpose, 1);
    coldSha2Update(s, &counter, 1);
    coldSha2Update(s, walletKey, 32);
    coldSha2Update(s, random, sizeof(random));
    coldSha2Final(s, out);
    coldWipe(random, sizeof(random));

    ColdU256 k;
    coldU256FromBytes(k, out);
    const bool valid = coldP256ScalarValid(k);
    coldWipe(&k, sizeof(k));
    if (valid) return true;
  }
  coldWipe(out, 32);
  return false;
}

/// Writes the wallet key into `keyId`, bound to the phone key in
/// `phoneKeyId`, inside an encrypted session opened with a temporary key
/// in `tempId`. Steps 1 to 4 at the top of this file.
static inline SeSealedResult se05xImportKeyPairSealed(uint32_t keyId, uint32_t phoneKeyId, uint32_t tempId,
                                                      const uint8_t privateKey[32],
                                                      const uint8_t publicKey[SE_EC_POINT_LEN]) {
  // An earlier try that stopped half-way may have left its temporary key.
  const int leftover = se05xExists(tempId);
  if (leftover < 0) return SE_SEALED_NO_ANSWER;
  if (leftover == 1 && !se05xDeleteObject(tempId)) return SE_SEALED_SLOT_TAKEN;

  uint8_t tempKey[32], oneTimeKey[32], tempPublic[SE_EC_POINT_LEN];
  SeSession session;
  SeApdu payload;
  SeSealedResult result = SE_SEALED_OK;
  if (!coldSessionKey(tempKey, 'T', privateKey) || !coldSessionKey(oneTimeKey, 'E', privateKey) ||
      !coldP256PublicKey(tempKey, tempPublic)) {
    result = SE_SEALED_NO_SESSION;
  } else if (!se05xWriteSessionKey(tempId, tempPublic)) {
    result = se05xLastSW ? SE_SEALED_NO_SESSION : SE_SEALED_NO_ANSWER;
  } else if (!se05xOpenECKeySession(session, tempId, tempKey, oneTimeKey)) {
    // A bad receipt leaves se05xLastSW at 9000: the card agreed, the keys didn't.
    result = se05xLastSW == ISO_SW_SUCCESS ? SE_SEALED_TAMPERED
           : se05xLastSW ? SE_SEALED_NO_SESSION : SE_SEALED_NO_ANSWER;
  } else {
    seStart(payload, SE_INS_WRITE, SE_P1_KEY_PAIR | SE_P1_EC, SE_P2_DEFAULT);
    seKeyPairPayload(payload, keyId, phoneKeyId, privateKey, publicKey);
    uint8_t answer[16];
    const int16_t written = payload.overflow ? -1
        : se05xSessionRun(session, SE_INS_WRITE, SE_P1_KEY_PAIR | SE_P1_EC, SE_P2_DEFAULT,
                          payload.bytes + 5, (uint8_t)(payload.len - 5), answer, sizeof(answer));
    if (written == -2)     result = SE_SEALED_TAMPERED;
    else if (written < 0)  result = se05xLastSW ? SE_SEALED_KEY_REFUSED : SE_SEALED_NO_ANSWER;
  }

  // The temporary key goes, whatever happened. The session it opened
  // ends with the card's power, a moment from now; with its key deleted,
  // nothing can be started with it again. If this fails, the next write
  // removes it first.
  const uint16_t outcomeSW = se05xLastSW;
  if (se05xExists(tempId) == 1) se05xDeleteObject(tempId);
  se05xLastSW = outcomeSW;

  coldWipe(tempKey, sizeof(tempKey));
  coldWipe(oneTimeKey, sizeof(oneTimeKey));
  coldWipe(&session, sizeof(session));
  seWipe(payload);
  return result;
}

#endif // COLD_SESSION_H
