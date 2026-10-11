//
//  CreateWalletView.swift
//  toluWallet
//
//  Create a wallet: name it, pick the tag slots and a password, then tap the
//  tag. Laid out like toluTag's create-key screen. A wallet made from a seed
//  phrase shows its words, and checks them, between the taps.
//

import SwiftUI

struct CreateWalletView: View {
    @Environment(Router.self) private var router
    @State private var model: CreateWalletViewModel

    private let accent = Tolu.Palette.lime

    init(store: WalletStore) {
        _model = State(initialValue: CreateWalletViewModel(store: store))
    }

    var body: some View {
        ZStack {
            ToluBackground()
            VStack(spacing: 0) {
                ScreenHeader(title: title, onBack: goBack)
                ScrollView {
                    Group {
                        switch model.stage {
                        case .setup: CreateWalletSetupSection(model: model)
                        case .run: CreateWalletRunSection(model: model)
                        case .words: SeedWordsSection(model: model)
                        case .quiz: SeedQuizSection(model: model)
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
        // Copying twelve words onto paper outlasts the auto-lock.
        .keepsScreenAwake(model.stage == .words || model.stage == .quiz)
        // A seed phrase doesn't get to sit in memory indefinitely.
        .task(id: model.holdsSeedPhrase) {
            guard model.holdsSeedPhrase else { return }
            try? await Task.sleep(for: CreateWalletViewModel.seedPhraseLifetime)
            // Never in the middle of a tap: let it finish, then decide.
            while model.running, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled else { return }
            model.seedPhraseExpired()
        }
    }

    private var title: String {
        switch model.stage {
        case .setup: "new wallet · setup"
        case .run: "new wallet"
        case .words: "new wallet · seed phrase"
        case .quiz: "new wallet · check"
        }
    }

    private func goBack() {
        switch model.stage {
        case .setup:
            router.pop()
        case .run:
            if model.isComplete { router.pop() } else { model.backToSetup() }
        case .words:
            model.backToSetup()
        case .quiz:
            model.backToWords()
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        Group {
            switch model.stage {
            case .setup:
                PrimaryButton("Continue", systemImage: "arrow.right", isEnabled: model.canContinue) {
                    dismissKeyboard()
                    model.goToRun()
                }
            case .run:
                if model.isComplete {
                    PrimaryButton("Done", systemImage: "checkmark") { router.pop() }
                } else {
                    PrimaryButton(model.actionTitle, systemImage: "wave.3.forward",
                                  isEnabled: model.isNfcAvailable && !model.running,
                                  isLoading: model.running) {
                        model.runCurrentStep()
                    }
                }
            case .words:
                PrimaryButton("I wrote them down", systemImage: "checkmark") {
                    model.startQuiz()
                }
            case .quiz:
                // The answers are the buttons.
                EmptyView()
            }
        }
        .padding(.horizontal, Tolu.Spacing.screen)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
}

#Preview {
    NavigationStack {
        CreateWalletView(store: WalletStore())
            .environment(Router())
    }
    .preferredColorScheme(.dark)
    .tint(Tolu.Palette.lime)
}
