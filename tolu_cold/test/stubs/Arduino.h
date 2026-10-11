// Just enough of the Arduino core for the NFC modules to compile on a computer.
#pragma once

#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>

#define LOW  0
#define HIGH 1

inline void delay(unsigned long) {}

struct SerialStub {
  void println(const char*) {}
};
static SerialStub Serial;
