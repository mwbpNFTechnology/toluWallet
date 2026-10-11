//
//  TransactionSignature.swift
//  toluWallet
//
//  An ECDSA signature in the form a transaction carries: r, low-S s, and the
//  recovery bit.
//

import Foundation

nonisolated struct TransactionSignature: Sendable {
    let r: BigUInt
    let s: BigUInt
    /// 0 or 1 — which of the two candidate public keys signed.
    let yParity: Int
}
