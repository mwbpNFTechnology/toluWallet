//
//  WalletStore.swift
//  toluWallet
//
//  The wallets saved on this phone. They live in one Keychain item whose
//  access control requires Face ID (or the device passcode), so nothing can be
//  read until the owner is present — and nothing is held in memory while the
//  store is locked. Follows toluTag's KeyStore, with the Face ID check moved
//  from the app into the Keychain item itself.
//

import Foundation
import LocalAuthentication
import Security

@Observable
final class WalletStore {

    private(set) var isUnlocked = false
    private(set) var wallets: [WalletRecord] = []
    /// A cold-device wallet that was sent to the device but not yet checked
    /// against its card. Kept so the setup survives the app locking while the
    /// seed phrase is being written down.
    private(set) var coldDraft: ColdWalletDraft?

    /// The authenticated context from the last unlock. Reused for Keychain
    /// writes so saving a wallet doesn't prompt a second time.
    @ObservationIgnored private var context: LAContext?

    @ObservationIgnored private let service = "io.mwbp.toluWallet.wallets"
    @ObservationIgnored private let account = "toluWallet.records"
    @ObservationIgnored private let draftAccount = "toluWallet.coldDraft"

    /// "Face ID", "Touch ID", or "Passcode" — whatever this device unlocks with.
    let unlockMethodName: String
    /// The SF Symbol that goes with `unlockMethodName`.
    let unlockSymbolName: String

    init() {
        let probe = LAContext()
        _ = probe.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch probe.biometryType {
        case .faceID: (unlockMethodName, unlockSymbolName) = ("Face ID", "faceid")
        case .touchID: (unlockMethodName, unlockSymbolName) = ("Touch ID", "touchid")
        case .opticID: (unlockMethodName, unlockSymbolName) = ("Optic ID", "opticid")
        default: (unlockMethodName, unlockSymbolName) = ("Passcode", "lock.open")
        }
    }

    // MARK: - Lock

    /// Asks for Face ID (passcode as fallback), then loads the wallets.
    func unlock() async throws {
        let context = LAContext()
        context.localizedFallbackTitle = "Enter Passcode"
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            throw WalletStoreError.authenticationUnavailable
        }
        _ = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your wallets")

        guard let data = try read(account, using: context) else {
            wallets = []
            finishUnlock(with: context)
            return
        }
        // A blob that won't decode is an error, not an empty list — treating
        // it as empty would let the next save overwrite real wallets.
        guard let list = try? JSONDecoder().decode([WalletRecord].self, from: data) else {
            throw WalletStoreError.unreadable
        }
        wallets = list
        finishUnlock(with: context)
    }

    private func finishUnlock(with context: LAContext) {
        // The draft is a convenience: one that can't be read is simply gone.
        let draftData = try? read(draftAccount, using: context)
        coldDraft = draftData.flatMap { try? JSONDecoder().decode(ColdWalletDraft.self, from: $0) }
        self.context = context
        isUnlocked = true
    }

    /// Drops everything from memory. The next read needs Face ID again.
    func lock() {
        context?.invalidate()
        context = nil
        wallets = []
        coldDraft = nil
        isUnlocked = false
    }

    // MARK: - Records

    func wallet(id: WalletRecord.ID) -> WalletRecord? {
        wallets.first { $0.id == id }
    }

    /// Saves a wallet. One with the same address replaces the saved copy.
    func add(_ record: WalletRecord) throws {
        guard isUnlocked else { throw WalletStoreError.locked }
        var list = wallets.filter { $0.address != record.address }
        list.append(record)
        try write(try JSONEncoder().encode(list), to: account)
        wallets = list
    }

    /// Removes a wallet from this phone. The key stays on the tag.
    func remove(_ id: WalletRecord.ID) throws {
        guard isUnlocked else { throw WalletStoreError.locked }
        let list = wallets.filter { $0.id != id }
        try write(try JSONEncoder().encode(list), to: account)
        wallets = list
    }

    /// Remembers (or, with `nil`, forgets) the cold wallet being set up.
    func setColdDraft(_ draft: ColdWalletDraft?) throws {
        guard isUnlocked else { throw WalletStoreError.locked }
        if let draft {
            try write(try JSONEncoder().encode(draft), to: draftAccount)
        } else {
            SecItemDelete(baseQuery(draftAccount) as CFDictionary)
        }
        coldDraft = draft
    }

    /// Object ids already used by saved wallets — to suggest free slots.
    var usedObjectIDs: [UInt32] {
        var ids = wallets.flatMap { [$0.keyObjectID, $0.passwordObjectID] }
        if let coldDraft { ids += [coldDraft.keyObjectID, coldDraft.passwordObjectID] }
        return ids.compactMap { UInt32($0, radix: 16) }
    }

    // MARK: - Keychain

    private func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    /// The item's data, or `nil` if there is no such item.
    private func read(_ account: String, using context: LAContext) throws -> Data? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = context

        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        switch status {
        case errSecSuccess:
            guard let data = out as? Data else { throw WalletStoreError.unreadable }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw WalletStoreError.keychain(status)
        }
    }

    private func write(_ data: Data, to account: String) throws {
        var query = baseQuery(account)
        if let context { query[kSecUseAuthenticationContext as String] = context }
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess { return }

        // No item yet, or the update was refused: write a fresh one.
        if updateStatus != errSecItemNotFound {
            SecItemDelete(baseQuery(account) as CFDictionary)
        }
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, nil
        ) else {
            throw WalletStoreError.authenticationUnavailable
        }
        query[kSecValueData as String] = data
        query[kSecAttrAccessControl as String] = access
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw WalletStoreError.keychain(addStatus) }
    }
}
