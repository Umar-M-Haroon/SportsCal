//
//  SettingsData.swift
//  SettingsData
//
//  Created by Umar Haroon on 8/15/21.
//

import Foundation
import SwiftUI

enum Durations: String {
    case oneWeek = "1 Week"
    case twoWeeks = "2 Weeks"
    case threeWeeks = "3 Weeks"
    case oneMonth = "1 Month"
    case twoMonths = "2 Months"
    case sixMonths = "6 Months"
    case oneYear = "1 Year"
}

class SettingsObject: ObservableObject {
    @Published var hidePastEvents: Bool = false
    @Published var dateFormatString: String = "E, dd.MM.yy"
    @Published var durations: Durations = .oneWeek
    @Published var dateFormats: [DateFormatStrings] = [
        .longest,
        .long,
        .slashesMDY,
        .shortMonth,
        .dotsDMY,
        .dotsShortDay,
        .slashesDMY,
        .dashesDMY,
        .slashesLongYearDMY,
        .dashesLongYearDMY
    ]
    @Published var dateFormatsStrings: [String] = [
        DateFormatStrings.longest.toExample(),
        DateFormatStrings.long.toExample(),
        DateFormatStrings.slashesMDY.toExample(),
        DateFormatStrings.shortMonth.toExample(),
        DateFormatStrings.dotsDMY.toExample(),
        DateFormatStrings.dotsShortDay.toExample(),
        DateFormatStrings.slashesDMY.toExample(),
        DateFormatStrings.dashesDMY.toExample(),
        DateFormatStrings.slashesLongYearDMY.toExample(),
        DateFormatStrings.dashesLongYearDMY.toExample()
    ]
    @State var selectedFormat: DateFormatStrings = .dotsDMY
    
}
enum DateFormatStrings: String, Hashable {
    case longest = "EEEE, MMMM d, yyyy"
    case long = "EEEE, MMM d, yyyy"
    case slashesMDY = "MM/dd/yyyy"
    case shortMonth = "MMM d, yyyy"
    case dotsDMY = "dd.MM.yy"
    case dotsShortDay = "E, dd.MM.yy"
    case slashesDMY = "dd/MM/yy"
    case dashesDMY = "dd-MM-yy"
    case slashesLongYearDMY = "dd/MM/yyyy"
    case dashesLongYearDMY = "dd-MM-yyyy"
    init?(dateString: String) {
        switch dateString {
        case "Monday, August 14, 2021":
            self.init(.longest)
        case "Monday, Aug 14, 2021":
            self.init(.long)
        case "08/14/2021":
            self.init(.slashesMDY)
        case "Aug 14, 2021":
            self.init(.shortMonth)
        case "14.08.21":
            self.init(.dotsDMY)
        case "Mon, 14.08.21":
            self.init(.dotsShortDay)
        case "14/08/21":
            self.init(.slashesDMY)
        case "14-08-21":
            self.init(.dashesDMY)
        case "14/08/2021":
            self.init(.slashesLongYearDMY)
        case "14-08-2021":
            self.init(.dashesLongYearDMY)
        default:
            self.init(.dotsShortDay)
        }
    }
    init(_ date: DateFormatStrings) {
        self = date
    }
    func toExample() -> String {
        switch self {
        case .longest:
            return "Monday, August 14, 2021"
        case .long:
            return "Monday, Aug 14, 2021"
        case .slashesMDY:
            return "08/14/2021"
        case .shortMonth:
            return "Aug 14, 2021"
        case .dotsDMY:
            return "14.08.21"
        case .dotsShortDay:
            return "Mon, 14.08.21"
        case .slashesDMY:
            return "14/08/21"
        case .dashesDMY:
            return "14-08-21"
        case .slashesLongYearDMY:
            return "14/08/2021"
        case .dashesLongYearDMY:
            return "14-08-2021"
        }
    }
}
