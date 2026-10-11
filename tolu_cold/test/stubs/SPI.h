// The SPI bus, as far as the NFC modules use it.
#pragma once

#include <cstdint>

struct SPIClass {
  void setFrequency(uint32_t) {}
};
static SPIClass SPI;
