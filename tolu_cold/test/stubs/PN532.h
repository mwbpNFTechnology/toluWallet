// The parts of the PN532 library the firmware names: its command codes
// (same values as the real header) and the reader-mode calls.
#pragma once

#include "PN532_SPI.h"

#define PN532_COMMAND_RFCONFIGURATION  (0x32)
#define PN532_COMMAND_INDATAEXCHANGE   (0x40)
#define PN532_COMMAND_TGGETDATA        (0x86)
#define PN532_COMMAND_TGINITASTARGET   (0x8C)
#define PN532_COMMAND_TGSETDATA        (0x8E)
#define PN532_MIFARE_ISO14443A         (0x00)

struct PN532 {
  explicit PN532(PN532_SPI&) {}
  void begin() {}
  bool SAMConfig() { return true; }
  void setPassiveActivationRetries(uint8_t) {}
  bool readPassiveTargetID(uint8_t, uint8_t*, uint8_t*, uint16_t) { return false; }
};
