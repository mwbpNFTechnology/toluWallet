//
//  WalletSetupFields.swift
//  toluWallet
//
//  The four things every way of making a wallet asks for: a label, the slot
//  for the key, the password, and the slot for the password.
//

import SwiftUI

struct WalletSetupFields: View {
    @Binding var label: String
    @Binding var keyObjectID: String
    @Binding var password: String
    @Binding var passwordObjectID: String
    /// True when the two slots hold the same id.
    let slotsCollide: Bool
    var accent: Color = Tolu.Palette.lime

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            field(hint: "a name so you recognise this wallet later.") {
                ToluTextField(label: "label", text: $label, placeholder: "e.g. daily wallet", mono: false)
            }

            field(hint: "the slot on the tag where the secp256k1 key is stored.") {
                HexBlockField(label: "key object id", text: $keyObjectID, accent: accent)
            }

            field(hint: "the tag asks for this before every signature. it is saved on this phone behind face id. \(WalletRecord.defaultPasswordAttemptLimit) wrong tries lock the key for good.") {
                PasswordField(label: "password", text: $password, accent: accent)
            }

            VStack(alignment: .leading, spacing: 11) {
                HexBlockField(label: "password object id", text: $passwordObjectID, accent: accent)
                SetupHint("the slot on the tag that holds the password guarding the key.")
                if slotsCollide {
                    Text("the password slot must differ from the key slot.")
                        .font(.system(size: 12))
                        .foregroundStyle(Tolu.Palette.coral)
                }
            }
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
                          password: .constant("hunter2"), passwordObjectID: .constant("00000002"),
                          slotsCollide: false)
            .padding()
    }
    .background(Tolu.Palette.ink)
}
