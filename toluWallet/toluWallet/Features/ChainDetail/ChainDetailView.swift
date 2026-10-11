//
//  ChainDetailView.swift
//  toluWallet
//
//  One chain of a wallet: the native coin and tokens, NFTs, and the recent
//  history. A chain holding nothing shows how to fund it instead.
//

import SwiftUI

struct ChainDetailView: View {
    @Environment(Router.self) private var router

    let portfolio: WalletPortfolio
    let chain: Chain

    @State private var activity: ChainActivityModel
    @State private var showReceive = false
    @State private var showTransfer = false

    init(portfolio: WalletPortfolio, chain: Chain) {
        self.portfolio = portfolio
        self.chain = chain
        _activity = State(initialValue: ChainActivityModel(wallet: portfolio.wallet, chain: chain))
    }

    private var wallet: WalletRecord { portfolio.wallet }
    private var balance: ChainBalance { portfolio.balance(for: chain) }
    private var holdings: [Holding] { portfolio.holdings(on: chain) }

    var body: some View {
        ZStack {
            ToluBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: chain.name) { router.pop() }

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        summary
                        actions

                        if balance.isEmpty {
                            emptyState
                        } else {
                            assetsSection
                            if !balance.nfts.isEmpty { nftSection }
                        }

                        activitySection
                    }
                    .padding(.horizontal, Tolu.Spacing.screen)
                    .padding(.top, 14)
                    .padding(.bottom, 20)
                }
                .refreshable { await reload() }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await portfolio.loadIfStale()
            if !activity.hasLoaded { await activity.load() }
        }
        .sheet(isPresented: $showReceive) {
            ReceiveSheet(wallet: wallet)
        }
        .fullScreenCover(isPresented: $showTransfer) {
            TransferFlowView(
                wallet: wallet,
                holdings: holdings,
                onClose: { showTransfer = false },
                onSent: { Task { await reload() } }
            )
        }
    }

    private func reload() async {
        async let assets: Void = portfolio.load(chain)
        async let history: Void = activity.load()
        _ = await (assets, history)
    }

    // MARK: - Header

    private var summary: some View {
        VStack(spacing: 11) {
            HStack(spacing: 11) {
                CoinBadge(symbol: chain.symbol, size: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text(chain.name)
                        .font(.toluTitle(20))
                        .tracking(-0.7)
                        .foregroundStyle(Tolu.Palette.text)
                        .lineLimit(1)
                    MonoLabel(chain.isTestnet ? "chain \(chain.id) · testnet" : "chain \(chain.id)",
                              size: 8.5, color: chain.isTestnet ? Tolu.Palette.amber : Tolu.Palette.dim, tracking: 1.1)
                }

                Spacer(minLength: 6)

                if balance.nativeUsdPrice != nil {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(UsdFormat.string(balance.usdValue))
                            .font(.toluMono(18))
                            .tracking(-0.4)
                            .foregroundStyle(Tolu.Palette.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        MonoLabel("value here", size: 8.5, tracking: 1.2)
                    }
                    .accessibilityElement(children: .combine)
                } else if balance.isLoading, !balance.isLoaded {
                    ProgressView().controlSize(.small).tint(Tolu.Palette.lime)
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
            .disabled(holdings.isEmpty)
            .opacity(holdings.isEmpty ? 0.45 : 1)
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

    // MARK: - Assets

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            ToluHeading(text: "nothing here yet", size: 22)
            Text("This wallet holds no \(chain.symbol), tokens or NFTs on \(chain.name). Send some to its address and they'll show up here.")
                .font(.system(size: 13))
                .foregroundStyle(Tolu.Palette.mute)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            PrimaryButton("Receive on \(chain.name)", systemImage: "arrow.down") {
                showReceive = true
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .toluCard(radius: Tolu.Radius.card)
    }

    private var assetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "tokens", trailing: "\(holdings.count)")
                .padding(.top, 6)
            if let error = balance.error {
                note(error, color: Tolu.Palette.coral)
            }
            ForEach(holdings) { holding in
                AssetRow(holding: holding)
            }
            if !chain.hasIndexer {
                note("Only \(chain.symbol) and the built-in tokens are checked on \(chain.name). Other tokens and NFTs don't show here yet.")
            } else if balance.isPartial {
                note("The full token list didn't load, so only \(chain.symbol) and the built-in tokens are shown. Pull down to try again.",
                     color: Tolu.Palette.amber)
            }
        }
    }

    private var nftSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "nfts", trailing: "\(balance.nftCount)")
                .padding(.top, 6)
            ForEach(balance.nfts) { collection in
                NftCollectionRow(collection: collection)
            }
        }
    }

    // MARK: - History

    @ViewBuilder
    private var activitySection: some View {
        SectionHeader(title: "transactions", trailing: activity.items.isEmpty ? nil : "\(activity.items.count)")
            .padding(.top, 6)

        if !chain.hasIndexer {
            note("Transaction history isn't available for \(chain.name) in the app yet.")
            explorerLink
        } else if let error = activity.error {
            note(error, color: Tolu.Palette.coral)
        } else if activity.items.isEmpty {
            if activity.isLoading || !activity.hasLoaded {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small).tint(Tolu.Palette.lime)
                    MonoLabel("reading history", size: 9, tracking: 1.4)
                }
                .padding(.vertical, 6)
            } else {
                note("No transactions yet.")
            }
        } else {
            ForEach(activity.items) { item in
                ActivityRow(item: item)
            }
            explorerLink
        }
    }

    @ViewBuilder
    private var explorerLink: some View {
        if let url = chain.addressURL(wallet.address) {
            Link(destination: url) {
                Label("View everything on the explorer", systemImage: "arrow.up.right.square")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Tolu.Palette.mute)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
        }
    }

    private func note(_ text: String, color: Color = Tolu.Palette.mute) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(color)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    NavigationStack {
        ChainDetailView(portfolio: WalletPortfolio(wallet: .preview), chain: ChainRegistry.all[0])
            .environment(Router())
    }
    .preferredColorScheme(.dark)
}
