//
//  ProtectedKeyWriterError.swift
//  toluWallet
//
//  What can go wrong while creating a key pair on a tag.
//

import Foundation

enum ProtectedKeyWriterError: LocalizedError {
    case noNFCTag, unsupportedTagType, connectionError(Error), commandError(Error)
    case responseError(sw1: UInt8, sw2: UInt8), invalidObjectIDFormat, invalidUserIDLength
    case appletSelectionFailed, curveInitializationFailed, userIDCreationFailed
    case keyPairCreationFailed, publicKeyReadFailed
    case keySlotInUse, passwordSlotInUse
    case passwordObjectRefused(sw1: UInt8, sw2: UInt8)
    case keyRefused(sw1: UInt8, sw2: UInt8)

    var errorDescription: String? {
        switch self {
        case .noNFCTag: return "No NFC tag detected"
        case .unsupportedTagType: return "Unsupported tag type"
        case .connectionError(let e): return "Connection error: \(e.localizedDescription)"
        case .commandError(let e): return "Command error: \(e.localizedDescription)"
        case .responseError(let sw1, let sw2): return "Response error: SW1=\(String(format: "%02X", sw1)), SW2=\(String(format: "%02X", sw2))"
        case .invalidObjectIDFormat: return "Invalid Object ID format"
        case .invalidUserIDLength: return "Password must be between 4 and 16 characters"
        case .appletSelectionFailed: return "Failed to select SE050 applet"
        case .curveInitializationFailed: return "Failed to initialize secp256k1 curve"
        case .userIDCreationFailed: return "Failed to create UserID"
        case .keyPairCreationFailed: return "Failed to create protected key pair"
        case .publicKeyReadFailed: return "Failed to read public key"
        case .keySlotInUse: return "That key object id is already used on this tag. To use the key in it, choose “already on the tag”."
        case .passwordSlotInUse: return "That password object id is already used on this tag"
        case .passwordObjectRefused(let sw1, let sw2):
            return String(format: "The tag refused the password object (%02X%02X). Nothing was written.", sw1, sw2)
        case .keyRefused(let sw1, let sw2):
            return String(format: "The tag refused the key (%02X%02X).", sw1, sw2)
        }
    }
}
