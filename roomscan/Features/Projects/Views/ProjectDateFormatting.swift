//
//  ProjectDateFormatting.swift
//  roomscan
//

import Foundation

enum ProjectDateFormatting {
    static func relativeText(
        _ date: Date,
        now: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        var displayCalendar = calendar
        displayCalendar.timeZone = timeZone

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = displayCalendar
        formatter.timeZone = timeZone
        formatter.dateFormat = displayCalendar.isDate(date, equalTo: now, toGranularity: .year)
            ? "MMM d"
            : "MMM d, yyyy"
        return formatter.string(from: date)
    }
}
