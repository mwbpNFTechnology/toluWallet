//
//  CreateWalletSetupSection.swift
//  toluWallet
//
//  Stage one of creating a wallet: the label, the tag slots, the password,
//  and where the key comes from.
//

import SwiftUI

struct CreateWalletSetupSection: View {
    @Bindable var model: CreateWalletViewModel

    private let accent = Tolu.Palette.lime

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ToluHeading(text: "name it, pick a slot,\nthen tap the tag", accent: accent)
                .padding(.bottom, 2)

            WalletSetupFields(
                label: $model.label,
                keyObjectID: $model.keyObjectIdText,
                password: $model.password,
                passwordObjectID: $model.passwordObjectIdText,
                slotsCollide: model.slotsCollide,
                accent: accent
            )

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "where the key comes from")
                ForEach(KeyOrigin.allCases) { origin in
                    ChoiceCard(title: origin.title, detail: origin.detail,
                               isSelected: model.origin == origin, accent: accent) {
                        model.origin = origin
                    }
                }
            }

            notice

            if let error = model.setupError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(Tolu.Palette.coral)
                    .fixedSize(horizontal: false, vertical: true)
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

    /// What is worth knowing about the chosen way before going on.
    @ViewBuilder
    private var notice: some View {
        switch model.origin {
        case .tag:
            NoticeCard(
                systemImage: "exclamationmark.triangle",
                text: "The key is generated inside the tag and can't be exported or backed up. If the tag is lost, or the password is forgotten or entered wrong \(WalletRecord.defaultPasswordAttemptLimit) times, whatever this wallet holds is gone."
            )
        case .seedPhrase:
            NoticeCard(
                systemImage: "pencil.and.list.clipboard",
                text: "Have pen and paper ready, somewhere private. This phone makes the 12 words and holds their key for a moment before it goes onto the tag. For a key that never touches a phone, create the wallet with a cold device instead."
            )
        case .existing:
            EmptyView()
        }
    }
}

#Preview {
    ScrollView {
        CreateWalletSetupSection(model: CreateWalletViewModel(store: WalletStore()))
            .padding()
    }
    .background(Tolu.Palette.ink)
}
