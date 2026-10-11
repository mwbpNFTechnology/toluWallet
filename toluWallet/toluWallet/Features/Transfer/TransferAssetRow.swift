//
//  TransferAssetRow.swift
//  toluWallet
//
//  One selectable asset in the transfer picker.
//

import SwiftUI

struct TransferAssetRow: View {
    let holding: Holding
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? Tolu.Palette.lime : Tolu.Palette.line2, lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                    if isSelected {
                        Circle().fill(Tolu.Palette.lime).frame(width: 9, height: 9)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(holding.symbol)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Tolu.Palette.text)
                    MonoLabel("\(holding.chain.name) · chain \(holding.chain.id)", size: 8.5, tracking: 1)
                }
                Spacer(minLength: 6)
                Text(holding.balanceText)
                    .font(.toluMono(11))
                    .foregroundStyle(isSelected ? Tolu.Palette.lime : Tolu.Palette.dim)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .toluCard(radius: 12, stroke: isSelected ? Tolu.Palette.lime.opacity(0.5) : Tolu.Palette.line)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    VStack(spacing: 8) {
        TransferAssetRow(
            holding: Holding(chain: ChainRegistry.all[0], token: nil, balance: BigUInt(1_250_000_000_000_000_000)),
            isSelected: true
        ) {}
    }
    .padding()
    .background(Tolu.Palette.ink)
}
