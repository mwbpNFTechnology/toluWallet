//
//  KeyOrigin.swift
//  toluWallet
//
//  Where a wallet's key comes from when it is added in the app.
//

import Foundation

enum KeyOrigin: CaseIterable, Identifiable {
    /// The tag generates the key. It never exists anywhere else.
    case tag
    /// This phone makes a seed phrase, shows it once, and puts its key on the tag.
    case seedPhrase
    /// The key is already on the tag; only its address is read.
    case existing

    var id: Self { self }

    var title: String {
        switch self {
        case .tag: "Made inside the tag"
        case .seedPhrase: "From a seed phrase"
        case .existing: "Already on the tag"
        }
    }

    var detail: String {
        switch self {
        case .tag:
            "the tag generates the key and it never leaves. no backup exists — lose the tag and the wallet is gone."
        case .seedPhrase:
            "12 words made from a random number generated inside the tag's secure element, mixed with this phone's own. you write them down, then their key goes onto the tag. the words restore the wallet anywhere."
        case .existing:
            "import a wallet made earlier. nothing is written — the tag is only read, using the slots and password above."
        }
    }

    /// What a wallet made this way has for a backup. Unknown for a key that
    /// was already there.
    var backup: WalletBackup? {
        switch self {
        case .tag: .noBackup
        case .seedPhrase: .seedPhrase
        case .existing: nil
        }
    }
}
