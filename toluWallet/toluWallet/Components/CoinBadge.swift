//
//  CoinBadge.swift
//  toluWallet
//
//  A round badge showing an asset's symbol, tinted with a colour that stays
//  the same for that symbol on every load.
//

import SwiftUI

struct CoinBadge: View {
    let symbol: String
    var size: CGFloat = 34

    private var tint: Color {
        let palette: [Color] = [Tolu.Palette.sky, Tolu.Palette.amber, Tolu.Palette.violet,
                                Tolu.Palette.lime, Tolu.Palette.teal]
        let hash = symbol.lowercased().unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[hash % palette.count]
    }

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.08))
                .overlay(Circle().stroke(tint.opacity(0.55), lineWidth: 1))
            Text(symbol.prefix(4))
                .font(.toluMono(size * 0.26))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

#Preview {
    HStack {
        CoinBadge(symbol: "ETH")
        CoinBadge(symbol: "USDC")
        CoinBadge(symbol: "POL")
    }
    .padding()
    .background(Tolu.Palette.ink)
}
