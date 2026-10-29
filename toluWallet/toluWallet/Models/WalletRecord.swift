//
//  WalletRecord.swift
//  toluWallet
//
//  One saved wallet: where its key sits on the tag, what unlocks it, and
//  the address it controls.
//

import Foundation

struct WalletRecord: Identifiable, Hashable, Sendable {
    var id = UUID()
    var label: String
    /// The slot on the tag holding the secp256k1 key pair (8 hex digits).
    let keyObjectID: String
    /// The slot holding what unlocks the key (8 hex digits): this iPhone's
    /// public key, or for older wallets their password.
    let authObjectID: String
    let unlock: WalletUnlock
    /// Uncompressed public key, `0x04…` hex.
    let publicKey: String
    /// Lower-case `0x` address derived from the public key.
    let address: String
    /// The chip's factory unique id (normalized hex), when it was read.
    let cardUniqueId: String?
    /// Wrong passwords the card allows before the key locks for good. Only
    /// password wallets have one; `nil` too where the app can't tell.
    var passwordAttemptLimit: Int?
    /// What exists to restore this wallet. `nil` where the app can't tell:
    /// wallets saved before this was recorded, and imported ones.
    var backup: WalletBackup?
    let createdAt: Date

    /// The address in EIP-55 checksum form, as it is shown and shared.
    var displayAddress: String { EthereumAddress.checksummed(address) }
}
