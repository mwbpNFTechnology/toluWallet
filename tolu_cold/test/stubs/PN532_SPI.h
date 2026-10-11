// A pretend PN532: it records every command written to it, and answers
// with whatever the test queued (by default a bare "status OK").
#pragma once

#include <deque>
#include <vector>
#include "Arduino.h"
#include "SPI.h"

struct PN532_SPI {
  PN532_SPI(SPIClass&, uint8_t) {}

  /// Every command written, header and body joined.
  std::vector<std::vector<uint8_t>> sent;
  /// Answers to hand out, oldest first. An empty answer means "no reply".
  std::deque<std::vector<uint8_t>> answers;

  int8_t writeCommand(const uint8_t* header, uint8_t headerLen, const uint8_t* body = nullptr, uint8_t bodyLen = 0) {
    std::vector<uint8_t> frame(header, header + headerLen);
    if (body) frame.insert(frame.end(), body, body + bodyLen);
    sent.push_back(frame);
    return 0;
  }

  int16_t readResponse(uint8_t buffer[], uint8_t size, uint16_t) {
    std::vector<uint8_t> answer = { 0x00 };
    if (!answers.empty()) {
      answer = answers.front();
      answers.pop_front();
    }
    if (answer.empty()) return -2;                   // timeout, as the library reports it
    if (answer.size() > size) return -3;
    memcpy(buffer, answer.data(), answer.size());
    return (int16_t)answer.size();
  }
};
