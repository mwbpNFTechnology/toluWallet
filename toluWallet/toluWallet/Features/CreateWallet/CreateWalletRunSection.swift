//
//  CreateWalletRunSection.swift
//  toluWallet
//
//  Stage two of creating a wallet: the taps, their progress, and the address
//  that comes back.
//

import SwiftUI

struct CreateWalletRunSection: View {
    let model: CreateWalletViewModel

    private let accent = Tolu.Palette.lime

    var body: some View {
        VStack(spacing: 0) {
            NfcPulseMark(done: model.isComplete, accent: accent)
                .padding(.top, 6)
                .accessibilityHidden(true)

            Text(model.isComplete ? "wallet ready" : "hold the tag to\nthe top of your phone")
                .toluTitle(26)
                .tracking(-1)
                .multilineTextAlignment(.center)
                .foregroundStyle(Tolu.Palette.text)
                .padding(.top, 10)

            Text(subtitle)
                .toluFont(13.5)
                .foregroundStyle(Tolu.Palette.mute)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 300)
                .padding(.top, 8)

            StepsCard(steps: model.steps.map { step in
                StepsCard.Item(id: step.id, state: model.state(for: step.id), title: step.title, hint: step.hint)
            })
            .padding(.top, 18)

            if let wallet = model.createdWallet {
                VStack(alignment: .leading, spacing: 14) {
                    InfoRow(label: "wallet address", value: wallet.displayAddress, valueColor: accent)
                    InfoRow(label: "public key", value: wallet.publicKey, valueColor: Tolu.Palette.mute)
                }
                .padding(16)
                .toluCard(radius: Tolu.Radius.card, fill: Tolu.Palette.ink3)
                .padding(.top, 14)
            }

            if let error = model.runError {
                Text(error)
                    .toluFont(12.5)
                    .foregroundStyle(Tolu.Palette.coral)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var subtitle: String {
        if model.isComplete {
            return model.origin == .seedPhrase
                ? "the key is on the tag, the wallet is saved behind face id, and this phone has forgotten the words."
                : "the key is on the tag and the wallet is saved behind face id."
        }
        switch model.origin {
        case .existing:
            return "face id, then one tap: this iphone opens its encrypted session and reads the address."
        case .tag:
            return "face id, then one tap: the tag makes the key, binds it to this iphone, and the address is read back — all encrypted."
        case .seedPhrase:
            return model.currentStep == 0
                ? "one tap checks that the slots are free and takes a random number from the tag's secure element — the seed phrase is made from it. nothing is written yet."
                : "face id, then one tap: the key from your words goes onto the tag inside an encrypted session, and the address is read back."
        }
    }
}

#Preview {
    CreateWalletRunSection(model: CreateWalletViewModel(store: WalletStore()))
        .padding()
        .background(Tolu.Palette.ink)
}
