//
//  DateFormatters.swift
//  SportsCal
//
//  Created by Umar Haroon on 10/23/22.
//

import Foundation

class DateFormatters {
    static let isoFormatter = ISO8601DateFormatter()
    static let dateFormatter = DateFormatter()
    static let backupISOFormatter = DateFormatter()
    static let relativeFormatter = RelativeDateTimeFormatter()
}
