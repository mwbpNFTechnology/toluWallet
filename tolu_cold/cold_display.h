// ============================================================
// cold_display.h - TFT screens for the cold-wallet flow
// ============================================================
// Adafruit GFX with its built-in font, and the QR generator that ships
// in the ESP32 Arduino core. Layouts are computed from the screen size,
// so the smaller TFTs work too — they just page through the words.
// ============================================================
#ifndef COLD_DISPLAY_H
#define COLD_DISPLAY_H

#include <SPI.h>
#include <Adafruit_GFX.h>
#include "qrcode.h"   // esp_qrcode_*, part of the ESP32 Arduino core
#include "config.h"
#include "cold_bip39_words.h"

#if defined(TFT_ILI9341)
  #include <Adafruit_ILI9341.h>
#else
  #include <Adafruit_ST7735.h>
#endif

// RGB565
#define COL_BG     0x0000  // black
#define COL_FG     0xFFFF  // white
#define COL_DIM    0x8410  // grey
#define COL_LIME   0xC789  // tolu lime  (#C6F24E)
#define COL_AMBER  0xF587  // tolu amber (#F5B13A)
#define COL_ERR    0xF800  // red
#define COL_PANEL  0x18E3  // dark grey panel

// The built-in font is 6x8 pixels at size 1 and scales by whole numbers.
#define FONT_W        6
#define FONT_H        8
#define MARGIN        12   // left and right inset of body text
#define LINE_GAP      4    // between wrapped lines
#define HOLD_BAR_H    4
#define ADDRESS_LEN   42   // "0x" + 40 hex digits

// The display has an SPI bus to itself (see config.h).
SPIClass tftSPI(HSPI);

#if defined(TFT_ILI9341)
// Some 2.4"/2.8" boards sold as ILI9341 carry a controller that scans
// 320x240 natively. Adafruit's setRotation() assumes 240x320, so the
// scan direction and size are set by hand instead.
class ColdTFT : public Adafruit_ILI9341 {
 public:
  using Adafruit_ILI9341::Adafruit_ILI9341;

  void useNativeLandscape(uint8_t madctl) {
    sendCommand(ILI9341_MADCTL, &madctl, 1);
    _width  = 320;
    _height = 240;
  }
};
ColdTFT tft(&tftSPI, TFT_DC, TFT_CS, TFT_RST);
#else
Adafruit_ST7735 tft(&tftSPI, TFT_CS, TFT_DC, TFT_RST);
#endif

// How far the hold bar is drawn, so it is only redrawn when it moves.
static uint8_t holdBarPercent = 0;

// ── Text ─────────────────────────────────────────────────────
static inline int imin(int a, int b) { return a < b ? a : b; }
static inline int imax(int a, int b) { return a > b ? a : b; }

static inline int16_t lineHeight(uint8_t size) { return FONT_H * size; }
static inline int16_t textWidth(const char* text, uint8_t size) { return (int16_t)strlen(text) * FONT_W * size; }
static inline int16_t bodyWidth() { return tft.width() - 2 * MARGIN; }

// Size 1 on the small 128px screens, size 2 on 240px+ screens.
static inline uint8_t baseTextSize() { return imin(tft.width(), tft.height()) >= 200 ? 2 : 1; }

/// Largest size (up to `maxSize`) at which `text` fits in `width`.
static inline uint8_t fitTextSize(const char* text, uint8_t maxSize, int16_t width) {
  for (uint8_t size = maxSize; size > 1; size--) {
    if (textWidth(text, size) <= width - 8) return size;
  }
  return 1;
}

static inline void printAt(const char* text, int16_t x, int16_t y, uint8_t size, uint16_t color) {
  tft.setTextSize(size);
  tft.setTextColor(color);
  tft.setCursor(x, y);
  tft.print(text);
}

/// Centred in [x, x + w); by default across the whole screen.
static inline void printCentered(const char* text, int16_t y, uint8_t size, uint16_t color,
                                 int16_t x = 0, int16_t w = -1) {
  if (w < 0) w = tft.width();
  printAt(text, x + (w - textWidth(text, size)) / 2, y, size, color);
}

