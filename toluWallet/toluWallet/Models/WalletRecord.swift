//
//  WalletRecord.swift
//  toluWallet
//
//  Everything the phone keeps about one wallet. The private key is not here —
//  it never leaves the tag. This is what is needed to ask the tag to sign:
//  which slots to use and the password that unlocks them. Stored in the
//  Keychain behind Face ID.
//

import Foundation

struct WalletRecord: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var label: String
    /// The slot on the tag holding the secp256k1 key pair (8 hex digits).
    let keyObjectID: String
    /// The slot on the tag holding the password that guards the key (8 hex digits).
    let passwordObjectID: String
    let password: String
    /// Uncompressed public key, `0x04…` hex.
    let publicKey: String
    /// Lower-case `0x` address derived from the public key.
    let address: String
    /// The chip's factory unique id (normalized hex), when it was read.
    let cardUniqueId: String?
    /// Wrong passwords the card allows before the key locks for good. `nil`
    /// for wallets made before the limit existed, or imported ones, where the
    /// app can't tell.
    var passwordAttemptLimit: Int?
    /// What exists to restore this wallet. `nil` where the app can't tell:
    /// wallets saved before this was recorded, and imported ones.
    var backup: WalletBackup?
    let createdAt: Date

    /// The limit new wallets are created with.
    static let defaultPasswordAttemptLimit = 5

    /// The address in EIP-55 checksum form, as it is shown and shared.
    var displayAddress: String { EthereumAddress.checksummed(address) }
}
