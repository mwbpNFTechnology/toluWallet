//
//  WalletRecordTests.swift
//  toluWalletTests
//
//  Saved wallets have to keep loading as the record grows.
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

    @Test func keepsTheBackupThroughSaving() throws {
        for backup in [WalletBackup.seedPhrase, .noBackup] {
            var record = WalletRecord.preview
            record.backup = backup
            let copy = try JSONDecoder().decode(WalletRecord.self, from: JSONEncoder().encode(record))
            #expect(copy.backup == backup)
        }
    }
}
