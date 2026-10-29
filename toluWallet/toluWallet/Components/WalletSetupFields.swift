//
//  WalletSetupFields.swift
//  toluWallet
//
//  The three things every way of making a wallet asks for: a label, the
//  slot for the key, and the slot for this iPhone's key that unlocks it.
//

import SwiftUI

struct WalletSetupFields: View {
    @Binding var label: String
    @Binding var keyObjectID: String
    @Binding var phoneKeyObjectID: String
    /// True when the two slots hold the same id.
    let slotsCollide: Bool
    /// True once the slots are in use on the tag: only the label can change.
    var slotsLocked = false
    var accent: Color = Tolu.Palette.lime

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            field(hint: "a name so you recognise this wallet later.") {
                ToluTextField(label: "label", text: $label, placeholder: "e.g. daily wallet", mono: false)
            }

            Group {
                field(hint: "the slot on the tag where the secp256k1 key is stored.") {
                    HexBlockField(label: "key object id", text: $keyObjectID, accent: accent)
                }

                VStack(alignment: .leading, spacing: 11) {
                    HexBlockField(label: "phone key object id", text: $phoneKeyObjectID, accent: accent)
                    SetupHint("the slot on the tag for this iphone's public key. the wallet key only works in a session this iphone opens, after face id — nothing secret ever crosses nfc. several wallets can share it.")
                    if slotsCollide {
                        Text("the phone key slot must differ from the key slot.")
                            .toluFont(12)
                            .foregroundStyle(Tolu.Palette.coral)
                    }
                }
            }
            .disabled(slotsLocked)
            .opacity(slotsLocked ? 0.5 : 1)
        }
    }

    private func field(hint: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
            SetupHint(hint)
        }
    }
}

#Preview {
    ScrollView {
        WalletSetupFields(label: .constant("daily wallet"), keyObjectID: .constant("00000001"),
                          phoneKeyObjectID: .constant("00000002"), slotsCollide: false)
            .padding()
    }
    .background(Tolu.Palette.ink)
}
