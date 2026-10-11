// ============================================================
// cold_reader.h - the PN532 as a reader, talking to the tolu card
// ============================================================
// The card is activated with readPassiveTargetID, then APDUs go through
// InDataExchange, which runs ISO 14443-4 (block numbers, chaining,
// waiting-time extensions) inside the PN532.
// ============================================================
#ifndef COLD_READER_H
#define COLD_READER_H

#include "cold_pn532.h"

// The card may take a while over key operations; the PN532 answers its
// waiting-time extensions by itself in the meantime.
#define READER_EXCHANGE_TIMEOUT_MS  8000

/// Puts the PN532 into reader mode with its field on.
static inline void readerBegin() {
  nfcBegin();
  nfc.SAMConfig();
  nfc.setPassiveActivationRetries(0x03);
  delay(50);
}

/// Looks for an ISO 14443-A card for up to `timeoutMs`.
static inline bool readerFindCard(uint16_t timeoutMs) {
  uint8_t uid[10];
  uint8_t uidLen = 0;
  return nfc.readPassiveTargetID(PN532_MIFARE_ISO14443A, uid, &uidLen, timeoutMs);
}

/// Sends one APDU to the activated card. Returns the number of response
/// bytes written to `rsp` (data followed by SW1 SW2), or <0 on failure
/// (see nfcExchange).
static inline int16_t readerExchange(const uint8_t* apdu, uint8_t apduLen, uint8_t* rsp, uint8_t rspSize) {
  const uint8_t header[2] = { PN532_COMMAND_INDATAEXCHANGE, 0x01 };    // to target #1
  return nfcExchange(header, sizeof(header), apdu, apduLen, rsp, rspSize, READER_EXCHANGE_TIMEOUT_MS);
}

#endif // COLD_READER_H
