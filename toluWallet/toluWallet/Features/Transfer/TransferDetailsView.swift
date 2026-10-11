//
//  TransferDetailsView.swift
//  toluWallet
//
//  Transfer, step one: what to send, how much, and to whom. After tolu's
//  vault send-details screen.
//

import SwiftUI

struct TransferDetailsView: View {
    @Bindable var form: TransferFormModel
    let onBack: () -> Void
    let onReview: (TransferDraft) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "transfer · 1 / 2", backSystemImage: "xmark", onBack: onBack)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headline
                    assetPicker
                    if form.selected != nil {
                        amountField
                        recipientField
                    }
                    signNote
                }
                .padding(.horizontal, Tolu.Spacing.screen)
                .padding(.top, 14)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)

            VStack(spacing: 8) {
                if let blocker = form.blocker {
                    Text(blocker)
                        .font(.toluMono(9.5))
                        .foregroundStyle(Tolu.Palette.amber)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                PrimaryButton("Review transfer", systemImage: "arrow.right", isEnabled: form.draft != nil) {
                    guard let draft = form.draft else { return }
                    dismissKeyboard()
                    onReview(draft)
                }
            }
            .padding(.horizontal, Tolu.Spacing.screen)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .contentShape(Rectangle())
        .onTapGesture { dismissKeyboard() }
    }

    // MARK: - Pieces

    private var headline: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("send it \(Text("out").foregroundStyle(Tolu.Palette.lime)).")
                .font(.toluTitle(25))
                .tracking(-1)
                .foregroundStyle(Tolu.Palette.text)
            Text("Pick an asset, an amount and a recipient. Your tolu tag signs exactly that transaction — nothing leaves without the tap.")
                .font(.system(size: 13.5))
                .foregroundStyle(Tolu.Palette.mute)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var assetPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonoLabel("asset", size: 8.5, color: Tolu.Palette.dim, tracking: 1.2)
            if form.holdings.isEmpty {
                Text("This wallet holds nothing yet. Use Receive to fund it — you'll also need the chain's own coin to pay network fees.")
                    .font(.system(size: 13))
                    .foregroundStyle(Tolu.Palette.mute)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .toluCard(radius: 12)
            } else {
                VStack(spacing: 8) {
                    ForEach(form.holdings) { holding in
                        TransferAssetRow(holding: holding, isSelected: holding.id == form.selected?.id) {
                            form.select(holding)
                        }
                    }
                }
            }
        }
    }

    private var amountField: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                MonoLabel("amount", size: 8.5, color: Tolu.Palette.dim, tracking: 1.2)
                Spacer(minLength: 0)
                Button("Max") { form.fillMaximum() }
                    .font(.toluMono(9))
                    .textCase(.uppercase)
                    .foregroundStyle(Tolu.Palette.lime)
                    .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                TextField("0.0", text: $form.amountText)
                    .font(.toluMono(15))
                    .foregroundStyle(Tolu.Palette.text)
                    .keyboardType(.decimalPad)
                MonoLabel(form.selected?.symbol ?? "", size: 10, color: Tolu.Palette.mute, tracking: 1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 13)
            .toluCard(radius: 11, stroke: Tolu.Palette.line2)

            if form.sendsMaximum, form.selected?.isNative == true {
                MonoLabel("the network fee is taken out of this amount", size: 8.5, color: Tolu.Palette.dim, tracking: 1)
            }
        }
    }

    private var recipientField: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                MonoLabel("to", size: 8.5, color: Tolu.Palette.dim, tracking: 1.2)
                Spacer(minLength: 0)
                Button("Paste") { form.pasteRecipient() }
                    .font(.toluMono(9))
                    .textCase(.uppercase)
                    .foregroundStyle(Tolu.Palette.lime)
                    .buttonStyle(.plain)
            }
            TextField("0x…", text: $form.recipientText, axis: .vertical)
                .font(.toluMono(12))
                .foregroundStyle(Tolu.Palette.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .lineLimit(1...2)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .toluCard(radius: 11,
                          stroke: form.recipientLooksWrong ? Tolu.Palette.coral.opacity(0.6) : Tolu.Palette.line2)
        }
    }

    private var signNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 13))
                .foregroundStyle(Tolu.Palette.lime)
                .accessibilityHidden(true)
            Text("The next screen shows the network fee before anything is signed. A sent transfer can't be undone, so check the address and the network.")
                .font(.toluMono(9.5))
                .foregroundStyle(Tolu.Palette.dim)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .toluCard(radius: 12)
    }
}

#Preview {
    TransferDetailsView(
        form: TransferFormModel(wallet: .preview, holdings: [
            Holding(chain: ChainRegistry.all[0], token: nil, balance: BigUInt(1_250_000_000_000_000_000))
        ]),
        onBack: {},
        onReview: { _ in }
    )
    .background(Tolu.Palette.ink)
    .preferredColorScheme(.dark)
}
