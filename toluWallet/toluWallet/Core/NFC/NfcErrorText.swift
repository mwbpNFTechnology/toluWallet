//
//  NfcErrorText.swift
//  toluWallet
//
//  Turns the errors a tag tap can end in into something a person can act on.
//

import CoreNFC
import Foundation
import LocalAuthentication

enum NfcErrorText {

    static func describe(_ error: Error) -> String {
        if let authError = error as? LAError,
           [.userCancel, .appCancel, .systemCancel].contains(authError.code) {
            return "Cancelled before the tag was touched."
        }
        if let nfcError = error as? NFCReaderError {
            switch nfcError.code {
            case .readerSessionInvalidationErrorUserCanceled:
                return "Scan cancelled."
            case .readerSessionInvalidationErrorSessionTimeout:
                return "The scan timed out. Try again and hold the tag still."
            default:
                break
            }
        }
        if case let Se05xError.apdu(operation, sw1, sw2) = error {
            switch operation {
            case "get random":
                return String(format: "The tag gave no random numbers (%02X%02X), so a seed phrase can't be made with it.", sw1, sw2)
            case "check slot":
                return String(format: "The tag couldn't say whether the slots are free (%02X%02X). Nothing was written.", sw1, sw2)
            case "create session":
                return "This tag has nothing in that slot to open a session with. Check the phone key object id."
            case "open session":
                return String(format: "The tag refused this iPhone's session (%02X%02X). If the wallet was made with another iPhone or another slot, that's why.", sw1, sw2)
            case "read public key" where sw1 == 0x69 && sw2 == 0x85:
                return "This iPhone may not use the key in that slot: it is bound to another key."
            case "verify pin":
                return "The tag rejected the password. A wallet with an attempt limit locks for good once the limit is used up."
            default:
                break
            }
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
