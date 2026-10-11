//
//  ChainBalanceCard.swift
//  toluWallet
//
//  One chain on the wallet screen: what it holds and what that is worth.
//  A chain holding nothing is greyed out but still opens.
//

import SwiftUI

struct ChainBalanceCard: View {
    let chain: Chain
    let balance: ChainBalance

    var body: some View {
        HStack(spacing: 11) {
            CoinBadge(symbol: chain.symbol)
                .saturation(balance.isEmpty ? 0 : 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(chain.name)
                    .font(.system(size: 14.5, weight: .medium))
                    .tracking(-0.25)
                    .foregroundStyle(Tolu.Palette.text)
                    .lineLimit(1)
                MonoLabel(detail, size: 8.5, color: chain.isTestnet ? Tolu.Palette.amber : Tolu.Palette.dim, tracking: 1.1)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            amounts

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Tolu.Palette.dim)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .toluCard()
        .opacity(balance.isEmpty ? 0.45 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(chain.name)")
    }

    /// "CHAIN 1 · 4 TOKENS · 2 NFTS"
    private var detail: String {
        var parts = ["chain \(chain.id)"]
        if chain.isTestnet { parts.append("testnet") }
        if !balance.tokens.isEmpty {
            parts.append("\(balance.tokens.count) token\(balance.tokens.count == 1 ? "" : "s")")
        }
        if balance.nftCount > 0 {
            parts.append("\(balance.nftCount) nft\(balance.nftCount == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var amounts: some View {
        if let native = balance.native {
            let nativeText = "\(TokenAmount.format(native, decimals: 18)) \(chain.symbol)"
            VStack(alignment: .trailing, spacing: 3) {
                if chain.priceChain != nil, balance.nativeUsdPrice != nil {
                    // A priced chain leads with its dollar value.
                    Text(UsdFormat.string(balance.usdValue))
                        .font(.toluMono(14))
                        .tracking(-0.2)
                        .foregroundStyle(balance.isEmpty ? Tolu.Palette.dim : Tolu.Palette.lime)
                    MonoLabel(nativeText, size: 8.5, tracking: 0.8)
                } else {
                    Text(nativeText)
                        .font(.toluMono(13))
                        .tracking(-0.2)
                        .foregroundStyle(balance.isEmpty ? Tolu.Palette.dim : Tolu.Palette.text)
                    MonoLabel(chain.isTestnet ? "no value" : "no price", size: 8.5, tracking: 0.8)
                }
            }
            .opacity(balance.isLoading ? 0.5 : 1)
        } else if balance.isLoading {
            ProgressView()
                .controlSize(.small)
                .tint(Tolu.Palette.lime)
        } else {
            MonoLabel(balance.error ?? "unavailable", size: 8.5, color: Tolu.Palette.coral, tracking: 1)
        }
    }
}

#Preview {
    VStack(spacing: 10) {
        ChainBalanceCard(
            chain: ChainRegistry.all[0],
            balance: ChainBalance(native: BigUInt(1_250_000_000_000_000_000), nativeUsdPrice: 2500)
        )
        ChainBalanceCard(chain: ChainRegistry.all[1], balance: ChainBalance(native: .zero, nativeUsdPrice: 2500))
        ChainBalanceCard(chain: ChainRegistry.all[2], balance: ChainBalance(isLoading: true))
    }
    .padding()
    .background(Tolu.Palette.ink)
}
