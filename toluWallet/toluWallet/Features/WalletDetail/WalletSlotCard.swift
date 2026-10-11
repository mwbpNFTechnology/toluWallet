//
//  WalletSlotCard.swift
//  toluWallet
//
//  Where this wallet lives on the tag: its slots, password and card id. These
//  are what is needed to import the wallet on another phone.
//

import SwiftUI

struct WalletSlotCard: View {
    let wallet: WalletRecord

    @State private var passwordVisible = false

    var body: some View {
        VStack(spacing: 9) {
            DetailRow(label: "key object id", value: "0x\(wallet.keyObjectID)")
            DetailRow(label: "password object id", value: "0x\(wallet.passwordObjectID)")

            HStack(spacing: 8) {
                MonoLabel("password", size: 8.5, color: Tolu.Palette.dim, tracking: 1.2)
                Rectangle().fill(Tolu.Palette.line).frame(height: 1)
                Text(passwordVisible ? wallet.password : String(repeating: "•", count: wallet.password.count))
                    .font(.toluMono(11))
                    .foregroundStyle(Tolu.Palette.mute)
                    .lineLimit(1)
                    .textSelection(.enabled)
                    .accessibilityLabel(passwordVisible ? wallet.password : "hidden")
                Button(passwordVisible ? "Hide password" : "Show password",
                       systemImage: passwordVisible ? "eye.slash" : "eye") {
                    passwordVisible.toggle()
                }
                .labelStyle(.iconOnly)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Tolu.Palette.mute)
                .buttonStyle(.plain)
            }

            if let limit = wallet.passwordAttemptLimit {
                DetailRow(label: "wrong passwords", value: "\(limit), then locked", valueColor: Tolu.Palette.amber)
            }
            if let backup = wallet.backup {
                DetailRow(label: "backup", value: backup.summary)
            }
            if let card = wallet.cardUniqueId {
                DetailRow(label: "card id", value: EthereumAddress.short(card))
            }
            DetailRow(label: "created", value: wallet.createdAt.formatted(date: .abbreviated, time: .omitted))
        }
        .padding(14)
        .toluCard()
    }
}

#Preview {
    WalletSlotCard(wallet: .preview)
        .padding()
        .background(Tolu.Palette.ink)
}
