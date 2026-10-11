// ============================================================
// cold_util.h - the few helpers every module shares
// ============================================================
#ifndef COLD_UTIL_H
#define COLD_UTIL_H

#include <stdint.h>
#include <stddef.h>

/// Overwrites a buffer in a way the optimiser may not remove. Used on
/// everything that held a password, a seed word or a key.
static inline void coldWipe(void* p, size_t n) {
  volatile uint8_t* v = (volatile uint8_t*)p;
  while (n--) *v++ = 0;
}

// ── Big-endian integers ──────────────────────────────────────
static inline uint32_t coldLoadBe32(const uint8_t* p) {
  return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

static inline void coldStoreBe32(uint8_t* p, uint32_t v) {
  p[0] = (uint8_t)(v >> 24);
  p[1] = (uint8_t)(v >> 16);
  p[2] = (uint8_t)(v >> 8);
  p[3] = (uint8_t)v;
}

static inline uint64_t coldLoadBe64(const uint8_t* p) {
  return ((uint64_t)coldLoadBe32(p) << 32) | coldLoadBe32(p + 4);
}

static inline void coldStoreBe64(uint8_t* p, uint64_t v) {
  coldStoreBe32(p, (uint32_t)(v >> 32));
  coldStoreBe32(p + 4, (uint32_t)v);
}

// The same, chosen by the type of the value — for code written once for
// both word sizes.
static inline void coldLoadBe(const uint8_t* p, uint32_t& out) { out = coldLoadBe32(p); }
static inline void coldLoadBe(const uint8_t* p, uint64_t& out) { out = coldLoadBe64(p); }
static inline void coldStoreBe(uint8_t* p, uint32_t v) { coldStoreBe32(p, v); }
static inline void coldStoreBe(uint8_t* p, uint64_t v) { coldStoreBe64(p, v); }

#endif // COLD_UTIL_H
