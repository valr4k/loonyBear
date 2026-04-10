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
}
