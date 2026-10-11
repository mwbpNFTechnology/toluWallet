//
//  AssetRow.swift
//  toluWallet
//
//  One coin or token on a chain screen: how much, and what it is worth.
//

import SwiftUI

struct AssetRow: View {
    let holding: Holding

    var body: some View {
        HStack(spacing: 11) {
            CoinBadge(symbol: holding.symbol)

            VStack(alignment: .leading, spacing: 3) {
                Text(holding.symbol)
                    .font(.system(size: 14.5, weight: .medium))
                    .tracking(-0.25)
                    .foregroundStyle(Tolu.Palette.text)
                    .lineLimit(1)
                MonoLabel(holding.isNative ? "native coin" : holding.name, size: 8.5, tracking: 1)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 3) {
                Text(holding.balanceText)
                    .font(.toluMono(14))
                    .tracking(-0.2)
                    .foregroundStyle(Tolu.Palette.text)
                    .lineLimit(1)
                MonoLabel(valueText, size: 8.5, color: holding.usdValue == nil ? Tolu.Palette.dim : Tolu.Palette.mute, tracking: 0.8)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .toluCard()
        .accessibilityElement(children: .combine)
        .contextMenu {
            if let token = holding.token {
                Button("Copy contract address", systemImage: "doc.on.doc") {
                    Clipboard.copy(token.address)
                }
            }
        }
    }

    private var valueText: String {
        if let value = holding.usdValue { return UsdFormat.string(value) }
        return holding.chain.isTestnet ? "no value" : "no price"
    }
}

#Preview {
    VStack(spacing: 8) {
        AssetRow(holding: Holding(chain: ChainRegistry.all[0], token: nil,
                                  balance: BigUInt(1_250_000_000_000_000_000), usdPrice: 2500))
        AssetRow(holding: Holding(chain: ChainRegistry.all[0], token: KnownTokens.forChain(1)[0],
                                  balance: BigUInt(25_000_000), usdPrice: 1))
    }
    .padding()
    .background(Tolu.Palette.ink)
}
