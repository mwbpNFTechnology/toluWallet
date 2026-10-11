//
//  SeedQuizTests.swift
//  toluWalletTests
//
//  The three-word check that a seed phrase was written down.
//

import Testing
@testable import toluWallet

@MainActor
struct SeedQuizTests {

    private let words = [
        "logic", "flower", "crane", "notable", "sting", "shaft",
        "milk", "vault", "general", "swap", "sauce", "orange"
    ]

    @Test func passesAfterThreeRightAnswers() throws {
        var quiz = try #require(SeedQuiz(words: words))
        var asked: Set<Int> = []

        for question in 0..<SeedQuiz.questionCount {
            asked.insert(quiz.position)
            #expect(quiz.choices.count == SeedQuiz.choiceCount)
            #expect(Set(quiz.choices).count == SeedQuiz.choiceCount)
            #expect(quiz.choices.contains(words[quiz.position]))

            let isLast = question == SeedQuiz.questionCount - 1
            #expect(quiz.answer(words[quiz.position]) == (isLast ? .passed : .next))
        }
        // Three different places in the phrase.
        #expect(asked.count == SeedQuiz.questionCount)
    }

    @Test func reportsAWrongWordWithItsPosition() throws {
        var quiz = try #require(SeedQuiz(words: words))
        let position = quiz.position
        let wrong = try #require(quiz.choices.first { $0 != words[position] })
        #expect(quiz.answer(wrong) == .wrong(position: position))
        // A wrong answer doesn't move on.
        #expect(quiz.position == position)
    }

    /// A phrase may hold one word many times over; the choices still differ
    /// and the right one is still accepted.
    @Test func handlesAPhraseThatRepeatsAWord() throws {
        let repeated = [String](repeating: "abandon", count: 11) + ["about"]
        var quiz = try #require(SeedQuiz(words: repeated))
        #expect(Set(quiz.choices).count == SeedQuiz.choiceCount)
        #expect(quiz.answer(repeated[quiz.position]) == .next)
    }

    @Test func refusesAPhraseTooShortToAskAbout() {
        #expect(SeedQuiz(words: ["logic", "flower"]) == nil)
    }
}
