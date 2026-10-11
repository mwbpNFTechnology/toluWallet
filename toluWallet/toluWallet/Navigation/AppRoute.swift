//
//  AppRoute.swift
//  toluWallet
//
//  Every screen that can be pushed onto the navigation stack.
//

import Foundation

enum AppRoute: Hashable {
    case createWallet
    /// Create a wallet with a toluCold device (or pick up an unfinished one).
    case createColdWallet
    case wallet(WalletRecord.ID)
    /// One chain of one wallet: its tokens, NFTs and history.
    case chain(wallet: WalletRecord.ID, chainID: Int)
}
