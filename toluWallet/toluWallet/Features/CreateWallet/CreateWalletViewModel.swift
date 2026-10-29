//
//  CreateWalletViewModel.swift
//  toluWallet
//
//  Wallet creation: configure the label and slots, then run it as taps. Every
//  wallet key is bound to this iPhone's Secure Enclave key: Face ID first,
//  then a tap that opens an encrypted session only this iPhone can open. How
//  many taps depends on where the key comes from:
//
//  - made inside the tag: one — the tag generates the key in the session and
//    it is read straight back;
//  - from a seed phrase: two, with the words in between — one tap checks the
//    slots and takes random bytes from the tag, the words are shown and
//    confirmed, then the key is written, encrypted, and read back;
//  - already on the tag: one, and nothing is written.
//

import CoreNFC
import Foundation

@Observable
final class CreateWalletViewModel {

    enum Stage {
        case setup
        case run
        /// The seed phrase is on screen.
        case words
        /// Confirming that it was written down.
        case quiz
    }

    struct Step: Identifiable {
        let id: Int
        let title: String
        let hint: String
    }

    /// How long a seed phrase may sit on this phone before it is erased.
    static let seedPhraseLifetime: Duration = .seconds(600)
    /// 16 bytes of entropy make 12 words.
    private static let seedEntropyByteCount = 16

    var stage: Stage = .setup

    // Setup
    var label = ""
    var keyObjectIdText: String
    var phoneKeyObjectIdText: String
    var origin: KeyOrigin = .tag
    var setupError: String?

    // Run
    private(set) var currentStep = 0
    private(set) var running = false
    private(set) var failedStep = -1
    private(set) var createdWallet: WalletRecord?
    private(set) var runError: String?

    // Seed phrase
    private(set) var words: [String] = []
    private(set) var quiz: SeedQuiz?
    private(set) var derivingKey = false
    /// Why the words are on screen again, after a wrong answer.
    private(set) var wordsNotice: String?

    @ObservationIgnored private let store: WalletStore
    @ObservationIgnored private let runner = Se05xNfcRunner()
    /// While true, the phone key slot tracks the key slot (key + 1).
    @ObservationIgnored private var phoneKeySlotFollowsKey = true
    /// The key the confirmed words stand for, until the tag has it.
    @ObservationIgnored private var seedKey: SeedPhraseKey?
    /// A tap of this run got as far as writing the key. The slot may hold it
    /// now, so a retry reads it instead of refusing the slot.
    private var keyWriteStarted = false

    init(store: WalletStore) {
        self.store = store
        // Start past every slot a saved wallet already uses.
        let keySlot = SlotSuggestion.firstFree(after: store.usedObjectIDs)
        keyObjectIdText = keySlot
        phoneKeyObjectIdText = SlotSuggestion.next(after: keySlot) ?? keySlot
    }

    var isNfcAvailable: Bool { NFCTagReaderSession.readingAvailable }
    var isComplete: Bool { createdWallet != nil }
    var usesExistingKey: Bool { origin == .existing }
    /// True while a seed phrase is in memory — the time it must not outlive.
    var holdsSeedPhrase: Bool { !words.isEmpty }

    /// This run may already have put the key on the tag, where it can't be
    /// removed. Until the wallet is saved, the slots and origin stay as they
    /// are; only the label may change.
    var hasWrittenToTag: Bool { keyWriteStarted && !isComplete }

    var steps: [Step] {
        switch origin {
        case .existing:
            [Step(id: 0, title: "Read the key", hint: "face id, then this iphone's session reads the address")]
        case .tag:
            [Step(id: 0, title: "Create the key", hint: "face id, then one tap: the tag makes the key, bound to this iphone")]
        case .seedPhrase:
            [
                Step(id: 0, title: "Prepare", hint: "check slots & take random from the secure element"),
                Step(id: 1, title: "Write the key", hint: "face id, then one tap: your words' key goes on, encrypted")
            ]
        }
    }

    private var trimmedLabel: String { label.trimmingCharacters(in: .whitespacesAndNewlines) }

    var slotsCollide: Bool {
        keyObjectIdText.count == 8 && keyObjectIdText == phoneKeyObjectIdText
    }

    /// 0x7FFFxxxx is the range NXP reserves for the chip's own objects.
    private var usesReservedSlot: Bool {
        [keyObjectIdText, phoneKeyObjectIdText].contains { $0.lowercased().hasPrefix("7fff") }
    }

