//
//  WalletBackup.swift
//  toluWallet
//
//  Whether anything outside the tag can bring a wallet back.
//

import Foundation

enum WalletBackup: String, Codable, Sendable {
    /// The tag generated the key. Nothing can restore it.
    case noBackup = "none"
    /// A seed phrase was shown when the wallet was made — on this phone or on
    /// a cold device — and is, one hopes, on paper somewhere.
    case seedPhrase

    var summary: String {
        switch self {
        case .noBackup: "none · key made in the tag"
        case .seedPhrase: "seed phrase · on paper"
        }
    }
}
