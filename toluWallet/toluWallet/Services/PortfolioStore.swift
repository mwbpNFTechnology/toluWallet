//
//  PortfolioStore.swift
//  toluWallet
//
//  Keeps one `WalletPortfolio` per wallet for as long as the app is unlocked,
//  so every screen about a wallet reads the same balances.
//

import Foundation

final class PortfolioStore {

    private var portfolios: [WalletRecord.ID: WalletPortfolio] = [:]

    func portfolio(for wallet: WalletRecord) -> WalletPortfolio {
        if let existing = portfolios[wallet.id] { return existing }
        let portfolio = WalletPortfolio(wallet: wallet)
        portfolios[wallet.id] = portfolio
        return portfolio
    }

    /// Forgets everything — called when the app locks.
    func clear() {
        portfolios.removeAll()
    }
}
