// ═══════════════════════════════════════════════════════════════
//  tolu_cold.ino — offline key ceremony for a toluWallet card
//
//  Makes a wallet whose private key never touches a phone or the
//  internet. The phone hands over only the slots and its own public key
//  — nothing secret. The seed phrase starts from random numbers
//  generated inside the card's secure element, mixed with this chip's
//  own; it is shown once on this screen, and the key goes straight onto
//  the card, bound to the phone's key: only a session that phone opens,
//  after Face ID, can ever use it.
//
//    1. phone on the reader   → slots + the phone's public key arrive
//    2. card on the reader    → random numbers from the secure element → 12 words
//    3. write the words down  → confirm three of them with the button
//    4. card on the reader    → phone key + wallet key written, the key
//                               inside an encrypted session (cold_session.h)
//    5. QR with the address   → scan it in toluWallet, which checks the
//                               card in its own session
//
//  Until the wallet is finished the phone can tap again to cancel, or
//  to start over with new details; while the card is awaited, holding
//  the button cancels too.
//
//  Libraries: PN532 + PN532_SPI (Seeed-Studio/PN532), Adafruit GFX and
//  Adafruit ILI9341 (or ST7735). The QR generator is part of the ESP32
//  Arduino core. Pins and options are in config.h.
//
//  There is no Wi-Fi, no Bluetooth and no serial protocol in this
//  sketch. Serial prints progress only — never the words or the key.
//  Keep it that way.
// ═══════════════════════════════════════════════════════════════

#include <SPI.h>
#include <esp_random.h>
#include <bootloader_random.h>

#include "config.h"
#include "cold_util.h"
#include "cold_sha2.h"
#include "cold_secp256k1.h"
#include "cold_keccak.h"
#include "cold_bip39.h"
#include "cold_bip32.h"
#include "cold_entropy.h"
#include "cold_display.h"
#include "cold_button.h"
#include "cold_target.h"
#include "cold_reader.h"
#include "cold_se05x.h"
#include "cold_aes.h"
#include "cold_p256.h"
#include "cold_session.h"
#include "cold_state.h"

ColdButton  button;
ColdSecrets secrets;
ColdQuiz    quiz;
ColdState   state = ST_WAIT_PHONE;
ColdState   retryState = ST_WAIT_PHONE;   // where a hold on the failure screen leads
bool        targetArmed = false;
uint32_t    lastActivity = 0;
int         cardMisses = 0;
int         wordPage = 0;

// ── Small helpers ────────────────────────────────────────────
static void touch() { lastActivity = millis(); }

/// A number below `below`. It only ever decides which words the quiz
/// asks about — nothing a key is made from.
static uint32_t randomBelow(uint32_t below) { return esp_random() % below; }

/// A random value below `below` that is not one of the first `count`
/// entries of `taken`.
static uint16_t randomExcept(uint16_t below, const uint16_t* taken, int count) {
  for (;;) {
    const uint16_t candidate = (uint16_t)randomBelow(below);
    bool isTaken = false;
    for (int i = 0; i < count; i++) isTaken = isTaken || taken[i] == candidate;
    if (!isTaken) return candidate;
  }
}

/// The PN532 at rest: field off, not listening.
static void radioOff() {
  nfcFieldOff();
  targetArmed = false;
}

/// The PN532 as a reader, field on, ready to look for the card.
static void radioReader() {
  readerBegin();
  targetArmed = false;
}

/// Moves to a state that waits on the button. A press that began on the
/// screen before is let go first, so it cannot count as an answer here.
static void awaitButton(ColdState next) {
  state = next;
  button.waitRelease();
  touch();
}

static void enterWaitPhone() {
  secrets.wipeAll();
  state = ST_WAIT_PHONE;
  targetArmed = false;
  showIdleScreen();
  touch();
}

