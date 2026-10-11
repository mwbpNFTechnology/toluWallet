// Shared by the tests: a count of failed checks, and hex in both directions.
#pragma once

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

static int failures = 0;

static inline void check(bool ok, const std::string& what) {
  if (ok) return;
  if (++failures <= 25) printf("FAIL: %s\n", what.c_str());
}

static inline std::string hex(const uint8_t* bytes, size_t count) {
  static const char* digits = "0123456789abcdef";
  std::string text;
  for (size_t i = 0; i < count; i++) {
    text += digits[bytes[i] >> 4];
    text += digits[bytes[i] & 0x0F];
  }
  return text;
}

static inline std::string hex(const std::vector<uint8_t>& bytes) { return hex(bytes.data(), bytes.size()); }

/// "-" stands for no bytes at all.
static inline std::vector<uint8_t> unhex(const std::string& text) {
  std::vector<uint8_t> bytes;
  if (text == "-") return bytes;
  for (size_t i = 0; i + 1 < text.size(); i += 2) {
    bytes.push_back((uint8_t)strtol(text.substr(i, 2).c_str(), nullptr, 16));
  }
  return bytes;
}

/// Prints the verdict and gives main() its exit code.
static inline int finish(const std::string& summary) {
  printf("%s — %s\n", failures ? "FAILED" : "ALL PASS", summary.c_str());
  return failures ? 1 : 0;
}
