//
//  NfcErrorText.swift
//  toluWallet
//
//  Turns the errors a tag tap can end in into something a person can act on.
//

import CoreNFC
import Foundation

enum NfcErrorText {

    static func describe(_ error: Error) -> String {
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
                return "This tag has no password object in that slot."
            case "verify pin":
                return "The tag rejected the password. A wallet with an attempt limit locks for good once the limit is used up."
            default:
                break
            }
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
