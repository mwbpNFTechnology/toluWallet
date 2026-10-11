//
//  ProtectedKeyConfiguration.swift
//  toluWallet
//
//  What the writer reports back after creating a key pair.
//

import Foundation

struct ProtectedKeyConfiguration {
    let userIDValue: String
    let userIDObjectID: String
    let keyObjectID: String
    let maxAttempts: Int
    let publicKey: String?
    let uniqueId: String?
    let createdDate: Date
}
