//
//  SeedPhraseKey.swift
//  toluWallet
//
//  The key pair a seed phrase stands for: the phrase's first Ethereum account
//  (m/44'/60'/0'/0/0). It exists on this phone only between the moment the
//  words are confirmed and the moment the tag has it.
//

import Foundation

nonisolated struct SeedPhraseKey: Sendable {
    /// 32 bytes.
    let privateKey: [UInt8]
    /// `0x04 || X || Y`, 65 bytes.
    let publicKeyPoint: [UInt8]

    /// `nil` for a key that is zero or not below the curve's group order.
    init?(privateKey: [UInt8]) {
        guard let point = Secp256k1.publicKeyPoint(privateKey: privateKey) else { return nil }
        self.privateKey = privateKey
        self.publicKeyPoint = point
    }

    init?(words: [String]) {
        guard let privateKey = Bip32.privateKey(seed: Bip39.seed(words: words)) else { return nil }
        self.init(privateKey: privateKey)
    }

    /// `init(words:)` off the main actor: the derivation is a few curve
    /// multiplications in plain big-number arithmetic, long enough to stall
    /// the interface if it ran there.
    @concurrent
    static func derived(from words: [String]) async -> SeedPhraseKey? {
        SeedPhraseKey(words: words)
    }
}
