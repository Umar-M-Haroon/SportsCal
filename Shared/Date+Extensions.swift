//
//  Date+Extensions.swift
//  Date+Extensions
//
//  Created by Umar Haroon on 7/22/21.
//

import Foundation
extension DateComponents {
    func formatted(format: String = "MM/dd/yyyy") -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = format
        guard let date = self.date else { return "" }
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
    func toDetailedString() -> String{
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour], from: Date(), to: self)
        var returnedString = ""
        guard let hours = components.hour else {return ""}
        if let months = components.month{
            if months != 0{
                if months > 1{
                    returnedString += "\(months) months, "
                }else{
                    returnedString += "\(months) month, "
                }
            }
        }
        if var days = components.day{
            if hours == 23{
                days += 1
            }
            if days != 0{
                if days > 1{
                    returnedString += "\(days) days"
                }else{
                    returnedString += "\(days) day"
                }
            }
        }
        return returnedString
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

    static func isoStringToDateString(dateString: String) -> String {
        let cal = Calendar.current
        let df = DateFormatters.dateFormatter
        guard let date = DateFormatters.isoFormatter.date(from: dateString) else { return "" }
        if cal.isDateInToday(date) {
            df.dateFormat = "h:mm a"
            return df.string(from: date)
        }
        df.dateFormat = "MM/dd"
        return df.string(from: date)
    }
    
    static func currentDateToDayString() -> String {
        let df = DateFormatter()
        df.dateFormat = "EEE"
        return df.string(from: Date())
    }
    
    static func currentDateToNumberString() -> String {
        let df = DateFormatter()
        df.dateFormat = "d MMM"
        return df.string(from: Date())
    }
    
    static func dateToString(formatString: String = "MM/dd", date: Date) -> String {
        
        let df = DateFormatter()
        df.dateFormat = formatString
        return df.string(from: date)
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
