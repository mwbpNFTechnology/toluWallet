//
//  Se05xError.swift
//  toluWallet
//
//  Errors surfaced from the NFC / SE05x scan flow.
//

import Foundation

enum Se05xError: LocalizedError {
    case nfcUnavailable
    case notSupportedTag
    case apdu(String, UInt8, UInt8)
    case noKey
    case notSecp256k1
    case severalTags

    var errorDescription: String? {
        switch self {
        case .nfcUnavailable:
            return "NFC is not available on this device."
        case .notSupportedTag:
            return "That isn't a supported tolu tag."
        case let .apdu(operation, sw1, sw2):
            return String(format: "%@ failed (SW=%02X%02X)", operation, sw1, sw2)
        case .noKey:
            return "No key found at this object id."
        case .notSecp256k1:
            return "The key at this object id isn't a secp256k1 key, so it can't hold an Ethereum wallet."
        case .severalTags:
            return "More than one tag is in range. Hold only your tolu tag."
        }
    }
}