/// Lays `text` out word-wrapped and centred inside [x, x + w), and
/// returns the y below it. With `draw` false it only measures.
static inline int16_t layoutWrapped(const char* text, int16_t x, int16_t y, int16_t w,
                                    uint8_t size, uint16_t color, bool draw = true) {
  const int16_t maxChars = (int16_t)imax(1, w / (FONT_W * size));
  char line[64];
  const char* p = text;
  while (*p) {
    while (*p == ' ') p++;
    int16_t len = 0, lastSpace = -1;
    while (p[len] && len < maxChars && len < (int16_t)sizeof(line) - 1) {
      if (p[len] == ' ') lastSpace = len;
      len++;
    }
    if (p[len] && p[len] != ' ' && lastSpace > 0) len = lastSpace;   // break at a space
    if (draw) {
      memcpy(line, p, len);
      line[len] = '\0';
      printCentered(line, y, size, color, x, w);
    }
    y += lineHeight(size) + LINE_GAP;
    p += len;
  }
  return y;
}

// ── Screen furniture ─────────────────────────────────────────
static inline void clearScreen() {
  tft.fillScreen(COL_BG);
  holdBarPercent = 0;
}

static inline int16_t headerBottom() { return 8 + lineHeight(baseTextSize()) + 12; }

static inline void drawHeader(const char* title, uint16_t color) {
  clearScreen();
  printAt(title, 8, 8, baseTextSize(), color);
  tft.drawFastHLine(0, headerBottom() - 6, tft.width(), COL_PANEL);
}

/// One dim line of hints along the bottom.
static inline void drawFooter(const char* hint) {
  const int16_t y = tft.height() - 18;
  tft.fillRect(0, y - 4, tft.width(), 2 * FONT_H, COL_BG);
  printCentered(hint, y, 1, COL_DIM);
}

/// A thin bar along the bottom edge that fills while the button is
/// held. Call it as often as you like: it draws only when it changes.
static inline void showHoldProgress(uint8_t percent) {
  if (percent == holdBarPercent) return;
  holdBarPercent = percent;
  const int16_t y = tft.height() - HOLD_BAR_H;
  const int16_t filled = (int16_t)((int32_t)tft.width() * percent / 100);
  tft.fillRect(0, y, filled, HOLD_BAR_H, COL_LIME);
  tft.fillRect(filled, y, tft.width() - filled, HOLD_BAR_H, COL_BG);
}

// ── Screens ──────────────────────────────────────────────────
static inline void displayBegin() {
  tftSPI.begin(TFT_SCK, -1, TFT_MOSI, TFT_CS);

#if defined(TFT_ILI9341)
  tft.begin();
  tft.useNativeLandscape(TFT_LANDSCAPE_MADCTL);
#elif defined(TFT_ST7735_18)
  tft.initR(INITR_BLACKTAB);
  tft.setRotation(0);
#else
  tft.initR(INITR_144GREENTAB);
  tft.setRotation(0);
#endif

  clearScreen();
}

/// A title and a few centred lines: every "do this now" moment in the flow.
static inline void showMessage(const char* title, uint16_t titleColor,
                               const char* body, const char* footer = nullptr) {
  drawHeader(title, titleColor);
  const uint8_t size = baseTextSize();
  const int16_t top = headerBottom();
  const int16_t room = tft.height() - top - 24;
  const int16_t height = layoutWrapped(body, MARGIN, 0, bodyWidth(), size, COL_FG, false);
  layoutWrapped(body, MARGIN, top + (int16_t)imax(4, (room - height) / 2), bodyWidth(), size, COL_FG);
  if (footer) drawFooter(footer);
}

static inline void showErrorScreen(const char* message, const char* footer = nullptr) {
  showMessage("PROBLEM", COL_ERR, message, footer);
}

