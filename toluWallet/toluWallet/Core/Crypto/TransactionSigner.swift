//
//  TransactionSigner.swift
//  toluWallet
//
//  Turns the DER signature the tag returns into a transaction signature. The
//  SE05x only gives (r, s), so the recovery bit is found by recovering the
//  public key for both candidates and keeping the one that matches the tag's
//  own key. No match means no signature — a wrong bit would sign for a
//  different sender, so it is never guessed.
//

import Foundation

nonisolated enum TransactionSigner {

    /// - Parameters:
    ///   - der: `SEQUENCE { INTEGER r, INTEGER s }` from the tag.
    ///   - hash: the 32-byte digest that was signed.
    ///   - publicKey: the tag's uncompressed key (`0x04 || X || Y`, 65 bytes).
    static func signature(der: [UInt8], hash: [UInt8], publicKey: [UInt8]) -> TransactionSignature? {
        guard let (r, parsedS) = EcdsaDer.parse(der) else { return nil }

        // Ethereum only accepts the low-S form (EIP-2).
        let s = parsedS > Secp256k1.halfN ? Secp256k1.n - parsedS : parsedS

        let hashData = Data(hash)
        let publicKeyData = Data(publicKey)
        for recoveryId in 0...1 {
            let candidate = Secp256k1.recoverPublicKey(r: r, s: s, hash: hashData, recoveryId: recoveryId)
            if candidate == publicKeyData {
                return TransactionSignature(r: r, s: s, yParity: recoveryId)
            }
        }
        return nil
    }

    /// `signature(der:hash:publicKey:)` off the main actor. Recovery is a few
    /// hundred milliseconds of big-number arithmetic on a phone — long enough
    /// to stall the interface if it ran there.
    @concurrent
    static func recoverSignature(der: [UInt8], hash: [UInt8], publicKey: [UInt8]) async -> TransactionSignature? {
        signature(der: der, hash: hash, publicKey: publicKey)
    }
}
