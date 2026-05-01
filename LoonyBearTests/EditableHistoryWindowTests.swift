import Foundation
import Testing

@testable import LoonyBear

@MainActor
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
    func stateMachineStartsPastDayGapsWithPositiveState() {
        let today = TestSupport.makeDate(2026, 4, 30)
        let yesterday = TestSupport.makeDate(2026, 4, 29)

        #expect(
            EditableHistoryStateMachine.nextSelection(current: .positive, for: yesterday, today: today) == .skipped
        )
        #expect(
            EditableHistoryStateMachine.nextSelection(current: .skipped, for: yesterday, today: today) == .positive
        )
        #expect(
            EditableHistoryStateMachine.nextSelection(current: .none, for: yesterday, today: today) == .positive
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

    @Test
    func normalizationCanLeavePastEditableNoneUnfinalized() {
        let today = TestSupport.makeDate(2026, 4, 30)
        let yesterday = TestSupport.makeDate(2026, 4, 29)
        let requiredFinalizedDays: Set<Date> = [yesterday]

        let normalized = EditableHistoryContract.normalizedSelection(
            positiveDays: [],
            skippedDays: [],
            requiredFinalizedDays: requiredFinalizedDays,
            pastDefaultSelection: .none,
            today: today
        )

        #expect(normalized.positiveDays.isEmpty)
        #expect(normalized.skippedDays.isEmpty)
    }

    @Test
    func monthWindowBuildsSortedMonthListFromDates() {
        let dates: Set<Date> = [
            TestSupport.makeDate(2026, 4, 30),
            TestSupport.makeDate(2026, 4, 1),
            TestSupport.makeDate(2026, 3, 29),
        ]

        let months = HistoryMonthWindow.months(containing: dates)

        #expect(months == [
            TestSupport.makeDate(2026, 3, 1),
            TestSupport.makeDate(2026, 4, 1),
        ])
    }

    @Test
    func monthWindowBuildsInclusiveMonthRangeFromStartDate() {
        let startDate = TestSupport.makeDate(2026, 2, 14)
        let endDate = TestSupport.makeDate(2026, 4, 30)

        let months = HistoryMonthWindow.months(from: startDate, through: endDate)

        #expect(months == [
            TestSupport.makeDate(2026, 2, 1),
            TestSupport.makeDate(2026, 3, 1),
            TestSupport.makeDate(2026, 4, 1),
        ])
    }

    @Test
    func startDateSelectionWindowReturnsClosedRangeEndingToday() {
        let today = TestSupport.makeDate(2026, 4, 30)
        let calendar = Calendar.current

        let range = StartDateSelectionWindow.range(
            offset: DateComponents(day: -29),
            today: today,
            calendar: calendar
        )

        #expect(range.lowerBound == TestSupport.makeDate(2026, 4, 1))
        #expect(range.upperBound == today)
    }
}
