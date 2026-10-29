//
//  WalletUnlock.swift
//  toluWallet
//
//  What opens the session in which a wallet's key may sign.
//

import Foundation

enum WalletUnlock: Codable, Hashable, Sendable {
    /// This iPhone's Secure Enclave key, after Face ID: an encrypted ECKey
    /// session. Every wallet made now.
    case thisPhone
    /// A password sent to the tag in the clear. Only wallets made before
    /// the iPhone key: a tag's policy can't be changed once it is written.
    case password(String)
}
