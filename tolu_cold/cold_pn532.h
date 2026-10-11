// ============================================================
// cold_pn532.h - the PN532, and what its two roles share
// ============================================================
// One PN532 does two jobs here. It is a CARD while the phone hands
// over the setup (cold_target.h) and a READER while it talks to the
// tolu card (cold_reader.h). Both roles come down to the same two
// conversations with the chip: a command that is only acknowledged,
// and a command answered with a status byte followed by data.
// ============================================================
#ifndef COLD_PN532_H
#define COLD_PN532_H

#include <Arduino.h>
#include <SPI.h>
#include <PN532_SPI.h>
#include <PN532.h>
#include "config.h"
#include "cold_util.h"

PN532_SPI pn532spi(SPI, NFC_SS);
PN532     nfc(pn532spi);

// The PN532 library carries lengths in a uint8_t, so one frame — and
// with it every APDU and every response — stays under 255 bytes.
#define NFC_FRAME_MAX        254
#define NFC_ACK_TIMEOUT_MS   300

/// Starts the SPI link to the PN532.
///
/// nfc.begin() sets the clock with setClockDivider(SPI_CLOCK_DIV8), a
/// raw register value computed for the classic ESP32. On the ESP32-S3
/// the same value gives ~10 MHz, over the PN532's 5 MHz limit: short
/// replies survive, longer ones time out. So the clock is set again,
/// in hertz, after every begin().
static inline void nfcBegin() {
  nfc.begin();
  SPI.setFrequency(NFC_SPI_HZ);
  delay(50);
}

/// A command the PN532 only acknowledges.
static inline bool nfcCommand(const uint8_t* header, uint8_t headerLen,
                              const uint8_t* body, uint8_t bodyLen, uint16_t timeoutMs) {
  if (pn532spi.writeCommand(header, headerLen, body, bodyLen) != 0) return false;
  uint8_t ack[8];
  return pn532spi.readResponse(ack, sizeof(ack), timeoutMs) >= 0;
}

/// A command the PN532 answers with a status byte and data. Copies the
/// data to `out` and returns its length, or:
///   -1  the command could not be sent
///   -2  no answer in time
///   -3  the status byte reports an error (RF error, the other side gone)
///   -4  the data does not fit in `out`
static inline int16_t nfcExchange(const uint8_t* header, uint8_t headerLen,
                                  const uint8_t* body, uint8_t bodyLen,
                                  uint8_t* out, uint8_t outSize, uint16_t timeoutMs) {
  if (pn532spi.writeCommand(header, headerLen, body, bodyLen) != 0) return -1;

  uint8_t frame[NFC_FRAME_MAX];
  const int16_t n = pn532spi.readResponse(frame, sizeof(frame), timeoutMs);
  int16_t result;
  if (n < 1)                 result = -2;
  else if (frame[0] != 0x00) result = -3;
  else if (n - 1 > outSize)  result = -4;
  else {
    result = n - 1;
    memcpy(out, frame + 1, result);
  }
  coldWipe(frame, sizeof(frame));      // it may have carried a password
  return result;
}

/// Switches the PN532's own RF field off.
///
/// SAMConfig() leaves the chip in reader mode with its field on, and an
/// iPhone in a reader field assumes it is at a payment terminal and
/// offers Apple Pay. A card does not need a field of its own — the
/// phone powers it — and neither does an idle device.
static inline bool nfcFieldOff() {
  const uint8_t command[3] = { PN532_COMMAND_RFCONFIGURATION, 0x01, 0x00 };   // item 1 = RF field, off
  return nfcCommand(command, sizeof(command), nullptr, 0, NFC_ACK_TIMEOUT_MS);
}

#endif // COLD_PN532_H
