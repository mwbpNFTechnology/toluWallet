//
//  ColdWalletView.swift
//  toluWallet
//
//  Create a wallet with a toluCold device: enter the details, hand them to
//  the device, then scan its QR and check the card. Once the details have
//  been sent it can be cancelled at any step — on the device too, with one
//  more tap, or on this phone alone.
//

import SwiftUI

struct ColdWalletView: View {
    @Environment(Router.self) private var router
    @State private var model: ColdWalletViewModel
    @State private var confirmCancel = false

    private let accent = Tolu.Palette.violet

    init(store: WalletStore) {
        _model = State(initialValue: ColdWalletViewModel(store: store))
    }

    var body: some View {
        @Bindable var model = model

        ZStack {
            ToluBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: model.stage == .setup ? "cold wallet · setup" : "cold wallet", accent: accent) {
                    if model.canEditSetup {
                        model.backToSetup()
                    } else {
                        // A setup that was sent stays saved; it can be picked
                        // up again from the wallet list.
                        router.pop()
                    }
                }
                ScrollView {
                    Group {
                        switch model.stage {
                        case .setup: ColdWalletSetupSection(model: model)
                        case .device: ColdWalletDeviceSection(model: model)
                        }
                    }
                    .padding(.horizontal, Tolu.Spacing.screen)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
                }
                .scrollDismissesKeyboard(.interactively)
                bottomBar
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { dismissKeyboard() }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $model.showScanner) {
            QRScannerView(title: "wallet address", hint: "point at the QR code on the toluCold screen") { code in
                model.handleScanned(code)
            }
        }
        .confirmationDialog("Cancel this cold wallet?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Cancel on the device too") {
                Task {
                    if await model.cancelOnDevice() { router.pop() }
                }
            }
            Button("Cancel on this phone only", role: .destructive) {
                model.discard()
                router.pop()
            }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Tap the phone on the device and it erases the seed phrase and goes back to its start screen. If the key is already on the card, the card keeps it — you can add it later with “Already on the tag”.")
        }
    }

    private func cancel() {
        if model.hasSentSetup {
            confirmCancel = true
        } else {
            // Nothing was sent yet, so there is only this screen to leave.
            router.pop()
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        VStack(spacing: 10) {
            switch model.stage {
            case .setup:
                PrimaryButton("Continue", systemImage: "arrow.right", accent: accent, isEnabled: model.canContinue) {
                    dismissKeyboard()
                    model.continueToDevice()
                }
            case .device:
                if model.isComplete {
                    PrimaryButton("Done", systemImage: "checkmark") { router.pop() }
                } else {
                    PrimaryButton(model.actionTitle, systemImage: model.actionSymbol, accent: accent,
                                  isEnabled: !model.running && (model.step == .scan || model.isNfcAvailable),
                                  isLoading: model.running) {
                        model.runAction()
                    }
                    if !model.running {
                        HStack(spacing: 26) {
                            if model.step != .send {
                                Button("Send again") { model.sendAgain() }
                                    .foregroundStyle(Tolu.Palette.mute)
                            }
                            Button("Cancel", action: cancel)
                                .foregroundStyle(Tolu.Palette.coral)
                        }
                        .font(.system(size: 14, weight: .medium))
                        .frame(minHeight: 44)
                    }
                }
            }
        }
        .padding(.horizontal, Tolu.Spacing.screen)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
}

#Preview {
    NavigationStack {
        ColdWalletView(store: WalletStore())
            .environment(Router())
    }
    .preferredColorScheme(.dark)
}