// ── Failures ─────────────────────────────────────────────────
/// Shows what went wrong. A hold then leads to `next`.
static void fail(const char* message, ColdState next, const char* footer) {
  radioOff();
  retryState = next;
  showErrorScreen(message, footer);
  awaitButton(ST_FAILED);
}

/// A failure nothing can be done about from here: start again.
static void failFatal(const char* message) {
  fail(message, ST_WAIT_PHONE, "hold: start over");
}

/// A card step that can be tried again: a hold leads back to the wait
/// it came from. Shows the card's status word when it gave one.
static void failCardStep(const char* what) {
  char message[96];
  if (se05xLastSW) snprintf(message, sizeof(message), "%s (card said %04X).", what, se05xLastSW);
  else             snprintf(message, sizeof(message), "%s. Keep the card still on the reader.", what);
  fail(message, state, "hold: try again");
}

// ── Waiting for the card ─────────────────────────────────────
/// Starts looking for a card, leaving whatever is on screen.
static void startCardWait(ColdState next) {
  state = next;
  cardMisses = 0;
  radioReader();
  touch();
}

/// Asks for the card on screen, then starts looking for it.
static void waitForCard(ColdState next) {
  const char* cancelHint = "hold: cancel";
  if (next == ST_WAIT_CARD_ENTROPY) {
    showMessage("CARD", COL_LIME, "Hold the tolu card on the reader.", cancelHint);
  } else {
    showMessage("ALMOST DONE", COL_LIME, "Hold the tolu card on the reader again to write the key.", cancelHint);
  }
  startCardWait(next);
}

/// Selects the SE05x applet on the card that was just found. If it will
/// not select — not a tolu card, or it moved — says so and goes back to
/// waiting; nothing is lost.
static bool selectCard() {
  // The chip needs a moment once the field powers it, and the first
  // SELECT sometimes fails where the second works.
  for (int attempt = 0; attempt < 3; attempt++) {
    delay(CARD_SETTLE_MS);
    if (se05xSelect()) return true;
  }
  showMessage("NOT A TOLU CARD", COL_ERR, "Hold the tolu card flat on the reader.");
  delay(NOTICE_MS);
  waitForCard(state);
  return false;
}

/// True when the phone key slot is free or already holds this phone's
/// key. Otherwise the flow has been failed, as for `slotIsFree`.
static bool phoneKeySlotUsable() {
  const int slot = se05xPhoneKeySlot(secrets.setup.phoneKeyId, secrets.setup.phoneKey);
  if (slot == 0 || slot == 1) return true;
  if (slot < 0) {
    failCardStep("The card did not answer");
    return false;
  }
  failFatal("The phone key slot holds another key on this card. Choose another object id in the app.");
  return false;
}

/// True when nothing is in the slot. Otherwise the flow has been
/// failed: for good if the slot is taken, for another try if the card
/// did not say.
static bool slotIsFree(uint32_t objectId, const char* name) {
  const int exists = se05xExists(objectId);
  if (exists == 0) return true;
  if (exists < 0) {
    failCardStep("The card did not answer");
    return false;
  }
  char message[112];
  snprintf(message, sizeof(message),
           "The %s slot is already used on this card. Choose another object id in the app.", name);
  failFatal(message);
  return false;
}

// ── The phone ────────────────────────────────────────────────
/// Starts a ceremony with the setup the phone just handed over —
/// replacing whatever was going on before.
static void beginCeremony(const ColdSetup& setup) {
  secrets.wipeAll();
  secrets.setup = setup;
  showSetupScreen(setup.keyId, setup.phoneKeyId);
  // Give the phone time to leave before the reader field comes on — a
  // phone in a reader field offers Apple Pay.
  delay(PHONE_AWAY_MS);
  startCardWait(ST_WAIT_CARD_ENTROPY);
}

