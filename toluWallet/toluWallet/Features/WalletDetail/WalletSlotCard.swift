//
//  WalletSlotCard.swift
//  toluWallet
//
//  Where this wallet lives on the tag: its slots, what unlocks it, and the
//  card id. A wallet made before the iPhone key still shows its password.
//

import SwiftUI

struct WalletSlotCard: View {
    let wallet: WalletRecord

    @State private var passwordVisible = false

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isSceneCaptured) private var isSceneCaptured

    /// Same rule as the seed words: never shown while the app isn't in front
    /// (so the app-switcher snapshot can't hold it) or the screen is recorded.
    private var showsPassword: Bool { passwordVisible && scenePhase == .active && !isSceneCaptured }

    var body: some View {
        VStack(spacing: 9) {
            DetailRow(label: "key object id", value: "0x\(wallet.keyObjectID)")

            switch wallet.unlock {
            case .thisPhone:
                DetailRow(label: "phone key object id", value: "0x\(wallet.authObjectID)")
                DetailRow(label: "unlocks with", value: "this iphone · face id", valueColor: Tolu.Palette.lime)
            case .password(let password):
                DetailRow(label: "password object id", value: "0x\(wallet.authObjectID)")
                passwordRow(password)
                DetailRow(label: "unlocks with", value: "password, sent in the clear", valueColor: Tolu.Palette.amber)
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
        // Leaving the app hides it again: coming back shows dots.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { passwordVisible = false }
        }
    }

    private func passwordRow(_ password: String) -> some View {
        HStack(spacing: 8) {
            MonoLabel("password", size: 8.5, color: Tolu.Palette.dim, tracking: 1.2)
            Rectangle().fill(Tolu.Palette.line).frame(height: 1)
            Text(showsPassword ? password : String(repeating: "•", count: password.count))
                .toluMono(11)
                .foregroundStyle(Tolu.Palette.mute)
                .lineLimit(1)
                .textSelection(.enabled)
                .accessibilityLabel(showsPassword ? password : "hidden")
            Button(passwordVisible ? "Hide password" : "Show password",
                   systemImage: passwordVisible ? "eye.slash" : "eye") {
                passwordVisible.toggle()
            }
            .labelStyle(.iconOnly)
            .toluFont(11, weight: .medium)
            .foregroundStyle(Tolu.Palette.mute)
            .buttonStyle(TapTargetStyle())
        }
    }
}

#Preview {
    WalletSlotCard(wallet: .preview)
        .padding()
        .background(Tolu.Palette.ink)
}
