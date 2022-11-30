//
//  Game+Extensions.swift
//  SportsCal
//
//  Created by Umar Haroon on 11/22/22.
//

import Foundation
import SportsCalModel

extension Game {
    func getDate() -> Date? {
        DateFormatters.backupISOFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        DateFormatters.backupISOFormatter.timeZone = .init(secondsFromGMT: 0)
        guard let timestamp = strTimestamp else { return nil }
        if let date = DateFormatters.isoFormatter.date(from: timestamp) {
            return date
        }
        if let date = DateFormatters.backupISOFormatter.date(from: timestamp) {
            return date
        }
        DateFormatters.backupISOFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        if let date = DateFormatters.backupISOFormatter.date(from: timestamp) {
            return date
        }
        return nil
    }
}