/// Stops the ceremony and forgets everything: asked for by the phone,
/// or by holding the button while the card is awaited.
static void cancelCeremony() {
  const char* onCard = secrets.keyWritten ? "The key may already be on the card: use another key slot next time."
                                         : "No key was written to the card.";
  secrets.wipeAll();
  radioOff();
  Serial.println("[flow] cancelled");

  char message[136];
  snprintf(message, sizeof(message), "Everything here was erased. %s", onCard);
  showMessage("CANCELLED", COL_AMBER, message);
  delay(LONG_NOTICE_MS);
  enterWaitPhone();
}

/// Listens for the phone for `waitMs` — as a card, with no field of our
/// own, so an iPhone sees a tag and not a payment terminal. A setup
/// starts a ceremony, a cancel ends the one in progress. Returns true
/// when either happened, so the caller drops what it was doing.
static bool listenForPhone(uint16_t waitMs) {
  if (!targetArmed) {
    nfcFieldOff();
    targetArmed = targetArm();
    if (!targetArmed) {
      delay(NFC_RETRY_MS);
      return false;
    }
  }

  ColdTap tap;
  const int result = targetCheck(tap, waitMs);
  if (result == 0) return false;           // nobody yet; still armed
  targetArmed = false;                     // a tap ended, one way or the other

  bool acted = true;
  if (tap.setup.complete)                         beginCeremony(tap.setup);
  else if (tap.cancel && state != ST_WAIT_PHONE)  cancelCeremony();
  else                                            acted = false;
  tap.setup.reset();
  return acted;
}

// ── Step 2: random numbers → seed phrase ─────────────────────
static void showWords() {
  showWordsScreen(secrets.words, secrets.wordCount, wordPage);
}

static void enterShowWords() {
  wordPage = 0;
  showWords();
  awaitButton(ST_SHOW_WORDS);
}

/// Fills `entropy` from two generators hashed into one (cold_entropy.h):
/// the one inside the card's secure element, and this chip's. Returns
/// false — with the flow already failed — if the card's cannot be used.
static bool gatherEntropy(uint8_t* entropy, uint8_t entropyLen) {
  uint8_t cardRandom[COLD_ENTROPY_SOURCE_BYTES];
  if (!se05xGetRandom(cardRandom, sizeof(cardRandom))) {
    failCardStep("The card gave no random numbers");
    return false;
  }

  // A generator that returns one repeated byte is broken. The mix would
  // still make a good phrase, but a card like that cannot be trusted to
  // sign either — it needs a fresh random number every time.
  bool usable = false;
  for (size_t i = 1; i < sizeof(cardRandom); i++) usable = usable || cardRandom[i] != cardRandom[0];

  uint8_t deviceRandom[COLD_ENTROPY_SOURCE_BYTES];
  esp_fill_random(deviceRandom, sizeof(deviceRandom));
  if (usable) coldMixEntropy(cardRandom, deviceRandom, entropy, entropyLen);
  coldWipe(cardRandom, sizeof(cardRandom));
  coldWipe(deviceRandom, sizeof(deviceRandom));

  if (!usable) failFatal("The card's random numbers look wrong. Do not use this card.");
  return usable;
}

static void readEntropy() {
  showMessage("READING CARD", COL_AMBER,
              "Taking random numbers from the card's secure element. Keep it on the reader.");
  if (!selectCard()) return;

  // This card, and no other, gets the key.
  if (!se05xReadUniqueId(secrets.cardId)) {
    failCardStep("The card did not say which card it is");
    return;
  }
  secrets.cardChosen = true;

  // Find out now that a slot is taken — not after the words are written down.
  if (!slotIsFree(secrets.setup.keyId, "key") || !phoneKeySlotUsable()) return;

  const uint8_t entropyLen = (COLD_MNEMONIC_WORDS == 24) ? 32 : 16;
  uint8_t entropy[32];
  if (!gatherEntropy(entropy, entropyLen)) return;
  secrets.wordCount = coldMnemonicFromEntropy(entropy, entropyLen, secrets.words);
  coldWipe(entropy, sizeof(entropy));
  if (secrets.wordCount == 0) {
    failFatal("Could not build the seed phrase.");
    return;
  }

  radioOff();                         // the card can come off the reader now
  Serial.println("[flow] seed phrase on screen");
  enterShowWords();
}

