//
//  WalletRecord+Codable.swift
//  toluWallet
//
//  Records saved before the iPhone key have `passwordObjectID` and
//  `password` instead of `authObjectID` and `unlock`; they still load, as
//  password wallets.
//

import Foundation

extension WalletRecord: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, label, keyObjectID, authObjectID, unlock, publicKey, address
        case cardUniqueId, passwordAttemptLimit, backup, createdAt
        // Older records
        case passwordObjectID, password
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        keyObjectID = try container.decode(String.self, forKey: .keyObjectID)
        if let unlock = try container.decodeIfPresent(WalletUnlock.self, forKey: .unlock) {
            self.unlock = unlock
            authObjectID = try container.decode(String.self, forKey: .authObjectID)
        } else {
            unlock = .password(try container.decode(String.self, forKey: .password))
            authObjectID = try container.decode(String.self, forKey: .passwordObjectID)
        }
        publicKey = try container.decode(String.self, forKey: .publicKey)
        address = try container.decode(String.self, forKey: .address)
        cardUniqueId = try container.decodeIfPresent(String.self, forKey: .cardUniqueId)
        passwordAttemptLimit = try container.decodeIfPresent(Int.self, forKey: .passwordAttemptLimit)
        backup = try container.decodeIfPresent(WalletBackup.self, forKey: .backup)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(keyObjectID, forKey: .keyObjectID)
        try container.encode(authObjectID, forKey: .authObjectID)
        try container.encode(unlock, forKey: .unlock)
        try container.encode(publicKey, forKey: .publicKey)
        try container.encode(address, forKey: .address)
        try container.encodeIfPresent(cardUniqueId, forKey: .cardUniqueId)
        try container.encodeIfPresent(passwordAttemptLimit, forKey: .passwordAttemptLimit)
        try container.encodeIfPresent(backup, forKey: .backup)
        try container.encode(createdAt, forKey: .createdAt)
    }
}
