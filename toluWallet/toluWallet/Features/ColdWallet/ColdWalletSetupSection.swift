//
//  ColdWalletSetupSection.swift
//  toluWallet
//
//  Stage one of a cold-device wallet: the same label, slots and password as
//  any wallet — they are what the phone hands to the device.
//

import SwiftUI

struct ColdWalletSetupSection: View {
    @Bindable var model: ColdWalletViewModel

    private let accent = Tolu.Palette.violet

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                ToluHeading(text: "the key is made\noff this phone", accent: accent)
                Text("A toluCold device makes the seed phrase from a random number generated inside the card's secure element, shows it to you once, and writes the key to the card. This phone only sends where the key goes and the password that guards it.")
                    .font(.system(size: 13))
                    .foregroundStyle(Tolu.Palette.mute)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            WalletSetupFields(
                label: $model.label,
                keyObjectID: $model.keyObjectIdText,
                password: $model.password,
                passwordObjectID: $model.passwordObjectIdText,
                slotsCollide: model.slotsCollide,
                accent: accent
            )

            NoticeCard(
                systemImage: "pencil.and.list.clipboard",
                text: "Have pen and paper ready. The device shows 12 words once — they are the only backup of this wallet, and anyone who has them has the wallet.",
                color: accent
            )

            if let error = model.setupError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(Tolu.Palette.coral)
            }
            if !model.isNfcAvailable {
                Text("nfc isn't available here — run on a real iphone.")
                    .font(.system(size: 12))
                    .foregroundStyle(Tolu.Palette.amber)
            }
        }
        .onChange(of: model.keyObjectIdText) { model.keySlotChanged() }
        .onChange(of: model.passwordObjectIdText) { model.passwordSlotChanged() }
    }
}

#Preview {
    ScrollView {
        ColdWalletSetupSection(model: ColdWalletViewModel(store: WalletStore()))
            .padding()
    }
    .background(Tolu.Palette.ink)
}
