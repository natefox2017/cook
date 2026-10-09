// Developer: gengyun
// Purpose: Verifies meal-plan week boundaries for system, Sunday, and Monday preferences.

import Foundation
import Testing

@testable import RecipeCore

@Test func weekStartPreferenceChangesSevenDayIntervalAcrossNewYear() throws {
    var systemCalendar = Calendar(identifier: .gregorian)
    systemCalendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    systemCalendar.firstWeekday = 3  // Tuesday, to detect System Default fallback.
    systemCalendar.minimumDaysInFirstWeek = 1

    let selectedDate = try #require(
        systemCalendar.date(
            from: DateComponents(year: 2026, month: 1, day: 1, hour: 12)
        )
    )

    let cases: [(String, Int, DateComponents)] = [
        ("System Default", 3, DateComponents(year: 2025, month: 12, day: 30)),
        ("Sunday", 1, DateComponents(year: 2025, month: 12, day: 28)),
        ("Monday", 2, DateComponents(year: 2025, month: 12, day: 29)),
    ]

    for (preference, expectedWeekday, expectedStart) in cases {
        let calendar = RecipeWeekCalendar.configured(
            weekStart: preference,
            systemCalendar: systemCalendar
        )

        #expect(calendar.firstWeekday == expectedWeekday)

        let interval = try #require(
            calendar.dateInterval(of: .weekOfYear, for: selectedDate)
        )
        let startDate = calendar.dateComponents(
            [.year, .month, .day],
            from: interval.start
        )
        #expect(startDate == expectedStart)

        let dates = (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: interval.start)
        }
        #expect(dates.count == 7)
        #expect(dates.contains { calendar.isDate($0, inSameDayAs: selectedDate) })
        #expect(interval.end == calendar.date(byAdding: .day, value: 7, to: interval.start))
    }
}
