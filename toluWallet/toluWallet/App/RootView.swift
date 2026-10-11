//
//  RootView.swift
//  toluWallet
//
//  The app's composition root. Nothing is shown until the wallet store is
//  unlocked with Face ID; after that it owns the single NavigationStack and
//  maps each `AppRoute` to its screen. The app locks itself again after a
//  spell in the background.
//

import SwiftUI

struct RootView: View {
    @State private var router = Router()
    @State private var store = WalletStore()
    @State private var portfolios = PortfolioStore()
    @State private var backgroundedAt: Date?

    @Environment(\.scenePhase) private var scenePhase

    /// How long the app may sit in the background before it locks. Long enough
    /// to copy an address from another app.
    private let lockDelay: TimeInterval = 60

    var body: some View {
        Group {
            if store.isUnlocked {
                NavigationStack(path: $router.path) {
                    WalletListView()
                        .navigationDestination(for: AppRoute.self) { route in
                            destination(for: route)
                        }
                }
            } else {
                LockView()
            }
        }
        .environment(router)
        .environment(store)
        .tint(Tolu.Palette.lime)
        .onChange(of: scenePhase) { _, phase in
            handle(phase)
        }
        // However the app got locked, cached balances go with it.
        .onChange(of: store.isUnlocked) { _, isUnlocked in
            if !isUnlocked { portfolios.clear() }
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .createWallet:
            CreateWalletView(store: store)
        case .createColdWallet:
            ColdWalletView(store: store)
        case .wallet(let id):
            if let wallet = store.wallet(id: id) {
                WalletDetailView(portfolio: portfolios.portfolio(for: wallet))
            }
        case .chain(let walletID, let chainID):
            if let wallet = store.wallet(id: walletID), let chain = ChainRegistry.chain(id: chainID) {
                ChainDetailView(portfolio: portfolios.portfolio(for: wallet), chain: chain)
            }
        }
    }

    private func handle(_ phase: ScenePhase) {
        switch phase {
        case .background:
            backgroundedAt = backgroundedAt ?? .now
        case .active:
            if let backgroundedAt, Date.now.timeIntervalSince(backgroundedAt) > lockDelay {
                router.popToRoot()
                store.lock()
            }
            backgroundedAt = nil
        default:
            break
        }
    }
}

#Preview {
    RootView()
        .preferredColorScheme(.dark)
}
