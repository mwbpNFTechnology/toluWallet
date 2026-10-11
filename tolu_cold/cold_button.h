// ============================================================
// cold_button.h - one button: click to move, hold to select
// ============================================================
#ifndef COLD_BUTTON_H
#define COLD_BUTTON_H

#include <Arduino.h>
#include "config.h"

enum ColdButtonEvent { BTN_NONE, BTN_CLICK, BTN_HOLD };

class ColdButton {
 public:
  void begin() {
    pinMode(BTN_PIN, BTN_ACTIVE_LEVEL == LOW ? INPUT_PULLUP : INPUT_PULLDOWN);
    reset();
  }

  /// Call often. Returns a click when the button is let go early, and a
  /// hold — once — the moment it has been down for BTN_HOLD_MS.
  ColdButtonEvent poll() {
    const uint32_t now = millis();
    const bool raw = isDown();
    if (raw != _lastRaw) { _lastRaw = raw; _changedAt = now; }

    if (raw != _stable && now - _changedAt >= BTN_DEBOUNCE_MS) {
      _stable = raw;
      if (_stable) {
        _downAt = now;
        _holdFired = false;
      } else if (!_holdFired) {
        return BTN_CLICK;
      }
    }

    if (_stable && !_holdFired && now - _downAt >= BTN_HOLD_MS) {
      _holdFired = true;
      return BTN_HOLD;
    }
    return BTN_NONE;
  }

  /// 0..100 while the button is on its way to a hold, otherwise 0.
  uint8_t holdProgress() const {
    if (!_stable || _holdFired) return 0;
    const uint32_t held = millis() - _downAt;
    if (held < BTN_PROGRESS_AFTER_MS) return 0;       // a click should not flash the bar
    const uint32_t percent = held * 100 / BTN_HOLD_MS;
    return (uint8_t)(percent > 100 ? 100 : percent);
  }

  /// Blocks until the button is up, so a press that began on one screen
  /// cannot count as an answer on the next.
  void waitRelease() {
    while (isDown()) delay(5);
    reset();
  }

 private:
  static bool isDown() { return digitalRead(BTN_PIN) == BTN_ACTIVE_LEVEL; }

  void reset() {
    _stable = false;
    _lastRaw = false;
    _holdFired = false;
    _changedAt = millis();
  }

  bool     _stable = false;
  bool     _lastRaw = false;
  bool     _holdFired = false;
  uint32_t _changedAt = 0;
  uint32_t _downAt = 0;
};

#endif // COLD_BUTTON_H
