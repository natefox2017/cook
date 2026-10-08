// Developer: gengyun
// Purpose: Applies the user's week-start preference to calendar-based meal planning.

import Foundation

public enum RecipeWeekCalendar {
    /// Preserve the device's own week rules unless the user explicitly chooses
    /// Sunday or Monday. Never mutate Calendar.current.
    public static func configured(
        weekStart: String,
        systemCalendar: Calendar = .current
    ) -> Calendar {
        var calendar = systemCalendar

        switch weekStart {
        case "Sunday":
            calendar.firstWeekday = 1
        case "Monday":
            calendar.firstWeekday = 2
        default:
            break
        }

        return calendar
    }
}
