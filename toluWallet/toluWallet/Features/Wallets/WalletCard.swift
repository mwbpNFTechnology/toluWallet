//
//  WalletCard.swift
//  toluWallet
//
//  One wallet in the home list.
//

import SwiftUI

struct WalletCard: View {
    let wallet: WalletRecord
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: Tolu.Radius.control, style: .continuous)
                        .fill(Tolu.Palette.lime.opacity(0.1))
                    Image(systemName: "wallet.bifold")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Tolu.Palette.lime)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 5) {
                    Text(wallet.label)
                        .font(.toluTitle(18))
                        .tracking(-0.4)
                        .foregroundStyle(Tolu.Palette.text)
                        .lineLimit(1)
                    Text(EthereumAddress.short(wallet.displayAddress))
                        .font(.toluMono(11))
                        .foregroundStyle(Tolu.Palette.mute)
                    MonoLabel("slot 0x\(wallet.keyObjectID)", size: 8.5, tracking: 1.2)
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Tolu.Palette.dim)
            }
            .padding(16)
            .toluCard(radius: Tolu.Radius.card, fill: Tolu.Palette.ink3)
        }
        .buttonStyle(PressableCardStyle())
    }
}

#Preview {
    WalletCard(wallet: .preview) {}
        .padding()
        .background(Tolu.Palette.ink)
}
