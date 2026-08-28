//
//  YearBoundaryTimelineSchedule.swift
//  roomscan
//

import Foundation
import SwiftUI

struct YearBoundaryTimelineSchedule: TimelineSchedule {
    var calendar: Calendar = .current

    func entries(from startDate: Date, mode: Mode) -> YearBoundaryEntries {
        YearBoundaryEntries(date: startDate, calendar: calendar)
    }

    static func nextBoundary(after date: Date, calendar: Calendar = .current) -> Date? {
        guard let yearStart = calendar.dateInterval(of: .year, for: date)?.start else {
            return nil
        }
        return calendar.date(byAdding: .year, value: 1, to: yearStart)
    }
}

struct YearBoundaryEntries: Sequence, IteratorProtocol {
    var date: Date
    var calendar: Calendar
    private var isFirst = true

    init(date: Date, calendar: Calendar) {
        self.date = date
        self.calendar = calendar
    }

    mutating func next() -> Date? {
        if isFirst {
            isFirst = false
            return date
        }

        guard let nextBoundary = YearBoundaryTimelineSchedule.nextBoundary(after: date, calendar: calendar) else {
            return nil
        }
        date = nextBoundary
        return date
    }
}

extension TimelineSchedule where Self == YearBoundaryTimelineSchedule {
    static var yearBoundary: YearBoundaryTimelineSchedule {
        YearBoundaryTimelineSchedule()
    }
}
