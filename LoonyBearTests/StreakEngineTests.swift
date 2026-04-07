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
}
