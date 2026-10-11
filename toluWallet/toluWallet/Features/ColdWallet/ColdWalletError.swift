//
//  ColdWalletError.swift
//  toluWallet
//

import Foundation

enum ColdWalletError: LocalizedError {
    case addressMismatch(card: String, device: String)

    var errorDescription: String? {
        switch self {
        case .addressMismatch(let card, let device):
            return "This card's key is for \(EthereumAddress.short(card)), but the device showed \(EthereumAddress.short(device)). Use the card the device wrote, or scan the QR again."
        }
    }
}
