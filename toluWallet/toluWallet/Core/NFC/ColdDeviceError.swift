//
//  ColdDeviceError.swift
//  toluWallet
//

import Foundation

enum ColdDeviceError: LocalizedError {
    case unavailable
    case notAColdDevice
    case refused(UInt8, UInt8)
    case invalidSetup

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "This phone can't use NFC."
        case .notAColdDevice:
            return "That isn't a toluCold device — hold the phone to its reader, with no card lying on it."
        case .refused(0x6A, 0x80):
            return "The device refused those details. Check that the two object ids differ and the password is 4–16 characters."
        case .refused(let sw1, let sw2):
            return String(format: "The device refused (%02X%02X). Try the tap again.", sw1, sw2)
        case .invalidSetup:
            return "Those object ids or that password can't be sent."
        }
    }
}