static inline void showIdleScreen() {
  clearScreen();
  const uint8_t small = baseTextSize();
  const uint8_t title = fitTextSize(COLD_NAME, 4, tft.width());
  int16_t y = tft.height() / 2 - lineHeight(title) - 28;
  printCentered(COLD_NAME, y, title, COL_LIME);
  y += lineHeight(title) + 10;
  printCentered("cold wallet setup", y, small, COL_FG);
  y += lineHeight(small) + 16;
  layoutWrapped("In toluWallet choose Create with a cold device, then hold the phone here.",
                MARGIN, y, bodyWidth(), 1, COL_DIM);
  drawFooter("not connected to anything");
}

/// What the phone sent, so it can be checked before a card is touched.
/// The password itself is never drawn.
static inline void showSetupScreen(uint32_t keyId, uint32_t passwordId, uint8_t passwordLen) {
  drawHeader("SETUP RECEIVED", COL_LIME);
  const uint8_t size = baseTextSize();
  int16_t y = headerBottom() + 4;
  char line[40];
  auto printRow = [&](uint16_t color) {
    printAt(line, MARGIN, y, size, color);
    y += lineHeight(size) + 8;
  };

  snprintf(line, sizeof(line), "key slot  %08lX", (unsigned long)keyId);
  printRow(COL_FG);
  snprintf(line, sizeof(line), "pass slot %08lX", (unsigned long)passwordId);
  printRow(COL_FG);
  snprintf(line, sizeof(line), "password  %u characters", passwordLen);
  printRow(COL_FG);
  snprintf(line, sizeof(line), "attempts  %u, then locked", (unsigned)COLD_MAX_ATTEMPTS);
  printRow(COL_AMBER);

  layoutWrapped("Take the phone away, then hold the tolu card on the reader.",
                MARGIN, y + 6, bodyWidth(), 1, COL_DIM);
  drawFooter("hold: cancel");
}

/// How the phrase is laid out: columns, rows per page, and pages. Rows
/// are balanced, so 12 words show as 6 + 6 rather than 7 + 5.
struct WordLayout {
  int     cols, rows, perPage, pages;
  int16_t rowHeight;
};

static inline WordLayout wordLayout(int count) {
  WordLayout l;
  l.rowHeight = lineHeight(baseTextSize()) + 10;
  l.cols = (tft.width() >= 300) ? 2 : 1;
  const int maxRows = imax(1, (tft.height() - headerBottom() - 22) / l.rowHeight);
  l.pages = (count + maxRows * l.cols - 1) / (maxRows * l.cols);
  const int perPageNeeded = (count + l.pages - 1) / l.pages;
  l.rows = imin(maxRows, (perPageNeeded + l.cols - 1) / l.cols);
  l.perPage = l.rows * l.cols;
  return l;
}

/// One page of the seed phrase, numbered.
static inline void showWordsScreen(const uint16_t* words, int count, int page) {
  const WordLayout l = wordLayout(count);
  char title[48];
  if (l.pages > 1) snprintf(title, sizeof(title), "WRITE THESE DOWN %d/%d", page + 1, l.pages);
  else             snprintf(title, sizeof(title), "WRITE THESE DOWN");
  drawHeader(title, COL_AMBER);

  const uint8_t size = baseTextSize();
  const int16_t colWidth = tft.width() / l.cols;
  const int first = page * l.perPage;

  for (int i = 0; i < l.perPage && first + i < count; i++) {
    const int col = i / l.rows, row = i % l.rows;    // fill down the column, then across
    const int16_t x = col * colWidth + 10;
    const int16_t y = headerBottom() + row * l.rowHeight;
    char number[16];
    snprintf(number, sizeof(number), "%2d.", first + i + 1);
    printAt(number, x, y, size, COL_DIM);
    printAt(COLD_BIP39_WORDS[words[first + i] & 0x7FF], x + 4 * FONT_W * size, y, size, COL_FG);
  }
  drawFooter(l.pages > 1 ? "click: next page   hold: I wrote them all"
                         : "hold the button when all are written down");
}

