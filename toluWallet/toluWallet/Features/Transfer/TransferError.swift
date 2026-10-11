//
//  TransferError.swift
//  toluWallet
//

import Foundation

enum TransferError: LocalizedError {
    case invalidRecipient
    case notPrepared
    case wrongTag
    case badSignature
    case insufficientFunds(needed: String, symbol: String)
    case needsGas(fee: String, symbol: String, chain: String)
    case reverted
    case stillPending

    var errorDescription: String? {
        switch self {
        case .invalidRecipient:
            return "The recipient address isn't valid."
        case .notPrepared:
            return "The transfer isn't ready to sign yet."
        case .wrongTag:
            return "This tag holds a different key. Tap the tag this wallet was created on."
        case .badSignature:
            return "The tag's signature couldn't be verified, so nothing was sent."
        case .insufficientFunds(let needed, let symbol):
            return "Not enough \(symbol): the amount plus the network fee comes to \(needed) \(symbol)."
        case .needsGas(let fee, let symbol, let chain):
            return "You need about \(fee) \(symbol) on \(chain) to pay the network fee."
        case .reverted:
            return "The network included the transaction but it failed. Only the fee was spent."
        case .stillPending:
            return "Still waiting for the network. The transaction was sent — check the explorer, or keep waiting."
        }
    }
}
