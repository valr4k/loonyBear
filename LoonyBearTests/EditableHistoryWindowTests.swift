import Foundation
import Testing

@testable import LoonyBear

@Suite
struct EditableHistoryWindowTests {
    @Test
    func datesUseThirtyDayWindowWhenStartDateIsEarlier() {
        let today = TestSupport.makeDate(2026, 4, 30)
        let startDate = TestSupport.makeDate(2026, 1, 1)

        let dates = EditableHistoryWindow.dates(startDate: startDate, today: today)

        #expect(dates.count == 30)
        #expect(dates.contains(TestSupport.makeDate(2026, 4, 30)))
        #expect(dates.contains(TestSupport.makeDate(2026, 4, 1)))
        #expect(!dates.contains(TestSupport.makeDate(2026, 3, 31)))
    }

    @Test
    func datesRespectRecentStartDate() {
        let today = TestSupport.makeDate(2026, 4, 30)
        let startDate = TestSupport.makeDate(2026, 4, 27)

        let dates = EditableHistoryWindow.dates(startDate: startDate, today: today)

        #expect(dates == Set([
            TestSupport.makeDate(2026, 4, 27),
            TestSupport.makeDate(2026, 4, 28),
            TestSupport.makeDate(2026, 4, 29),
            TestSupport.makeDate(2026, 4, 30),
        ]))
    }

    @Test
    func stateMachineKeepsThreeStateCycleForToday() {
        let today = TestSupport.makeDate(2026, 4, 30)

        #expect(
            EditableHistoryStateMachine.nextSelection(current: .none, for: today, today: today) == .positive
        )
        #expect(
            EditableHistoryStateMachine.nextSelection(current: .positive, for: today, today: today) == .skipped
        )
        #expect(
            EditableHistoryStateMachine.nextSelection(current: .skipped, for: today, today: today) == .none
        )
    }

    @Test
    func stateMachineDoesNotReturnPastDayToNone() {
        let today = TestSupport.makeDate(2026, 4, 30)
        let yesterday = TestSupport.makeDate(2026, 4, 29)

        #expect(
            EditableHistoryStateMachine.nextSelection(current: .positive, for: yesterday, today: today) == .skipped
        )
        #expect(
            EditableHistoryStateMachine.nextSelection(current: .skipped, for: yesterday, today: today) == .positive
        )
        #expect(
            EditableHistoryStateMachine.nextSelection(current: .none, for: yesterday, today: today) == .skipped
        )
    }

    @Test
    func normalizationAutoFinalizesPastEditableNoneAsSkippedByDefault() {
        let today = TestSupport.makeDate(2026, 4, 30)
        let yesterday = TestSupport.makeDate(2026, 4, 29)
        let requiredFinalizedDays: Set<Date> = [yesterday]

        let normalized = EditableHistoryContract.normalizedSelection(
            positiveDays: [],
            skippedDays: [],
            requiredFinalizedDays: requiredFinalizedDays,
            today: today
        )

        #expect(normalized.positiveDays.isEmpty)
        #expect(normalized.skippedDays == Set([yesterday]))
    }

    @Test
    func normalizationCanAutoFinalizePastEditableNoneAsCompleted() {
        let today = TestSupport.makeDate(2026, 4, 30)
        let yesterday = TestSupport.makeDate(2026, 4, 29)
        let requiredFinalizedDays: Set<Date> = [yesterday]

        let normalized = EditableHistoryContract.normalizedSelection(
            positiveDays: [],
            skippedDays: [],
            requiredFinalizedDays: requiredFinalizedDays,
            pastDefaultSelection: .positive,
            today: today
        )

        #expect(normalized.positiveDays == Set([yesterday]))
        #expect(normalized.skippedDays.isEmpty)
    }
}