/// "Word #7 is…" with the choices underneath, one of them highlighted.
static inline void showQuizScreen(int question, int total, int position,
                                  const uint16_t* options, int optionCount, int selected) {
  char title[32];
  snprintf(title, sizeof(title), "CONFIRM %d/%d", question + 1, total);
  drawHeader(title, COL_LIME);

  const uint8_t size = baseTextSize();
  char ask[32];
  snprintf(ask, sizeof(ask), "word #%d is", position + 1);
  printCentered(ask, headerBottom(), size, COL_FG);

  const uint8_t optionSize = size + 1;
  const int16_t boxHeight = lineHeight(optionSize) + 8;
  const int16_t top = headerBottom() + lineHeight(size) + 12;
  for (int i = 0; i < optionCount; i++) {
    const int16_t y = top + i * (boxHeight + 6);
    const bool on = i == selected;
    tft.fillRect(MARGIN, y, bodyWidth(), boxHeight, on ? COL_LIME : COL_PANEL);
    printCentered(COLD_BIP39_WORDS[options[i] & 0x7FF], y + (boxHeight - lineHeight(optionSize)) / 2,
                  optionSize, on ? COL_BG : COL_FG);
  }
  drawFooter("click: move   hold: choose");
}

// esp_qrcode_generate() takes a plain C callback, so the square the QR
// should fill is passed through these.
static int16_t qrX, qrY, qrSide;

static inline void drawQrCallback(esp_qrcode_handle_t qr) {
  const int size   = esp_qrcode_get_size(qr);
  const int border = 2;                                   // quiet zone, in modules
  const int total  = size + border * 2;
  const int scale  = imax(1, qrSide / total);
  const int px     = total * scale;
  const int ox     = qrX + (qrSide - px) / 2;
  const int oy     = qrY + (qrSide - px) / 2;

  tft.fillRect(ox, oy, px, px, COL_FG);
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      if (esp_qrcode_get_module(qr, x, y)) {
        tft.fillRect(ox + (x + border) * scale, oy + (y + border) * scale, scale, scale, COL_BG);
      }
    }
  }
}

/// A QR code of `text`, as large as fits the square at (x, y).
static inline void drawQr(const char* text, int16_t x, int16_t y, int16_t side) {
  qrX = x;
  qrY = y;
  qrSide = side;

  esp_qrcode_config_t config = {};
  config.display_func       = drawQrCallback;
  config.qrcode_ecc_level   = ESP_QRCODE_ECC_MED;
  config.max_qrcode_version = 6;      // a 42-character address is version 3
  if (esp_qrcode_generate(&config, text) != ESP_OK) printAt("QR error", x + 8, y + 8, 1, COL_ERR);
}

/// The wallet exists: its address as a QR for the phone, and as text.
static inline void showDoneScreen(const char* address) {
  clearScreen();

  if (tft.width() > tft.height()) {
    // Wide: the QR on the left, the words on the right.
    const int16_t side = tft.height() - 20;
    drawQr(address, 4, 4, side);

    const int16_t x = side + 10, w = tft.width() - x - 4;
    printCentered("WALLET", 12, 2, COL_LIME, x, w);
    printCentered("READY", 32, 2, COL_LIME, x, w);
    int16_t y = layoutWrapped("Scan this in toluWallet, then tap the card on the phone.", x, 62, w, 1, COL_FG) + 8;

    // The address in three rows.
    const int rowLen = ADDRESS_LEN / 3;
    char row[ADDRESS_LEN / 3 + 1];
    for (int i = 0; i < ADDRESS_LEN; i += rowLen) {
      memcpy(row, address + i, rowLen);
      row[rowLen] = '\0';
      printCentered(row, y, 1, COL_DIM, x, w);
      y += FONT_H + LINE_GAP;
    }
  } else {
    drawQr(address, 0, 0, tft.width());
    printCentered("WALLET READY", tft.width() + 4, 1, COL_LIME);
  }
  drawFooter("hold: finish and clear");
}

#endif // COLD_DISPLAY_H
