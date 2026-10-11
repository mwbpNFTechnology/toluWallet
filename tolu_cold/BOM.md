# toluCold Bill of Materials

Everything needed to build one toluCold. There is no custom PCB: the device is
three off-the-shelf modules, one button and some wire, for under 15 USD in
components. How they connect is in the [README](README.md#wiring).

Values marked **[verify]** depend on the exact module you buy. Check them
against the part in your hand before publishing or ordering in quantity.

## Per-device components

These go into every finished device.

| Ref | Component | Value / Part | Qty | Notes |
|---|---|---|---|---|
| U1 | Microcontroller board | ESP32-S3 dev board, N16R8 [verify: exact board] — or a classic ESP32 Dev Module (ESP32-WROOM-32) | 1 | The default pins in `config.h` are for an S3 N16R8 camera board; the classic ESP32 has its own set, picked automatically. Any ESP32-S3 or ESP32 board with 4 MB of flash or more will run it: the firmware is about 370 KB and uses no PSRAM |
| U2 | NFC module | PN532 NFC module V3, 13.56 MHz, with on-board antenna | 1 | Mode switches set to **SPI**. It is both the reader for the card and the "card" the phone taps |
| U3 | Display | SPI TFT, ILI9341, 240×320, 2.4" or 2.8" [verify: size] | 1 | Recommended: 12 words fit on one page. A touch panel or SD slot on the module is not used. Alternatives the firmware supports: ST7735 1.8" (128×160) or 1.44" (128×128) |
| SW1 | Push button | Momentary, normally open — for example a 6×6 mm tactile switch [verify] | 1 | Optional: the board's own BOOT button (GPIO 0) does the job. A touch module that drives its output high (TTP223 type) also works, with `BTN_ACTIVE_LEVEL HIGH` |
| W1 | Jumper wires | Dupont, 10–20 cm | 16 | 6 for the PN532, 8 for the display, 2 for the button. Female–female when wiring pin to pin, male–female through a breadboard |
| — | Breadboard or perfboard | Half-size breadboard, or a small perfboard for a permanent build | 1 | Three connections go to 3V3 and three to GND, which is more than most boards have pins for |

> Everything runs from the board's 3V3 pin; there is no battery and no separate
> regulator. The PN532 with its field on and the display's backlight together
> draw a few hundred milliamps **[verify: your board's 3V3 regulator can supply
> it]** — a weak supply shows up as NFC reads that fail at random.

## To use it

Not part of the device, but nothing happens without them.

| Item | Suggested | Notes |
|---|---|---|
| tolu card | A [toluTag](https://github.com/mwbpNFTechnology/toluTag) in the card form factor (NXP SE051C) | What the wallet's key is written to. Build one from that repository's `Hardware` folder, or request a dev kit there |
| iPhone with NFC | Running the toluWallet app | Hands over the slots and the password, and checks the card at the end |
| USB power | 5 V charger or power bank, and a cable for the board [verify: USB-C or micro-USB] | Run the ceremony from a charger, not from a computer |
| Pen and paper | — | The seed phrase is shown once and exists nowhere else |

## Tools

Needed once, to put a device together and flash it.

| Item | Suggested | Notes |
|---|---|---|
| Computer | Arduino IDE 2, or `arduino-cli` | Flashes the firmware; see [Build and flash](README.md#build-and-flash) for the board package and libraries |
| USB data cable | To match the board | A charge-only cable powers the board but cannot flash it |
| Soldering iron | Fine tip | Only if a module arrives with its pin header loose — PN532 boards often do — or for a perfboard build |

## Notes

- **3.3 V only.** The ESP32's pins are 3.3 V logic; power both modules from
  3V3, not 5 V.
- **Two SPI buses.** The PN532 and the display must not share clock or data
  wires — they run at different speeds and bit orders. That is why the wiring
  uses separate pins for each and the count is 16 wires rather than fewer.
- **The display's backlight pin (LED)** goes to 3V3, or the screen stays dark.
  Its MISO pin stays unconnected.
- **No enclosure is designed yet.** If you make one, keep metal away from the
  PN532's antenna and leave it reachable: the card and the phone both have to
  rest within a couple of centimetres of it.
- Quantities are for one device.
