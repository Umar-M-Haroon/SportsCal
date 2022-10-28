//
//  UserDefaultStorage.swift
//  SportsCal (iOS)
//
//  Created by Umar Haroon on 11/14/21.
//

import Foundation
import SwiftUI
import SportsCalModel

class UserDefaultStorage: NSObject, ObservableObject {
//    static func == (lhs: UserDefaultStorage, rhs: UserDefaultStorage) -> Bool {
//        return lhs.shouldShowF1 == rhs.shouldShowF1 &&
//               lhs.hidePastEvents == rhs.hidePastEvents &&
//        lhs.shouldShowNBA == rhs.shouldShowNBA &&
//        lhs.shouldShowNFL == rhs.shouldShowNFL &&
//        lhs.shouldShowNHL == rhs.shouldShowNHL &&
//        lhs.shouldShowSoccer == rhs.shouldShowSoccer &&
//        lhs.shouldShowMLB == rhs.shouldShowMLB &&
//        lhs.shouldShowOnboarding == rhs.shouldShowOnboarding &&
//        lhs.hidePastEvents == rhs.hidePastEvents &&
//        lhs.soonestOnTop == rhs.soonestOnTop &&
//        lhs.durations == rhs.durations
//    }
    
    @AppStorage("shouldShowNBA") var shouldShowNBA: Bool = false
    @AppStorage("shouldShowNFL") var shouldShowNFL: Bool = false
    @AppStorage("shouldShowNHL") var shouldShowNHL: Bool = false
    @AppStorage("shouldShowSoccer") var shouldShowSoccer: Bool = false
    @AppStorage("shouldShowF1") var shouldShowF1: Bool = false
    @AppStorage("shouldShowMLB") var shouldShowMLB: Bool = false
    @AppStorage("shouldShowOnboarding") var shouldShowOnboarding: Bool = true
    @AppStorage("hidesPastEvents") var hidePastEvents: Bool = true
    @AppStorage("soonestOnTop") var soonestOnTop: Bool = true
    @AppStorage("duration") var durations: Durations = .threeWeeks
    @AppStorage("launches") var launches: Int = 0
    @AppStorage("dateFormat") var dateFormat: String = "E, dd.MM.yy"
    @AppStorage("hidePastGamesDuration") var hidePastGamesDuration: Durations = .threeWeeks
    @AppStorage("showStartTime") var showStartTime: Bool = true
    
    @AppStorage("hiddenCompetitions") var hiddenCompetitions: [String] = []
    func switchTo(sportType: SportType) {
        switch sportType {
        case .hockey:
            shouldShowNFL = false
            shouldShowNBA = false
            shouldShowNHL = true
            shouldShowSoccer = false
            shouldShowMLB = false
            break
        case .nfl:
            shouldShowNFL = true
            shouldShowNBA = false
            shouldShowNHL = false
            shouldShowSoccer = false
            shouldShowMLB = false
            break
        case .basketball:
            shouldShowNFL = false
            shouldShowNBA = true
            shouldShowNHL = false
            shouldShowSoccer = false
            shouldShowMLB = false
            break
        case .mlb:
            shouldShowNFL = false
            shouldShowNBA = false
            shouldShowNHL = false
            shouldShowSoccer = false
            shouldShowMLB = true
            break
        case .soccer:
            shouldShowNFL = false
            shouldShowNBA = false
            shouldShowNHL = false
            shouldShowSoccer = true
            shouldShowMLB = false
            break
        }
    }
}
extension Array: RawRepresentable where Element: Codable {
    public init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let result = try? JSONDecoder().decode([Element].self, from: data)
        else {
            return nil
        }
        self = result
    }
    
    public var rawValue: String {
        guard let data = try? JSONEncoder().encode(self),
              let result = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return result
    }
}
