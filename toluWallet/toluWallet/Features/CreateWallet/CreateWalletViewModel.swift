//
//  CreateWalletViewModel.swift
//  toluWallet
//
//  Wallet creation, after toluTag's create-key flow: configure the label, slots
//  and password, then run it as taps. How many taps depends on where the key
//  comes from:
//
//  - made inside the tag: two — the tag generates the key, then a second tap
//    opens a password session and reads the address back;
//  - from a seed phrase: three, with the words in between — one tap checks the
//    slots and takes random bytes from the tag, the words are shown and
//    confirmed, then the key is written and read back;
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
    var passwordObjectIdText: String
    var password = ""
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
    @ObservationIgnored private let writer = SE050ProtectedKeyPairWriter()
    @ObservationIgnored private let runner = Se05xNfcRunner()
    /// While true, the password slot tracks the key slot (key + 1).
    @ObservationIgnored private var passwordSlotFollowsKey = true
    /// The card id the create tap reported — kept only as a fallback label in
    /// case the verify tap can't read it. Nothing is decided on it.
    @ObservationIgnored private var cardFromCreateTap: String?
    /// The key the confirmed words stand for, until the tag has it.
    @ObservationIgnored private var seedKey: SeedPhraseKey?
    /// The public half of that key, kept past the write so the verify tap can
    /// be held to it.
    @ObservationIgnored private var expectedPublicKey: [UInt8]?
    /// A write tap got the password object onto the tag but not the key, so
    /// the next try has to accept it there instead of tripping over it.
    @ObservationIgnored private var passwordObjectOnTag = false

    init(store: WalletStore) {
        self.store = store
        // Start past every slot a saved wallet already uses.
        let keySlot = SlotSuggestion.firstFree(after: store.usedObjectIDs)
        keyObjectIdText = keySlot
        passwordObjectIdText = SlotSuggestion.next(after: keySlot) ?? keySlot
    }

    var isNfcAvailable: Bool { NFCTagReaderSession.readingAvailable }
    var isComplete: Bool { createdWallet != nil }
    var usesExistingKey: Bool { origin == .existing }
    /// True while a seed phrase is in memory — the time it must not outlive.
    var holdsSeedPhrase: Bool { !words.isEmpty }

    var steps: [Step] {
        switch origin {
        case .existing:
            [Step(id: 0, title: "Read the key", hint: "open the password session & read the address")]
        case .tag:
            [
                Step(id: 0, title: "Create the key", hint: "the tag generates secp256k1 & stores the password"),
                Step(id: 1, title: "Verify", hint: "tap again to read the address back")
            ]
        case .seedPhrase:
            [
                Step(id: 0, title: "Prepare", hint: "check slots & take random from the secure element"),
                Step(id: 1, title: "Write the key", hint: "store the password & the key from your words"),
                Step(id: 2, title: "Verify", hint: "tap again to read the address back")
            ]
        }
    }

    private var trimmedLabel: String { label.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var passwordIsValid: Bool {
        (PasswordField.minLength...PasswordField.maxLength).contains(password.count)
    }

    var slotsCollide: Bool {
        keyObjectIdText.count == 8 && keyObjectIdText == passwordObjectIdText
    }

    var canContinue: Bool {
        !trimmedLabel.isEmpty && keyObjectIdText.count == 8 && passwordObjectIdText.count == 8
            && !slotsCollide && passwordIsValid
    }

    var actionTitle: String {
        if running { return "Hold the tag…" }
        switch (origin, currentStep) {
        case (.existing, _): return "Scan to read"
        case (.tag, 0): return "Scan to create"
        case (.seedPhrase, 0): return "Scan to start"
        case (.seedPhrase, 1): return "Scan to write the key"
        default: return "Scan to verify"
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
        guard passwordSlotFollowsKey, let suggestion = SlotSuggestion.next(after: keyObjectIdText) else { return }
        passwordObjectIdText = suggestion
    }

    func passwordSlotChanged() {
        passwordSlotFollowsKey = passwordObjectIdText == SlotSuggestion.next(after: keyObjectIdText)
    }

    // MARK: - Stage navigation

    func goToRun() {
        guard !trimmedLabel.isEmpty else { setupError = "give the wallet a label"; return }
        guard keyObjectIdText.count == 8 else { setupError = "key object id must be 8 hex digits"; return }
        guard passwordObjectIdText.count == 8 else { setupError = "password object id must be 8 hex digits"; return }
        guard !slotsCollide else { setupError = "the password object id must differ from the key object id"; return }
        guard passwordIsValid else {
            setupError = "password must be \(PasswordField.minLength)–\(PasswordField.maxLength) characters"; return
        }
        setupError = nil
        resetRun()
        stage = .run
    }

    /// Back to the form. Whatever seed phrase was in memory goes with it.
    func backToSetup() {
        stage = .setup
        resetRun()
    }

    // MARK: - Run

    func runCurrentStep() {
        guard !running, !isComplete else { return }
        guard let key = ObjectId.parse(keyObjectIdText), let slot = ObjectId.parse(passwordObjectIdText) else {
            runError = "invalid object id"
            return
        }
        running = true
        runError = nil
        failedStep = -1

        switch (origin, currentStep) {
        case (.seedPhrase, 0):
            Task { await prepareSeedPhrase(key: key, slot: slot) }
        case (.tag, 0):
            write(key: key, slot: slot, importing: nil, alert: "Hold the tag to create the wallet key.")
        case (.seedPhrase, 1):
            guard let seedKey else {
                running = false
                failedStep = currentStep
                runError = SeedPhraseError.keyMissing.errorDescription
                return
            }
            write(key: key, slot: slot, importing: seedKey, alert: "Hold the tag to write the wallet key.")
        default:
            Task { await readKey(key: key, slot: slot) }
        }
    }

    /// The tap that puts the password object and the key on the tag — a key
    /// the tag generates, or the one from the seed phrase.
    private func write(key: ObjectId, slot: ObjectId, importing seedKey: SeedPhraseKey?, alert: String) {
        writer.onFinish = { [weak self] outcome in
            Task { @MainActor in self?.handleWrite(outcome) }
        }
        writer.createProtectedKeyPair(
            userID: password,
            userIDObjectID: slot.hex,
            keyObjectID: key.hex,
            maxAttempts: WalletRecord.defaultPasswordAttemptLimit,
            deletable: false,
            usePin: true,
            importing: seedKey,
            allowExistingPassword: passwordObjectOnTag,
            alert: alert
        )
    }

    private func handleWrite(_ outcome: Result<ProtectedKeyConfiguration, Error>) {
        running = false
        switch outcome {
        case .success(let configuration):
            cardFromCreateTap = CardUid.normalize(configuration.uniqueId)
            keyIsOnTag()
        case .failure(let error):
            // The tag acknowledged the key and the tap dropped afterwards: the
            // key is there, and the verify tap is what proves it.
            if writer.didWriteKey {
                keyIsOnTag()
                return
            }
            if writer.didWritePasswordObject { passwordObjectOnTag = true }
            failedStep = currentStep
            runError = NfcErrorText.describe(error)
        }
    }

    /// The write step is done. From here this phone needs nothing secret: the
    /// words and the private key are dropped, and only the public key stays to
    /// hold the verify tap to.
    private func keyIsOnTag() {
        expectedPublicKey = seedKey?.publicKeyPoint
        forgetSeedPhrase()
        currentStep += 1
    }

    /// Opens a password session, reads the public key, and saves the wallet.
    private func readKey(key: ObjectId, slot: ObjectId) async {
        let passwordBytes = Array(password.utf8)
        do {
            let (point, uniqueId) = try await runner.run(
                alertMessage: "Hold the tag to read the wallet address."
            ) { tag in
                let uniqueId = try? await tag.readUniqueId()
                try await tag.openUserIdSession(userObjectId: slot.bytes, pin: passwordBytes)
                let point = try await tag.readPublicKeyPoint(objectId: key.bytes)
                return (point, uniqueId)
            }

            // As in tolu's key-set flow, the verify tap is trusted on what it
            // proves: a tag that opens this password slot and returns a key
            // from this key slot is the wallet's tag. A seed-phrase wallet
            // asks one thing more — that the key is the one from the words.
            if let expectedPublicKey, point != expectedPublicKey {
                throw SeedPhraseError.keyMismatch
            }
            guard let address = EthereumAddress.from(publicKeyPoint: point) else {
                throw Se05xError.noKey
            }

            let record = WalletRecord(
                label: trimmedLabel,
                keyObjectID: keyObjectIdText,
                passwordObjectID: passwordObjectIdText,
                password: password,
                publicKey: "0x" + Hex.string(point),
                address: address,
                cardUniqueId: CardUid.normalize(uniqueId) ?? cardFromCreateTap,
                // Known for a key this app just made; unknown for an imported one.
                passwordAttemptLimit: usesExistingKey ? nil : WalletRecord.defaultPasswordAttemptLimit,
                backup: origin.backup,
                createdAt: .now
            )
            try store.add(record)

            running = false
            createdWallet = record
            currentStep = steps.count
        } catch {
            running = false
            failedStep = currentStep
            runError = NfcErrorText.describe(error)
        }
    }

    // MARK: - Seed phrase

    /// The first tap of a seed-phrase wallet. Finds out now that a slot is
    /// taken — not after the words are written down — and takes the tag's
    /// share of the randomness. Nothing is written.
    private func prepareSeedPhrase(key: ObjectId, slot: ObjectId) async {
        do {
            let tagRandom = try await runner.run(alertMessage: "Hold the tag to start.") { tag in
                if try await tag.objectExists(key.bytes) { throw ProtectedKeyWriterError.keySlotInUse }
                if try await tag.objectExists(slot.bytes) { throw ProtectedKeyWriterError.passwordSlotInUse }
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
            running = false
            failedStep = currentStep
            runError = NfcErrorText.describe(error)
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
    /// screen it was on. Nothing was written to the tag yet, so nothing is lost.
    func seedPhraseExpired() {
        guard holdsSeedPhrase else { return }
        backToSetup()
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
        cardFromCreateTap = nil
        expectedPublicKey = nil
        passwordObjectOnTag = false
        forgetSeedPhrase()
    }
}
