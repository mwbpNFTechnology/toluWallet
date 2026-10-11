//
//  SeedQuiz.swift
//  toluWallet
//
//  The check that a seed phrase was really written down: three of its words,
//  asked for by position, each to be picked out of three. The toluCold device
//  asks the same way.
//

import Foundation

struct SeedQuiz {

    enum Outcome: Equatable {
        /// Right; there is another question.
        case next
        /// Right, and that was the last one.
        case passed
        /// Not the word at this (zero-based) position.
        case wrong(position: Int)
    }

    static let questionCount = 3
    static let choiceCount = 3

    private let words: [String]
    private let positions: [Int]
    private(set) var question = 0
    private(set) var choices: [String]

    /// `nil` for a phrase too short to ask about.
    init?(words: [String]) {
        guard words.count >= Self.questionCount else { return nil }
        self.words = words
        positions = Array(words.indices.shuffled().prefix(Self.questionCount))
        choices = Self.choices(around: words[positions[0]])
    }

    /// Zero-based position in the phrase of the word being asked for.
    var position: Int { positions[question] }

    mutating func answer(_ choice: String) -> Outcome {
        guard choice == words[position] else { return .wrong(position: position) }
        guard question + 1 < positions.count else { return .passed }
        question += 1
        choices = Self.choices(around: words[position])
        return .next
    }

    /// The right word and others from the list, in random order.
    private static func choices(around correct: String) -> [String] {
        var picked: Set<String> = [correct]
        while picked.count < choiceCount, let other = Bip39Wordlist.words.randomElement() {
            picked.insert(other)
        }
        return picked.shuffled()
    }
}
