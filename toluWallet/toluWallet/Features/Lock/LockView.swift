//
//  LockView.swift
//  toluWallet
//
//  The gate in front of everything: wallets are only read from the Keychain
//  once Face ID (or the passcode) succeeds.
//

import LocalAuthentication
import SwiftUI

struct LockView: View {
    @Environment(WalletStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    @State private var isUnlocking = false
    @State private var didAutoPrompt = false
    @State private var errorText: String?

    var body: some View {
        ZStack {
            ToluBackground()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    ToluWordmark()
                    Spacer()
                    MonoLabel("◉ locked", size: 10, color: Tolu.Palette.amber, tracking: 2)
                }

                Spacer(minLength: 24)

                lockMark
                    .frame(maxWidth: .infinity)

                Spacer(minLength: 28)

                VStack(alignment: .leading, spacing: 14) {
                    MonoLabel("secp256k1 · keys stay on your tolu tag", color: Tolu.Palette.violet, tracking: 1.8)
                    ToluHeading(text: "unlock your\nwallets")
                    Text("your wallets, their tag slots and passwords are stored in the keychain behind \(store.unlockMethodName).")
                        .font(.system(size: 13))
                        .foregroundStyle(Tolu.Palette.mute)
                        .lineSpacing(2)
                        .frame(maxWidth: 320, alignment: .leading)
                }

                if let errorText {
                    Text(errorText)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Tolu.Palette.coral)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)
                }

                PrimaryButton("Unlock with \(store.unlockMethodName)", systemImage: store.unlockSymbolName,
                              isEnabled: !isUnlocking, isLoading: isUnlocking) {
                    Task { await unlock() }
                }
                .padding(.top, 22)

                MonoLabel("developed by mwbp.io - connecting blockchain to the world",
                          size: 9, color: Tolu.Palette.dim, tracking: 1.2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 22)
            }
            .padding(.horizontal, Tolu.Spacing.screen)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        // Prompt once on arrival, but only when the app is actually in front.
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active, !didAutoPrompt else { return }
            didAutoPrompt = true
            Task { await unlock() }
        }
    }

    private var lockMark: some View {
        ZStack {
            Circle()
                .stroke(Tolu.Palette.line2, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .frame(width: 186, height: 186)
            Circle()
                .fill(Tolu.Palette.lime.opacity(0.07))
                .overlay(Circle().stroke(Tolu.Palette.lime, lineWidth: 1))
                .frame(width: 104, height: 104)
            Image(systemName: "lock.fill")
                .font(.system(size: 38))
                .foregroundStyle(Tolu.Palette.lime)
        }
        .accessibilityHidden(true)
    }

    private func unlock() async {
        guard !isUnlocking else { return }
        isUnlocking = true
        errorText = nil
        defer { isUnlocking = false }
        do {
            try await store.unlock()
        } catch let error as LAError where Self.isCancellation(error) {
            // Dismissing the prompt isn't an error worth showing.
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private static func isCancellation(_ error: LAError) -> Bool {
        [.userCancel, .appCancel, .systemCancel].contains(error.code)
    }
}

#Preview {
    LockView()
        .environment(WalletStore())
        .preferredColorScheme(.dark)
}
