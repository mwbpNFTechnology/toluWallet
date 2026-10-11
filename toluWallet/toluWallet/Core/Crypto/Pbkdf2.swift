//
//  Pbkdf2.swift
//  toluWallet
//
//  PBKDF2 with HMAC-SHA512 (RFC 8018), built on CryptoKit's HMAC. BIP-39 uses
//  it to stretch a seed phrase into a seed.
//

import CryptoKit
import Foundation

nonisolated enum Pbkdf2 {

    static func hmacSha512(password: [UInt8], salt: [UInt8], rounds: Int, byteCount: Int) -> [UInt8] {
        let key = SymmetricKey(data: password)
        var output: [UInt8] = []
        var blockIndex: UInt32 = 1

        while output.count < byteCount {
            // U1 = HMAC(password, salt || INT(blockIndex)), big-endian.
            let counter: [UInt8] = [
                UInt8(truncatingIfNeeded: blockIndex >> 24), UInt8(truncatingIfNeeded: blockIndex >> 16),
                UInt8(truncatingIfNeeded: blockIndex >> 8), UInt8(truncatingIfNeeded: blockIndex)
            ]
            var round = Array(HMAC<SHA512>.authenticationCode(for: salt + counter, using: key))
            var block = round
            for _ in 1..<rounds {
                round = Array(HMAC<SHA512>.authenticationCode(for: round, using: key))
                for index in block.indices { block[index] ^= round[index] }
            }
            output += block
            blockIndex += 1
        }
        return Array(output.prefix(byteCount))
    }
}