    var canContinue: Bool {
        !trimmedLabel.isEmpty && keyObjectIdText.count == 8 && phoneKeyObjectIdText.count == 8
            && !slotsCollide && !usesReservedSlot
    }

    var actionTitle: String {
        if running { return "Hold the tag…" }
        switch (origin, currentStep) {
        case (.existing, _): return "Scan to read"
        case (.tag, _): return "Scan to create"
        case (.seedPhrase, 0): return "Scan to start"
        case (.seedPhrase, _): return "Scan to write the key"
        }
    }

    func state(for index: Int) -> StepState {
        if failedStep == index { return .error }
        if isComplete || index < currentStep { return .done }
        if index == currentStep { return running ? .active : .pending }
        return .pending
    }

    // MARK: - Slots

    func keySlotChanged() {
        guard phoneKeySlotFollowsKey, let suggestion = SlotSuggestion.next(after: keyObjectIdText) else { return }
        phoneKeyObjectIdText = suggestion
    }

    func phoneKeySlotChanged() {
        phoneKeySlotFollowsKey = phoneKeyObjectIdText == SlotSuggestion.next(after: keyObjectIdText)
    }

    // MARK: - Stage navigation

    func goToRun() {
        guard !trimmedLabel.isEmpty else { setupError = "give the wallet a label"; return }
        guard keyObjectIdText.count == 8 else { setupError = "key object id must be 8 hex digits"; return }
        guard phoneKeyObjectIdText.count == 8 else { setupError = "phone key object id must be 8 hex digits"; return }
        guard !slotsCollide else { setupError = "the phone key object id must differ from the key object id"; return }
        guard !usesReservedSlot else { setupError = "ids starting 7FFF belong to the chip itself"; return }
        setupError = nil
        if !hasWrittenToTag { resetRun() }
        stage = .run
    }

    /// Back to the form. Whatever seed phrase was in memory goes with it —
    /// unless this run already wrote to the tag. Then the run is kept, so the
    /// next scan carries on instead of finding its own slot taken.
    func backToSetup() {
        stage = .setup
        if !hasWrittenToTag { resetRun() }
    }

    // MARK: - Run

    func runCurrentStep() {
        guard !running, !isComplete else { return }
        guard let key = ObjectId.parse(keyObjectIdText), let slot = ObjectId.parse(phoneKeyObjectIdText) else {
            runError = "invalid object id"
            return
        }
        running = true
        runError = nil
        failedStep = -1

        switch (origin, currentStep) {
        case (.seedPhrase, 0):
            Task { await prepareSeedPhrase(key: key, slot: slot) }
        case (.seedPhrase, _):
            guard let seedKey else {
                fail(SeedPhraseError.keyMissing)
                return
            }
            Task { await install(key: key, slot: slot, importing: seedKey) }
        case (.tag, _):
            Task { await install(key: key, slot: slot, importing: nil) }
        case (.existing, _):
            Task { await readExisting(key: key, slot: slot) }
        }
    }

    /// Face ID, then the tap that puts the key on the tag and reads it back
    /// — a key the tag makes, or the one from the seed phrase.
    private func install(key: ObjectId, slot: ObjectId, importing seedKey: SeedPhraseKey?) async {
        do {
            let signer = try await DeviceKey.unlock(reason: "Bind the new wallet to this iPhone")
            let resuming = keyWriteStarted
            let installed = try await runner.run(
                alertMessage: seedKey == nil ? "Hold the tag to create the wallet key."
                                             : "Hold the tag to write the wallet key."
            ) { tag in
                try await WalletKeyInstaller.install(
                    on: tag, keyObjectId: key.bytes, phoneKeyObjectId: slot.bytes, signer: signer,
                    importing: seedKey, resumingKey: resuming,
                    keyWriteStarting: { self.keyWriteStarted = true }
                )
            }
            try save(installed)
        } catch {
            fail(error)
        }
    }

    /// Face ID, then one read-only tap in this iPhone's session.
    private func readExisting(key: ObjectId, slot: ObjectId) async {
        do {
            let signer = try await DeviceKey.unlock(reason: "Read the wallet on your tag")
            let installed = try await runner.run(alertMessage: "Hold the tag to read the wallet address.") { tag in
                try await WalletKeyInstaller.readExisting(on: tag, keyObjectId: key.bytes,
                                                          phoneKeyObjectId: slot.bytes, signer: signer)
            }
            try save(installed)
        } catch {
            fail(error)
        }
    }

