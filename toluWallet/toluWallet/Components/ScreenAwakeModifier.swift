//
//  ScreenAwakeModifier.swift
//  toluWallet
//
//  Keeps the display from dimming and locking while something has to be read
//  slowly — a seed phrase being copied onto paper. SwiftUI has no way to ask
//  for this, so it goes through the application's idle timer.
//

import SwiftUI

struct ScreenAwakeModifier: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: isActive, initial: true) { _, isActive in
                UIApplication.shared.isIdleTimerDisabled = isActive
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
            }
    }
}

extension View {
    func keepsScreenAwake(_ isActive: Bool) -> some View {
        modifier(ScreenAwakeModifier(isActive: isActive))
    }
}
