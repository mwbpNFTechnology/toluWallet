// ============================================================
// cold_state.h - where the flow is, and what the device is holding
// ============================================================
// In a header rather than the sketch because the Arduino builder
// writes function prototypes above the sketch's own code, and those
// prototypes mention these types.
// ============================================================
#ifndef COLD_STATE_H
#define COLD_STATE_H

#include <stdint.h>
#include "config.h"
#include "cold_util.h"
#include "cold_bip39.h"
#include "cold_target.h"

enum ColdState {
  ST_WAIT_PHONE,          // armed as a card, waiting for the setup
  ST_WAIT_CARD_ENTROPY,   // waiting for the card: check slots, get random
  ST_SHOW_WORDS,          // the seed phrase is on screen
  ST_QUIZ,                // confirming words
  ST_WAIT_CARD_WRITE,     // waiting for the card: write password + key
  ST_DONE,                // address QR
  ST_FAILED               // a message; hold to go on
};

// How many words each quiz question offers.
#define COLD_QUIZ_CHOICES 3

/// The check that the phrase was written down.
struct ColdQuiz {
  uint16_t positions[COLD_QUIZ_WORDS];      // which words are asked for, in order
  uint16_t choices[COLD_QUIZ_CHOICES];      // word-list indexes on screen
  int      question = 0;
  int      selected = 0;

  /// Position in the phrase of the word being asked for.
  int position() const { return positions[question]; }
};

// Everything secret this device ever holds, in one place so it can be
// wiped in one call.
struct ColdSecrets {
  ColdSetup setup;
  uint16_t  words[COLD_MAX_WORDS];
  int       wordCount = 0;
  uint8_t   privateKey[32];
  uint8_t   publicKey[65];
  char      address[43];
  // What already made it onto the card in this run, so a retry picks
  // up where it stopped instead of tripping over its own objects.
  bool      passwordWritten = false;
  bool      keyWritten = false;

  void wipeKeyMaterial() {
    coldWipe(words, sizeof(words));
    coldWipe(privateKey, sizeof(privateKey));
    wordCount = 0;
    setup.reset();
  }

  void wipeAll() {
    wipeKeyMaterial();
    coldWipe(publicKey, sizeof(publicKey));
    coldWipe(address, sizeof(address));
    passwordWritten = false;
    keyWritten = false;
  }
};

#endif // COLD_STATE_H