// ── Step 3: confirm three words ──────────────────────────────
static void showQuiz() {
  showQuizScreen(quiz.question, COLD_QUIZ_WORDS, quiz.position(), quiz.choices, COLD_QUIZ_CHOICES, quiz.selected);
}

/// Puts the current question on screen: the right word and others from
/// the list, all different, in random order.
static void askQuizQuestion() {
  quiz.choices[0] = secrets.words[quiz.position()];
  for (int i = 1; i < COLD_QUIZ_CHOICES; i++) {
    quiz.choices[i] = randomExcept(COLD_BIP39_WORD_COUNT, quiz.choices, i);
  }
  // The right word is first so far; move it to a random place.
  const uint32_t place = randomBelow(COLD_QUIZ_CHOICES);
  const uint16_t correct = quiz.choices[0];
  quiz.choices[0] = quiz.choices[place];
  quiz.choices[place] = correct;

  quiz.selected = 0;
  showQuiz();
}

static void startQuiz() {
  // Different positions, in a random order.
  for (int i = 0; i < COLD_QUIZ_WORDS; i++) {
    quiz.positions[i] = randomExcept((uint16_t)secrets.wordCount, quiz.positions, i);
  }
  quiz.question = 0;
  askQuizQuestion();
  awaitButton(ST_QUIZ);
}

// ── Step 4: derive the key and put it on the card ────────────
static bool deriveWallet() {
  showMessage("WORKING", COL_AMBER, "Deriving the wallet key from the words...");

  uint8_t seed[64];
  bool ok = coldSeedFromMnemonic(secrets.words, secrets.wordCount, seed);
  ok = ok && coldDeriveEthereumKey(seed, secrets.privateKey);
  ok = ok && coldPublicKey(secrets.privateKey, secrets.publicKey);
  coldWipe(seed, sizeof(seed));
  if (!ok) return false;

  uint8_t address[20];
  coldAddressFromPublicKey(secrets.publicKey, address);
  coldChecksumAddress(address, secrets.address);
  return true;
}

