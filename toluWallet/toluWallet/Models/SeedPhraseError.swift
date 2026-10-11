//
//  SeedPhraseError.swift
//  toluWallet
//
//  What can go wrong while making a wallet from a seed phrase on this phone.
//

import Foundation

enum SeedPhraseError: LocalizedError {
    case tagRandomLooksBroken
    case phoneRandomFailed
    case phraseFailed
    case keyFailed
    case keyMissing
    case keyMismatch

    var errorDescription: String? {
        switch self {
        case .tagRandomLooksBroken:
            "The tag's random numbers look wrong. Don't use this tag for a wallet."
        case .phoneRandomFailed:
            "This phone couldn't produce random numbers. Try again."
        case .phraseFailed:
            "The seed phrase couldn't be built. Try again."
        case .keyFailed:
            "That seed phrase can't be used for a wallet. Start again — you will get new words."
        case .keyMissing:
            "The key from your words is no longer on this phone. Go back and start again — you will get new words."
        case .keyMismatch:
            "The key on the tag is not the one from your words. Don't use this wallet."
        }
    }
}
