//
//  ActivityItem.swift
//  toluWallet
//
//  One line of a wallet's history on a chain: a coin or token moving in or
//  out, or a contract call.
//

import Foundation

struct ActivityItem: Identifiable, Equatable {

    enum Direction {
        case incoming
        case outgoing
        case neutral
    }

    let id: String
    let hash: String
    let date: Date?
    let direction: Direction
    /// "Received", "Sent", "Minted", or the contract method that was called.
    let title: String
    /// "25 USDC", "#1888 MoAI" — `nil` when nothing moved.
    let amountText: String?
    /// The other side of the movement.
    let counterparty: String?
    let failed: Bool
    let url: URL?
}
