import SwiftUI
import Testing

@testable import LoonyBear

@MainActor
struct CardReminderStyleTests {
    struct Scenario {
        var isArchived = false
        var startsInFuture = false
        var isOverdue = false
        var needsHistoryReview = false
        var isCompleted = false
        var isSkipped = false
        let expected: CardReminderStyle
    }

    @Test(arguments: [
        Scenario(expected: .scheduled),
        Scenario(isCompleted: true, expected: .completed),
        Scenario(isSkipped: true, expected: .skipped),
        Scenario(needsHistoryReview: true, expected: .historyReview),
        Scenario(isOverdue: true, expected: .overdue),
        Scenario(startsInFuture: true, expected: .neutral),
        Scenario(isArchived: true, expected: .neutral),
        Scenario(isOverdue: true, needsHistoryReview: true, expected: .overdue),
        Scenario(needsHistoryReview: true, isCompleted: true, expected: .historyReview),
        Scenario(needsHistoryReview: true, isSkipped: true, expected: .historyReview),
        Scenario(isOverdue: true, isCompleted: true, expected: .overdue),
        Scenario(isOverdue: true, isSkipped: true, expected: .overdue),
        Scenario(startsInFuture: true, isOverdue: true, needsHistoryReview: true, expected: .neutral),
        Scenario(isArchived: true, isOverdue: true, needsHistoryReview: true, expected: .neutral)
    ])
    func resolvesStateAndPriority(_ scenario: Scenario) {
        let style = CardReminderStyle(
            isArchived: scenario.isArchived,
            startsInFuture: scenario.startsInFuture,
            isOverdue: scenario.isOverdue,
            needsHistoryReview: scenario.needsHistoryReview,
            isCompleted: scenario.isCompleted,
            isSkipped: scenario.isSkipped
        )

        #expect(style == scenario.expected)
    }

    @Test
    func matchesRequestedPalette() {
        #expect(CardReminderStyle.neutral.color == Color.secondary)
        #expect(CardReminderStyle.overdue.color == Color.red)
        #expect(CardReminderStyle.completed.color == Color.green)
        #expect(CardReminderStyle.scheduled.color == Color.blue.opacity(0.75))
        #expect(CardReminderStyle.historyReview.color == Color.orange.opacity(0.75))
        #expect(CardReminderStyle.skipped.color == Color.red.opacity(0.75))
    }
}
