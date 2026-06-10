import Foundation
import Testing

@testable import LoonyBear

struct EventModelTests {
    private let calendar = Calendar(identifier: .gregorian)

    @Test
    func countdownDateCanBeTodayOrFuture() {
        let today = TestSupport.makeDate(2026, 5, 8, calendar: calendar)
        let yesterday = TestSupport.makeDate(2026, 5, 7, calendar: calendar)
        let tomorrow = TestSupport.makeDate(2026, 5, 9, calendar: calendar)

        #expect(!EventValidation.isDateValid(mode: .countdown, date: yesterday, today: today, calendar: calendar))
        #expect(EventValidation.isDateValid(mode: .countdown, date: today, today: today, calendar: calendar))
        #expect(EventValidation.isDateValid(mode: .countdown, date: tomorrow, today: today, calendar: calendar))
        #expect(EventValidation.validationMessage(mode: .countdown, date: yesterday, today: today, calendar: calendar) == "Countdown date must be in the future.")
    }

    @Test
    func countUpDateCanBeTodayOrPast() {
        let today = TestSupport.makeDate(2026, 5, 8, calendar: calendar)
        let yesterday = TestSupport.makeDate(2026, 5, 7, calendar: calendar)
        let tomorrow = TestSupport.makeDate(2026, 5, 9, calendar: calendar)

        #expect(EventValidation.isDateValid(mode: .countUp, date: yesterday, today: today, calendar: calendar))
        #expect(EventValidation.isDateValid(mode: .countUp, date: today, today: today, calendar: calendar))
        #expect(!EventValidation.isDateValid(mode: .countUp, date: tomorrow, today: today, calendar: calendar))
        #expect(EventValidation.validationMessage(mode: .countUp, date: tomorrow, today: today, calendar: calendar) == "Count Up date must be in the past.")
    }

    @Test
    func countdownDurationStopsAtZero() {
        let today = TestSupport.makeDate(2026, 5, 8, calendar: calendar)
        let event = EventCardProjection(
            id: UUID(),
            name: "Launch",
            mode: .countdown,
            date: TestSupport.makeDate(2026, 5, 10, calendar: calendar),
            sortOrder: 0
        )
        let pastEvent = EventCardProjection(
            id: UUID(),
            name: "Past",
            mode: .countdown,
            date: TestSupport.makeDate(2026, 5, 7, calendar: calendar),
            sortOrder: 1
        )

        #expect(EventDurationFormatter.text(for: event, now: today, calendar: calendar) == "2d")
        #expect(EventDurationFormatter.text(for: pastEvent, now: today, calendar: calendar) == "0d")
        #expect(EventDurationFormatter.isCountdownComplete(pastEvent, now: today, calendar: calendar))
    }

    @Test
    func countUpDurationShowsElapsedCalendarTime() {
        let today = TestSupport.makeDate(2026, 5, 8, calendar: calendar)
        let todayEvent = EventCardProjection(
            id: UUID(),
            name: "Started Today",
            mode: .countUp,
            date: today,
            sortOrder: 0
        )
        let yesterdayEvent = EventCardProjection(
            id: UUID(),
            name: "Started Yesterday",
            mode: .countUp,
            date: TestSupport.makeDate(2026, 5, 7, calendar: calendar),
            sortOrder: 1
        )
        let birthdayEvent = EventCardProjection(
            id: UUID(),
            name: "Birthday",
            mode: .countUp,
            date: TestSupport.makeDate(1988, 7, 5, calendar: calendar),
            sortOrder: 2
        )
        let birthdayNow = TestSupport.makeDate(2026, 6, 8, calendar: calendar)

        #expect(EventDurationFormatter.text(for: todayEvent, now: today, calendar: calendar) == "0d")
        #expect(EventDurationFormatter.text(for: yesterdayEvent, now: today, calendar: calendar) == "1d")
        #expect(EventDurationFormatter.text(for: birthdayEvent, now: birthdayNow, calendar: calendar) == "37yr 11mo 3d")
    }
}
