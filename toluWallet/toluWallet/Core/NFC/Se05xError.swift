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
        }
    }
}
