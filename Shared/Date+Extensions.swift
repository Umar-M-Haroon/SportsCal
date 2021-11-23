//
//  Date+Extensions.swift
//  Date+Extensions
//
//  Created by Umar Haroon on 7/22/21.
//

import Foundation
extension DateComponents {
    func formatted(format: String = "E, dd.MM.yy") -> String {
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
}