static void writeKey() {
  showMessage("WRITING", COL_AMBER, "Keep the card on the reader.");
  if (!selectCard()) return;

  const ColdSetup& setup = secrets.setup;

  // Only the card the words were made with. On any other card the key
  // slot could hold someone else's key, and the phone key would be missing.
  uint8_t cardId[SE_UNIQUE_ID_LEN];
  if (!se05xReadUniqueId(cardId)) {
    failCardStep("The card did not say which card it is");
    return;
  }
  const bool sameCard = secrets.cardChosen && memcmp(cardId, secrets.cardId, sizeof(cardId)) == 0;
  coldWipe(cardId, sizeof(cardId));
  if (!sameCard) {
    fail("This is not the card the words were made with. Hold that card on the reader.", state, "hold: try again");
    return;
  }

  // The phone key: free, or already this phone's (an earlier wallet, or
  // an earlier try of this one).
  const int phoneSlot = se05xPhoneKeySlot(setup.phoneKeyId, setup.phoneKey);
  if (phoneSlot < 0) { failCardStep("The card did not answer"); return; }
  if (phoneSlot == 2) {
    failFatal("The phone key slot holds another key on this card. Choose another object id in the app.");
    return;
  }

  // The key slot was free when the words were made. Taken now, it is
  // this run's key — but only if this run got as far as writing it.
  const int keySlot = se05xExists(setup.keyId);
  if (keySlot < 0) { failCardStep("The card did not answer"); return; }
  if (keySlot == 1 && !secrets.keyWritten) {
    failFatal("The key slot is already used on this card. Choose another object id in the app.");
    return;
  }

  // Same order as the toluWallet app: curves, phone key, wallet key.
  if (phoneSlot == 0 || keySlot == 0) se05xInitCurves();
  if (phoneSlot == 0 && !se05xWritePhoneKey(setup.phoneKeyId, setup.phoneKey)) {
    failCardStep("The phone key could not be written");
    return;
  }
  if (keySlot == 0) {
    // From here the slot may hold the key, even if its answer gets lost.
    secrets.keyWritten = true;
    const SeSealedResult sealed = se05xImportKeyPairSealed(setup.keyId, setup.phoneKeyId, COLD_TEMP_KEY_ID,
                                                           secrets.privateKey, secrets.publicKey);
    switch (sealed) {
      case SE_SEALED_OK:
        break;
      case SE_SEALED_SLOT_TAKEN: {
        char message[112];
        snprintf(message, sizeof(message), "Slot %08lX on this card holds an object this device can't remove. It needs that slot.",
                 (unsigned long)COLD_TEMP_KEY_ID);
        failFatal(message);
        return;
      }
      case SE_SEALED_NO_SESSION:
        failCardStep("The card would not open an encrypted session");
        return;
      case SE_SEALED_KEY_REFUSED:
        failCardStep("The key could not be written");
        return;
      case SE_SEALED_TAMPERED:
        failCardStep("An answer from the card did not check out");
        return;
      case SE_SEALED_NO_ANSWER:
      default:
        failCardStep("The card did not answer");
        return;
    }
    Serial.println("[card] key written, encrypted");
  }

  // This device can't read the key back: only the phone's session may.
  // That is the phone's last step — it reads the key in its own session
  // and must find the address on this screen. Here: the key is there.
  if (se05xExists(setup.keyId) != 1) {
    failCardStep("The key is not on the card");
    return;
  }

  // Done. From here the only copies of the key are the card and the paper.
  secrets.wipeKeyMaterial();
  radioOff();
  Serial.println("[flow] wallet ready");
  showDoneScreen(secrets.address);
  awaitButton(ST_DONE);
}

static void pollCard() {
  if (readerFindCard(CARD_POLL_MS)) {
    touch();
    if (state == ST_WAIT_CARD_ENTROPY) readEntropy();
    else                               writeKey();
    return;
  }

  // No card yet, and the wait can be called off: by holding the button…
  if (button.poll() == BTN_HOLD) {
    cancelCeremony();
    return;
  }
  // …or from the phone, for which the PN532 has to stop being a reader
  // for a moment and listen.
  const bool listens = PHONE_LISTEN_MS > 0;
  if (listens && listenForPhone(PHONE_LISTEN_MS)) return;

  // Back to reader mode after listening. Without listening, a restart
  // now and then keeps a stalled poll from sticking.
  if (listens || ++cardMisses % CARD_REARM_MISSES == 0) radioReader();
}

// ── The button ───────────────────────────────────────────────
/// Words on screen: a click turns the page, a hold starts the quiz.
static void onWordsButton(ColdButtonEvent event) {
  if (event == BTN_HOLD) {
    startQuiz();
    return;
  }
  const int pages = wordLayout(secrets.wordCount).pages;
  if (pages > 1) {
    wordPage = (wordPage + 1) % pages;
    showWords();
  }
}

/// A quiz question on screen: a click moves, a hold answers.
static void onQuizButton(ColdButtonEvent event) {
  if (event == BTN_CLICK) {
    quiz.selected = (quiz.selected + 1) % COLD_QUIZ_CHOICES;
    showQuiz();
    return;
  }

  if (quiz.choices[quiz.selected] != secrets.words[quiz.position()]) {
    char message[80];
    snprintf(message, sizeof(message),
             "That is not word #%d. Read the words again and check what you wrote.", quiz.position() + 1);
    showMessage("NOT QUITE", COL_ERR, message);
    delay(NOTICE_MS);
    enterShowWords();
  } else if (++quiz.question < COLD_QUIZ_WORDS) {
    askQuizQuestion();
  } else if (deriveWallet()) {
    waitForCard(ST_WAIT_CARD_WRITE);
  } else {
    failFatal("The key could not be derived. Start again.");
  }
}

