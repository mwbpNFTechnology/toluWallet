//
//  Bip39.swift
//  toluWallet
//
//  Entropy → seed phrase → seed (BIP-39). 16 bytes of entropy make 12 words.
//  The last word carries a checksum, so a phrase written down wrong is caught
//  when it is typed into any other wallet. The same steps run on the toluCold
//  device (tolu_cold/cold_bip39.h).
//

import CryptoKit
import Foundation

nonisolated enum Bip39 {

    /// The words for `entropy` — 16, 20, 24, 28 or 32 bytes, giving 12 to 24
    /// words — or `nil` for any other length.
    static func words(entropy: [UInt8]) -> [String]? {
        guard (16...32).contains(entropy.count), entropy.count % 4 == 0 else { return nil }

        // entropy || checksum, where the checksum is the first ENT/32 bits of
        // SHA-256(entropy). That is never more than one byte.
        var bits = entropy
        bits.append(Array(SHA256.hash(data: entropy))[0])

        let count = (entropy.count * 8 + entropy.count / 4) / 11
        return (0..<count).map { word in
            var index = 0
            for bit in 0..<11 {
                let position = word * 11 + bit
                index = (index << 1) | Int((bits[position / 8] >> (7 - position % 8)) & 1)
            }
            return Bip39Wordlist.words[index]
        }
    }

    /// The 64-byte seed BIP-32 starts from: PBKDF2-HMAC-SHA512 over the phrase,
    /// salted with "mnemonic" (no passphrase), 2048 rounds.
    static func seed(words: [String]) -> [UInt8] {
        Pbkdf2.hmacSha512(
            password: Array(words.joined(separator: " ").utf8),
            salt: Array("mnemonic".utf8),
            rounds: 2048,
            byteCount: 64
        )
    }
}
