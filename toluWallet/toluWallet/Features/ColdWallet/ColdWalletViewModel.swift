//
//  ColdWalletViewModel.swift
//  toluWallet
//
//  Creating a wallet with a toluCold device, from the phone's side. The phone
//  never sees the key or the seed phrase: it sends the slots and password to
//  the device, waits while the device does its part, then scans the address
//  the device shows and checks that the card really holds that key.
//
//      1. send   — tap the phone on the device
//      2. scan   — after the device has shown the words and written the card,
//                  scan the QR it ends on
//      3. check  — tap the card: its address must equal the QR's
//

import CoreNFC
import Foundation

@Observable
final class ColdWalletViewModel {

    enum Stage {
        case setup
        case device
    }

    enum Step: Int, CaseIterable, Identifiable {
        case send, scan, check

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .send: return "Send to the device"
            case .scan: return "Follow the device, then scan its QR"
            case .check: return "Check the card"
            }
        }
    }

    var stage: Stage = .setup

    // Setup
    var label = ""
    var keyObjectIdText: String
    var passwordObjectIdText: String
    var password = ""
    var setupError: String?

    // Device stage
    private(set) var step: Step = .send
    private(set) var running = false
    private(set) var failedStep: Step?
    private(set) var runError: String?
    /// The address from the device's QR, lower-case.
    private(set) var scannedAddress: String?
    private(set) var createdWallet: WalletRecord?
    var showScanner = false

    @ObservationIgnored private let store: WalletStore
    @ObservationIgnored private let sender = ColdDeviceSender()
    @ObservationIgnored private let runner = Se05xNfcRunner()
    @ObservationIgnored private var passwordSlotFollowsKey = true

    init(store: WalletStore) {
        self.store = store
        if let draft = store.coldDraft {
            // Picking up a setup that was already sent to the device.
            label = draft.label
            keyObjectIdText = draft.keyObjectID
            passwordObjectIdText = draft.passwordObjectID
            password = draft.password
            passwordSlotFollowsKey = false
            stage = .device
            step = .scan
        } else {
            let keySlot = SlotSuggestion.firstFree(after: store.usedObjectIDs)
            keyObjectIdText = keySlot
            passwordObjectIdText = SlotSuggestion.next(after: keySlot) ?? keySlot
        }
    }

    var isNfcAvailable: Bool { NFCTagReaderSession.readingAvailable }
    var isComplete: Bool { createdWallet != nil }

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

    // MARK: - Presentation

    func state(for step: Step) -> StepState {
        if isComplete { return .done }
        if failedStep == step { return .error }
        if step.rawValue < self.step.rawValue { return .done }
        return step == self.step ? .active : .pending
    }

    func hint(for step: Step) -> String {
        switch step {
        case .send:
            return "hold the phone on the device's reader"
        case .scan:
            if let scannedAddress { return EthereumAddress.short(EthereumAddress.checksummed(scannedAddress)) }
            return "it shows the qr once the key is on the card"
        case .check:
            return "tap the card: its address must match the qr"
        }
    }

    var actionTitle: String {
        if running { return step == .send ? "Hold the phone to the device…" : "Hold the card…" }
        switch step {
        case .send: return "Tap the device"
        case .scan: return "Scan the device's QR"
        case .check: return "Tap the card to check"
        }
    }

    var actionSymbol: String {
        step == .scan ? "qrcode.viewfinder" : "wave.3.forward"
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

    func continueToDevice() {
        guard !trimmedLabel.isEmpty else { setupError = "give the wallet a label"; return }
        guard keyObjectIdText.count == 8 else { setupError = "key object id must be 8 hex digits"; return }
        guard passwordObjectIdText.count == 8 else { setupError = "password object id must be 8 hex digits"; return }
        guard !slotsCollide else { setupError = "the password object id must differ from the key object id"; return }
        guard passwordIsValid else {
            setupError = "password must be \(PasswordField.minLength)–\(PasswordField.maxLength) characters"; return
        }
        setupError = nil
        resetRun()
        stage = .device
    }

    /// Back to the form. Only before anything has been sent — afterwards the
    /// device already holds these details.
    var canEditSetup: Bool { stage == .device && step == .send && !running }

    func backToSetup() {
        stage = .setup
        resetRun()
    }

    /// Sends the same details again — the device was switched off, the first
    /// tap was on the wrong thing, or it should simply start over: a device
    /// in the middle of a ceremony drops it for the new setup.
    func sendAgain() {
        guard !running else { return }
        scannedAddress = nil
        failedStep = nil
        runError = nil
        step = .send
    }

    /// True once a setup was sent to the device and is still remembered here
    /// — the point from which there is something to cancel.
    var hasSentSetup: Bool { store.coldDraft != nil }

    /// Forgets the setup on this phone. The device is not told.
    func discard() {
        try? store.setColdDraft(nil)
        resetRun()
        stage = .setup
    }

    /// Cancels on the device too: one tap makes it erase the seed phrase and
    /// go back to its start screen, then the setup is forgotten here. Returns
    /// false — with the reason in `runError` — if the device didn't get it;
    /// nothing is forgotten in that case.
    func cancelOnDevice() async -> Bool {
        guard !running else { return false }
        begin()
        do {
            try await sender.cancel()
            discard()
            return true
        } catch {
            running = false
            runError = "The device didn't get the cancel. \(NfcErrorText.describe(error)) "
                + "If it is switched off or already showing its QR, cancel on this phone only."
            return false
        }
    }

    // MARK: - Steps

    func runAction() {
        guard !running, !isComplete else { return }
        switch step {
        case .send: Task { await sendToDevice() }
        case .scan: showScanner = true
        case .check: Task { await checkCard() }
        }
    }

    private func sendToDevice() async {
        guard let key = ObjectId.parse(keyObjectIdText), let slot = ObjectId.parse(passwordObjectIdText) else {
            runError = "invalid object id"
            return
        }
        begin()
        do {
            try await sender.send(keyObjectID: key.bytes, passwordObjectID: slot.bytes, password: Array(password.utf8))
            // From here the device holds the details, so they must survive
            // the app locking while the words are written down.
            try store.setColdDraft(ColdWalletDraft(
                label: trimmedLabel, keyObjectID: keyObjectIdText, passwordObjectID: passwordObjectIdText,
                password: password, createdAt: .now
            ))
            running = false
            step = .scan
        } catch {
            fail(error)
        }
    }

    /// Takes what the scanner read. Returns a message when it isn't an
    /// address, so the scanner can say so and keep looking.
    func handleScanned(_ text: String) -> String? {
        guard let address = EthereumAddress.fromScanned(text) else {
            return "That isn't a wallet address. Point at the QR on the toluCold screen."
        }
        scannedAddress = address
        failedStep = nil
        runError = nil
        step = .check
        return nil
    }

    /// Opens a password session on the card, reads its public key, and saves
    /// the wallet only if that key's address is the one the device showed.
    private func checkCard() async {
        guard let expected = scannedAddress,
              let key = ObjectId.parse(keyObjectIdText), let slot = ObjectId.parse(passwordObjectIdText) else {
            runError = "scan the device's QR first"
            return
        }
        let passwordBytes = Array(password.utf8)
        begin()
        do {
            let (point, uniqueId) = try await runner.run(
                alertMessage: "Hold the card to check the wallet address."
            ) { tag in
                let uniqueId = try? await tag.readUniqueId()
                try await tag.openUserIdSession(userObjectId: slot.bytes, pin: passwordBytes)
                let point = try await tag.readPublicKeyPoint(objectId: key.bytes)
                return (point, uniqueId)
            }

            guard let address = EthereumAddress.from(publicKeyPoint: point) else { throw Se05xError.noKey }
            guard address == expected else {
                throw ColdWalletError.addressMismatch(card: address, device: expected)
            }

            let record = WalletRecord(
                label: trimmedLabel,
                keyObjectID: keyObjectIdText,
                passwordObjectID: passwordObjectIdText,
                password: password,
                publicKey: "0x" + Hex.string(point),
                address: address,
                cardUniqueId: CardUid.normalize(uniqueId),
                passwordAttemptLimit: WalletRecord.defaultPasswordAttemptLimit,
                backup: .seedPhrase,
                createdAt: .now
            )
            try store.add(record)
            try? store.setColdDraft(nil)

            running = false
            createdWallet = record
        } catch {
            fail(error)
        }
    }

    // MARK: - State

    private func begin() {
        running = true
        runError = nil
        failedStep = nil
    }

    private func fail(_ error: Error) {
        running = false
        failedStep = step
        runError = NfcErrorText.describe(error)
    }

    private func resetRun() {
        step = .send
        running = false
        failedStep = nil
        runError = nil
        scannedAddress = nil
        createdWallet = nil
    }
}