/// The failure screen was acknowledged: try the step again, or start over.
static void leaveFailure() {
  if (retryState == ST_WAIT_PHONE) enterWaitPhone();
  else                             waitForCard(retryState);
}

static void pollButton() {
  // The phone can cancel, or start over, from any of these screens but
  // the last. Once the wallet is finished the device stays silent: the
  // phone's next tap is for the card, and the card may still be lying
  // right here on the reader.
  if (state != ST_DONE && listenForPhone(PHONE_GLANCE_MS)) return;

  const ColdButtonEvent event = button.poll();
  if (event == BTN_NONE) {
    showHoldProgress(button.holdProgress());
    delay(5);
    return;
  }

  touch();
  switch (state) {
    case ST_SHOW_WORDS: onWordsButton(event); break;
    case ST_QUIZ:       onQuizButton(event);  break;
    case ST_DONE:       if (event == BTN_HOLD) enterWaitPhone(); break;
    case ST_FAILED:     if (event == BTN_HOLD) leaveFailure();   break;
    default:            break;
  }
}

// ── Start-up and the main loop ───────────────────────────────
/// The PN532 can take a few tries to answer after power-up.
static bool findPn532() {
  uint32_t firmware = 0;
  for (int attempt = 1; attempt <= 10 && !firmware; attempt++) {
    nfcBegin();
    firmware = nfc.getFirmwareVersion();
    if (!firmware) delay(100 * attempt);
  }
  if (!firmware) return false;
  Serial.printf("PN532 OK  FW %d.%d\n", (int)((firmware >> 16) & 0xFF), (int)((firmware >> 8) & 0xFF));
  return true;
}

/// A seed phrase left on screen with nobody there gets forgotten.
static bool wipeIfIdle() {
  if (state == ST_WAIT_PHONE || state == ST_DONE) return false;
  if (millis() - lastActivity <= IDLE_WIPE_MS) return false;

  Serial.println("[flow] idle too long - cleared");
  radioOff();
  secrets.wipeAll();
  showMessage("CLEARED", COL_AMBER,
              "Nothing was pressed for a while, so the words were erased. Start again from the phone.");
  delay(LONG_NOTICE_MS);
  enterWaitPhone();
  return true;
}

void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println("\n=== " COLD_NAME " ===");

  // With no radio running, the ESP32's random generator has nothing
  // feeding it. This switches on its internal noise source (the SAR
  // ADC) and leaves it on — nothing in this sketch uses the ADC, I2S or
  // a radio, which are what it must not be shared with.
  bootloader_random_enable();

  button.begin();
  displayBegin();

  SPI.begin(NFC_SCK, NFC_MISO, NFC_MOSI, NFC_SS);
  if (!findPn532()) {
    Serial.println("PN532 NOT FOUND - check wiring / DIP switches (SPI)");
    showErrorScreen("PN532 not found. Check the wiring and the SPI switches.");
    while (true) delay(1000);
  }
  nfc.SAMConfig();
  se05xExchange = readerExchange;
  coldSessionRandom = esp_fill_random;

  enterWaitPhone();
  Serial.println("Ready.");
}

void loop() {
  if (wipeIfIdle()) return;

  switch (state) {
    case ST_WAIT_PHONE:
      listenForPhone(PHONE_POLL_MS);
      break;
    case ST_WAIT_CARD_ENTROPY:
    case ST_WAIT_CARD_WRITE:
      pollCard();
      break;
    default:
      pollButton();
      break;
  }
}
