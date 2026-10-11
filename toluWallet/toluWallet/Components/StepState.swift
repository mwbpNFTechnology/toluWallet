//
//  StepState.swift
//  toluWallet
//

import Foundation

/// Where one row of a multi-step flow stands.
enum StepState {
    case pending
    case active
    case done
    case error
}
