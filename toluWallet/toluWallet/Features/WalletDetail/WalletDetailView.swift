//
//  WalletDetailView.swift
//  toluWallet
//
//  One wallet: its address, what it is worth, every chain ordered by value,
//  and the two things to do with it — receive and transfer. Tapping a chain
//  opens its tokens, NFTs and history.
//

import SwiftUI

struct WalletDetailView: View {
    @Environment(Router.self) private var router
    @Environment(WalletStore.self) private var store

    let portfolio: WalletPortfolio

    @State private var showReceive = false
    @State private var showTransfer = false
    @State private var confirmRemove = false
    @State private var errorText: String?

    private var wallet: WalletRecord { portfolio.wallet }

    var body: some View {
        ZStack {
            ToluBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: "wallet", onBack: { router.pop() }) {
                    Menu("Wallet options", systemImage: "ellipsis") {
                        Button("Remove from this phone", systemImage: "trash", role: .destructive) {
                            confirmRemove = true
                        }
                    }
                    .labelStyle(.iconOnly)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Tolu.Palette.mute)
                    .frame(width: 32, height: 32)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        identity
                        actions

                        if let errorText {
                            Text(errorText)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Tolu.Palette.coral)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        SectionHeader(title: "chains", trailing: "by value")
                            .padding(.top, 6)
                        ForEach(portfolio.sortedChains) { chain in
                            Button {
                                router.push(.chain(wallet: wallet.id, chainID: chain.id))
                            } label: {
                                ChainBalanceCard(chain: chain, balance: portfolio.balance(for: chain))
                            }
                            .buttonStyle(PressableCardStyle())
                        }

                        SectionHeader(title: "on the tag")
                            .padding(.top, 6)
                        WalletSlotCard(wallet: wallet)
                    }
                    .padding(.horizontal, Tolu.Spacing.screen)
                    .padding(.top, 14)
                    .padding(.bottom, 20)
                }
                .refreshable { await portfolio.load() }
                .animation(.default, value: portfolio.sortedChains)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await portfolio.loadIfStale() }
        .sheet(isPresented: $showReceive) {
            ReceiveSheet(wallet: wallet)
        }
        .fullScreenCover(isPresented: $showTransfer) {
            TransferFlowView(
                wallet: wallet,
                holdings: portfolio.holdings,
                onClose: { showTransfer = false },
                onSent: { Task { await portfolio.load() } }
            )
        }
        .confirmationDialog("Remove “\(wallet.label)” from this phone?",
                            isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove wallet", role: .destructive) { remove() }
        } message: {
            Text("The key stays on the tag. To use it again you'll need its object ids and password.")
        }
    }

    // MARK: - Pieces

    private var identity: some View {
        VStack(spacing: 11) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Tolu.Palette.lime.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Tolu.Palette.lime, lineWidth: 1))
                    Image(systemName: "wallet.bifold")
                        .font(.system(size: 16))
                        .foregroundStyle(Tolu.Palette.lime)
                }
                .frame(width: 38, height: 38)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(wallet.label)
                        .font(.toluTitle(20))
                        .tracking(-0.7)
                        .foregroundStyle(Tolu.Palette.text)
                        .lineLimit(1)
                    MonoLabel("secp256k1 · one address on every evm chain", size: 8.5, tracking: 1.1)
                }
                Spacer(minLength: 6)
                if portfolio.totalUsd > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(UsdFormat.string(portfolio.totalUsd))
                            .font(.toluMono(18))
                            .tracking(-0.4)
                            .foregroundStyle(Tolu.Palette.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        MonoLabel("total value", size: 8.5, tracking: 1.2)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            AddressBar(address: wallet.displayAddress)
        }
    }

    private var actions: some View {
        HStack(spacing: 9) {
            actionButton("Receive", systemImage: "arrow.down", tint: Tolu.Palette.lime) {
                showReceive = true
            }
            actionButton("Transfer", systemImage: "arrow.up", tint: Tolu.Palette.text) {
                showTransfer = true
            }
        }
    }

    private func actionButton(_ title: String, systemImage: String, tint: Color,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .tracking(-0.2)
                    .foregroundStyle(Tolu.Palette.text)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .toluCard(radius: 12, stroke: Tolu.Palette.line2)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
    }

    private func remove() {
        do {
            try store.remove(wallet.id)
            router.pop()
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        WalletDetailView(portfolio: WalletPortfolio(wallet: .preview))
            .environment(Router())
            .environment(WalletStore())
    }
    .preferredColorScheme(.dark)
}
