//
//  WalletRecordTests.swift
//  toluWalletTests
//

import Foundation
import Testing
@testable import toluWallet

@MainActor
struct WalletRecordTests {

    /// A wallet saved before the app recorded attempt limits or backups has
    /// neither key in its JSON.
    @Test func readsARecordSavedBeforeTheNewerFields() throws {
        let encoded = try JSONEncoder().encode(WalletRecord.preview)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["backup"] = nil
        object["passwordAttemptLimit"] = nil

        let old = try JSONDecoder().decode(WalletRecord.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(old.backup == nil)
        #expect(old.passwordAttemptLimit == nil)
        #expect(old.address == WalletRecord.preview.address)
    }

    /// A wallet saved before the iPhone key stored a password and its slot.
    /// It still loads — as a password wallet, signing the old way.
    @Test func readsAPasswordWalletSavedBeforeTheIPhoneKey() throws {
        let encoded = try JSONEncoder().encode(WalletRecord.preview)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["authObjectID"] = nil
        object["unlock"] = nil
        object["passwordObjectID"] = "00000002"
        object["password"] = "hunter22"
        object["passwordAttemptLimit"] = 5

        let old = try JSONDecoder().decode(WalletRecord.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(old.unlock == .password("hunter22"))
        #expect(old.authObjectID == "00000002")
        #expect(old.passwordAttemptLimit == 5)

        // Saved again, it keeps being a password wallet.
        let resaved = try JSONDecoder().decode(WalletRecord.self, from: JSONEncoder().encode(old))
        #expect(resaved.unlock == .password("hunter22"))
        #expect(resaved.authObjectID == "00000002")
    }

    @Test func keepsWhatUnlocksTheWalletThroughSaving() throws {
        let copy = try JSONDecoder().decode(WalletRecord.self, from: JSONEncoder().encode(WalletRecord.preview))
        #expect(copy.unlock == .thisPhone)
        #expect(copy.authObjectID == WalletRecord.preview.authObjectID)
        #expect(copy == WalletRecord.preview)
    }

    @Test func keepsTheBackupThroughSaving() throws {
        for backup in [WalletBackup.seedPhrase, .noBackup] {
            var record = WalletRecord.preview
            record.backup = backup
            let copy = try JSONDecoder().decode(WalletRecord.self, from: JSONEncoder().encode(record))
            #expect(copy.backup == backup)
        }
    }
}
