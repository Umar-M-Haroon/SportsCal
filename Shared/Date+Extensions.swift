//
//  Date+Extensions.swift
//  Date+Extensions
//
//  Created by Umar Haroon on 7/22/21.
//

import Foundation
extension DateComponents {
    func formatted(format: Int = 4, isRelative: Bool) -> String {
        guard let date = self.date,
        let formatStyle = DateFormatter.Style(rawValue: UInt(format))
        else { return "" }
        let dateFormatter = DateFormatters.dateFormatter
        dateFormatter.dateStyle = formatStyle
        dateFormatter.timeStyle = .none
        dateFormatter.doesRelativeDateFormatting = isRelative
        return dateFormatter.string(from: date)
    }
}
extension Date{
    static func dateAfterWeeksFromNow(weeks: Int) -> Date{
        return Calendar(identifier: .gregorian).date(byAdding: .day, value: 7*weeks, to: Date())!
    }
    static func dateAfterYearsFromNow(years: Int) -> Date{
        return Calendar(identifier: .gregorian).date(byAdding: .year, value: years, to: Date())!
    }
    static func dateAfterMonthsFromNow(months: Int) -> Date{
        return Calendar(identifier: .gregorian).date(byAdding: .month, value: months, to: Date())!
    }
    static func dateAfterHoursFromNow(hours: Int) -> Date{
        return Calendar(identifier: .gregorian).date(byAdding: .hour, value: hours, to: Date())!
    }
    static func dateAfterDaysFromNow(days: Int) -> Date{
        return Calendar(identifier: .gregorian).date(byAdding: .day, value: days, to: Date())!
    }
    func afterHoursFromNow(hours: Int) -> Date {
        return Calendar(identifier: .gregorian).date(byAdding: .hour, value: hours, to: self)!
    }
    func afterSecondsFromNow(seconds: Int) -> Date {
        return Calendar(identifier: .gregorian).date(byAdding: .second, value: seconds, to: self)!
    }

    func toGMT() -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        formatter.timeZone = TimeZone(abbreviation: "GMT")
        return formatter.date(from: formatter.string(from: Date()))!
    }
    func formatToTime() -> String {
        DateFormatters.dateFormatter.dateStyle = .none
        DateFormatters.dateFormatter.timeStyle = .short
        return DateFormatters.dateFormatter.string(from: self)
    }
    
    func formatToDate(dateFormat: String) -> String? {
        DateFormatters.dateFormatter.dateFormat = dateFormat
        return DateFormatters.dateFormatter.string(from: self)
    }
    
    static func sampleDate(hoursInFuture hours: Int) -> String {
        let calendar = Calendar.current
        let date = calendar.date(byAdding: .hour, value: hours, to: Date(), wrappingComponents: true)!
        return DateFormatters.isoFormatter.string(from: date)
    }
    
    static func sampleDate(daysInFuture days: Int) -> String {
        let calendar = Calendar.current
        let date = calendar.date(byAdding: .day, value: days, to: Date(), wrappingComponents: true)!
        return DateFormatters.isoFormatter.string(from: date)
    }
}
