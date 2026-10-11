//
//  PasswordField.swift
//  toluWallet
//
//  The wallet password input: hidden by default with an eye toggle. Limited to
//  what the tag's password object can hold — 4 to 16 single-byte characters.
//

import SwiftUI

struct PasswordField: View {
    let label: String
    @Binding var text: String
    var accent: Color = Tolu.Palette.lime

    static let minLength = 4
    static let maxLength = 16

    @State private var isVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                MonoLabel(label, tracking: 1.6)
                MonoLabel("\(Self.minLength)–\(Self.maxLength) characters", size: 8, color: Tolu.Palette.dim, tracking: 1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .toluCard(radius: 5, fill: Tolu.Palette.ink3, stroke: Tolu.Palette.line2)
                Spacer(minLength: 0)
                MonoLabel("\(text.count)/\(Self.maxLength)", size: 8.5, color: Tolu.Palette.dim, tracking: 1)
            }

            HStack(spacing: 10) {
                Group {
                    if isVisible {
                        TextField("password", text: $text)
                    } else {
                        SecureField("password", text: $text)
                    }
                }
                .font(.toluMono(15))
                .foregroundStyle(Tolu.Palette.text)
                .tint(accent)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)

                Button(isVisible ? "Hide password" : "Show password",
                       systemImage: isVisible ? "eye.slash" : "eye") {
                    isVisible.toggle()
                }
                .labelStyle(.iconOnly)
                .font(.system(size: 15))
                .foregroundStyle(Tolu.Palette.mute)
                .buttonStyle(.plain)
            }
            .padding(14)
            .toluCard(fill: Tolu.Palette.ink3)
        }
        .onChange(of: text) { _, value in
            let filtered = String(value.filter { $0.isASCII && !$0.isWhitespace && !$0.isNewline }.prefix(Self.maxLength))
            if filtered != value { text = filtered }
        }
    }
}

#Preview {
    PasswordField(label: "password", text: .constant("hunter2"))
        .padding()
        .background(Tolu.Palette.ink)
}
