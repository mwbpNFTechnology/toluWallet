//
//  WalletStoreError.swift
//  toluWallet
//

import Foundation

enum WalletStoreError: LocalizedError {
    case authenticationUnavailable
    case locked
    case unreadable
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .authenticationUnavailable:
            return "Set up Face ID or a device passcode to protect your wallets."
        case .locked:
            return "Unlock your wallets first."
        case .unreadable:
            return "The saved wallets couldn't be read. Nothing was changed."
        case .keychain(let status):
            return "The Keychain refused the request (\(status))."
        }
    }
}
