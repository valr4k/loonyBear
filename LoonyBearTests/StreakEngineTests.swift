import Foundation
import Testing

@testable import LoonyBear

@Suite
struct StreakEngineTests {
    @Test
    func streakUsesScheduleHistoryTimeline() {
        let habitID = UUID()
        let april1 = TestSupport.makeDate(2026, 4, 1)
        let april2 = TestSupport.makeDate(2026, 4, 2)
        let april4 = TestSupport.makeDate(2026, 4, 4)
        let april5 = TestSupport.makeDate(2026, 4, 5)

        let schedules = [
            TestSupport.makeSchedule(habitID: habitID, weekdays: .daily, effectiveFrom: april1, version: 1),
            TestSupport.makeSchedule(habitID: habitID, weekdays: .weekends, effectiveFrom: april5, version: 2),
        ]

        let completions = [
            TestSupport.makeCompletion(habitID: habitID, localDate: april1),
            TestSupport.makeCompletion(habitID: habitID, localDate: april2),
            TestSupport.makeCompletion(habitID: habitID, localDate: april4),
        ]

        #expect(StreakEngine.currentStreak(completions: completions, schedules: schedules, today: april5) == 1)
        #expect(StreakEngine.longestStreak(completions: completions, schedules: schedules) == 2)
    }

    @Test
    func uncompletedScheduledTodayDoesNotResetCurrentStreakYet() {
        let habitID = UUID()
        let april1 = TestSupport.makeDate(2026, 4, 1)
        let april2 = TestSupport.makeDate(2026, 4, 2)
        let april3 = TestSupport.makeDate(2026, 4, 3)

        let schedules = [
            TestSupport.makeSchedule(habitID: habitID, weekdays: .daily, effectiveFrom: april1, version: 1),
        ]
        let completions = [
            TestSupport.makeCompletion(habitID: habitID, localDate: april1),
            TestSupport.makeCompletion(habitID: habitID, localDate: april2),
        ]

        #expect(StreakEngine.currentStreak(completions: completions, schedules: schedules, today: april3) == 2)
    }

    @Test
    func scheduledTodaySkippedResetsCurrentStreakImmediately() {
        let habitID = UUID()
        let april1 = TestSupport.makeDate(2026, 4, 1)
        let april2 = TestSupport.makeDate(2026, 4, 2)
        let april3 = TestSupport.makeDate(2026, 4, 3)

        let schedules = [
            TestSupport.makeSchedule(habitID: habitID, weekdays: .daily, effectiveFrom: april1, version: 1),
        ]
        let completions = [
            TestSupport.makeCompletion(habitID: habitID, localDate: april1),
            TestSupport.makeCompletion(habitID: habitID, localDate: april2),
        ]
        let skipped = [
            TestSupport.makeCompletion(habitID: habitID, localDate: april3, source: .skipped),
        ]

        #expect(StreakEngine.currentStreak(completions: completions, skippedCompletions: skipped, schedules: schedules, today: april3) == 0)
    }

    @Test
    func unscheduledTodaySkippedDoesNotResetCurrentStreak() {
        let habitID = UUID()
        let april2 = TestSupport.makeDate(2026, 4, 2)
        let april3 = TestSupport.makeDate(2026, 4, 3)
        let april4 = TestSupport.makeDate(2026, 4, 4)

        let schedules = [
            TestSupport.makeSchedule(habitID: habitID, weekdays: .weekdays, effectiveFrom: april2, version: 1),
        ]
        let completions = [
            TestSupport.makeCompletion(habitID: habitID, localDate: april2),
            TestSupport.makeCompletion(habitID: habitID, localDate: april3),
        ]
        let skipped = [
            TestSupport.makeCompletion(habitID: habitID, localDate: april4, source: .skipped),
        ]

        #expect(StreakEngine.currentStreak(completions: completions, skippedCompletions: skipped, schedules: schedules, today: april4) == 2)
    }

    @Test
    func changingSkippedTodayToCompletedRestoresStreak() {
        let habitID = UUID()
        let april1 = TestSupport.makeDate(2026, 4, 1)
        let april2 = TestSupport.makeDate(2026, 4, 2)
        let april3 = TestSupport.makeDate(2026, 4, 3)

        let schedules = [
            TestSupport.makeSchedule(habitID: habitID, weekdays: .daily, effectiveFrom: april1, version: 1),
        ]
        let baseline = [
            TestSupport.makeCompletion(habitID: habitID, localDate: april1),
            TestSupport.makeCompletion(habitID: habitID, localDate: april2),
        ]
        let completedToday = baseline + [
            TestSupport.makeCompletion(habitID: habitID, localDate: april3),
        ]

        #expect(StreakEngine.currentStreak(completions: baseline, skippedCompletions: [
            TestSupport.makeCompletion(habitID: habitID, localDate: april3, source: .skipped),
        ], schedules: schedules, today: april3) == 0)
        #expect(StreakEngine.currentStreak(completions: completedToday, schedules: schedules, today: april3) == 3)
    }

    @Test
    func clearingSkippedTodayRestoresUnfinishedTodayBehavior() {
        let habitID = UUID()
        let april1 = TestSupport.makeDate(2026, 4, 1)
        let april2 = TestSupport.makeDate(2026, 4, 2)
        let april3 = TestSupport.makeDate(2026, 4, 3)

        let schedules = [
            TestSupport.makeSchedule(habitID: habitID, weekdays: .daily, effectiveFrom: april1, version: 1),
        ]
        let completions = [
            TestSupport.makeCompletion(habitID: habitID, localDate: april1),
            TestSupport.makeCompletion(habitID: habitID, localDate: april2),
        ]

        #expect(StreakEngine.currentStreak(completions: completions, skippedCompletions: [
            TestSupport.makeCompletion(habitID: habitID, localDate: april3, source: .skipped),
        ], schedules: schedules, today: april3) == 0)
        #expect(StreakEngine.currentStreak(completions: completions, schedules: schedules, today: april3) == 2)
    }

    @Test
    func longestStreakIsUnchangedBySkippedTodayRule() {
        let habitID = UUID()
        let april1 = TestSupport.makeDate(2026, 4, 1)
        let april2 = TestSupport.makeDate(2026, 4, 2)
        let april3 = TestSupport.makeDate(2026, 4, 3)

        let schedules = [
            TestSupport.makeSchedule(habitID: habitID, weekdays: .daily, effectiveFrom: april1, version: 1),
        ]
        let completions = [
            TestSupport.makeCompletion(habitID: habitID, localDate: april1),
            TestSupport.makeCompletion(habitID: habitID, localDate: april2),
        ]
        let skipped = [
            TestSupport.makeCompletion(habitID: habitID, localDate: april3, source: .skipped),
        ]

        #expect(StreakEngine.currentStreak(completions: completions, skippedCompletions: skipped, schedules: schedules, today: april3) == 0)
        #expect(StreakEngine.longestStreak(completions: completions, schedules: schedules) == 2)
    }
}
