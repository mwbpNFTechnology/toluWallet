// ============================================================
// config.h - toluCold configuration
// ============================================================
// Hardware: an ESP32-S3 or a classic ESP32 Dev Module, a PN532 NFC
// module in SPI mode, an SPI TFT, and one push button. The PN532 and
// the TFT are on SEPARATE SPI buses: the PN532 talks LSB-first at
// ~1 MHz, the TFT MSB-first at 20+ MHz, so sharing one bus garbles
// NFC reads.
// ============================================================
#ifndef CONFIG_H
#define CONFIG_H

#define COLD_NAME          "toluCold"

// ---- The wallet it makes ----
// 12 words (128 bits of entropy) or 24 words (256 bits).
#define COLD_MNEMONIC_WORDS   12
// Wrong passwords the card accepts before the key locks for good.
// 0 would mean unlimited.
#define COLD_MAX_ATTEMPTS     5
// How many words of the phrase have to be confirmed.
#define COLD_QUIZ_WORDS       3

// ---- The button ----
// One push button between this pin and GND. GPIO 0 is the BOOT button
// that is already on the board, so the sketch works with no wiring at
// all; change it to the pin your own button is on.
// A touch module such as a TTP223 drives its output HIGH when touched:
// set BTN_ACTIVE_LEVEL to HIGH for those.
#define BTN_PIN            0
#define BTN_ACTIVE_LEVEL   LOW
#define BTN_HOLD_MS            800    // held this long = "select"
#define BTN_DEBOUNCE_MS        25
#define BTN_PROGRESS_AFTER_MS  120    // the hold bar appears after this long

// ---- Timing ----
#define NFC_SPI_HZ         1000000   // PN532 SPI clock (max 5 MHz)
#define NFC_RETRY_MS       200       // pause before arming the reader again
#define PHONE_POLL_MS      60        // one look for a phone on the start screen
#define CARD_POLL_MS       250       // one look for a card
// The app can cancel a ceremony, or start it over, by tapping the phone
// again. While the device waits for the card it therefore stops being a
// reader for this long, between looks for the card, and listens for the
// phone instead. 0 = never listen there: cancel with the button only.
#define PHONE_LISTEN_MS    300
#define PHONE_GLANCE_MS    10        // the same, on screens that wait for the button
#define CARD_REARM_MISSES  8         // restart the reader after this many empty looks
#define CARD_SETTLE_MS     300       // the chip needs a moment once the field powers it
#define PHONE_AWAY_MS      3500      // time to take the phone off the reader
#define NOTICE_MS          2500      // how long a passing message stays up
#define LONG_NOTICE_MS     4000      // the same, for one with more to read
// With a seed phrase on screen and nobody pressing anything, forget it.
#define IDLE_WIPE_MS       (10UL * 60UL * 1000UL)

// ---- Pins ----
// Picked automatically from the board selected in Tools → Board.
#if defined(CONFIG_IDF_TARGET_ESP32S3)
  // ESP32-S3 N16R8 CAM board. Avoids the camera (4-18), octal
  // PSRAM/flash (26-37), USB (19/20), UART0 (43/44) and the RGB LED (48).

  // PN532 on FSPI (the default SPI object)
  #define NFC_SCK    40
  #define NFC_MISO   41
  #define NFC_MOSI   42
  #define NFC_SS     39

  // TFT on HSPI
  #define TFT_SCK    21
  #define TFT_MOSI   47   // board label: SDA / SDI / MOSI
  #define TFT_CS     14
  #define TFT_DC      2   // board label: A0 / DC / RS
  #define TFT_RST     1   // board label: RESET / RST
#else
  // ESP32 Dev Module (classic ESP32)

  // PN532 on VSPI
  #define NFC_SCK    18
  #define NFC_MISO   19
  #define NFC_MOSI   23
  #define NFC_SS      5

  // TFT on HSPI
  #define TFT_SCK    14
  #define TFT_MOSI   13   // board label: SDA / SDI / MOSI
  #define TFT_CS     32
  #define TFT_DC     27   // board label: A0 / DC / RS
  #define TFT_RST    26   // board label: RESET / RST
#endif

// ---- TFT model: uncomment exactly ONE ----
// #define TFT_ST7735_144   // 1.44" 128x128
// #define TFT_ST7735_18    // 1.8"  128x160
#define TFT_ILI9341      // 2.4" / 2.8" 240x320  (recommended: 12 words fit on one page)

// ---- 2.4" / 2.8" orientation (ILI9341 only) ----
// Screen scan direction. Start with 0x88. If the picture is:
//   upside down               → flip 0x80 (0x88 ↔ 0x08)
//   mirrored (text backwards) → flip 0x40 (0x88 ↔ 0xC8)
//   upside down + mirrored    → 0x48
#define TFT_LANDSCAPE_MADCTL  0x88

#endif // CONFIG_H