    private func save(_ installed: InstalledWalletKey) throws {
        guard let address = EthereumAddress.from(publicKeyPoint: installed.publicKey) else {
            throw Se05xError.noKey
        }
        let record = WalletRecord(
            label: trimmedLabel,
            keyObjectID: keyObjectIdText,
            authObjectID: phoneKeyObjectIdText,
            unlock: .thisPhone,
            publicKey: "0x" + Hex.string(installed.publicKey),
            address: address,
            cardUniqueId: CardUid.normalize(installed.cardUniqueId),
            backup: origin.backup,
            createdAt: .now
        )
        try store.add(record)

        // From here the only copies of a seed-phrase key are the tag and the paper.
        forgetSeedPhrase()
        running = false
        createdWallet = record
        currentStep = steps.count
    }

    private func fail(_ error: Error) {
        running = false
        failedStep = currentStep
        runError = NfcErrorText.describe(error)
    }

    // MARK: - Seed phrase

    /// The first tap of a seed-phrase wallet. Finds out now that a slot is
    /// taken — not after the words are written down — and takes the tag's
    /// share of the randomness. Nothing is written.
    private func prepareSeedPhrase(key: ObjectId, slot: ObjectId) async {
        do {
            let phoneKey = try DeviceKey.publicKey()
            let tagRandom = try await runner.run(alertMessage: "Hold the tag to start.") { tag in
                if try await tag.objectExists(key.bytes) { throw Se05xError.keySlotInUse }
                if try await tag.phoneKeySlot(slot.bytes, publicKey: phoneKey) == .taken {
                    throw Se05xError.phoneKeySlotTaken
                }
                return try await tag.random(count: EntropyMixer.sourceByteCount)
            }
            // A generator that returns one repeated byte is broken. The mix
            // below would still make a good phrase, but a tag like that can't
            // be trusted to sign either.
            guard Set(tagRandom).count > 1 else { throw SeedPhraseError.tagRandomLooksBroken }
            guard let phoneRandom = EntropyMixer.phoneRandom() else { throw SeedPhraseError.phoneRandomFailed }
            guard let entropy = EntropyMixer.mix(tag: tagRandom, phone: phoneRandom,
                                                 byteCount: Self.seedEntropyByteCount),
                  let words = Bip39.words(entropy: entropy)
            else { throw SeedPhraseError.phraseFailed }

            self.words = words
            running = false
            currentStep = 1
            stage = .words
        } catch {
            fail(error)
        }
    }

    func startQuiz() {
        guard let quiz = SeedQuiz(words: words) else { return }
        self.quiz = quiz
        wordsNotice = nil
        stage = .quiz
    }

    func backToWords() {
        guard !derivingKey else { return }
        quiz = nil
        stage = .words
    }

    func answerQuiz(_ choice: String) {
        guard var quiz, !derivingKey else { return }
        switch quiz.answer(choice) {
        case .next:
            self.quiz = quiz
        case .wrong(let position):
            self.quiz = nil
            wordsNotice = "That isn't word \(position + 1). Check what you wrote, then try again."
            stage = .words
        case .passed:
            Task { await deriveKey() }
        }
    }

    /// The words are confirmed: work out the key they stand for.
    private func deriveKey() async {
        derivingKey = true
        let key = await SeedPhraseKey.derived(from: words)
        derivingKey = false
        // The phrase was thrown away while this ran.
        guard stage == .quiz else { return }
        guard let key else {
            backToSetup()
            setupError = SeedPhraseError.keyFailed.errorDescription
            return
        }
        seedKey = key
        quiz = nil
        stage = .run
    }

    /// A phrase that has been on this phone too long is erased, whatever
    /// screen it was on.
    func seedPhraseExpired() {
        guard holdsSeedPhrase else { return }
        stage = .setup
        resetRun()
        setupError = "The seed phrase was on this phone for ten minutes, so it was erased. Start again — you will get new words."
    }

    private func forgetSeedPhrase() {
        words = []
        quiz = nil
        seedKey = nil
        wordsNotice = nil
    }

    private func resetRun() {
        currentStep = 0
        running = false
        failedStep = -1
        createdWallet = nil
        runError = nil
        keyWriteStarted = false
        forgetSeedPhrase()
    }
}
