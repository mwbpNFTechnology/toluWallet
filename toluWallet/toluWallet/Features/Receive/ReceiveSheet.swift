//
//  ReceiveSheet.swift
//  toluWallet
//
//  The wallet's address as a QR code and as text, to hand to whoever is
//  sending. After tolu's vault receive sheet.
//

import SwiftUI

struct ReceiveSheet: View {
    let wallet: WalletRecord

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            MonoLabel("receive", size: 10, color: Tolu.Palette.dim, tracking: 2)
                .frame(height: 34)
                .padding(.top, 8)

            ScrollView {
                VStack(spacing: 16) {
                    QRCodeView(text: wallet.displayAddress)
                        .padding(.top, 8)

                    VStack(spacing: 8) {
                        Text("send to this \(Text("wallet").foregroundStyle(Tolu.Palette.lime)).")
                            .font(.toluTitle(23))
                            .tracking(-1)
                            .foregroundStyle(Tolu.Palette.text)
                        Text("The same address works on every EVM chain. Check the sender picks a network this wallet lists.")
                            .font(.system(size: 13.5))
                            .foregroundStyle(Tolu.Palette.mute)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .frame(maxWidth: 300)
                    }

                    addressCard
                }
                .padding(.horizontal, Tolu.Spacing.screen)
                .padding(.bottom, 16)
            }

            PrimaryButton(copied ? "Address copied" : "Copy address",
                          systemImage: copied ? "checkmark" : "doc.on.doc") {
                Clipboard.copy(wallet.displayAddress)
                copied = true
            }
            .padding(.horizontal, Tolu.Spacing.screen)

            HStack(spacing: 22) {
                ShareLink(item: wallet.displayAddress) {
                    Text("Share")
                }
                Button("Done") { dismiss() }
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Tolu.Palette.mute)
            .padding(.top, 14)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tolu.Palette.ink)
        .presentationDragIndicator(.visible)
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.4))
            copied = false
        }
    }

    private var addressCard: some View {
        VStack(spacing: 9) {
            DetailRow(label: "wallet", value: wallet.label)
            DetailRow(label: "networks", value: "evm · \(ChainRegistry.all.count) chains")
            Rectangle().fill(Tolu.Palette.line).frame(height: 1)
            Text(wallet.displayAddress)
                .font(.toluMono(11.5))
                .foregroundStyle(Tolu.Palette.text)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .toluCard()
    }
}

#Preview {
    ReceiveSheet(wallet: .preview)
        .preferredColorScheme(.dark)
}
