//
//  ColdWalletDeviceSection.swift
//  toluWallet
//
//  Stage two of a cold-device wallet: the three steps, what to do on the
//  device in between, and the address once the card has been checked.
//

import SwiftUI

struct ColdWalletDeviceSection: View {
    let model: ColdWalletViewModel

    private let accent = Tolu.Palette.violet

    var body: some View {
        VStack(spacing: 0) {
            NfcPulseMark(done: model.isComplete, accent: model.isComplete ? Tolu.Palette.lime : accent)
                .padding(.top, 6)
                .accessibilityHidden(true)

            Text(headline)
                .font(.toluTitle(26))
                .tracking(-1)
                .multilineTextAlignment(.center)
                .foregroundStyle(Tolu.Palette.text)
                .padding(.top, 10)

            Text(subtitle)
                .font(.system(size: 13.5))
                .foregroundStyle(Tolu.Palette.mute)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 310)
                .padding(.top, 8)

            StepsCard(steps: ColdWalletViewModel.Step.allCases.map { step in
                StepsCard.Item(id: step.id, state: model.state(for: step), title: step.title, hint: model.hint(for: step))
            })
            .padding(.top, 18)

            if model.step == .scan, !model.isComplete {
                deviceInstructions.padding(.top, 14)
            }

            if let wallet = model.createdWallet {
                VStack(alignment: .leading, spacing: 14) {
                    InfoRow(label: "wallet address", value: wallet.displayAddress, valueColor: Tolu.Palette.lime)
                    InfoRow(label: "public key", value: wallet.publicKey, valueColor: Tolu.Palette.mute)
                }
                .padding(16)
                .toluCard(radius: Tolu.Radius.card, fill: Tolu.Palette.ink3)
                .padding(.top, 14)
            }

            if let error = model.runError {
                Text(error)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Tolu.Palette.coral)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var headline: String {
        if model.isComplete { return "wallet ready" }
        switch model.step {
        case .send: return "hold the phone to\nthe toluCold reader"
        case .scan: return "now it's the\ndevice's turn"
        case .check: return "hold the card to\nthe top of your phone"
        }
    }

    private var subtitle: String {
        if model.isComplete { return "the card holds the key the device made, and the wallet is saved behind face id." }
        switch model.step {
        case .send: return "the device should be showing its start screen."
        case .scan: return "this can take a few minutes. the app may lock meanwhile — your details are kept."
        case .check: return "one tap opens the password session and reads the card's address."
        }
    }

    private var deviceInstructions: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel("on the device", size: 9, color: Tolu.Palette.dim, tracking: 1.5)
            instruction(1, "Take the phone away and hold the card on its reader.")
            instruction(2, "Write down the words it shows, in order. They are the only backup.")
            instruction(3, "Confirm three of them with the button: click moves, hold selects.")
            instruction(4, "Hold the card on the reader again so the key is written.")
            instruction(5, "When it shows a QR code, scan it here.")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .toluCard()
    }

    private func instruction(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.toluMono(11))
                .foregroundStyle(accent)
                .frame(width: 14, alignment: .leading)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Tolu.Palette.text)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ScrollView {
        ColdWalletDeviceSection(model: ColdWalletViewModel(store: WalletStore()))
            .padding()
    }
    .background(Tolu.Palette.ink)
}
